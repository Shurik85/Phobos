#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/wg-easy}"
COMPOSE_FILE="docker-compose.yml"

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m  !\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash $0"

printf '\e[1;31m'
printf '┌─────────────────────────────────────────────┐\n'
printf '│  DESTRUCTIVE OPERATION — NO UNDO POSSIBLE   │\n'
printf '│                                             │\n'
printf '│  Will permanently remove:                   │\n'
printf '│    • wg-easy container                      │\n'
printf '│    • Docker volumes (wireguard keys, DB)    │\n'
printf '│    • Docker network wg-easy_wg              │\n'
printf '│    • Docker image wg-easy:local             │\n'
printf '│    • Deploy directory %s          │\n' "$DEPLOY_DIR"
printf '│    • /var/log/wg-easy (if present)          │\n'
printf '└─────────────────────────────────────────────┘\n'
printf '\e[0m'
printf '\nType YES to continue: '
read -r CONFIRM
[ "$CONFIRM" = "YES" ] || { warn "Aborted."; exit 0; }

# ── 1. Stop & remove container ──────────────────────────────────────────────
log "Stopping container"
if [ -d "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/$COMPOSE_FILE" ]; then
    docker compose -f "$DEPLOY_DIR/$COMPOSE_FILE" down \
        --remove-orphans --timeout 15 2>/dev/null || true
    ok "Compose stack torn down"
else
    docker stop wg-easy 2>/dev/null && docker rm wg-easy 2>/dev/null || true
    warn "No compose file found — stopped container directly"
fi

# ── 2. Remove Docker volumes ─────────────────────────────────────────────────
log "Removing Docker volumes"
for VOL in etc_wireguard sqlite_data certs_data acme_data; do
    for CANDIDATE in "${VOL}" "wg-easy_${VOL}"; do
        if docker volume inspect "$CANDIDATE" >/dev/null 2>&1; then
            docker volume rm "$CANDIDATE"
            ok "Volume removed: $CANDIDATE"
        fi
    done
done

# ── 3. Remove Docker network ─────────────────────────────────────────────────
log "Removing Docker network"
for NET in wg-easy_wg wg_easy_wg; do
    if docker network inspect "$NET" >/dev/null 2>&1; then
        docker network rm "$NET"
        ok "Network removed: $NET"
    fi
done

# ── 4. Remove Docker images ──────────────────────────────────────────────────
log "Removing Docker images"
for IMG in "wg-easy:local" "ghcr.io/ground-zerro/phobos:latest"; do
    if docker image inspect "$IMG" >/dev/null 2>&1; then
        docker rmi "$IMG"
        ok "Image removed: $IMG"
    fi
done

# ── 5. Remove deploy directory ───────────────────────────────────────────────
log "Removing deploy directory: $DEPLOY_DIR"
if [ -d "$DEPLOY_DIR" ]; then
    rm -rf "$DEPLOY_DIR"
    ok "Removed $DEPLOY_DIR"
else
    warn "Deploy directory not found, skipping"
fi

# ── 6. Remove logs ───────────────────────────────────────────────────────────
log "Removing logs"
for LOG_PATH in /var/log/wg-easy /var/log/wg-easy.log; do
    if [ -e "$LOG_PATH" ]; then
        rm -rf "$LOG_PATH"
        ok "Removed $LOG_PATH"
    fi
done

# ── 7. Remove .env residuals in common locations ─────────────────────────────
for ENV_FILE in /root/.wg-easy.env /etc/wg-easy.env; do
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        ok "Removed $ENV_FILE"
    fi
done

# ── 8. Prune dangling build cache (optional) ─────────────────────────────────
log "Pruning dangling Docker build cache"
docker builder prune -f --filter type=exec.cachemount 2>/dev/null || \
    docker builder prune -f 2>/dev/null || true
ok "Build cache pruned"

printf '\n\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  wg-easy fully removed from this server\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n\n'
