# Фаза 7 — Жизненный цикл и setup-флоу

## Цели

1. Интегрировать `Obfuscator.Startup()` в последовательность запуска Nitro после `WireGuard.Startup()`.
2. Обеспечить инвалидацию `PhobosPackage.#cache` и рестарт обфускатора при всех мутациях, влияющих на конфиг клиента или обфускатора.
3. В setup-флоу первого запуска задать начальные значения obfuscator-параметров.

## Плагин Startup

### Текущий код

`src/server/plugins/` содержит плагин Nitro, где вызывается `WireGuard.Startup()`. Найти файл:

```bash
grep -rn "WireGuard.Startup" src/server/plugins/
```

Ожидается `src/server/plugins/migrate.ts` или `startup.ts`.

### Изменение

```ts
import { WireGuard } from '#utils/WireGuard';
import { Obfuscator } from '#utils/Obfuscator';

export default defineNitroPlugin(async () => {
  await migrate();
  await WireGuard.Startup();
  await Obfuscator.Startup();
});
```

Порядок критичен:
1. `migrate()` — применение Drizzle-миграций.
2. `WireGuard.Startup()` — создаёт интерфейс по умолчанию в БД (если его нет), генерирует WG-ключи, пишет `/etc/wireguard/wg0.conf`, делает `wg-quick up wg0`.
3. `Obfuscator.Startup()` — на этом шаге в БД уже гарантированно есть интерфейс; генерирует obfuscator-параметры при первом запуске, пишет `/etc/wg-obfuscator.conf`, инициирует `s6-svc -r`.

## Инвалидация кэша пакетов

### Точки вызова

Ищем все места, где мутируется клиент или интерфейс:

```bash
grep -rn "clients.create\|clients.update\|clients.delete\|interfaces.update\|updateKeyPair\|changeCidr" src/server/
```

### Централизация

Вместо точечных `invalidate()` вызовов в каждом API-роуте — внести в сервисы репозиториев.

#### `src/server/database/repositories/client/service.ts`

```ts
import PhobosPackage from '#utils/PhobosPackage';

export class ClientService {
  // ... existing code

  async create(input: ClientCreateType): Promise<ClientType> {
    const created = await this.#statements.create.execute(input);
    return created;
  }

  async update(id: ID, patch: Partial<ClientType>): Promise<void> {
    await this.#statements.update.execute({ id, ...patch });
    PhobosPackage.invalidate(id);
  }

  async delete(id: ID): Promise<void> {
    await this.#statements.delete.execute({ id });
    PhobosPackage.invalidate(id);
  }
}
```

Для `create` инвалидация не нужна: кэша для нового ID ещё нет.

#### `src/server/database/repositories/interface/service.ts`

```ts
import { Obfuscator } from '#utils/Obfuscator';
import PhobosPackage from '#utils/PhobosPackage';

export class InterfaceService {
  // ... existing code

  async update(patch: Partial<InterfaceType>): Promise<void> {
    await this.#statements.update.execute(patch);
    PhobosPackage.invalidate();
  }

  async updateKeyPair(privateKey: string, publicKey: string): Promise<void> {
    await this.#statements.updateKeyPair.execute({ privateKey, publicKey });
    PhobosPackage.invalidate();
  }

  async changeCidr(ipv4Cidr: string, ipv6Cidr: string): Promise<void> {
    await this.#statements.changeCidr.execute({ ipv4Cidr, ipv6Cidr });
    PhobosPackage.invalidate();
  }
}
```

### Импортные циклы

`PhobosPackage.ts` уже импортирует `Database`, а `Database` (через `ClientService`) будет импортировать `PhobosPackage`. Это циклическая зависимость.

Решение: **не** импортировать `PhobosPackage` напрямую в сервисах; использовать паттерн event-emitter, либо вызывать инвалидацию **из API-слоя**:

#### Альтернатива (выбираем её)

Инвалидация остаётся в API-роутах / use-case функциях, а не в репозиториях:

- `src/server/api/admin/interface/index.post.ts` → после `Database.interfaces.update()` → `PhobosPackage.invalidate()` (уже в Phase 6).
- `src/server/api/admin/interface/cidr.post.ts` → после `Database.interfaces.changeCidr()` → `PhobosPackage.invalidate()`.
- `src/server/api/admin/interface/regenerateObfuscatorKey.post.ts` → уже в Phase 6.
- `src/server/api/client/[clientId]/index.post.ts` (update client) → `PhobosPackage.invalidate(id)`.
- `src/server/api/client/[clientId]/index.delete.ts` → `PhobosPackage.invalidate(id)` (после delete).
- `src/server/api/client/[clientId]/enable.post.ts`, `disable.post.ts` → инвалидировать не нужно (enable/disable не влияет на содержимое tarball'а).
- `src/server/api/client/index.post.ts` (create) → инвалидировать не нужно.

Эта стратегия явная: видно в API-коде, когда cache становится невалидным. Нет скрытой магии в репозиториях.

## Обязательные invalidate-точки

Сводная таблица:

| Endpoint | invalidate(id?) | Obfuscator.restart() |
|----------|-----------------|----------------------|
| `POST /api/client/:id` (update) | `invalidate(id)` | — |
| `DELETE /api/client/:id` | `invalidate(id)` | — |
| `POST /api/admin/interface` | полный `invalidate()` | если изменились obfuscator-поля |
| `POST /api/admin/interface/cidr` | полный `invalidate()` | — (CIDR не влияет на обфускатор) |
| `POST /api/admin/interface/restart` | полный `invalidate()` | `restart()` (WG-keys могли поменяться) |
| `POST /api/admin/interface/regenerateObfuscatorKey` | полный `invalidate()` | `restart()` |
| `POST /api/admin/interface/regenerateObfuscatorPort` | полный `invalidate()` | `restart()` |

## Setup-флоу

### Файл

`src/server/api/setup/` — существующие endpoints для первичной настройки (регистрация первого admin, создание интерфейса).

### Изменения

Найти endpoint, создающий интерфейс (`src/server/api/setup/*.post.ts`). При INSERT в `interfaces_table` дополнительно задавать начальные obfuscator-поля. Простейший путь — положиться на `Obfuscator.Startup()`:

- Setup кладёт стандартные поля (host, port=51820, WG-ключи).
- Obfuscator-поля инициализируются дефолтами из схемы (Phase 2): `obfuscatorExtPort=51822`, `obfuscatorKey=''`, `serverPublicIpV4=''`.
- При старте `Obfuscator.Startup()` видит пустые значения → выполняет init (generateKey, detectPublicIpV4, findFreePort или env).

Это не требует правок в setup API. Достаточно обеспечить, что **после** setup вызов `Obfuscator.Startup()` может пройти заново (уже описано — Startup идемпотентен).

### Альтернатива для свежей установки

Если пользователь проходит setup впервые в интерактивном режиме (UI), можно показывать obfuscator-параметры на setup-странице с возможностью переопределить. Это опциональное улучшение; базовый путь — autogen на Startup.

## Завершение работы

При остановке контейнера `s6-overlay` по умолчанию корректно останавливает все service'ы. Никакой специальной логики shutdown в Node не требуется.

Если Node падает — `node/finish` останавливает весь контейнер через `s6-svscanctl -t`, `wg-obfuscator` будет также остановлен.

## Проверка фазы

### Startup

```bash
docker compose up --build
docker compose logs | grep -i obfuscator
# → "Starting Obfuscator..." "First-run initialization" "Obfuscator started"
```

### Генерация и установка

```bash
TOKEN=$(curl -s -X POST -H "Cookie: ..." http://localhost:51821/api/client/1/generateInstallLink | jq -r .token)
curl -s http://localhost:51821/api/install/$TOKEN
# → валидный install.sh
```

### Инвалидация при смене порта

```bash
# 1. Получить текущий tarball
curl -sL -o /tmp/a.tar.gz http://localhost:51821/api/install/$TOKEN/package.tar.gz
sha256sum /tmp/a.tar.gz

# 2. Сменить ключ
curl -X POST -H "Cookie: ..." http://localhost:51821/api/admin/interface/regenerateObfuscatorKey

# 3. Снова скачать tarball по ТОМУ ЖЕ токену
curl -sL -o /tmp/b.tar.gz http://localhost:51821/api/install/$TOKEN/package.tar.gz
sha256sum /tmp/b.tar.gz

# → хэши должны отличаться (старый токен ведёт на новый tarball)
```

### s6 restart

```bash
docker exec <id> s6-svstat /run/service/wg-obfuscator
# → ready, pid >0, uptime

curl -X POST -H "Cookie: ..." http://localhost:51821/api/admin/interface/regenerateObfuscatorKey

docker exec <id> s6-svstat /run/service/wg-obfuscator
# → pid изменился, uptime сброшен
```

## Результат фазы

- Коммит входит в состав API-коммитов (7,8) и в плагин Startup.
- После фазы 7 система работоспособна end-to-end: UI + API + обфускатор + WG + install-ссылки.
