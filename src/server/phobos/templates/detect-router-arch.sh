#!/bin/sh

. "$(dirname "$0")/lib-client.sh"

PLATFORM=$(detect_router_platform)
ARCH=$(detect_arch)

echo "=========================================="
echo "  Phobos Router Architecture Detector"
echo "=========================================="
echo ""
echo "Платформа:        ${PLATFORM}"
echo "uname -m:          $(uname -m)"
echo "Ядро:             $(uname -s) $(uname -r)"
echo ""
echo "Источники определения:"

if [ -r /opt/etc/entware_release ]; then
  echo "  entware_release arch=  $(grep '^arch=' /opt/etc/entware_release | head -1 | cut -d= -f2)"
fi
if [ -r /etc/openwrt_release ]; then
  echo "  DISTRIB_ARCH=          $( . /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ARCH" )"
fi
if command -v opkg >/dev/null 2>&1; then
  echo "  opkg arch=             $(opkg print-architecture 2>/dev/null | grep '^arch ' | grep -v ' all ' | grep -v ' noarch ' | sort -k3 -n | tail -1 | awk '{print $2}')"
fi
if command -v apk >/dev/null 2>&1; then
  echo "  apk arch=              $(apk --print-arch 2>/dev/null)"
fi

echo ""
echo "Определённая архитектура: ${ARCH}"

if [ "$ARCH" = "unknown" ]; then
  echo "  ⚠ Не удалось определить архитектуру"
  exit 1
fi

echo "  ✓ Бинарник: wg-obfuscator-${ARCH}"
echo ""
