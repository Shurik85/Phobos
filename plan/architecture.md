# Целевая архитектура

## Проблема

На входе два независимых проекта:

1. **wg-easy** — Node.js/Nuxt веб-панель для WireGuard. SQLite+Drizzle, аутентификация, per-client one-time-ссылки на скачивание `.conf`, Docker на Alpine.
2. **Phobos** — bash-обвязка над C-обфускатором `wg-obfuscator`. Поднимает на Ubuntu VPS: WG, обфускатор (UDP-прокси), `darkhttpd` для раздачи пакетов, cron-cleanup, интерактивное TUI-меню.

Оба управляют одними и теми же сущностями (WG-сервер, клиенты, ключи), но никак не связаны. Цель — единый продукт: web-UI wg-easy с обфускатором «из коробки» и единой поверхностью управления.

## Целевая архитектура

```
┌─────────────────────────── Docker container ────────────────────────────┐
│                                                                          │
│  /init  (s6-overlay pid 1)                                               │
│    │                                                                     │
│    ├── svc/node           node /app/server/index.mjs                     │
│    │        │                                                            │
│    │        ├─ HTTP :51821  — UI + REST API                              │
│    │        └─ invokes      — wg, wg-quick, s6-svc                       │
│    │                                                                     │
│    ├── svc/wg-obfuscator   xargs -a /run/wg-obfuscator.args              │
│    │                          /usr/local/bin/wg-obfuscator               │
│    │        │                                                            │
│    │        ▼                                                            │
│    │  UDP 0.0.0.0:<OBF_PORT>  ──────►  UDP 127.0.0.1:51820               │
│    │                                                                     │
│    └── WG-интерфейс wg0     127.0.0.1:51820 (bind-only-loopback via      │
│                              iptables в PostUp)                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
    ▲                                                    ▲
    │ HTTP :51821                                        │ UDP :<OBF_PORT>
    │                                                    │
┌───┴───────────┐                                 ┌──────┴─────────────┐
│  Администратор│                                 │  Клиенты           │
│  (браузер)    │                                 │  (роутеры, PC)     │
└───────────────┘                                 └────────────────────┘
```

## Компоненты и ответственности

| Компонент | Ответственность |
|-----------|-----------------|
| **Node.js / Nuxt** | UI, REST API, управление БД, генерация WG- и obfuscator-конфигов, сборка tar.gz, управление процессами через `s6-svc` |
| **s6-overlay** | Супервизор; запуск и перезапуск `node` и `wg-obfuscator`, graceful-shutdown, перенаправление сигналов |
| **wg-quick wg0** | WG-интерфейс; `ListenPort=51820` внутри контейнера, доступ только с `127.0.0.1` |
| **wg-obfuscator** | Внешняя UDP-точка входа; STUN-маскировка + XOR-обфускация; forward → `127.0.0.1:51820` |
| **SQLite (Drizzle)** | Перманентное хранилище: интерфейс с обфускатор-параметрами, клиенты, install-tokens |
| **In-memory cache** | Собранные tar.gz пакеты (`PhobosPackage.#cache`) |

## Поток провиженинга клиента

```
Admin                 wg-easy UI/API           БД            Файлы              Процессы
─────                 ──────────────           ───           ─────              ────────
  │                                                                                │
  │  New Client       │                                                            │
  ├──────────────────►│                                                            │
  │                   │   INSERT client       │                                    │
  │                   ├──────────────────────►│                                    │
  │                   │                       │                                    │
  │                   │   wg.sync()                                                │
  │                   ├──────────────────────────────────────────────────────────► │
  │                   │                                                            │
  │  copy install     │                                                            │
  │  link (click OTL) │                                                            │
  ├──────────────────►│                                                            │
  │                   │   INSERT installLink  │                                    │
  │                   ├──────────────────────►│                                    │
  │◄──────────────────┤                                                            │
  │   token (TTL 5m)  │                                                            │
  │                                                                                │
  │   clipboard: curl -sL http://<origin>/api/install/<token> | sh                 │
  │                                                                                │
  ▼ (пересылает ссылку на роутер)
                                                       Роутер
                                                       ──────
                                                       │  curl → install.sh
                                                       ├─ GET /api/install/<token>
                                                       │  → install.sh
                                                       ├─ GET /api/install/<token>/package.tar.gz
                                                       │  → tar.gz (собран on-demand из cache)
                                                       ├─ tar xz → ./install-router.sh
                                                       └─ detect platform → install обфускатор + WG
```

## Поток трафика (runtime)

```
Клиентское устройство               Сервер (Docker)
───────────────────────             ─────────────────

app ──► 127.0.0.1:13255             0.0.0.0:<OBF_PORT>
   (локальный                         (wg-obfuscator server)
    wg/wg-quick)                          │
      │                                   │  STUN unwrap + XOR decode
      │ plain WG                          ▼
      ▼                                127.0.0.1:51820
 127.0.0.1:13255                         (wg0)
 (wg-obfuscator client)                    │
      │                                    │  WG декапсуляция
      │  XOR encode + STUN wrap            ▼
      ▼                                 iptables FORWARD → внешний интерфейс
 UDP → <server_ip>:<OBF_PORT>               │
                                            ▼
                                      Интернет
```

Обратный путь симметричен.

## Поверхность хранения

### Персистентная (SQLite)

| Таблица | Назначение |
|---------|------------|
| `interfaces_table` | Единственная запись интерфейса + обфускатор-параметры |
| `clients_table` | WG-peers |
| `install_links_table` | Токены для публичной раздачи установочных пакетов |
| `users_table`, `user_config_table`, `hooks_table` | Без изменений |

### In-memory

| Структура | Назначение |
|-----------|------------|
| `PhobosPackage.#cache: Map<ID, Buffer>` | Последний собранный tar.gz на клиента |
| `Obfuscator.#lastWrittenHash` | SHA-256 предыдущего содержимого args-файла (опционально, для избежания лишних перезапусков) |

### Файловая система контейнера

| Путь | Назначение |
|------|------------|
| `/run/wg-obfuscator.args` | Список CLI-аргументов для обфускатора (один на строку, 0600); перезаписывается Node; `xargs -a` передаёт в `wg-obfuscator` |
| `/etc/wireguard/wg0.conf` | WG-конфиг (как сейчас) |
| `/etc/amnezia/amneziawg/wg0.conf` | Симлинк (как сейчас) |
| `/app/phobos/bin/wg-obfuscator-*` | Multi-arch бинари (RO) |
| `/app/phobos/templates/*` | Shell-шаблоны клиентской стороны (RO) |
| `/etc/s6-overlay/s6-rc.d/{node,wg-obfuscator}/` | Service-каталоги s6 |

## Принципы

1. **Obfuscator always-on** — нет toggle, нет fallback на открытый WG.
2. **Один обфускатор на все интерфейсы** — multi-instance `[section]` в конфиге пока не используется, но структура остаётся совместимой.
3. **Single-source-of-truth** — все настройки obfuscator хранятся в `interfaces_table`; файл `/etc/wg-obfuscator.conf` регенерируется из БД при любом изменении.
4. **Zero persistent files** для пакетов — tar.gz живёт только в RAM (`PhobosPackage.#cache`), пересобирается по инвалидации.
5. **Token → client_id**, не `token → frozen package` — старый токен после ребилда пакета ведёт на свежий tarball.
6. **Loopback-only WG** — внешний UDP доступ только через обфускатор.
