#!/usr/bin/env bash
set -euo pipefail

# One-shot SSH key bootstrap for a fresh remote host.
# Authenticates once with a password, installs your public key into
# the remote's authorized_keys, then verifies key-based login works.
#
# Usage:
#   scripts/deploy/setup-ssh.sh <user@host> [--key <path-to-pubkey>]
#
# Requires: sshpass, ssh-copy-id.
# Password is read interactively unless REMOTE_PASSWORD env var is set.

REMOTE=""
KEY_PATH="$HOME/.ssh/id_ed25519.pub"

usage() {
  sed -n '2,12p' "$0"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY_PATH="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else echo "Unknown arg: $1" >&2; usage; fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || usage

if [ ! -f "$KEY_PATH" ]; then
  echo "Public key not found at $KEY_PATH — generating a new ed25519 pair" >&2
  ssh-keygen -t ed25519 -N '' -f "${KEY_PATH%.pub}"
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass is required. Install with: apt-get install -y sshpass" >&2
  exit 2
fi

if [ -z "${REMOTE_PASSWORD:-}" ]; then
  read -rsp "Password for $REMOTE: " REMOTE_PASSWORD
  echo
fi

echo "==> Installing key into $REMOTE:~/.ssh/authorized_keys"
SSHPASS="$REMOTE_PASSWORD" sshpass -e ssh-copy-id \
  -i "$KEY_PATH" \
  -o StrictHostKeyChecking=accept-new \
  "$REMOTE"

echo "==> Verifying key-based login"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" 'echo OK: $(hostname) $(uname -sr)'

echo
echo "Key auth works. You can now run:"
echo "  scripts/deploy/remote-deploy.sh $REMOTE"
