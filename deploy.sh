#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Defaults (override via environment variables)
# ─────────────────────────────────────────────
DEPLOY_DIR="${DEPLOY_DIR:-/opt/wg-easy}"
OBF_PORT="${OBF_PORT:-51822}"
WG_HOST="${WG_HOST:-}"          # auto-detected if empty
COMPOSE_FILE="docker-compose.yml"

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash $0"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

install_docker() {
    log "Installing Docker"
    local distro
    distro="$(detect_distro)"

    case "$distro" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/"${distro}"/gpg \
                -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${distro} \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
              > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky|almalinux)
            dnf config-manager --add-repo \
                https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            log "Unknown distro — using get.docker.com script"
            curl -fsSL https://get.docker.com | sh
            ;;
    esac

    systemctl enable --now docker
    ok "Docker installed: $(docker --version)"
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        ok "Docker already present: $(docker --version)"
        return
    fi
    install_docker
}

load_wireguard_module() {
    if lsmod | grep -q wireguard 2>/dev/null; then
        ok "WireGuard kernel module already loaded"
        return
    fi
    if modprobe wireguard 2>/dev/null; then
        ok "WireGuard kernel module loaded"
    else
        log "Warning: could not load wireguard module — wireguard-go (userspace) will be used"
    fi
}

detect_public_ip() {
    local ip
    ip=$(curl -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null \
      || curl -fsSL --connect-timeout 5 https://ifconfig.me 2>/dev/null \
      || curl -fsSL --connect-timeout 5 https://icanhazip.com 2>/dev/null \
      || true)
    echo "${ip:-127.0.0.1}"
}

ensure_scripts_executable() {
    local base_dir="$1"
    [ -d "${base_dir}/scripts" ] || return 0

    local script_count=0
    local file

    shopt -s globstar nullglob
    for file in "${base_dir}"/scripts/**/*.sh; do
        chmod +x "$file"
        script_count=$((script_count + 1))
    done
    shopt -u globstar nullglob

    [ "${script_count}" -gt 0 ] || return 0
    ok "Executable bit set on ${script_count} scripts in ${base_dir}/scripts"
}

wait_healthy() {
    local ctr="${WAIT_HEALTHY_CONTAINER:-wg-easy}"
    local inspect_fmt='{{if .State.Health}}{{.State.Health.Status}}|{{.State.Health.FailingStreak}}{{else}}nohealth|0{{end}}'
    local hc_fmt='{{if .Config.Healthcheck}}{{.Config.Healthcheck.Interval}}|{{.Config.Healthcheck.Timeout}}|{{.Config.Healthcheck.StartPeriod}}|{{.Config.Healthcheck.Retries}}{{else}}0|0|0|0{{end}}'
    local raw hc_raw status streak interval_ns timeout_ns start_ns retries
    status="missing"
    streak=0
    interval_ns=0
    timeout_ns=0
    start_ns=0
    retries=0

    local poll_s="${WAIT_HEALTHY_POLL_SEC:-2}"
    local timeout_s="${WAIT_HEALTHY_TIMEOUT_SEC:-0}"
    local dynamic_timeout_s=240

    hc_raw=$(docker inspect "${ctr}" --format "${hc_fmt}" 2>/dev/null || echo "0|0|0|0")
    IFS='|' read -r interval_ns timeout_ns start_ns retries <<EOF
${hc_raw}
EOF

    if [ "${status}" != "nohealth" ] && [ "${status}" != "missing" ] && [ "${interval_ns}" -gt 0 ]; then
        local interval_s timeout_probe_s start_period_s retries_n
        interval_s=$((interval_ns / 1000000000))
        timeout_probe_s=$((timeout_ns / 1000000000))
        start_period_s=$((start_ns / 1000000000))
        retries_n="${retries:-3}"
        [ "${interval_s}" -gt 0 ] || interval_s=30
        [ "${timeout_probe_s}" -gt 0 ] || timeout_probe_s=5
        [ "${start_period_s}" -ge 0 ] || start_period_s=0
        [ "${retries_n}" -gt 0 ] || retries_n=3
        dynamic_timeout_s=$((start_period_s + (interval_s + timeout_probe_s) * (retries_n + 3)))
        [ "${dynamic_timeout_s}" -lt 90 ] && dynamic_timeout_s=90
        [ "${dynamic_timeout_s}" -gt 600 ] && dynamic_timeout_s=600
    fi

    if [ "${timeout_s}" -le 0 ]; then
        timeout_s="${dynamic_timeout_s}"
    fi

    log "Waiting for container ${ctr} (poll ${poll_s}s, timeout ${timeout_s}s)"

    local start_ts now_ts elapsed i=0
    start_ts=$(date +%s)
    while :; do
        raw=$(docker inspect "${ctr}" --format "${inspect_fmt}" 2>/dev/null || echo "missing|0|0|0|0|0")
        IFS='|' read -r status streak interval_ns timeout_ns start_ns retries <<EOF
${raw}
EOF

        now_ts=$(date +%s)
        elapsed=$((now_ts - start_ts))

        case "${status}" in
            healthy)
                ok "Container is healthy after ${elapsed}s"
                docker ps --filter "name=${ctr}" --format "  {{.Names}} | {{.Status}} | {{.Ports}}"
                return 0
                ;;
            unhealthy)
                fail "Container reported unhealthy after ${elapsed}s (failing streak: ${streak}). Logs:\n$(docker logs --tail 120 "${ctr}" 2>/dev/null || true)"
                ;;
            *)
                if [ $((i % 5)) -eq 0 ]; then
                    printf '    status=%s elapsed=%ss/%ss failing_streak=%s\n' "${status}" "${elapsed}" "${timeout_s}" "${streak}"
                fi
                ;;
        esac

        if [ "${elapsed}" -ge "${timeout_s}" ]; then
            fail "Container did not become healthy in ${timeout_s}s (last status: ${status}). Logs:\n$(docker logs --tail 150 "${ctr}" 2>/dev/null || true)"
        fi

        i=$((i + 1))
        sleep "${poll_s}"
    done
}

# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────
require_root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Sources directory: $SCRIPT_DIR"

ensure_scripts_executable "$SCRIPT_DIR"

ensure_docker
load_wireguard_module

# Resolve public IP
if [ -z "$WG_HOST" ]; then
    log "Detecting public IP"
    WG_HOST="$(detect_public_ip)"
    ok "Public IP: $WG_HOST"
fi

# Copy sources to deploy dir if not already there
if [ "$SCRIPT_DIR" != "$DEPLOY_DIR" ]; then
    log "Installing to $DEPLOY_DIR"
    mkdir -p "$DEPLOY_DIR"
    # tar-pipe: архивируем без лишних каталогов, распаковываем на месте
    tar -C "$SCRIPT_DIR" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='.nuxt' \
        --exclude='.output' \
        -cf - . \
    | tar -C "$DEPLOY_DIR" -xf -
    ok "Sources copied"
fi

ensure_scripts_executable "$DEPLOY_DIR"

cd "$DEPLOY_DIR"

# Write .env so docker compose picks it up
log "Writing .env"
cat > "$DEPLOY_DIR/.env" <<EOF
WG_HOST=${WG_HOST}
OBF_PORT=${OBF_PORT}
EOF
ok ".env written"

# Stop any running instance (ignore errors on fresh server)
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^wg-easy$'; then
    log "Stopping existing container"
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
fi

# Build
log "Building Docker image (first build takes ~5 min)"
docker build -t wg-easy:local .
docker tag wg-easy:local ghcr.io/wg-easy/wg-easy:latest
ok "Image built"

# Start
log "Starting stack (compose=$COMPOSE_FILE, OBF_PORT=$OBF_PORT)"
OBF_PORT="$OBF_PORT" docker compose -f "$COMPOSE_FILE" up -d --force-recreate
ok "Stack started"

wait_healthy

# ─────────────────────────────────────────────
#  Summary
# ─────────────────────────────────────────────
printf '\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  wg-easy deployed successfully\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '  Web UI      : http://%s:51821/\n' "$WG_HOST"
printf '  Obfuscator  : UDP %s:%s\n'       "$WG_HOST" "$OBF_PORT"
printf '  Deploy dir  : %s\n'              "$DEPLOY_DIR"
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\n'
docker ps --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"
printf '\n'
