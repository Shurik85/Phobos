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

wait_healthy() {
    log "Waiting for container to become healthy (up to 3 min)"
    local i status
    for i in $(seq 1 36); do
        status=$(docker inspect wg-easy --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
        case "$status" in
            healthy)
                ok "Container is healthy"
                return 0
                ;;
            unhealthy)
                fail "Container reported unhealthy. Logs:\n$(docker logs --tail 40 wg-easy)"
                ;;
            missing)
                sleep 5
                ;;
            *)
                sleep 5
                ;;
        esac
    done
    fail "Container did not become healthy within 3 minutes"
}

# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────
require_root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Sources directory: $SCRIPT_DIR"

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
printf '  WireGuard   : UDP %s:51820\n'    "$WG_HOST"
printf '  Obfuscator  : UDP %s:%s\n'       "$WG_HOST" "$OBF_PORT"
printf '  Deploy dir  : %s\n'              "$DEPLOY_DIR"
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\n'
docker ps --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"
printf '\n'
