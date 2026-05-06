#!/usr/bin/env bash
set -euo pipefail

# Fast iterate: sync code, rebuild image, restart container.
# Preserves volumes (wireguard config + sqlite DB).
#
# Usage:
#   scripts/deploy/update.sh <user@host> [--path <remote-dir>] [--port <obfuscator-udp-port>] [--https]

REMOTE=""
OBF_PORT="51822"
REMOTE_PATH="/opt/wg-easy"
HTTPS=0

usage() {
  sed -n '2,10p' "$0"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --port) OBF_PORT="$2"; shift 2 ;;
    --path) REMOTE_PATH="$2"; shift 2 ;;
    --https) HTTPS=1; shift ;;
    -h|--help) usage ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else echo "Unknown arg: $1" >&2; usage; fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || usage

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="docker-compose.yml"
[ $HTTPS -eq 1 ] && COMPOSE_FILE="docker-compose.https.yml"

echo "==> Syncing"
rsync -az --delete \
  --exclude 'node_modules' --exclude '.nuxt' --exclude '.output' \
  --exclude 'data' --exclude '.git' --exclude 'plan' --exclude 'MERGE_PLAN.md' \
  --exclude 'certs' \
  "$REPO_ROOT/" "$REMOTE:$REMOTE_PATH/"

echo "==> Rebuilding"
ssh "$REMOTE" "cd $REMOTE_PATH && docker build -t wg-easy:local . && docker tag wg-easy:local ghcr.io/wg-easy/wg-easy:latest"

echo "==> Restarting (compose=$COMPOSE_FILE, volumes preserved)"
ssh "$REMOTE" "cd $REMOTE_PATH && OBF_PORT=$OBF_PORT docker compose -f $COMPOSE_FILE up -d --force-recreate"

for i in $(seq 1 60); do
  status=$(ssh "$REMOTE" 'docker inspect wg-easy --format "{{.State.Health.Status}}"' 2>/dev/null || echo unknown)
  case "$status" in
    healthy) echo "    healthy"; break ;;
    unhealthy) ssh "$REMOTE" 'docker logs --tail 30 wg-easy'; exit 1 ;;
    *) sleep 5 ;;
  esac
done

ssh "$REMOTE" 'docker ps --format "{{.Names}} | {{.Status}}"'
