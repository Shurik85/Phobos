# Фазы 9-10 — Вспомогательное и полная зачистка рудиментов

## Фаза 9. Вспомогательное

### 1. README проекта

Файл `/root/wg-easy/README.md` — переписать:

1. Заголовок: `wg-easy + Phobos obfuscator` (или оставить `wg-easy`, сделав обфускатор неотъемлемой частью).
2. Краткое описание: «WireGuard-панель с встроенным STUN-обфускатором. Трафик от клиента до сервера маскируется под STUN и XOR-шифруется — для обхода DPI в странах с блокировками.»
3. Quickstart:
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
       cap_add: [NET_ADMIN, SYS_MODULE]
       sysctls:
         - net.ipv4.ip_forward=1
         - net.ipv4.conf.all.src_valid_mark=1
   ```
4. Раздел «How it works» с ASCII-диаграммой из [architecture.md](./architecture.md).
5. Раздел «Client installation»: админ копирует install-команду из UI, вставляет на клиенте — всё остальное автоматически.
6. Раздел «Supported client platforms»:
   - Keenetic / Netcraze (Entware + RCI API)
   - OpenWrt / ImmortalWrt (opkg + UCI)
   - Debian / Ubuntu Linux (apt + systemd)
   - 3x-ui panels (SQLite integration)
7. Раздел «Obfuscator tuning»: таблица пресетов 1-5, как в MERGE_PLAN.
8. Убрать всё, что было в старом README про голый wg-easy: пошаговый мануал по добавлению клиентов без обфускатора, примеры `.conf` без loopback-Endpoint и т.д.

### 2. CHANGELOG

Файл `/root/wg-easy/CHANGELOG.md` — добавить entry:

```markdown
## [X.Y.Z] — 2026-04-22

### Breaking

- Merged Phobos obfuscator. All WireGuard traffic now goes through
  `wg-obfuscator` (STUN masking + XOR). External WG port is no longer
  exposed; only the obfuscator UDP port is published.
- OneTimeLink replaced with Install-Link: button copies a shell command
  that installs a full Phobos package on the client (WG config +
  per-platform installer + obfuscator binary).
- `/api/client/:id/configuration` removed. Use `/api/client/:id/package.tar.gz`
  for direct download or `/api/install/:token` for public install flow.

### Added

- `wg-obfuscator` binary bundled in the image for all 5 supported arches.
- s6-overlay process supervision (replaces dumb-init).
- Admin UI: obfuscator configuration page (level preset, key regenerate,
  masking mode, idle/dummy tuning).
- `PhobosPackage` service: builds per-client tar.gz with WG and obfuscator
  configs, multi-arch binaries, and platform-aware installers.

### Removed

- `dumb-init` package.
- `OneTimeLink` entity and `/clients/:otl` public route.
- All files under `Phobos/` (repo-merged).
```

### 3. `docker-compose.yml` и `docker-compose.dev.yml`

Изменения из Phase 1: убрать публикацию `51820/udp`, добавить `${OBF_PORT}/udp`. Файлы уже редактировались; здесь — проверка финального состояния.

### 4. Unit-тесты

Новые файлы в `src/test/unit/`:

- `Obfuscator.spec.ts` — см. Phase 3.
- `PhobosPackage.spec.ts` — см. Phase 4.
- `wgHelper.spec.ts` — обновить существующие + добавить проверки из Phase 5.
- `InstallLinkService.spec.ts` — проверка generate/getByToken/TTL.
- `routes.install.spec.ts` — integration-тест для `/api/install/:token` (404/410/200).

Проверка:

```bash
cd src
pnpm test
```

### 5. CLI

`src/cli/` — не трогаем (решение #12). Опциональная проверка, что CLI-команды не ссылаются на удалённые API:

```bash
grep -rn "configuration\|oneTimeLink" src/cli/
```

Если есть упоминания — заменить на новые endpoints либо удалить соответствующие команды.

## Фаза 10. Полная зачистка рудиментов

### 1. Критические грепы

После всех предыдущих фаз запустить последовательно:

```bash
cd /root/wg-easy

# Ни одного упоминания Phobos-каталога или скриптов
grep -rn "phobos-menu\|phobos-client\|phobos-http\|darkhttpd\|server\.env\|tokens\.json\|/opt/Phobos" \
  --include="*.ts" --include="*.vue" --include="*.json" --include="*.yml" \
  --include="Dockerfile*" src/ docs/ .

# Ни одного упоминания oneTimeLink
grep -rnw "oneTimeLink\|OneTimeLink\|one_time_links_table" \
  --include="*.ts" --include="*.vue" --include="*.json" --include="*.sql" \
  src/

# Ни одного упоминания dumb-init
grep -rn "dumb-init" Dockerfile* docker-compose*.yml

# Удалённые i18n-ключи
grep -rn "otlDesc\|downloadConfig" src/i18n/
```

Каждый вывод должен быть **пустым**. Единственное допустимое исключение — C-исходники в `src/phobos-obfuscator/` (они неприкосновенны).

### 2. Физическое отсутствие Phobos-каталога

```bash
test ! -d /root/wg-easy/Phobos   # → $? = 0
find / -maxdepth 5 -name "phobos-*.sh" 2>/dev/null  # пусто
```

### 3. Статический анализ

```bash
cd src

pnpm tsc --noEmit                 # без ошибок типов
pnpm lint                         # без no-unused-vars, no-unreachable
pnpm test                         # все тесты зелёные
```

### 4. Build и runtime-проверка образа

```bash
docker build -t wg-easy-final /root/wg-easy
docker run -d --name wg-easy-test \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  -e OBF_PORT=51822 -p 51821:51821 -p 51822:51822/udp \
  wg-easy-final

sleep 15

docker exec wg-easy-test s6-rc -u list
# ожидается: base, node, wg-obfuscator (и системные s6-*)

docker exec wg-easy-test pgrep -a wg-obfuscator
# процесс запущен

docker exec wg-easy-test cat /etc/wg-obfuscator.conf
# валидный ini

docker exec wg-easy-test ss -ulpn | grep 51822
# порт слушается

curl -sf http://localhost:51821/
# 200 OK

docker logs wg-easy-test | grep -i error
# ожидается: пусто
```

### 5. БД — соответствие схемы

```bash
docker exec wg-easy-test sqlite3 /app/server/data/db.sqlite ".schema" | grep -E "install_links_table|interfaces_table"
docker exec wg-easy-test sqlite3 /app/server/data/db.sqlite ".schema" | grep -q "one_time_links_table" && echo "FAIL: legacy table present" || echo "OK: no legacy table"
```

### 6. UI — orphan-компоненты

```bash
cd src
pnpm nuxt analyze
# В отчёте не должно быть chunks, не попадающих в граф import'ов
```

Ручная проверка:

```bash
grep -rn "OneTimeLink\.vue\|Config\.vue" src/app/  # убедиться, что старые упоминания очищены
ls src/app/components/Icons/ | while read f; do
  base=$(basename "$f" .vue)
  matches=$(grep -rn "Icons${base}\b" src/app/ | wc -l)
  [ "$matches" = "0" ] && echo "ORPHAN icon: $f"
done
```

### 7. Docker-compose — финальная форма

```bash
docker compose config
```

- `ports:` содержит только `${OBF_PORT}:${OBF_PORT}/udp` и `51821:51821/tcp`.
- Нет упоминаний `51820`.

### 8. Проверочный чек-лист (финальный)

Commit-гейт `chore: final purge — no legacy references` проходит, если **все** пункты зелёные:

- [ ] `find . -name "Phobos" -o -name "phobos-*.sh" -o -name "darkhttpd*"` → пусто.
- [ ] `grep -rnw "oneTimeLink\|OneTimeLink\|darkhttpd\|phobos-menu\|phobos-http\|server\.env" src/` → пусто.
- [ ] `pnpm tsc --noEmit && pnpm lint && pnpm test` → зелёно.
- [ ] `docker build .` проходит.
- [ ] `docker exec <id> s6-rc -u list` показывает `node` и `wg-obfuscator` (плюс системные).
- [ ] Healthcheck зелёный.
- [ ] `pnpm nuxt analyze` — без orphan-chunks.
- [ ] В `sqlite_master` нет таблиц, не описанных в актуальной схеме.
- [ ] Все i18n-файлы содержат одинаковый набор ключей (`jq keys` сравнение всех локалей).

### 9. i18n — сверка полноты

```bash
cd src/i18n/locales
for f in *.json; do
  echo "=== $f ==="
  jq -r 'paths | map(tostring) | join(".")' "$f" | sort > /tmp/$(basename $f .json).keys
done

diff /tmp/en.keys /tmp/ru.keys
diff /tmp/en.keys /tmp/de.keys
# ... и так для каждой локали
```

Различия означают, что в какой-то локали остались legacy-ключи или не добавлены новые.

## Результат фаз 9-10

- Коммиты:
  - `chore: purge legacy oneTimeLink flow and stale i18n`
  - `docs: rewrite README for integrated product`
  - `chore: final purge — no legacy references`
- После финального коммита — `git status` чистый, `git log --oneline` показывает ровно 13 коммитов из MERGE_PLAN.
