# Deployment

End-to-end guide for running wg-easy + Phobos obfuscator on a remote Linux host.

## Target host requirements

| Component | Minimum |
|-----------|---------|
| OS | Ubuntu 22.04+/24.04, Debian 12+ (any distro supporting `get.docker.com`) |
| CPU | 1 vCPU |
| RAM | 1 GiB (2+ recommended; Docker build needs ~900 MiB during `pnpm install`) |
| Disk | 4 GiB free |
| Kernel | `wireguard` module or `wireguard-go` userspace available |
| Ports | TCP 51821 (UI) and one UDP port (obfuscator, default 51822) reachable |
| Access | root or sudo-capable SSH user |

Docker and rsync are installed automatically by the deploy script on first run.

## Files and scripts

```
scripts/deploy/
├── setup-ssh.sh     one-shot SSH key install via password
├── remote-deploy.sh full deploy: install Docker, rsync, build, up (--https for TLS)
├── update.sh        fast iteration: rsync, rebuild, restart (volumes kept)
├── certs.sh         manage TLS certificates on the remote host
├── logs.sh          tail container logs
└── teardown.sh      stop stack (+ optional --purge of volumes and repo)

scripts/cert/
└── cert-manager.sh  TLS issue/import/switch tool (runs on the remote host)
```

See [`tls-certificates.md`](./tls-certificates.md) for the full certificate workflow.

All scripts take `<user@host>` as the first positional argument and share the same defaults:

| Default | Value | Override with |
|---------|-------|---------------|
| Remote path | `/opt/wg-easy` | `--path <dir>` |
| Obfuscator UDP port | `51822` | `--port <n>` |
| SSH public key | `$HOME/.ssh/id_ed25519.pub` | `--key <path>` (setup-ssh.sh only) |

## 1. First-time deploy (password → key → deploy)

On your workstation:

```shell
# Bootstrap key auth. Prompts for the server password (or set REMOTE_PASSWORD=... in env).
scripts/deploy/setup-ssh.sh root@203.0.113.42

# Install Docker, rsync the repo, build the image, bring the stack up (HTTP on :51821).
scripts/deploy/remote-deploy.sh root@203.0.113.42 --port 51822

# Or with HTTPS: launches the cert manager on first run, then brings up Caddy + wg-easy.
scripts/deploy/remote-deploy.sh root@203.0.113.42 --port 51822 --https
```

The script waits up to 5 minutes for the container healthcheck. On success it prints:

```
UI:        http://203.0.113.42:51821/
Obf port:  UDP 203.0.113.42:51822
Remote:    root@203.0.113.42:/opt/wg-easy
```

Open the UI, complete the setup wizard. The obfuscator key, external IP, and port are auto-generated on first start and stored in the SQLite DB (persistent volume).

## 2. Iterating on the code

After pushing local changes:

```shell
scripts/deploy/update.sh root@203.0.113.42
```

Volumes (`etc_wireguard`, `sqlite_data`) are preserved, so the DB and WireGuard keys survive across rebuilds.

## 3. Viewing logs

```shell
scripts/deploy/logs.sh root@203.0.113.42          # tail 100
scripts/deploy/logs.sh root@203.0.113.42 -f       # follow
scripts/deploy/logs.sh root@203.0.113.42 --tail 500
```

## 4. Teardown

```shell
scripts/deploy/teardown.sh root@203.0.113.42           # stop only
scripts/deploy/teardown.sh root@203.0.113.42 --purge   # stop + delete volumes + remove /opt/wg-easy
```

## How the container is built

Multi-stage Dockerfile (`node:krypton-alpine`):

1. **build** stage — `pnpm install`, `pnpm build` (Nuxt → `.output/`), and compiles `amneziawg-go` + `amneziawg-tools` from source.
2. **runtime** stage — pulls s6-overlay 3.2.0.2, copies `.output/`, the phobos bin directory (`src/phobos-obfuscator/bin`), client templates (`src/server/phobos/templates`), and the s6 service definitions under `docker/s6-rc.d/`.

### Alpine-specific libsql fix

`pnpm install` in the build stage runs on glibc, so it fetches `@libsql/linux-x64-gnu`. The runtime image is musl (Alpine), which needs `@libsql/linux-x64-musl`. The runtime stage downloads the matching musl tarball directly from the npm registry and unpacks it into `node_modules/@libsql/linux-x64-musl` — no `npm install` is invoked against the Nuxt output bundle, which avoids the known `Cannot read properties of null (reading 'fsTop')` error caused by large dependency trees.

### s6-overlay services

Two long-running services supervised by s6:

```
/etc/s6-overlay/s6-rc.d/
├── node/            → node server/index.mjs
├── wg-obfuscator/   → xargs -a /run/wg-obfuscator.args /usr/local/bin/wg-obfuscator
└── user/contents.d/ bundle entries (both services)
```

The obfuscator reads its parameters from `/run/wg-obfuscator.args` (one CLI flag per line), written by Node on startup and whenever the admin changes obfuscator settings. After a rewrite Node issues `s6-svc -r /run/service/wg-obfuscator` for a zero-downtime restart.

## docker-compose.yml

```yaml
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    build: .
    container_name: wg-easy
    environment:
      - OBF_PORT=${OBF_PORT:-51822}
    ports:
      - "${OBF_PORT:-51822}:${OBF_PORT:-51822}/udp"
      - "51821:51821/tcp"
    volumes:
      - etc_wireguard:/etc/wireguard
      - sqlite_data:/app/server/data
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
```

### Why `OBF_PORT` is fixed via env

Docker `publish` mappings are locked in at `compose up` time. If the admin changed the obfuscator port via the UI later, the mapping would diverge from the actual bind and traffic would drop. The container therefore:

1. Reads `OBF_PORT` on first startup and pins it into the DB.
2. Returns `obfuscatorPortPinned: true` from `/api/information` when env is set.
3. Disables the "Pick free port" button in the UI while the env is set.

To change the port: edit `OBF_PORT`, run `scripts/deploy/update.sh`.

## Volumes

| Volume | Purpose |
|--------|---------|
| `etc_wireguard` | `wg0.conf`, `wg-easy.db` (SQLite), keys |
| `sqlite_data` | Reserved for future separation (currently unused when DB lives under `/etc/wireguard`) |

Both are named Docker volumes — survive container recreation, wiped only by `teardown.sh --purge` or manual `docker volume rm`.

## Troubleshooting

### Container stays `unhealthy`

```shell
scripts/deploy/logs.sh root@host --tail 200
```

Common causes:
- **`Cannot find module '@libsql/linux-x64-musl'`** — the runtime stage's musl tarball fetch failed (no internet during build). Rebuild with network access.
- **`wg-quick: syntax error`** — hook string built in `wgHelper.ts` got corrupted; check `sqlite3 /etc/wireguard/wg-easy.db "select * from hooks_table"` and reset defaults if needed.
- **Obfuscator exits immediately** — inspect `cat /run/wg-obfuscator.args` inside the container; the key must be 1–255 chars, port 1024–65535.

### Port already bound

```
Error starting userland proxy: listen udp4 0.0.0.0:51822: bind: address already in use
```

Something else is using UDP 51822. Either free it or redeploy with another port:

```shell
scripts/deploy/update.sh root@host --port 55555
```

### Rebuild from scratch

```shell
ssh root@host 'cd /opt/wg-easy && docker build --no-cache -t wg-easy:local .'
scripts/deploy/update.sh root@host
```

### Checking obfuscator runtime state

```shell
ssh root@host '
  docker exec wg-easy cat /run/wg-obfuscator.args
  docker exec wg-easy pgrep -af wg-obfuscator
  docker exec wg-easy ss -ulpn | grep 51822
'
```

## HTTPS / TLS

wg-easy refuses logins over plain HTTP (session cookies are `Secure`). Use the `--https` flag with `remote-deploy.sh` / `update.sh` to deploy the Caddy sidecar (`docker-compose.https.yml`). The cert manager runs automatically on first HTTPS deploy and offers Let's Encrypt (domain or IP), self-signed, or import. See [`tls-certificates.md`](./tls-certificates.md).

## Security notes

- The obfuscator key is passed via CLI and visible via `ps` inside the container. Since the container runs only `node` and `wg-obfuscator` as root with no other processes, this does not weaken the threat model vs. a mode-0600 config file. Do not rely on process-list hiding as a confidentiality boundary.
- The UI listens on `0.0.0.0:51821` in plain HTTP inside the Docker network. Use the `--https` deployment profile (Caddy sidecar) to terminate TLS. For deployments on top of another reverse proxy (nginx, Traefik), point it at `wg-easy:51821` and set `X-Forwarded-Proto: https`.
- The `/api/install/:token` endpoint is unauthenticated by design (the token itself is the secret, 32 hex chars, 5-minute TTL). Do not log full install links server-side.

## Manual deploy (without the scripts)

If you prefer not to use the helper scripts:

```shell
# 1. On the remote host, install Docker (once)
curl -sSL https://get.docker.com | sh

# 2. From your workstation
rsync -az --delete \
  --exclude node_modules --exclude .nuxt --exclude .output \
  --exclude data --exclude .git --exclude plan \
  ./ root@host:/opt/wg-easy/

# 3. On the remote host
cd /opt/wg-easy
docker build -t wg-easy:local .
docker tag wg-easy:local ghcr.io/wg-easy/wg-easy:latest
OBF_PORT=51822 docker compose up -d
docker logs -f wg-easy
```
