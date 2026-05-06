# Фаза 0 — Реорганизация репозитория

## Исходное дерево (фрагмент)

```
/root/wg-easy/
├── src/                              # wg-easy Nuxt проект
│   ├── app/
│   ├── server/
│   └── ...
├── Phobos/
│   ├── CLAUDE.md
│   ├── README.md
│   ├── phobos-deploy.sh
│   ├── client/
│   │   └── templates/
│   │       ├── 3xui.sh
│   │       ├── detect-router-arch.sh
│   │       ├── install-obfuscator.sh
│   │       ├── install-router.sh.template
│   │       ├── install-wireguard.sh
│   │       ├── lib-client.sh
│   │       ├── phobos-uninstall.sh
│   │       ├── router-configure-wireguard-openwrt.sh
│   │       └── router-configure-wireguard.sh
│   ├── docs/
│   │   └── bugfix-peer-management.md
│   ├── server/
│   │   └── scripts/              # bash-пакет установщика
│   └── wg-obfuscator/            # C-проект
│       ├── bin/                  # prebuilt multi-arch
│       ├── *.c, *.h, Makefile
│       └── wg-obfuscator.service
```

## Целевое дерево

```
/root/wg-easy/
├── src/
│   ├── phobos-obfuscator/        # перенесён as-is из Phobos/wg-obfuscator
│   │   ├── bin/
│   │   ├── *.c, *.h, Makefile
│   │   └── ...
│   └── server/
│       └── phobos/
│           └── templates/         # перенесён из Phobos/client/templates
│               ├── 3xui.sh
│               ├── detect-router-arch.sh
│               ├── install-obfuscator.sh
│               ├── install-router.sh.template
│               ├── install-wireguard.sh
│               ├── lib-client.sh
│               ├── phobos-uninstall.sh
│               ├── router-configure-wireguard-openwrt.sh
│               └── router-configure-wireguard.sh
└── MERGE_PLAN.md
└── plan/
```

Каталог `Phobos/` удаляется целиком.

## Команды миграции

```bash
cd /root/wg-easy
git mv Phobos/wg-obfuscator src/phobos-obfuscator
mkdir -p src/server/phobos
git mv Phobos/client/templates src/server/phobos/templates
git rm -r Phobos/server
git rm -r Phobos/docs
git rm Phobos/README.md
git rm Phobos/CLAUDE.md
git rm Phobos/phobos-deploy.sh
rmdir Phobos/client
rmdir Phobos
```

## Что удаляется полностью

| Путь | Причина |
|------|---------|
| `Phobos/server/scripts/lib-core.sh` | Env-loader; конфиг перенесён в БД |
| `Phobos/server/scripts/phobos-installer.sh` | VPS-установка заменена Dockerfile + s6 |
| `Phobos/server/scripts/phobos-menu.sh` | TUI-меню заменено web-UI |
| `Phobos/server/scripts/phobos-client.sh` | CRUD клиентов — в `clientsService` + `PhobosPackage` |
| `Phobos/server/scripts/phobos-system.sh` | status/monitor/cleanup — заменяется healthcheck + invalidate |
| `Phobos/server/scripts/vps-build-obfuscator.sh` | Копирование бинарей — через `Dockerfile COPY` |
| `Phobos/server/scripts/vps-obfuscator-config.sh` | Интерактивный редактор — заменён админ-страницей |
| `Phobos/server/scripts/vps-uninstall.sh` | Удаление контейнера — `docker compose down` |
| `Phobos/docs/bugfix-peer-management.md` | Исторический документ, неактуален |
| `Phobos/README.md`, `Phobos/CLAUDE.md` | Документация отдельного проекта |
| `Phobos/phobos-deploy.sh` | Bootstrap-скрипт VPS |

## Что сохраняется as-is

### `src/phobos-obfuscator/`

Неприкосновенно (решение пользователя). В том числе:
- `wg-obfuscator.c`, `*.h` — C-исходники.
- `Makefile`, `build-all-architectures.sh` — сборочная инфраструктура.
- `bin/wg-obfuscator-{x86_64,aarch64,armv7,mips,mipsel}` — prebuilt бинари.
- `wg-obfuscator.service` — не используется (systemd заменён s6), но остаётся в дереве как артефакт C-проекта.
- `wg-obfuscator.conf` (референс) — остаётся как пример.

### `src/server/phobos/templates/`

Shell-шаблоны клиентской стороны. Используются `PhobosPackage` при сборке tarball'а. Логика `{{CLIENT_NAME}}`-подстановки переносится в TS-код (`PhobosPackage.build`), но сами шаблоны остаются без правок текста.

## Импакт на импорт-пути в коде

После перемещения:
- В Node.js коде обращение идёт по абсолютному пути внутри образа (`/app/phobos/bin`, `/app/phobos/templates`) — см. `phase-01-docker.md`.
- В dev-режиме (локальный запуск) использовать `fileURLToPath(import.meta.url)` + относительный путь к `src/phobos-obfuscator/bin` и `src/server/phobos/templates`. Конкретная обёртка описана в `phase-04-package.md`.

## Проверка

После Фазы 0:

```bash
test ! -d /root/wg-easy/Phobos              # не существует
test -d /root/wg-easy/src/phobos-obfuscator
test -d /root/wg-easy/src/server/phobos/templates
git status                                   # renames, без диффов контента
```

## Результат фазы

- Коммит: `chore: relocate phobos obfuscator and templates into src tree`
- Затронуто: `Phobos/*`, `src/phobos-obfuscator/*`, `src/server/phobos/templates/*` (renames).
- Функциональных правок нет.
