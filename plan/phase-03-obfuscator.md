# Фаза 3 — Сервис `Obfuscator`

## Файл

`src/server/utils/Obfuscator.ts`

## Ответственность

1. Формирование аргументов CLI для `wg-obfuscator` из данных БД и запись в `/run/wg-obfuscator.args`.
2. Перезапуск `wg-obfuscator` через `s6-svc`.
3. Применение пресетов (1-5) к `obfuscatorKey.length` и `obfuscatorDummy`.
4. Автоопределение публичных IP.
5. Инициализация на первом старте (генерация ключа, подбор порта, детект IP).

## Почему аргументы, а не ini-файл

`wg-obfuscator` принимает **все** необходимые параметры через CLI (см. `src/phobos-obfuscator/config.c:14-33`): `--source-if`, `--source-lport`, `--target`, `--key`, `--masking`, `--idle-timeout`, `--max-dummy`, `--verbose`. Это позволяет избавиться от отдельного файла `/etc/wg-obfuscator.conf` на серверной стороне.

Компромисс: `--key=` будет виден через `ps` внутри контейнера. Для wg-easy это не деградация — контейнер работает от root, других пользователей/процессов кроме `node` и `wg-obfuscator` там нет, а БД уже хранит ключ в открытом виде. В более строгих развёртываниях (shared user, ptrace-права у непривилегированных процессов) имеет смысл вернуться к ini-файлу 0600.

Node пишет параметры в `/run/wg-obfuscator.args` — по одному аргументу на строку, режим 0600. s6-run делает `xargs -a` для передачи.

## Константы и пресеты

```ts
const ARGS_PATH = '/run/wg-obfuscator.args';
const SERVICE_DIR = '/run/service/wg-obfuscator';

const PRESETS = {
  1: { keyLen: 3,   maxDummy: 4   },
  2: { keyLen: 6,   maxDummy: 10  },
  3: { keyLen: 20,  maxDummy: 20  },
  4: { keyLen: 50,  maxDummy: 50  },
  5: { keyLen: 255, maxDummy: 100 },
} as const;

type PresetLevel = keyof typeof PRESETS;
```

Соответствует таблице из `Phobos/server/scripts/phobos-installer.sh:24-34`.

## Интерфейс класса

```ts
class Obfuscator {
  buildArgs(iface: InterfaceType): string[]
  async writeArgs(iface: InterfaceType): Promise<void>
  async restart(): Promise<void>
  async apply(iface: InterfaceType): Promise<void>
  applyPreset(level: PresetLevel): { keyLen: number; maxDummy: number }
  generateKey(length: number): string
  async detectPublicIpV4(): Promise<string>
  async detectPublicIpV6(): Promise<string | null>
  async findFreePort(min?: number, max?: number): Promise<number>
  async Startup(): Promise<void>
}

export const Obfuscator = new ObfuscatorService();
```

## Реализация

### `buildArgs` + `writeArgs` + `apply`

```ts
buildArgs(iface: InterfaceType): string[] {
  return [
    `--source-if=0.0.0.0`,
    `--source-lport=${iface.obfuscatorExtPort}`,
    `--target=127.0.0.1:${iface.port}`,
    `--key=${iface.obfuscatorKey}`,
    `--masking=${iface.obfuscatorMasking}`,
    `--verbose=INFO`,
    `--idle-timeout=${iface.obfuscatorIdle}`,
    `--max-dummy=${iface.obfuscatorDummy}`,
  ];
}

async writeArgs(iface: InterfaceType): Promise<void> {
  const args = this.buildArgs(iface);
  await writeFile(ARGS_PATH, args.join('\n') + '\n', { mode: 0o600 });
}

async apply(iface: InterfaceType): Promise<void> {
  await this.writeArgs(iface);
  await this.restart();
}
```

Опции сверены с `src/phobos-obfuscator/config.c:14-33`.

### `restart`

```ts
async restart(): Promise<void> {
  if (!existsSync(SERVICE_DIR)) {
    OBFUSCATOR_DEBUG('s6 service not available, skipping restart (dev mode)');
    return;
  }
  await exec(`s6-svc -r ${SERVICE_DIR}`);
  OBFUSCATOR_DEBUG('s6-svc -r issued');
}
```

`-r` — restart (down + up).

### `applyPreset`

```ts
applyPreset(level: PresetLevel) {
  return PRESETS[level];
}
```

### `generateKey`

```ts
generateKey(length: number): string {
  if (length < 1 || length > 255) {
    throw new Error('Key length must be 1..255');
  }
  return randomBytes(length * 2)
    .toString('base64')
    .replace(/[+/=]/g, '')
    .slice(0, length);
}
```

Логика из `Phobos/server/scripts/phobos-installer.sh:161` (urandom → base64 → trim).

### `detectPublicIpV4`

```ts
async detectPublicIpV4(): Promise<string> {
  const iface = (await exec('ip route')).match(/^default.+dev\s+(\S+)/m)?.[1];
  if (!iface) throw new Error('Default route not found');

  const out = await exec(`ip -4 addr show dev ${iface} scope global`);
  const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
  if (!ip) throw new Error(`No IPv4 on ${iface}`);

  return ip;
}
```

Соответствует `lib-core.sh:103-111`.

### `detectPublicIpV6`

```ts
async detectPublicIpV6(): Promise<string | null> {
  try {
    const iface = (await exec('ip route')).match(/^default.+dev\s+(\S+)/m)?.[1];
    if (!iface) return null;

    const out = await exec(`ip -6 addr show dev ${iface} scope global`);
    const ipv6 = out
      .match(/inet6\s+([0-9a-f:]+)/gi)
      ?.map((l) => l.replace(/^inet6\s+/i, ''))
      .find((addr) => !/^f[cd]/i.test(addr));
    return ipv6 ?? null;
  } catch {
    return null;
  }
}
```

Фильтр `!fc/fd` убирает ULA-адреса (fc00::/7), оставляет только публичные.

### `findFreePort`

```ts
async findFreePort(min = 1024, max = 49151): Promise<number> {
  const used = await exec('ss -ulnp');
  const taken = new Set(
    [...used.matchAll(/:(\d+)\s/g)].map((m) => Number(m[1]))
  );

  for (let i = 0; i < 100; i++) {
    const port = Math.floor(Math.random() * (max - min + 1)) + min;
    if (!taken.has(port)) return port;
  }
  throw new Error('No free UDP port in range');
}
```

### `Startup`

```ts
async Startup(): Promise<void> {
  OBFUSCATOR_DEBUG('Starting Obfuscator...');

  let iface = await Database.interfaces.get();

  const needsInit =
    !iface.obfuscatorKey ||
    !iface.serverPublicIpV4 ||
    !iface.obfuscatorExtPort;

  if (needsInit) {
    OBFUSCATOR_DEBUG('First-run initialization');

    const envPort = Number(process.env.OBF_PORT);
    const port =
      Number.isFinite(envPort) && envPort >= 1024 && envPort <= 49151
        ? envPort
        : await this.findFreePort();

    const preset = this.applyPreset(iface.obfuscatorLevel as PresetLevel);
    const key = iface.obfuscatorKey || this.generateKey(preset.keyLen);
    const ipv4 = iface.serverPublicIpV4 || (await this.detectPublicIpV4());
    const ipv6 = iface.serverPublicIpV6 ?? (await this.detectPublicIpV6());

    await Database.interfaces.update({
      obfuscatorExtPort: port,
      obfuscatorKey: key,
      obfuscatorDummy: preset.maxDummy,
      serverPublicIpV4: ipv4,
      serverPublicIpV6: ipv6,
    });
    iface = await Database.interfaces.get();
  }

  await this.writeConfig(iface);
  await this.restart();

  OBFUSCATOR_DEBUG('Obfuscator started');
}
```

Ключевые моменты:
- Идемпотентно — повторный вызов безопасен.
- Env `OBF_PORT` имеет приоритет над автоподбором (нужно для соответствия docker-compose publish).
- При наличии всех полей просто пишет конфиг и рестартит.

## Интеграция с существующей инфраструктурой

### Debug-логгер

В `src/server/utils/types.ts` (или где объявлены `WG_DEBUG`):

```ts
import debug from 'debug';
export const OBFUSCATOR_DEBUG = debug('Obfuscator');
```

И `DEBUG` env расширен: `Server,WireGuard,Database,CMD,Obfuscator`.

### `exec`

Уже существует в `src/server/utils/cmd.ts`. Используется напрямую.

### `Database.interfaces.update`

Добавить метод в `interface/service.ts`, если его нет:

```ts
async update(patch: Partial<InterfaceType>): Promise<void> {
  await this.db.update(wgInterface).set(patch).where(sql`1=1`);
}
```

Альтернатива: уже используемые методы update в репозитории интерфейса (см. существующий код).

### Singleton

В конце файла:

```ts
export const Obfuscator = new ObfuscatorService();
```

Импортируется как:

```ts
import { Obfuscator } from '#utils/Obfuscator';
```

## Пример итогового `/etc/wg-obfuscator.conf`

```ini
[instance]
source-if = 0.0.0.0
source-lport = 51822
target = 127.0.0.1:51820
key = a7Kp9XqR
masking = STUN
verbose = INFO
idle-timeout = 300
max-dummy = 10
```

## Unit-тест (Phase 9)

`src/test/unit/Obfuscator.spec.ts`:

```ts
describe('Obfuscator.writeConfig', () => {
  it('writes valid ini with all fields', async () => {
    const tmp = tmpFileSync();
    const iface = mockInterface({
      obfuscatorExtPort: 51822,
      obfuscatorKey: 'secret',
      obfuscatorMasking: 'AUTO',
      obfuscatorIdle: 600,
      obfuscatorDummy: 25,
    });
    await writeConfigTo(tmp.path, iface);

    const content = readFileSync(tmp.path, 'utf8');
    expect(content).toContain('source-lport = 51822');
    expect(content).toContain('key = secret');
    expect(content).toContain('masking = AUTO');
    expect(content).toContain('idle-timeout = 600');
    expect(content).toContain('max-dummy = 25');
  });
});

describe('Obfuscator.generateKey', () => {
  it('produces key of exact length without special chars', () => {
    for (const len of [3, 6, 20, 50, 255]) {
      const key = obf.generateKey(len);
      expect(key).toHaveLength(len);
      expect(key).toMatch(/^[A-Za-z0-9]+$/);
    }
  });
});

describe('Obfuscator.applyPreset', () => {
  it.each([[1, 3, 4], [2, 6, 10], [3, 20, 20], [4, 50, 50], [5, 255, 100]])(
    'preset %i → keyLen=%i maxDummy=%i',
    (level, keyLen, maxDummy) => {
      expect(obf.applyPreset(level)).toEqual({ keyLen, maxDummy });
    },
  );
});
```

## Результат фазы

- Коммит: `feat(server): Obfuscator utility and service lifecycle`
- Затронуто: `src/server/utils/Obfuscator.ts` (новый), `src/server/utils/types.ts` (DEBUG).
- Сервис изолирован, может быть вызван из плагина Startup (Phase 7).
