# Прогресс реализации

Дата старта: 2026-04-22.

| Фаза | Статус | Результат |
|------|--------|-----------|
| 0. Реорганизация репозитория | ✅ | `Phobos/` удалён; `src/phobos-obfuscator/`, `src/server/phobos/templates/` созданы |
| 1. Docker + s6-overlay | ✅ | Dockerfile переписан, `docker/s6-rc.d/` создан, docker-compose использует `OBF_PORT` |
| 2. Схема БД и миграция | ✅ | `interfaces_table` расширен; `one_time_links_table` → `install_links_table`; миграция `0005_phobos_integration.sql` |
| 3. Obfuscator сервис | ✅ | `src/server/utils/Obfuscator.ts`; встроен в `Database.ts` Startup; параметры передаются через CLI (`/run/wg-obfuscator.args`), отдельный ini‑конфиг не создаётся |
| 4. PhobosPackage | ✅ | `src/server/utils/PhobosPackage.ts`; в `package.json` добавлен `tar-stream`; убран `crc-32` |
| 5. wgHelper изменения | ✅ | Endpoint клиента → loopback; iptables DROP non-loopback в PostUp |
| 6. API endpoints | ✅ | `install/[token]/*`, `generateInstallLink`, `package.tar.gz`, `regenerateObfuscatorKey/Port`; OTL и `configuration` удалены |
| 7. Lifecycle | ✅ | `Obfuscator.Startup` встроен; invalidate в update/delete client, cidr, restart |
| 8. UI | ✅ | `InstallLinkBtn.vue`, обновлён `Config.vue`, админ‑страница с блоком Obfuscator; i18n обновлены во всех локалях |
| 9-10. Cleanup и docs | ✅ | README переписан; CHANGELOG с breaking-секцией; legacy‑грепы пусты |

## Отклонения от исходного плана (применённые не запланированные решения)

1. **SQL‑миграция написана вручную** (`0005_phobos_integration.sql`), без запуска `drizzle-kit generate`, потому что в среде выполнения drizzle‑kit недоступен. `meta/_journal.json` дополнен записью вручную. `meta/0005_snapshot.json` не создаётся — drizzle использует его только для генерации следующих миграций.

2. **Дефолтные значения для новых колонок интерфейса** заданы прямо в Drizzle‑схеме (`interfaces_table`), а не только в SQL‑миграции. Это упрощает первичную вставку через `initialSetup` без необходимости модификации существующих `INSERT` в других местах.

3. **`Obfuscator.Startup` интегрирован в `src/server/utils/Database.ts`** (после `WireGuard.Startup()`), а не в отдельный плагин `src/server/plugins/*`, потому что именно там исторически вызывается `WireGuard.Startup()`. Файл `plugins/manager.ts` управляет только `close`‑хуком и изменению не подвергался.

4. **Имя компонента `OneTimeLinkBtn.vue` переименовано в `InstallLinkBtn.vue`** (ref: phase-08 раздел «Переименование компонента (опционально)»). Устраняет рудимент в именах.

5. **Инвалидация `PhobosPackage.#cache` вызывается из API‑роутов**, а не из репозиториев (чтобы избежать циклической зависимости Database↔PhobosPackage). Это строго следует альтернативе, описанной в `phase-07-lifecycle.md`.

6. **Добавлен флаг `obfuscatorPortPinned` в `/api/information`** (а не в `/api/admin/general.get.ts`, как в плане), потому что `globalStore` в UI уже потребляет `/api/information`. Это экономит один лишний fetch и использует существующий реактивный стор.

7. **`PhobosPackage.build` читает `iface.port` вместо жёстко зашитого `51820`** для `target` серверного `wg-obfuscator.conf` — это делает конфиг корректным, если в БД у интерфейса другой порт.

8. **Клиентские компоненты `Config.vue`/`InstallLinkBtn.vue` используют существующий стор `useToast`** (метод `showToast`), а не гипотетический `toast.success/error`.

9. **Убрана зависимость `crc-32`** из `src/package.json` — старый `OneTimeLinkService` был единственным потребителем. Новый токен генерируется через `crypto.randomBytes` + `sha256`.

10. **В `InterfaceService.update` изменена сигнатура на `Partial<InterfaceUpdateType>`** — необходимо для частичных обновлений из `Obfuscator.Startup` и `regenerate*` endpoints.

11. **s6 service-файлы `user/contents.d/node` и `user/contents.d/wg-obfuscator`** созданы пустыми (формат s6 их и ожидает: само наличие файла включает сервис в bundle).

12. **i18n для локалей кроме en/ru** автоматически заполнены английскими строками для новых ключей — так сохранена структура. Переводы можно улучшать отдельно.

13. **Обфускатор запускается через CLI-аргументы, а не ini-файл** (`wg-obfuscator.c`/`config.c` поддерживают оба способа). `Obfuscator.writeArgs` пишет `/run/wg-obfuscator.args` (mode 0600, по одному аргументу на строку), s6-run использует `xargs -a`. Это убирает отдельный конфиг-файл и упрощает lifecycle. Компромисс — ключ виден через `ps` внутри контейнера; для wg-easy (всё работает от root, нет других процессов) это не деградация по сравнению с файлом 0600. Метод `writeConfig` заменён на `apply` (`writeArgs` + `restart`) во всех API-роутах.

14. **В s6-run для `wg-obfuscator` используется `[ ! -s ]`** (ждём непустой файл) — защита от race, если Node успел создать файл, но ещё не записал содержимое.

15. **Dockerfile делает `chmod +x`** на `run`/`finish` s6-скриптах после COPY — копирование из git не гарантирует сохранение executable-бита.

16. **libsql musl-вариант подтягивается в runtime-stage через прямое скачивание npm-tarball** (`wget | tar xz`), а не `npm install @libsql/linux-x64-musl`: штатный `npm install` валится с `Cannot read properties of null (reading 'fsTop')` на крупном `package.json` nitro-вывода. `pnpm install` в build-stage ставит только gnu-вариант (он работает на glibc build-стадии), musl для Alpine-рантайма добавляется отдельным шагом. Версия musl-пакета берётся из установленного gnu-пакета, чтобы варианты не расходились.

17. **Верхняя граница `OBF_PORT` поднята с 49151 до 65535** — изначально стояла «registered ports» граница IANA, но это исключало все «user-range» порты вроде 51822 из работы env-pinning (`obfuscatorPortPinned` всегда возвращался `false`). Синхронизированы: `Zod` schema, `findFreePort`, `information.get.ts`, `Obfuscator.Startup`, `regenerateObfuscatorPort.post.ts`.

18. **Двойной `;;` в PostUp/PreDown** — багаж от старого поведения `iptablesTemplate` (строки заканчиваются на `;`) + моего `join('; ')`: получалось `...-j ACCEPT;; iptables -I INPUT...` → `/usr/bin/wg-quick: eval: line 295: syntax error near unexpected token ';;'`. Исправлено хелпером `joinShell`, который нормализует trailing `;` у каждого фрагмента и склеивает через пробел.

19. **Шаг `npm install libsql` в runtime-stage удалён** — он был workaround для Nitro issue #3328, но теперь `.output/server/node_modules` уже содержит нужные `@libsql/*` пакеты после `pnpm build`; остаётся только добить musl-вариант (см. п. 16).

20. **Добавлены `scripts/deploy/*.sh`** (`setup-ssh`, `remote-deploy`, `update`, `logs`, `teardown`) и документация `docs/deployment.md` — рабочий процесс «чистый Ubuntu → развёрнутый wg-easy + Phobos» одной командой. Скрипты проверены на `94.232.40.58` (Ubuntu 22.04), контейнер поднимается в состояние `healthy`.

21. **HTTPS-профиль (`docker-compose.https.yml` + Caddy-sidecar)** — терминация TLS на `:443`, reverse-proxy на `wg-easy:51821`, 80→443 redirect. Caddyfile читает активные PEM из `/etc/caddy/certs/active/` (bind-mount от `/opt/wg-easy/certs/`).

22. **`scripts/cert/cert-manager.sh`** — адаптация функций `ssl_cert_issue*` из 3x-ui (`/root/3x-ui/source/x-ui.sh:985-1488`). Режимы: Let's Encrypt для домена, LE shortlived для IP, self-signed (openssl с SAN), импорт существующих PEM, list/show/activate/delete/reload. Активация через symlink `active → <name>`, перезагрузка через `docker exec caddy caddy reload` (zero-downtime), fallback на `docker restart` при ошибке. `scripts/deploy/certs.sh` — SSH-обёртка.

23. **Автоподхват cert-manager в `remote-deploy.sh --https`** — если нет `certs/active/`, скрипт открывает TUI на сервере через `ssh -t`, ждёт завершения, проверяет наличие cert и только потом запускает compose.

24. **Фикс тихого провала install-link при self-signed TLS** — `/api/information` отдаёт `tlsOrigin`/`tlsUntrusted` (читается при запросе из `/app/certs/active/origin`, примонтированного в контейнер read-only). `InstallLinkBtn.vue` и `PhobosPackage.installScript` добавляют `-k`/`--no-check-certificate` когда `tlsUntrusted === true`, иначе используют стандартные флаги. `src/server/utils/TlsInfo.ts` инкапсулирует чтение файла.

25. **`rsync --exclude certs`** в `remote-deploy.sh`/`update.sh` — без этого `--delete` уничтожал серверный каталог сертификатов при каждом апдейте.

## Не реализовано (осознанно)

- Unit‑тесты (`Obfuscator.spec.ts`, `PhobosPackage.spec.ts`, etc.) — план их рекомендует, но среда выполнения без pnpm/vitest, тесты лучше писать в активной dev‑среде.
- Ручная сборка образа (`docker build`) и e2e‑верификация — требуется Docker‑окружение.
- `pnpm tsc --noEmit` / `pnpm lint` — требуется установленный pnpm с локальными зависимостями.

Все артефакты на месте и структурно соответствуют плану. Остаётся собрать образ и прогнать приёмочные тесты.
