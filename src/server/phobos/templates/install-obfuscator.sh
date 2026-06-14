stop_existing_instance() {
  if [ -f "/opt/etc/init.d/${OBF_INIT_NAME}" ]; then
    /opt/etc/init.d/${OBF_INIT_NAME} stop >/dev/null 2>&1 || true
  fi

  if [ -f "/etc/init.d/${OBF_SERVICE_NAME}" ]; then
    /etc/init.d/${OBF_SERVICE_NAME} stop >/dev/null 2>&1 || true
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${OBF_SERVICE_NAME}.service" ]; then
    systemctl stop "${OBF_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

install_obfuscator() {
  local arch=$1

  log "Установка wg-obfuscator (${OBF_BINARY_NAME}) для архитектуры $arch..."

  stop_existing_instance

  local binary_name="wg-obfuscator-$arch"

  if [ ! -f "bin/$binary_name" ]; then
    log "Ошибка: бинарник $binary_name не найден в архиве"
    log "Доступные бинарники:"
    ls -1 bin/
    exit 1
  fi

  local target_path="/opt/bin/${OBF_BINARY_NAME}"
  if [ "$ROUTER_PLATFORM" = "openwrt" ]; then
    target_path="/usr/bin/${OBF_BINARY_NAME}"
  fi

  if [ -f "$target_path" ]; then
    rm "$target_path"
  fi

  if [ "$ROUTER_PLATFORM" = "openwrt" ]; then
    mkdir -p /usr/bin
  else
    mkdir -p /opt/bin
  fi

  cp "bin/$binary_name" "$target_path"
  chmod +x "$target_path"

  log "Бинарник wg-obfuscator установлен в $target_path"
}

create_init_script() {
  log "Создание init-скрипта для obfuscator..."

  cat > /opt/etc/init.d/${OBF_INIT_NAME} <<EOF
#!/bin/sh

ENABLED=yes
PROCS=${OBF_BINARY_NAME}
ARGS="--config $PHOBOS_DIR/${OBF_CONF_NAME}"
PREARGS=""
DESC=\$PROCS
PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF

  chmod +x /opt/etc/init.d/${OBF_INIT_NAME}

  log "Init-скрипт создан: /opt/etc/init.d/${OBF_INIT_NAME}"
}

start_obfuscator() {
  log "Запуск wg-obfuscator..."

  if [ "$ROUTER_PLATFORM" = "keenetic" ] || [ -f /opt/etc/init.d/${OBF_INIT_NAME} ]; then
    /opt/etc/init.d/${OBF_INIT_NAME} start
  elif [ "$ROUTER_PLATFORM" = "openwrt" ] && [ -f /etc/init.d/${OBF_SERVICE_NAME} ]; then
    /etc/init.d/${OBF_SERVICE_NAME} start
    /etc/init.d/${OBF_SERVICE_NAME} enable
  fi

  sleep 2

  local process_found=0

  if command -v pidof >/dev/null 2>&1 && pidof ${OBF_BINARY_NAME} >/dev/null 2>&1; then
    process_found=1
  elif command -v pgrep >/dev/null 2>&1 && pgrep -f "${OBF_BINARY_NAME}" >/dev/null 2>&1; then
    process_found=1
  elif ps w 2>/dev/null | grep -v grep | grep -q "${OBF_BINARY_NAME}"; then
    process_found=1
  elif ps 2>/dev/null | grep -v grep | grep -q "${OBF_BINARY_NAME}"; then
    process_found=1
  fi

  if [ $process_found -eq 0 ]; then
    if [ "$ROUTER_PLATFORM" = "keenetic" ] && [ -f /opt/etc/init.d/${OBF_INIT_NAME} ]; then
      local status_output=$(/opt/etc/init.d/${OBF_INIT_NAME} status 2>&1 || echo "")
      if echo "$status_output" | grep -q "alive"; then
        process_found=1
      fi
    elif [ "$ROUTER_PLATFORM" = "openwrt" ] && [ -f /etc/init.d/${OBF_SERVICE_NAME} ]; then
      if /etc/init.d/${OBF_SERVICE_NAME} status >/dev/null 2>&1; then
        process_found=1
      fi
    fi
  fi

  if [ $process_found -eq 1 ]; then
    log "✓ wg-obfuscator успешно запущен"
  else
    log "✗ wg-obfuscator не запущен. Проверьте логи."
  fi
}

create_procd_init_script() {
  log "Создание procd init-скрипта для obfuscator..."

  cat > /etc/init.d/${OBF_SERVICE_NAME} <<EOF
#!/bin/sh /etc/rc.common

START=$((49 + SLOT))
STOP=$((51 + SLOT))

USE_PROCD=1

PROG=/usr/bin/${OBF_BINARY_NAME}
CONFIG_FILE=${PHOBOS_DIR}/${OBF_CONF_NAME}

start_service() {
  if [ ! -f "\$PROG" ]; then
    echo "Error: wg-obfuscator not found at \$PROG"
    return 1
  fi

  if [ ! -f "\$CONFIG_FILE" ]; then
    echo "Error: config not found at \$CONFIG_FILE"
    return 1
  fi

  procd_open_instance
  procd_set_param command \$PROG --config \$CONFIG_FILE
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF

  chmod +x /etc/init.d/${OBF_SERVICE_NAME}

  log "Procd init-скрипт создан: /etc/init.d/${OBF_SERVICE_NAME}"
}

create_systemd_obfuscator_service() {
  log "Создание systemd service для obfuscator..."

  cat > /etc/systemd/system/${OBF_SERVICE_NAME}.service <<EOFS
[Unit]
Description=Phobos WireGuard Obfuscator (${CLIENT_NAME})
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/${OBF_BINARY_NAME} --config $PHOBOS_DIR/${OBF_CONF_NAME}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFS

  if [ ! -f /usr/local/bin/${OBF_BINARY_NAME} ]; then
    local target_path="/usr/local/bin/${OBF_BINARY_NAME}"
    if [ -f /opt/bin/${OBF_BINARY_NAME} ]; then
      cp /opt/bin/${OBF_BINARY_NAME} "$target_path"
      chmod +x "$target_path"
    elif [ -f /usr/bin/${OBF_BINARY_NAME} ]; then
      cp /usr/bin/${OBF_BINARY_NAME} "$target_path"
      chmod +x "$target_path"
    fi
  fi

  systemctl daemon-reload
  systemctl enable ${OBF_SERVICE_NAME}
  systemctl start ${OBF_SERVICE_NAME}

  log "Ожидание запуска obfuscator (до 10 секунд)..."
  local wait_count=0
  while [ $wait_count -lt 10 ]; do
    sleep 1
    if systemctl is-active --quiet ${OBF_SERVICE_NAME}; then
      log "✓ Obfuscator успешно запущен"
      break
    fi
    wait_count=$((wait_count + 1))
  done

  if [ $wait_count -ge 10 ]; then
    log "ПРЕДУПРЕЖДЕНИЕ: Obfuscator может быть не готов (таймаут 10 сек)"
  fi

  log "Systemd service создан: /etc/systemd/system/${OBF_SERVICE_NAME}.service"
}
