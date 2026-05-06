# Фаза 2 — Схема БД и миграция

## Изменения в `wgInterface`

### Файл

`src/server/database/repositories/interface/schema.ts`

### Добавляемые колонки

```ts
export const wgInterface = sqliteTable('interfaces_table', {
  // ... существующие поля остаются без изменений

  obfuscatorExtPort: int('obfuscator_ext_port').notNull().unique(),
  obfuscatorKey: text('obfuscator_key').notNull(),
  obfuscatorMasking: text('obfuscator_masking', {
    enum: ['STUN', 'AUTO', 'NONE'],
  })
    .notNull()
    .default('STUN'),
  obfuscatorIdle: int('obfuscator_idle').notNull().default(300),
  obfuscatorDummy: int('obfuscator_dummy').notNull().default(10),
  obfuscatorLevel: int('obfuscator_level').notNull().default(2),
  serverPublicIpV4: text('server_public_ip_v4').notNull(),
  serverPublicIpV6: text('server_public_ip_v6'),
  clientWgLocalPort: int('client_wg_local_port').notNull().default(13255),
});
```

### Зачем каждое поле

| Поле | Использование |
|------|---------------|
| `obfuscatorExtPort` | Публичный UDP-порт обфускатора на сервере; попадает в `source-lport` серверного `wg-obfuscator.conf` и в `target=<ip>:<port>` клиентского |
| `obfuscatorKey` | XOR-ключ; одинаков на сервере и всех клиентах |
| `obfuscatorMasking` | STUN/AUTO/NONE — режим маскировки |
| `obfuscatorIdle` | Таймаут неактивного клиента (сек) в `wg-obfuscator.conf` |
| `obfuscatorDummy` | `max-dummy` байт случайного паддинга в пакете |
| `obfuscatorLevel` | Индекс пресета 1-5; драйвит `keyLen`/`maxDummy` при `regenerate` |
| `serverPublicIpV4` | Подставляется в `target` клиентского конфига; автодетект при `setup` |
| `serverPublicIpV6` | IPv6-вариант, опциональный |
| `clientWgLocalPort` | Порт локального обфускатора на стороне клиента (`source-lport` клиентского); в клиентском WG-конфиге `Endpoint = 127.0.0.1:<этот порт>` |

### Валидация в Zod-схеме

`src/server/database/repositories/interface/types.ts`:

```ts
export const InterfaceUpdateSchema = z.object({
  // ... существующие
  obfuscatorExtPort: z.number().int().min(1024).max(49151),
  obfuscatorKey: z.string().min(3).max(255),
  obfuscatorMasking: z.enum(['STUN', 'AUTO', 'NONE']),
  obfuscatorIdle: z.number().int().min(30).max(3600),
  obfuscatorDummy: z.number().int().min(0).max(255),
  obfuscatorLevel: z.number().int().min(1).max(5),
  serverPublicIpV4: z.string().ip({ version: 'v4' }),
  serverPublicIpV6: z.string().ip({ version: 'v6' }).nullable(),
  clientWgLocalPort: z.number().int().min(1024).max(65535),
});
```

## Таблица `installLink` (переименование из `oneTimeLink`)

### Файл

`src/server/database/repositories/installLink/schema.ts`

### Схема

```ts
import { sql, relations } from 'drizzle-orm';
import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { client } from '../../schema';

export const installLink = sqliteTable('install_links_table', {
  id: int()
    .primaryKey()
    .references(() => client.id, {
      onDelete: 'cascade',
      onUpdate: 'cascade',
    }),
  token: text().notNull().unique(),
  expiresAt: text('expires_at').notNull(),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`)
    .$onUpdate(() => sql`(CURRENT_TIMESTAMP)`),
});

export const installLinksRelations = relations(installLink, ({ one }) => ({
  client: one(client, {
    fields: [installLink.id],
    references: [client.id],
  }),
}));
```

Ключевые отличия от старого `oneTimeLink`:
- Название таблицы: `install_links_table` (было `one_time_links_table`).
- Поле `one_time_link` → `token`.
- Связь с `client` через relation `installLink` (заменяет `oneTimeLink` в `clientsRelations`).

### Обновление `clientsRelations`

`src/server/database/repositories/client/schema.ts`:

```ts
export const clientsRelations = relations(client, ({ one }) => ({
  installLink: one(installLink, {
    fields: [client.id],
    references: [installLink.id],
  }),
  user: one(user, { ... }),
  interface: one(wgInterface, { ... }),
}));
```

### Сервис

`src/server/database/repositories/installLink/service.ts`:

```ts
import { eq, sql } from 'drizzle-orm';
import { randomBytes, createHash } from 'node:crypto';
import { installLink } from './schema';
import type { DBType } from '#db/sqlite';

const TTL_MS = 5 * 60 * 1000;

function createPreparedStatement(db: DBType) {
  return {
    delete: db
      .delete(installLink)
      .where(eq(installLink.id, sql.placeholder('id')))
      .prepare(),
    create: db
      .insert(installLink)
      .values({
        id: sql.placeholder('id'),
        token: sql.placeholder('token'),
        expiresAt: sql.placeholder('expiresAt'),
      })
      .onConflictDoUpdate({
        target: installLink.id,
        set: {
          token: sql.placeholder('token') as never as string,
          expiresAt: sql.placeholder('expiresAt') as never as string,
        },
      })
      .prepare(),
    findByToken: db.query.installLink
      .findFirst({
        where: eq(installLink.token, sql.placeholder('token')),
      })
      .prepare(),
  };
}

export class InstallLinkService {
  #statements: ReturnType<typeof createPreparedStatement>;

  constructor(db: DBType) {
    this.#statements = createPreparedStatement(db);
  }

  delete(id: ID) {
    return this.#statements.delete.execute({ id });
  }

  getByToken(token: string) {
    return this.#statements.findByToken.execute({ token });
  }

  async generate(id: ID) {
    const token = createHash('sha256')
      .update(randomBytes(32))
      .digest('hex')
      .slice(0, 32);
    const expiresAt = new Date(Date.now() + TTL_MS).toISOString();
    await this.#statements.create.execute({ id, token, expiresAt });
    return { token, expiresAt };
  }
}
```

Отличия от `OneTimeLinkService`:
- Метод `generate` возвращает `{ token, expiresAt }` (не void) — нужен для UI-ответа.
- Алгоритм генерации: sha256 от `randomBytes(32)` → 32 hex-символа (замена CRC32 для криптографической стойкости, хотя токен не требует её строго).
- Убран метод `erase` (аналог «истёк вот-вот») — не нужен в новом флоу.

### Типы

`src/server/database/repositories/installLink/types.ts`:

```ts
import { z } from 'zod';
import { createSelectSchema } from 'drizzle-zod';
import { installLink } from './schema';

export const InstallLinkSchema = createSelectSchema(installLink);
export type InstallLinkType = z.infer<typeof InstallLinkSchema>;

export const InstallTokenParamSchema = z.object({
  token: z.string().length(32).regex(/^[a-f0-9]{32}$/),
});
```

## Обновление `schema.ts` (корневой)

`src/server/database/schema.ts`:

```ts
// Было:
// export * from './repositories/oneTimeLink/schema';

// Стало:
export * from './repositories/installLink/schema';
```

И все другие импорты на уровне пакета.

## Обновление `Database.ts`

`src/server/utils/Database.ts`:

```ts
// Было:
// oneTimeLinks: new OneTimeLinkService(db),

// Стало:
installLinks: new InstallLinkService(db),
```

## Миграция Drizzle

Команда:

```bash
cd src
pnpm drizzle-kit generate
```

Ожидаемый SQL (в новом файле миграции):

```sql
ALTER TABLE `interfaces_table` ADD `obfuscator_ext_port` integer NOT NULL DEFAULT 51822 UNIQUE;
ALTER TABLE `interfaces_table` ADD `obfuscator_key` text NOT NULL DEFAULT '';
ALTER TABLE `interfaces_table` ADD `obfuscator_masking` text NOT NULL DEFAULT 'STUN';
ALTER TABLE `interfaces_table` ADD `obfuscator_idle` integer NOT NULL DEFAULT 300;
ALTER TABLE `interfaces_table` ADD `obfuscator_dummy` integer NOT NULL DEFAULT 10;
ALTER TABLE `interfaces_table` ADD `obfuscator_level` integer NOT NULL DEFAULT 2;
ALTER TABLE `interfaces_table` ADD `server_public_ip_v4` text NOT NULL DEFAULT '';
ALTER TABLE `interfaces_table` ADD `server_public_ip_v6` text;
ALTER TABLE `interfaces_table` ADD `client_wg_local_port` integer NOT NULL DEFAULT 13255;

DROP TABLE `one_time_links_table`;

CREATE TABLE `install_links_table` (
  `id` integer PRIMARY KEY NOT NULL,
  `token` text NOT NULL,
  `expires_at` text NOT NULL,
  `created_at` text NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  `updated_at` text NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY (`id`) REFERENCES `clients_table`(`id`) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE UNIQUE INDEX `install_links_table_token_unique` ON `install_links_table` (`token`);
```

Автогенерированная миграция может потребовать ручной правки, т.к. Drizzle не всегда корректно обрабатывает переименование таблиц — часто генерирует `DROP + CREATE`. Это приемлемо, так как старые токены при миграции и не должны переживать (политика no backwards-compat).

## Default values для существующих записей

При `ALTER TABLE ... ADD COLUMN NOT NULL DEFAULT` sqlite требует явного значения. Поля:
- `obfuscator_ext_port` — дефолт 51822 (будет перезаписан при первом `Obfuscator.Startup`).
- `obfuscator_key` — дефолт `''`, перезаписывается тем же Startup (генерируется случайный).
- `server_public_ip_v4` — дефолт `''`, перезаписывается autodetect.

Обработка в коде: при `Obfuscator.Startup()` если `!iface.obfuscatorKey || !iface.serverPublicIpV4`, выполнить инициализацию (generate key, detect IP) и сохранить.

## Удаление `oneTimeLink`

Удалить каталог `src/server/database/repositories/oneTimeLink/` целиком:
- `schema.ts`
- `service.ts`
- `types.ts`

## Проверка фазы

```bash
cd src
pnpm drizzle-kit generate   # миграция сгенерирована, SQL валиден
pnpm tsc --noEmit           # компилируется
pnpm dev                    # Startup проходит, Database содержит installLinks
```

Запрос к БД:

```bash
sqlite3 src/server/data/db.sqlite ".schema install_links_table"
sqlite3 src/server/data/db.sqlite ".schema interfaces_table" | grep obfuscator
```

## Результат фазы

- Коммит: `feat(db): add obfuscator fields to interface, rename oneTimeLink to installLink`
- Затронуто: `src/server/database/**`, `src/server/utils/Database.ts`.
- Миграция автоматически применяется при старте Node (существующий pipeline Nitro).
