# TLS certificates

wg-easy sets `secure` on session cookies unless `INSECURE=true`, so the panel only accepts logins over HTTPS. The `docker-compose.https.yml` profile wires in a Caddy sidecar that terminates TLS on :443 and proxies to `wg-easy:51821` inside the Docker network. Certificates are supplied by the **cert manager** (`scripts/cert/cert-manager.sh`), adapted from 3x-ui.

## Where certificates live

```
/opt/wg-easy/certs/
├── active -> <name>              symlink to the certificate Caddy uses
├── example.com/
│   ├── fullchain.pem
│   ├── privkey.pem               mode 0600
│   └── origin                    "letsencrypt" | "letsencrypt-ip" | "self-signed" | "imported"
├── ip-203.0.113.42/
│   └── ...
└── self-94.232.40.58/
    └── ...
```

The `certs/` directory is bind-mounted read-only into the Caddy container as `/etc/caddy/certs/`. `Caddyfile` points to `active/fullchain.pem` and `active/privkey.pem`, so switching certs is a symlink update plus `caddy reload` — no container restart, no dropped connections.

## Issuance modes

| Mode | Best for | Command |
|------|----------|---------|
| Let's Encrypt (domain) | Public server with a DNS name | `cert-manager.sh issue-le <domain>` |
| Let's Encrypt (IP, shortlived) | Public server without a domain | `cert-manager.sh issue-le-ip` |
| Self-signed | Private/lab networks, quick HTTPS without a CA | `cert-manager.sh self-signed <host-or-ip>` |
| Import | Existing certificate (wildcard, corporate CA, etc.) | `cert-manager.sh import <name> <cert.pem> <key.pem>` |

All modes end by updating the `active` symlink and reloading Caddy.

### Let's Encrypt prerequisites

- Public-facing server reachable on TCP port 80.
- `acme.sh` and `socat` are installed automatically on first run.
- For the domain mode, the DNS A/AAAA record must already point to the server.
- For the IP mode, Let's Encrypt issues a **6-day shortlived** certificate; `acme.sh` sets up an auto-renew cron entry (`acme.sh --upgrade --auto-upgrade`).

Port 80 must be free while ACME is running. The manager will stop Caddy for the duration of the HTTP-01 challenge and start it back up after. Use `ACME_PORT=<n>` env to use a different port (then forward external 80 → that port).

### Self-signed

Single-host certificate with `openssl req -x509`, SAN automatically picked (`DNS:` for hostnames, `IP:` for IPs), validity 10 years. Browsers will show a warning; add the cert to the trust store or accept the exception once.

### Import

For a wildcard or externally-issued cert. The manager validates both PEMs with `openssl x509 -noout` / `openssl pkey -noout` before copying.

## Workflow

### First-time HTTPS deploy

```shell
scripts/deploy/remote-deploy.sh root@host --https
```

If no `active/` cert is present, the script opens the cert manager menu over SSH, asking you to pick one of the four modes. After issuance it brings the stack up. On subsequent runs the existing cert is reused and the menu is skipped.

### Standalone certificate management

```shell
scripts/deploy/certs.sh root@host                                 # interactive menu
scripts/deploy/certs.sh root@host list                            # what's stored
scripts/deploy/certs.sh root@host show                            # details of active
scripts/deploy/certs.sh root@host issue-le example.com            # new Let's Encrypt
scripts/deploy/certs.sh root@host self-signed 94.232.40.58        # new self-signed
scripts/deploy/certs.sh root@host import corp *.pem key.pem       # upload your own
scripts/deploy/certs.sh root@host activate example.com            # switch active
scripts/deploy/certs.sh root@host delete self-94.232.40.58        # remove stored
scripts/deploy/certs.sh root@host reload                          # force Caddy reload
```

The wrapper just invokes `cert-manager.sh` over SSH with a TTY, so interactive prompts work.

### Renewing a Let's Encrypt certificate

`acme.sh` sets up its own cron entry; no action is needed in the common case. To force a renewal:

```shell
ssh root@host '~/.acme.sh/acme.sh --renew -d example.com --force'
scripts/deploy/certs.sh root@host reload
```

For IP certs the shortlived profile auto-renews every ~6 days. If you want to rotate the stored name too, reissue:

```shell
scripts/deploy/certs.sh root@host issue-le-ip
```

### Switching between certs

Multiple certs can coexist in `certs/`. Use `activate` to swap:

```shell
scripts/deploy/certs.sh root@host list
scripts/deploy/certs.sh root@host activate example.com
```

### Rotating compromised keys

1. Reissue with `issue-le` / `self-signed`.
2. `delete` the old entry.
3. Revoke the old cert if it was public (`~/.acme.sh/acme.sh --revoke -d <domain>`).

## Architecture

```
HTTPS :443  ─► Caddy (sidecar)  ─►  HTTP wg-easy:51821
                  │
                  └─ reads /etc/caddy/certs/active/{fullchain,privkey}.pem
                            ▲
                            │ bind-mount (ro)
                            │
             /opt/wg-easy/certs/active/  ──symlink──► /opt/wg-easy/certs/<name>/
```

The Caddy admin API is exposed on `:2019` inside the container (not published). `caddy reload --config /etc/caddy/Caddyfile` inside the container re-reads the PEM files; the symlink change is picked up immediately.

## Install-link behaviour

`POST /api/client/:id/generateInstallLink` returns a token, and the UI button builds `curl -sL <origin>/api/install/<token> | sh`. When the active certificate is self-signed (`tlsUntrusted: true` in `/api/information`), the UI switches the flag to `-ksL` and the generated install script uses `curl -fksSL` / `wget --no-check-certificate` for the inner package download. For Let's Encrypt / imported certificates the normal flags are kept.

Clients therefore never fail silently on `curl -sL https://...` just because the server presents a self-signed cert. The tradeoff is that `-k` bypasses TLS verification for the install bootstrap — acceptable here because the token itself is the secret (32 hex, 5-minute TTL) and the user originally obtained the command from a page they already trusted.

## Caveats

- `cert-manager.sh` expects `CERT_ROOT` to be the same directory that is bind-mounted into Caddy. Default is `/opt/wg-easy/certs`; override only if you changed the compose file too.
- Port 80 must be free during ACME issuance. The manager stops Caddy for the duration and restarts it afterwards.
- Self-signed certs for IPs won't be trusted by most mobile browsers. For public deployments prefer the IP shortlived mode when a domain isn't available.
- `caddy reload` preserves open connections. If it fails (syntax error in Caddyfile) the manager falls back to `docker restart`.
- acme.sh data lives in `~/.acme.sh/` of the **remote root user**, not inside a container. A full `teardown.sh --purge` does not delete it.
