# Фаза 1 — Docker-образ и s6-overlay

## Цели

1. В образ включить prebuilt `wg-obfuscator` и shell-шаблоны.
2. Заменить `dumb-init` на s6-overlay для управления двумя долгоживущими процессами.
3. `docker-compose.yml` перевести на обфускаторный UDP-порт, убрать публикацию `51820`.

## Версия s6-overlay

Используется `s6-overlay` 3.x (release-тarball, musl-совместимый). Качается с `https://github.com/just-containers/s6-overlay/releases/download/v3.2.0.2/`. Версия закрепляется в переменной `S6_OVERLAY_VERSION` в build-stage.

## Dockerfile (итоговый вид)

```dockerfile
FROM docker.io/library/node:krypton-alpine AS build
WORKDIR /app

RUN npm install --global corepack@latest
RUN corepack enable pnpm

COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install

COPY src ./
RUN pnpm build

RUN apk add linux-headers build-base go git && \
    git clone https://github.com/amnezia-vpn/amneziawg-tools.git && \
    git clone https://github.com/amnezia-vpn/amneziawg-go && \
    cd amneziawg-go && make && \
    cd ../amneziawg-tools/src && make

FROM docker.io/library/node:krypton-alpine
WORKDIR /app

ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TARGETARCH

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm /tmp/s6-overlay-*.tar.xz

HEALTHCHECK --interval=1m --timeout=5s --retries=3 CMD \
    /usr/bin/timeout 5s /bin/sh -c \
    "/usr/bin/wg show | /bin/grep -q interface && /usr/bin/pgrep wg-obfuscator >/dev/null || exit 1"

COPY --from=build /app/.output /app
COPY --from=build /app/server/database/migrations /app/server/database/migrations
COPY src/phobos-obfuscator/bin /app/phobos/bin
COPY src/server/phobos/templates /app/phobos/templates

RUN cd /app/server && \
    npm install --no-save --omit=dev libsql && \
    npm cache clean --force

COPY --from=build /app/cli/cli.sh /usr/local/bin/cli
RUN chmod +x /usr/local/bin/cli

COPY --from=build /app/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go
COPY --from=build /app/amneziawg-tools/src/wg /usr/bin/awg
COPY --from=build /app/amneziawg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick
RUN chmod +x /usr/bin/amneziawg-go /usr/bin/awg /usr/bin/awg-quick

RUN apk add --no-cache \
    dpkg iptables ip6tables nftables kmod \
    iptables-legacy wireguard-go wireguard-tools

RUN mkdir -p /etc/amnezia && \
    ln -s /etc/wireguard /etc/amnezia/amneziawg

RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 \
    --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore \
    --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save && \
    update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 \
    --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore \
    --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

RUN ARCH=$(uname -m) && \
    ln -sf /app/phobos/bin/wg-obfuscator-${ARCH} /usr/local/bin/wg-obfuscator && \
    chmod +x /app/phobos/bin/wg-obfuscator-*

COPY docker/s6-rc.d /etc/s6-overlay/s6-rc.d

ENV DEBUG=Server,WireGuard,Database,CMD,Obfuscator
ENV PORT=51821
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false
ENV DISABLE_IPV6=false
ENV S6_KEEP_ENV=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000

LABEL org.opencontainers.image.source=https://github.com/wg-easy/wg-easy

ENTRYPOINT ["/init"]
```

Ключевые изменения vs текущий `Dockerfile`:

| Было | Стало |
|------|-------|
| `CMD ["/usr/bin/dumb-init", "node", "server/index.mjs"]` | `ENTRYPOINT ["/init"]`, `CMD` пуст |
| Пакет `dumb-init` | Удалён |
| Один процесс | Два supervised процесса через s6-rc |
| HEALTHCHECK только WG | + проверка `pgrep wg-obfuscator` |
| — | `COPY src/phobos-obfuscator/bin` и `COPY src/server/phobos/templates` |
| — | Symlink `wg-obfuscator` под host-arch |

## Структура `docker/s6-rc.d/`

```
docker/s6-rc.d/
├── user/
│   └── contents.d/
│       ├── node
│       └── wg-obfuscator
├── node/
│   ├── type              → "longrun"
│   ├── run               → исполняемый скрипт
│   ├── dependencies.d/
│   │   └── base
│   └── finish            → cleanup при остановке
└── wg-obfuscator/
    ├── type              → "longrun"
    ├── run               → исполняемый скрипт
    ├── dependencies.d/
    │   └── base
    └── finish
```

### `node/type`

```
longrun
```

### `node/run`

```bash
#!/command/with-contenv sh
cd /app
exec node server/index.mjs
```

### `node/finish`

```bash
#!/command/execlineb -S0
foreground { s6-svscanctl -t /run/service }
exit 0
```

Если `node` падает — весь контейнер останавливается (main service).

### `wg-obfuscator/type`

```
longrun
```

### `wg-obfuscator/run`

```bash
#!/command/with-contenv sh

while [ ! -s /run/wg-obfuscator.args ]; do
  sleep 1
done

exec xargs -a /run/wg-obfuscator.args /usr/local/bin/wg-obfuscator
```

`wg-obfuscator` принимает все настройки через CLI-аргументы (см. `src/phobos-obfuscator/config.c`), отдельный ini-конфиг не нужен. Node пишет в `/run/wg-obfuscator.args` список аргументов (один на строку), s6 передаёт их через `xargs -a`. При любом изменении параметров Node перезаписывает файл и вызывает `s6-svc -r`.

### `wg-obfuscator/finish`

```bash
#!/command/execlineb -S0
exit 0
```

Падение обфускатора не останавливает весь контейнер — s6 перезапустит сервис. Политика рестартов по умолчанию (`s6-rc` infinite restart).

### `user/contents.d/`

Пустые файлы, включающие оба service в user-bundle:
- `user/contents.d/node`
- `user/contents.d/wg-obfuscator`

## Зависимости между сервисами

`node` и `wg-obfuscator` оба зависят от `base` (встроенный s6-bundle). Между собой — **не зависят**:

- `node` стартует первым, пишет `/run/wg-obfuscator.args` через `Obfuscator.Startup()`.
- `wg-obfuscator` ждёт появления файла аргументов в цикле (см. `run` выше).
- При изменениях параметров Node перезаписывает args-файл и вызывает `s6-svc -r /run/service/wg-obfuscator`.

## Управление обфускатором из Node

```ts
await exec('s6-svc -r /run/service/wg-obfuscator');
```

Для dev-режима (без s6) — fallback:

```ts
const SERVICE_PATH = '/run/service/wg-obfuscator';
const hasS6 = existsSync(SERVICE_PATH);
if (hasS6) {
  await exec(`s6-svc -r ${SERVICE_PATH}`);
} else {
  OBFUSCATOR_DEBUG('s6 not available, skipping restart');
}
```

## docker-compose.yml

### Было

```yaml
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
```

### Стало

```yaml
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    environment:
      - OBF_PORT=${OBF_PORT:-51822}
    ports:
      - "${OBF_PORT:-51822}:${OBF_PORT:-51822}/udp"
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

volumes:
  etc_wireguard:
  sqlite_data:
```

Ключевые изменения:

| Было | Стало |
|------|-------|
| Порт `51820/udp` проброшен | Порт убран (WG слушает только loopback) |
| — | Добавлен `${OBF_PORT}/udp` (значение из `interfaces_table.obfuscatorExtPort`) |
| — | `OBF_PORT` env — для первоначального выбора (иначе Node может поменять значение и выбранный при старте контейнера порт разойдётся с фактическим) |

## Коллизия `OBF_PORT` env и DB-значения

Проблема: `docker-compose` publish port фиксирован при `up`; если Node регенерирует порт через админ-UI, publish-mapping останется на старом порту.

Решение:
1. `OBF_PORT` задаётся пользователем один раз (env в compose).
2. При первом старте Node читает `process.env.OBF_PORT` и сохраняет в `interfaces_table.obfuscatorExtPort`.
3. UI для смены порта **скрыт**, пока значение не совпадает с env. Детектируется проверкой `readEnvInt('OBF_PORT') !== iface.obfuscatorExtPort` → предупреждение в админке: «Чтобы сменить порт, обновите переменную `OBF_PORT` в compose и пересоздайте контейнер».
4. Кнопка `regenerateObfuscatorPort` при этом disabled.

## Healthcheck

```bash
/usr/bin/wg show | /bin/grep -q interface && \
/usr/bin/pgrep wg-obfuscator >/dev/null || exit 1
```

Альтернатива (более точная — проверка привязки порта):

```bash
/bin/ss -ulpn | /bin/grep -q ":$OBF_PORT" && \
/usr/bin/wg show | /bin/grep -q interface || exit 1
```

## Проверка фазы

```bash
docker build -t wg-easy-test .
docker run --rm --cap-add NET_ADMIN --cap-add SYS_MODULE \
  -e OBF_PORT=51822 -p 51821:51821 -p 51822:51822/udp \
  -v wg-test:/etc/wireguard wg-easy-test &

sleep 10
docker exec <id> s6-rc -u list           # → base, node, wg-obfuscator
docker exec <id> pgrep -a node           # → 1 процесс
docker exec <id> pgrep -a wg-obfuscator  # → ≥1 процесс
docker exec <id> cat /etc/wg-obfuscator.conf  # → [instance] ...
curl -s http://localhost:51821/          # → 200
```

## Результат фазы

- Коммит: `feat(docker): s6-overlay supervision for node + wg-obfuscator`
- Затронуто: `Dockerfile`, `docker-compose.yml`, `docker/s6-rc.d/**`
- Образ запускается, оба процесса supervised, healthcheck зелёный.
