# wg-easy + Phobos obfuscator

[![Build & Publish latest Image](https://github.com/wg-easy/wg-easy/actions/workflows/deploy.yml/badge.svg?branch=production)](https://github.com/wg-easy/wg-easy/actions/workflows/deploy.yml)
[![Lint](https://github.com/wg-easy/wg-easy/actions/workflows/lint.yml/badge.svg?branch=master)](https://github.com/wg-easy/wg-easy/actions/workflows/lint.yml)
[![GitHub Stars](https://img.shields.io/github/stars/wg-easy/wg-easy)](https://github.com/wg-easy/wg-easy/stargazers)
[![License](https://img.shields.io/github/license/wg-easy/wg-easy)](LICENSE)

WireGuard admin panel with a built-in STUN obfuscator. Traffic from the client to the server is masked as STUN and XOR-encoded — to bypass DPI in regions with blocks.

<p align="center">
  <img src="./assets/screenshot.png" width="802" alt="wg-easy Screenshot" />
</p>

## Features

- WireGuard + Web UI + XOR/STUN obfuscator in a single container.
- s6-overlay supervises `node` and `wg-obfuscator` as independent long-running services.
- Public WireGuard port is not exposed; only the obfuscator UDP port is published.
- Per-client **install-link**: one shell command installs a full Phobos package on the client (WG config + platform installer + multi-arch obfuscator binary).
- Admin UI for tuning obfuscator level, masking mode, key, port.
- SQLite + Drizzle, multilanguage UI, 2FA, per-client firewall, IPv6, CIDR support.

## Quickstart (generic Docker)

```yaml
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    environment:
      - OBF_PORT=51822
    ports:
      - "51822:51822/udp"
      - "51821:51821/tcp"
    volumes:
      - etc_wireguard:/etc/wireguard
      - sqlite_data:/app/server/data
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped

volumes:
  etc_wireguard:
  sqlite_data:
```

Open `http://<host>:51821`, complete the initial setup, create a client.

## Deploy from this repository (ph-wg-easy branch)

To deploy the customized `wg-easy + Phobos` build from this repo on a fresh Ubuntu/Debian server:

```bash
sudo -i
apt update && apt install -y git

git clone -b ph-wg-easy https://github.com/Ground-Zerro/Phobos.git /root/wg
cd /root/wg

# WG_HOST — your public IP or domain, OBF_PORT — external obfuscator UDP port
WG_HOST=<PUBLIC_IP_OR_DOMAIN> OBF_PORT=51822 bash deploy.sh
```

The script will:

- install Docker + docker compose (if missing),
- copy sources to `/opt/wg-easy`,
- build the image from the included `Dockerfile`,
- bring up the stack via `docker-compose.yml`,
- wait until the `wg-easy` container is healthy.

After that:

- Web UI: `http://<WG_HOST>:51821/`
- WireGuard (internal server listen port): `51820/udp`
- Obfuscator (external UDP port): `<WG_HOST>:51822` (or your `OBF_PORT`)

## How it works

```
Client device                    Server (Docker)
─────────────                    ────────────────
 app ─► 127.0.0.1:13255           0.0.0.0:<OBF_PORT>
        (local WG client)          (wg-obfuscator server)
           │                            │  STUN unwrap + XOR decode
           │ plain WG                   ▼
           ▼                       127.0.0.1:51820 (wg0, loopback-only)
 127.0.0.1:13255                        │
 (wg-obfuscator client)                 │  WG
           │                            ▼
           │ XOR + STUN wrap       FORWARD → internet
           ▼
 UDP → <server_ip>:<OBF_PORT>
```

## Client installation

1. Admin creates a client in the Web UI.
2. Admin clicks the **install-link** button — the command is copied to the clipboard:
   ```
   curl -sL http://<origin>/api/install/<token> | sh
   ```
3. Admin pastes the command on the target device. The script downloads the Phobos package, detects the platform, installs `wg-obfuscator` and configures WireGuard.

## Supported client platforms

- Keenetic / Netcraze (Entware + RCI API)
- OpenWrt / ImmortalWrt (opkg + UCI)
- Debian / Ubuntu Linux (apt + systemd)
- 3x-ui panels (SQLite integration)

## Obfuscator tuning

| Level | Key length | Max dummy |
|-------|-----------|-----------|
| 1 — Light | 3 | 4 |
| 2 — Sufficient | 6 | 10 |
| 3 — Average | 20 | 20 |
| 4 — Above average | 50 | 50 |
| 5 — Nightmare | 255 | 100 |

## Remote deploy

Helper scripts in `scripts/deploy/` automate SSH setup, Docker install, build, and lifecycle:

```shell
scripts/deploy/setup-ssh.sh     root@HOST            # one-shot password → key
scripts/deploy/remote-deploy.sh root@HOST [--https]  # full deploy (Docker + build + up)
scripts/deploy/update.sh        root@HOST [--https]  # rsync + rebuild + restart
scripts/deploy/certs.sh         root@HOST            # manage TLS certificates
scripts/deploy/logs.sh          root@HOST            # tail container logs
scripts/deploy/teardown.sh      root@HOST            # stop; add --purge to wipe volumes
```

With `--https` the stack launches behind Caddy on :443 and a cert manager (Let's Encrypt / self-signed / import) runs on first deploy.

Full guides: [`docs/deployment.md`](docs/deployment.md), [`docs/tls-certificates.md`](docs/tls-certificates.md).

## Development

```shell
pnpm dev
```

## License

AGPL-3.0-only — see [LICENSE](LICENSE).

This project is not affiliated, associated, authorized, endorsed by, or in any way officially connected with Jason A. Donenfeld, ZX2C4 or Edge Security. "WireGuard" and the "WireGuard" logo are registered trademarks of Jason A. Donenfeld.
