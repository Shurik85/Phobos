# Фаза 4 — `PhobosPackage`: сборка установочного tarball

## Файл

`src/server/utils/PhobosPackage.ts`

## Ответственность

1. Формирование клиентского WG-конфига (через `wgHelper.generateClientConfig`).
2. Формирование клиентского `wg-obfuscator.conf`.
3. Подстановка `{{CLIENT_NAME}}` в shell-шаблоны.
4. Упаковка в tar.gz с multi-arch бинарями и скриптами.
5. In-memory кэш последнего собранного пакета на клиента.
6. Инвалидация кэша.
7. Генерация bootstrap-`install.sh` для раздачи по install-link.

## Пути к артефактам

```ts
const BIN_DIR = resolve('/app/phobos/bin');
const TEMPLATES_DIR = resolve('/app/phobos/templates');

const ARCHITECTURES = [
  'x86_64', 'aarch64', 'armv7', 'mips', 'mipsel',
] as const;

const TEMPLATES = [
  'lib-client.sh',
  'install-obfuscator.sh',
  'install-wireguard.sh',
  'router-configure-wireguard.sh',
  'router-configure-wireguard-openwrt.sh',
  '3xui.sh',
  'detect-router-arch.sh',
  'phobos-uninstall.sh',
] as const;

const TEMPLATE_WITH_PLACEHOLDER = 'install-router.sh.template';
```

Для dev-режима (когда нет `/app/phobos/...`) — fallback через `import.meta.url`:

```ts
const binDir = existsSync(BIN_DIR)
  ? BIN_DIR
  : fileURLToPath(new URL('../../phobos-obfuscator/bin', import.meta.url));
```

## Структура собранного tarball'а

```
phobos-<client-slug>/
├── <client-slug>.conf               # WG-конфиг клиента
├── wg-obfuscator.conf                # obfuscator-конфиг (клиентская сторона)
├── install-router.sh                 # после подстановки {{CLIENT_NAME}}
├── lib-client.sh
├── install-obfuscator.sh
├── install-wireguard.sh
├── router-configure-wireguard.sh
├── router-configure-wireguard-openwrt.sh
├── 3xui.sh
├── detect-router-arch.sh
├── phobos-uninstall.sh
├── README.txt                        # имя клиента, дата сборки, версия
└── bin/
    ├── wg-obfuscator-x86_64
    ├── wg-obfuscator-aarch64
    ├── wg-obfuscator-armv7
    ├── wg-obfuscator-mips
    └── wg-obfuscator-mipsel
```

## Формат клиентского `wg-obfuscator.conf`

```ini
[instance]
source-if = 127.0.0.1
source-lport = 13255
target = 203.0.113.42:51822
key = a7Kp9XqR
masking = STUN
verbose = INFO
idle-timeout = 300
max-dummy = 10
```

Где:
- `source-lport` = `iface.clientWgLocalPort` (client-side, localhost).
- `target` = `${iface.serverPublicIpV4}:${iface.obfuscatorExtPort}`.
- `key`, `masking`, `idle-timeout`, `max-dummy` — идентичны серверным (симметричная обфускация).

## Клиентский slug

```ts
function clientSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32) || `client-${id}`;
}
```

Такое же поведение, как в `phobos-client.sh:13` (`tr ' ' '-' | tr '[:upper:]' '[:lower:]'`).

## Интерфейс класса

```ts
class PhobosPackage {
  #cache = new Map<ID, Buffer>();

  async build(clientId: ID): Promise<Buffer>
  invalidate(clientId?: ID): void
  async installScript(token: string, origin: string): Promise<string>
  async getFilename(clientId: ID): Promise<string>
}

export default new PhobosPackage();
```

## Реализация

### `build`

```ts
async build(clientId: ID): Promise<Buffer> {
  const cached = this.#cache.get(clientId);
  if (cached) return cached;

  const iface = await Database.interfaces.get();
  const userConfig = await Database.userConfigs.get();
  const client = await Database.clients.get(clientId);
  if (!client) throw new Error(`Client ${clientId} not found`);

  const slug = clientSlug(client.name);
  const pkgRoot = `phobos-${slug}`;

  const wgConf = wg.generateClientConfig(iface, userConfig, client, {
    enableIpv6: !WG_ENV.DISABLE_IPV6,
  });

  const obfConf = this.buildClientObfConf(iface);

  const pack = tar.pack();

  pack.entry({ name: `${pkgRoot}/${slug}.conf`, mode: 0o600 }, wgConf);
  pack.entry({ name: `${pkgRoot}/wg-obfuscator.conf`, mode: 0o600 }, obfConf);

  const installRouter = (
    await readFile(join(TEMPLATES_DIR, TEMPLATE_WITH_PLACEHOLDER), 'utf8')
  ).replaceAll('{{CLIENT_NAME}}', slug);
  pack.entry(
    { name: `${pkgRoot}/install-router.sh`, mode: 0o755 },
    installRouter,
  );

  for (const file of TEMPLATES) {
    const content = await readFile(join(TEMPLATES_DIR, file));
    pack.entry({ name: `${pkgRoot}/${file}`, mode: 0o755 }, content);
  }

  for (const arch of ARCHITECTURES) {
    const bin = join(BIN_DIR, `wg-obfuscator-${arch}`);
    if (existsSync(bin)) {
      const content = await readFile(bin);
      pack.entry(
        { name: `${pkgRoot}/bin/wg-obfuscator-${arch}`, mode: 0o755 },
        content,
      );
    }
  }

  const readme = [
    `Phobos Client Package`,
    `Client: ${client.name}`,
    `Slug: ${slug}`,
    `Built: ${new Date().toISOString()}`,
    ``,
  ].join('\n');
  pack.entry({ name: `${pkgRoot}/README.txt` }, readme);

  pack.finalize();

  const gzipped = await streamToBuffer(pack.pipe(createGzip()));
  this.#cache.set(clientId, gzipped);
  return gzipped;
}
```

Где `tar` — из пакета `tar-stream`, `createGzip` — `node:zlib`, `streamToBuffer` — утилита собирания потока в буфер.

### `buildClientObfConf`

```ts
private buildClientObfConf(iface: InterfaceType): string {
  return [
    '[instance]',
    'source-if = 127.0.0.1',
    `source-lport = ${iface.clientWgLocalPort}`,
    `target = ${iface.serverPublicIpV4}:${iface.obfuscatorExtPort}`,
    `key = ${iface.obfuscatorKey}`,
    `masking = ${iface.obfuscatorMasking}`,
    'verbose = INFO',
    `idle-timeout = ${iface.obfuscatorIdle}`,
    `max-dummy = ${iface.obfuscatorDummy}`,
    '',
  ].join('\n');
}
```

### `invalidate`

```ts
invalidate(clientId?: ID): void {
  if (clientId === undefined) {
    this.#cache.clear();
    PACKAGE_DEBUG('cache fully invalidated');
  } else {
    this.#cache.delete(clientId);
    PACKAGE_DEBUG(`cache invalidated for client ${clientId}`);
  }
}
```

### `installScript`

```ts
async installScript(token: string, origin: string): Promise<string> {
  const link = await Database.installLinks.getByToken(token);
  if (!link) throw createError({ statusCode: 404 });

  const client = await Database.clients.get(link.id);
  if (!client) throw createError({ statusCode: 404 });

  const slug = clientSlug(client.name);
  const pkgUrl = `${origin}/api/install/${token}/package.tar.gz`;

  return [
    '#!/bin/sh',
    'set -e',
    `url="${pkgUrl}"`,
    `dir="/tmp/phobos_install_$$"`,
    `mkdir -p "$dir"`,
    `echo "Downloading Phobos package..."`,
    `if command -v curl >/dev/null 2>&1; then`,
    `  curl -fsSL -o "$dir/package.tar.gz" "$url"`,
    `else`,
    `  wget -q -O "$dir/package.tar.gz" "$url"`,
    `fi`,
    `if [ ! -s "$dir/package.tar.gz" ]; then`,
    `  echo "Download failed"; exit 1`,
    `fi`,
    `cd "$dir"`,
    `tar xzf package.tar.gz`,
    `cd "phobos-${slug}"`,
    `chmod +x install-router.sh`,
    `./install-router.sh`,
    '',
  ].join('\n');
}
```

Формат близок к `Phobos/server/scripts/phobos-client.sh:311-328` (`action_link`).

### `getFilename`

```ts
async getFilename(clientId: ID): Promise<string> {
  const client = await Database.clients.get(clientId);
  if (!client) throw new Error(`Client ${clientId} not found`);
  return `phobos-${clientSlug(client.name)}.tar.gz`;
}
```

## Зависимости

Добавить в `src/package.json`:

```json
{
  "dependencies": {
    "tar-stream": "^3.1.7"
  },
  "devDependencies": {
    "@types/tar-stream": "^3.1.3"
  }
}
```

`zlib` — встроенный `node:zlib`.

## Инвалидация: внешние триггеры

`PhobosPackage.invalidate()` вызывается из:

| Место | Диапазон |
|-------|----------|
| `clientsService.update()` | по `clientId` |
| `clientsService.create()` | не нужен (нет кэша) |
| `clientsService.delete()` | по `clientId` |
| `interfacesService.update()` | полный clear (`invalidate()`) |
| `interfacesService.updateKeyPair()` | полный clear |
| `interfacesService.changeCidr()` | полный clear |
| `Obfuscator.Startup()` | полный clear (после writeConfig) |

Список синхронизируется с фазой 7 (`lifecycle`).

## Unit-тест

`src/test/unit/PhobosPackage.spec.ts`:

```ts
describe('PhobosPackage.build', () => {
  it('produces tar.gz with required entries', async () => {
    mockDatabase({
      interface: { ... },
      client: { id: 1, name: 'My Phone' },
    });
    const buf = await pkg.build(1);

    const entries = await listTarGz(buf);
    expect(entries).toContain('phobos-my-phone/my-phone.conf');
    expect(entries).toContain('phobos-my-phone/wg-obfuscator.conf');
    expect(entries).toContain('phobos-my-phone/install-router.sh');
    expect(entries).toContain('phobos-my-phone/bin/wg-obfuscator-x86_64');
  });

  it('substitutes {{CLIENT_NAME}} in install-router.sh', async () => {
    const buf = await pkg.build(1);
    const content = await extractEntry(buf, 'phobos-my-phone/install-router.sh');
    expect(content).not.toContain('{{CLIENT_NAME}}');
    expect(content).toContain('CLIENT_NAME="my-phone"');
  });

  it('caches results', async () => {
    const a = await pkg.build(1);
    const b = await pkg.build(1);
    expect(a).toBe(b);
  });

  it('clears cache on invalidate', async () => {
    const a = await pkg.build(1);
    pkg.invalidate(1);
    const b = await pkg.build(1);
    expect(a).not.toBe(b);
  });
});

describe('PhobosPackage.installScript', () => {
  it('embeds package URL with origin', async () => {
    const script = await pkg.installScript('abc123...', 'https://host:51821');
    expect(script).toContain('https://host:51821/api/install/abc123.../package.tar.gz');
    expect(script).toContain('chmod +x install-router.sh');
  });
});
```

## Результат фазы

- Коммит: `feat(server): PhobosPackage tarball builder with in-memory cache`
- Затронуто: `src/server/utils/PhobosPackage.ts` (новый), `src/package.json` (+ tar-stream).
- Класс изолирован, используется из API-роутов (Phase 6) и жизненного цикла (Phase 7).
