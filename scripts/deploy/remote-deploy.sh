#!/usr/bin/env bash
set -euo pipefail

# wg-easy + Phobos remote deployer.
# Installs Docker on a fresh Ubuntu/Debian host, syncs this repo,
# builds the image, and starts the stack via docker compose.
#
# Usage:
#   scripts/deploy/remote-deploy.sh <user@host> [--port <obfuscator-udp-port>] [--path <remote-dir>] [--https]
#
# --https adds a Caddy reverse proxy with a self-signed cert on :443
# (uses docker-compose.https.yml instead of docker-compose.yml).
#
# Requires on the workstation: ssh, rsync.
# Requires on the remote host: SSH key auth (use setup-ssh.sh first).

REMOTE=""
OBF_PORT="51822"
REMOTE_PATH="/opt/wg-easy"
HTTPS=0

usage() {
  sed -n '2,15p' "$0"
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
cd "$REPO_ROOT"

COMPOSE_FILE="docker-compose.yml"
[ $HTTPS -eq 1 ] && COMPOSE_FILE="docker-compose.https.yml"

echo "==> Checking SSH connectivity to $REMOTE"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" true

echo "==> Ensuring Docker and rsync are installed on $REMOTE"
ssh "$REMOTE" '
  set -e
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com | sh
  fi
  if ! command -v rsync >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q rsync
    fi
  fi
  systemctl enable --now docker 2>/dev/null || true
'

echo "==> Syncing project tree to $REMOTE:$REMOTE_PATH"
ssh "$REMOTE" "mkdir -p $REMOTE_PATH"
rsync -az --delete \
  --exclude 'node_modules' \
  --exclude '.nuxt' \
  --exclude '.output' \
  --exclude 'data' \
  --exclude '.git' \
  --exclude 'plan' \
  --exclude 'MERGE_PLAN.md' \
  --exclude 'certs' \
  "$REPO_ROOT/" "$REMOTE:$REMOTE_PATH/"

echo "==> Building image on $REMOTE (this may take a few minutes on first run)"
ssh "$REMOTE" "cd $REMOTE_PATH && docker build -t wg-easy:local . && docker tag wg-easy:local ghcr.io/wg-easy/wg-easy:latest"

if [ $HTTPS -eq 1 ]; then
  echo "==> Checking for active TLS certificate"
  has_cert=$(ssh "$REMOTE" "[ -f $REMOTE_PATH/certs/active/fullchain.pem ] && [ -f $REMOTE_PATH/certs/active/privkey.pem ] && echo yes || echo no")
  if [ "$has_cert" != "yes" ]; then
    echo
    echo "    No active TLS certificate found. Launching cert manager..."
    echo "    (1 = Let's Encrypt domain, 2 = Let's Encrypt IP, 3 = Self-signed)"
    echo
    ssh -t "$REMOTE" "CERT_ROOT=$REMOTE_PATH/certs $REMOTE_PATH/scripts/cert/cert-manager.sh"
    has_cert=$(ssh "$REMOTE" "[ -f $REMOTE_PATH/certs/active/fullchain.pem ] && [ -f $REMOTE_PATH/certs/active/privkey.pem ] && echo yes || echo no")
    [ "$has_cert" = "yes" ] || { echo "Cert manager exited without an active cert; aborting." >&2; exit 1; }
  else
    echo "    Active cert present — reusing."
  fi
fi

echo "==> Starting stack (compose=$COMPOSE_FILE, OBF_PORT=$OBF_PORT)"
ssh "$REMOTE" "cd $REMOTE_PATH && OBF_PORT=$OBF_PORT docker compose -f $COMPOSE_FILE up -d --force-recreate"

echo "==> Waiting for container to become healthy"
for i in $(seq 1 60); do
  status=$(ssh "$REMOTE" 'docker inspect wg-easy --format "{{.State.Health.Status}}"' 2>/dev/null || echo "unknown")
  case "$status" in
    healthy) echo "    healthy"; break ;;
    unhealthy) echo "    container reported unhealthy"; ssh "$REMOTE" 'docker logs --tail 30 wg-easy'; exit 1 ;;
    *) sleep 5 ;;
  esac
done

echo "==> Summary"
ssh "$REMOTE" 'docker ps --format "{{.Names}} | {{.Status}} | {{.Ports}}"'

HOST=${REMOTE#*@}
echo
if [ $HTTPS -eq 1 ]; then
  echo "UI:        https://$HOST/  (self-signed cert — browser warning expected on first visit)"
else
  echo "UI:        http://$HOST:51821/"
fi
echo "Obf port:  UDP $HOST:$OBF_PORT"
echo "Remote:    $REMOTE:$REMOTE_PATH"
