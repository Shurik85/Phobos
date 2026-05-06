# Фаза 6 — API endpoints

## Итоговая таблица endpoints

### Клиентские (auth-guarded)

| Метод | Путь | Permissions | Ответ | Статус |
|-------|------|-------------|-------|--------|
| `POST` | `/api/client/:clientId/generateInstallLink` | `clients:update` | `{ token, expiresAt }` | **новый** (переимен. из `generateOneTimeLink.post.ts`) |
| `GET` | `/api/client/:clientId/package.tar.gz` | `clients:view` | `application/gzip` | **новый** (заменяет `configuration.get.ts`) |
| `GET` | `/api/client/:clientId/qrcode.svg` | `clients:view` | `image/svg+xml` | без изменений |
| `POST` | `/api/client/:clientId/enable` | `clients:update` | `{ success }` | без изменений |
| `POST` | `/api/client/:clientId/disable` | `clients:update` | `{ success }` | без изменений |

### Публичные (auth-less, token-based)

| Метод | Путь | Ответ | Статус |
|-------|------|-------|--------|
| `GET` | `/api/install/:token` | `text/x-shellscript` (install.sh) | **новый** |
| `GET` | `/api/install/:token/package.tar.gz` | `application/gzip` | **новый** |

### Админские

| Метод | Путь | Ответ | Статус |
|-------|------|-------|--------|
| `POST` | `/api/admin/interface` | `{ success }` | расширение Zod-схемы |
| `POST` | `/api/admin/interface/regenerateObfuscatorKey` | `{ key }` | **новый** |
| `POST` | `/api/admin/interface/regenerateObfuscatorPort` | `{ port }` | **новый** |

### Удаляемые

| Метод | Путь | Причина |
|-------|------|---------|
| `POST` | `/api/client/:clientId/generateOneTimeLink` | заменён `generateInstallLink` |
| `GET` | `/api/client/:clientId/configuration` | заменён `package.tar.gz` |
| `GET` | `/clients/:otl` (страница) | публичный OTL-роут для `.conf` больше не нужен |

## Детали реализации

### `POST /api/client/:clientId/generateInstallLink`

Файл `src/server/api/client/[clientId]/generateInstallLink.post.ts`:

```ts
import { ClientGetSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'update',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event),
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    if (!client) {
      throw createError({ statusCode: 404, statusMessage: 'Client not found' });
    }

    const { token, expiresAt } = await Database.installLinks.generate(clientId);
    return { token, expiresAt };
  },
);
```

Отличия от старого `generateOneTimeLink.post.ts`:
- Возвращает `{ token, expiresAt }` вместо `{ success: true }`. UI использует `token` для построения команды.

### `GET /api/client/:clientId/package.tar.gz`

Файл `src/server/api/client/[clientId]/package.tar.gz.get.ts`:

```ts
import { ClientGetSchema } from '#db/repositories/client/types';

export default definePermissionEventHandler(
  'clients',
  'view',
  async ({ event, checkPermissions }) => {
    const { clientId } = await getValidatedRouterParams(
      event,
      validateZod(ClientGetSchema, event),
    );

    const client = await Database.clients.get(clientId);
    checkPermissions(client);

    if (!client) {
      throw createError({ statusCode: 404, statusMessage: 'Client not found' });
    }

    const buf = await PhobosPackage.build(clientId);
    const filename = await PhobosPackage.getFilename(clientId);

    setHeader(event, 'Content-Type', 'application/gzip');
    setHeader(event, 'Content-Disposition', `attachment; filename="${filename}"`);
    setHeader(event, 'Content-Length', String(buf.length));
    return buf;
  },
);
```

### `GET /api/install/:token`

Файл `src/server/api/install/[token]/index.get.ts`:

```ts
import { InstallTokenParamSchema } from '#db/repositories/installLink/types';

export default defineEventHandler(async (event) => {
  const { token } = await getValidatedRouterParams(
    event,
    validateZod(InstallTokenParamSchema, event),
  );

  const link = await Database.installLinks.getByToken(token);
  if (!link) {
    throw createError({ statusCode: 404, statusMessage: 'Install link not found' });
  }

  if (new Date(link.expiresAt).getTime() < Date.now()) {
    throw createError({ statusCode: 410, statusMessage: 'Install link expired' });
  }

  const origin = getRequestURL(event).origin;
  const script = await PhobosPackage.installScript(token, origin);

  setHeader(event, 'Content-Type', 'text/x-shellscript; charset=utf-8');
  setHeader(event, 'Cache-Control', 'no-store');
  return script;
});
```

### `GET /api/install/:token/package.tar.gz`

Файл `src/server/api/install/[token]/package.tar.gz.get.ts`:

```ts
import { InstallTokenParamSchema } from '#db/repositories/installLink/types';

export default defineEventHandler(async (event) => {
  const { token } = await getValidatedRouterParams(
    event,
    validateZod(InstallTokenParamSchema, event),
  );

  const link = await Database.installLinks.getByToken(token);
  if (!link) {
    throw createError({ statusCode: 404, statusMessage: 'Install link not found' });
  }
  if (new Date(link.expiresAt).getTime() < Date.now()) {
    throw createError({ statusCode: 410, statusMessage: 'Install link expired' });
  }

  const client = await Database.clients.get(link.id);
  if (!client) {
    throw createError({ statusCode: 404, statusMessage: 'Client not found' });
  }

  const buf = await PhobosPackage.build(link.id);
  const filename = await PhobosPackage.getFilename(link.id);

  setHeader(event, 'Content-Type', 'application/gzip');
  setHeader(event, 'Content-Disposition', `attachment; filename="${filename}"`);
  setHeader(event, 'Content-Length', String(buf.length));
  setHeader(event, 'Cache-Control', 'no-store');
  return buf;
});
```

Важно: этот роут работает **без** аутентификации, только по валидному токену из `install_links_table`.

### `POST /api/admin/interface`

Файл `src/server/api/admin/interface/index.post.ts` — расширение существующего.

В Zod-схеме (импорт из `InterfaceUpdateSchema` из Phase 2):

```ts
import { InterfaceUpdateSchema } from '#db/repositories/interface/types';

export default definePermissionEventHandler(
  'interface',
  'update',
  async ({ event }) => {
    const body = await readValidatedBody(event, validateZod(InterfaceUpdateSchema, event));

    const prev = await Database.interfaces.get();
    const obfuscatorChanged =
      prev.obfuscatorExtPort !== body.obfuscatorExtPort ||
      prev.obfuscatorKey !== body.obfuscatorKey ||
      prev.obfuscatorMasking !== body.obfuscatorMasking ||
      prev.obfuscatorIdle !== body.obfuscatorIdle ||
      prev.obfuscatorDummy !== body.obfuscatorDummy ||
      prev.serverPublicIpV4 !== body.serverPublicIpV4 ||
      prev.serverPublicIpV6 !== body.serverPublicIpV6 ||
      prev.clientWgLocalPort !== body.clientWgLocalPort;

    await Database.interfaces.update(body);

    const iface = await Database.interfaces.get();

    if (obfuscatorChanged) {
      await Obfuscator.writeConfig(iface);
      await Obfuscator.restart();
      PhobosPackage.invalidate();
    }

    return { success: true };
  },
);
```

### `POST /api/admin/interface/regenerateObfuscatorKey`

Файл `src/server/api/admin/interface/regenerateObfuscatorKey.post.ts`:

```ts
export default definePermissionEventHandler(
  'interface',
  'update',
  async () => {
    const iface = await Database.interfaces.get();
    const preset = Obfuscator.applyPreset(iface.obfuscatorLevel as 1|2|3|4|5);
    const key = Obfuscator.generateKey(preset.keyLen);

    await Database.interfaces.update({
      obfuscatorKey: key,
      obfuscatorDummy: preset.maxDummy,
    });

    const updated = await Database.interfaces.get();
    await Obfuscator.writeConfig(updated);
    await Obfuscator.restart();
    PhobosPackage.invalidate();

    return { key };
  },
);
```

### `POST /api/admin/interface/regenerateObfuscatorPort`

Файл `src/server/api/admin/interface/regenerateObfuscatorPort.post.ts`:

```ts
export default definePermissionEventHandler(
  'interface',
  'update',
  async () => {
    const envPort = Number(process.env.OBF_PORT);
    if (Number.isFinite(envPort)) {
      throw createError({
        statusCode: 409,
        statusMessage: 'OBF_PORT pinned via environment; change OBF_PORT and recreate container',
      });
    }

    const port = await Obfuscator.findFreePort();
    await Database.interfaces.update({ obfuscatorExtPort: port });

    const updated = await Database.interfaces.get();
    await Obfuscator.writeConfig(updated);
    await Obfuscator.restart();
    PhobosPackage.invalidate();

    return { port };
  },
);
```

## Permissions

Используется существующая RBAC-система wg-easy. Ресурс `interface` и действие `update` уже зарегистрированы. Новых permission-ключей добавлять не нужно.

## Удаляемые файлы

```bash
git rm src/server/api/client/\[clientId\]/generateOneTimeLink.post.ts
git rm src/server/api/client/\[clientId\]/configuration.get.ts
git rm src/app/pages/clients/\[otl\].vue
```

Проверить, что больше нет ссылок:

```bash
grep -rn "generateOneTimeLink\|configuration.get\|pages/clients/\[otl\]" src/
```

Должно быть пусто.

## Маршрутизация Nitro

Nuxt/Nitro автоматически регистрирует `/api/install/[token]/...` как роуты по структуре каталогов `src/server/api/`. Namespace `/api/` добавляется автоматически.

## Проверка фазы

```bash
# Генерация install-link
curl -X POST http://localhost:51821/api/client/1/generateInstallLink \
  -H "Cookie: session=..." | jq .
# → {"token":"...","expiresAt":"..."}

# Публичный install-скрипт
curl -s http://localhost:51821/api/install/<token>
# → #!/bin/sh ...

# Публичный tarball
curl -sL http://localhost:51821/api/install/<token>/package.tar.gz | tar tz | head
# → phobos-<slug>/<slug>.conf, ...

# Regenerate key
curl -X POST http://localhost:51821/api/admin/interface/regenerateObfuscatorKey \
  -H "Cookie: session=..."
# → {"key":"a7Kp9XqR"}
```

## Результат фазы

- Коммит: `feat(api): install token endpoints and client package download` + `feat(api): admin obfuscator configuration and regenerate routes`
- Затронуто: `src/server/api/**`.
- Все старые OTL- и configuration-маршруты удалены, новые работают.
