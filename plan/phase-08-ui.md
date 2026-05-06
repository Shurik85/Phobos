# Фаза 8 — UI: ClientCard, админ-страница, i18n

## Изменения в ClientCard

### Файл

`src/app/components/ClientCard/ClientCard.vue`

### Правило распределения кнопок

| Кнопка | Действие | Источник |
|--------|----------|----------|
| `Switch` | enable/disable клиента | оригинал wg-easy (без правок) |
| `Edit` | открыть форму редактирования | оригинал wg-easy (без правок) |
| `QRCode` | показать QR с WG-конфигом | оригинал wg-easy (без правок) |
| `Config` (Download) | скачать **Phobos-пакет** (tar.gz) | модифицирован: endpoint + filename |
| `OneTimeLinkBtn` (Copy) | скопировать **install-ссылку** в буфер обмена | модифицирован: генерация install-link + clipboard |

Порядок отображения слева направо сохраняется: `Switch, Edit, QRCode, Config, OneTimeLinkBtn`.

### Удаляемый компонент

`src/app/components/ClientCard/OneTimeLink.vue` — inline-блок с отображением сгенерированной one-time ссылки прямо в карточке. В новой схеме ссылка копируется в clipboard, inline-отображение не нужно.

Удалить:
```bash
git rm src/app/components/ClientCard/OneTimeLink.vue
```

Убрать использование из `ClientCard.vue`:
```diff
-          <ClientCardOneTimeLink :client="client" />
```

## `OneTimeLinkBtn.vue` — новая реализация

### Файл

`src/app/components/ClientCard/OneTimeLinkBtn.vue`

### Содержимое

```vue
<template>
  <button
    class="inline-block rounded bg-gray-100 p-2 align-middle transition hover:bg-red-800 hover:text-white dark:bg-neutral-600 dark:text-neutral-300 dark:hover:bg-red-800 dark:hover:text-white"
    :title="$t('client.copyInstallLink')"
    @click="copyInstallLink"
  >
    <IconsLink class="w-5" />
  </button>
</template>

<script setup lang="ts">
const props = defineProps<{ client: LocalClient }>();
const { t } = useI18n();
const toast = useToast();

async function copyInstallLink() {
  try {
    const { token } = await $fetch<{ token: string; expiresAt: string }>(
      `/api/client/${props.client.id}/generateInstallLink`,
      { method: 'post' },
    );

    const command = `curl -sL ${window.location.origin}/api/install/${token} | sh`;

    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(command);
    } else {
      const ta = document.createElement('textarea');
      ta.value = command;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }

    toast.success(t('client.installLinkCopied'));
  } catch (err) {
    toast.error(t('client.installLinkFailed'));
    console.error(err);
  }
}
</script>
```

Ключевые особенности:
- Clipboard API с fallback для HTTP-контекста (роутеры в LAN часто подключаются к панели по HTTP).
- После копирования — единственная обратная связь через toast (без inline-UI).
- `window.location.origin` гарантирует корректный URL независимо от reverse proxy.

## `Config.vue` — новая реализация

### Файл

`src/app/components/ClientCard/Config.vue`

### Содержимое

```vue
<template>
  <a
    :href="`/api/client/${client.id}/package.tar.gz`"
    :download="`phobos-${clientSlug}.tar.gz`"
    class="inline-block rounded bg-gray-100 p-2 align-middle transition hover:bg-red-800 hover:text-white dark:bg-neutral-600 dark:text-neutral-300 dark:hover:bg-red-800 dark:hover:text-white"
    :title="$t('client.downloadPackage')"
  >
    <IconsDownload class="w-5" />
  </a>
</template>

<script setup lang="ts">
const props = defineProps<{ client: LocalClient }>();

const clientSlug = computed(() =>
  props.client.name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32) || `client-${props.client.id}`,
);
</script>
```

Функциональные отличия:
- `href` → `/api/client/:id/package.tar.gz` (Phase 6 endpoint).
- `download` атрибут задаёт имя файла в браузере; серверный `Content-Disposition` дублирует.
- `slug` вычисляется на клиенте локально (не требует доп. API-запроса).

## `QRCode.vue` — без изменений

Оставляется как есть — показывает WG-конфиг в QR. Хотя в обфускатор-режиме WG-клиент без обфускатора не подключится напрямую, QR остаётся для ручного импорта (решение #3 пользователя).

## Типы и store

### `LocalClient`

Файл `src/app/utils/types.ts` (или подобный) — найти через:

```bash
grep -rn "type LocalClient\|interface LocalClient" src/app/
```

Убрать поле `oneTimeLink`:

```diff
 export type LocalClient = ClientType & {
   // ...
-  oneTimeLink: string | null;
   // ...
 };
```

### Store

`src/app/stores/clientsStore.ts` (или аналогичный) — убрать любую логику, подгружающую `oneTimeLink`. Если ответ `/api/client/list` содержал поле `oneTimeLink` — убрать его из соответствующего DTO (`src/server/api/client/index.get.ts`).

## Админ-страница

### Файл

`src/app/pages/admin/interface.vue` — расширение существующей страницы.

### Добавляемый блок

Перед `<FormGroup>` с `{{ $t('form.actions') }}` — отдельный `FormGroup` для обфускатора:

```vue
<FormGroup>
  <FormHeading>{{ $t('admin.obfuscator.heading') }}</FormHeading>

  <FormSelectField
    id="obfuscatorLevel"
    v-model="data.obfuscatorLevel"
    :label="$t('admin.obfuscator.level')"
    :description="$t('admin.obfuscator.levelDesc')"
    :options="[
      { value: 1, label: $t('admin.obfuscator.level1') },
      { value: 2, label: $t('admin.obfuscator.level2') },
      { value: 3, label: $t('admin.obfuscator.level3') },
      { value: 4, label: $t('admin.obfuscator.level4') },
      { value: 5, label: $t('admin.obfuscator.level5') },
    ]"
    @change="onLevelChange"
  />

  <FormNumberField
    id="obfuscatorExtPort"
    v-model="data.obfuscatorExtPort"
    :label="$t('admin.obfuscator.extPort')"
    :description="$t('admin.obfuscator.extPortDesc')"
    :disabled="isPortPinned"
  />
  <FormSecondaryActionField
    v-if="!isPortPinned"
    :label="$t('admin.obfuscator.regeneratePort')"
    @click="regeneratePort"
  />

  <FormPasswordField
    id="obfuscatorKey"
    v-model="data.obfuscatorKey"
    :label="$t('admin.obfuscator.key')"
    :description="$t('admin.obfuscator.keyDesc')"
  />
  <FormSecondaryActionField
    :label="$t('admin.obfuscator.regenerateKey')"
    @click="regenerateKey"
  />

  <FormSelectField
    id="obfuscatorMasking"
    v-model="data.obfuscatorMasking"
    :label="$t('admin.obfuscator.masking')"
    :description="$t('admin.obfuscator.maskingDesc')"
    :options="[
      { value: 'STUN', label: 'STUN' },
      { value: 'AUTO', label: 'AUTO' },
      { value: 'NONE', label: 'NONE' },
    ]"
  />

  <FormNumberField
    id="obfuscatorIdle"
    v-model="data.obfuscatorIdle"
    :label="$t('admin.obfuscator.idle')"
    :description="$t('admin.obfuscator.idleDesc')"
  />

  <FormNumberField
    id="obfuscatorDummy"
    v-model="data.obfuscatorDummy"
    :label="$t('admin.obfuscator.dummy')"
    :description="$t('admin.obfuscator.dummyDesc')"
  />

  <FormTextField
    id="serverPublicIpV4"
    v-model="data.serverPublicIpV4"
    :label="$t('admin.obfuscator.publicIpV4')"
    :description="$t('admin.obfuscator.publicIpV4Desc')"
  />

  <FormNullTextField
    id="serverPublicIpV6"
    v-model="data.serverPublicIpV6"
    :label="$t('admin.obfuscator.publicIpV6')"
    :description="$t('admin.obfuscator.publicIpV6Desc')"
  />

  <FormNumberField
    id="clientWgLocalPort"
    v-model="data.clientWgLocalPort"
    :label="$t('admin.obfuscator.clientWgLocalPort')"
    :description="$t('admin.obfuscator.clientWgLocalPortDesc')"
  />
</FormGroup>
```

### Логика

```ts
const PRESETS_UI = {
  1: { keyLen: 3, dummy: 4 },
  2: { keyLen: 6, dummy: 10 },
  3: { keyLen: 20, dummy: 20 },
  4: { keyLen: 50, dummy: 50 },
  5: { keyLen: 255, dummy: 100 },
} as const;

function onLevelChange(level: number) {
  const preset = PRESETS_UI[level as 1 | 2 | 3 | 4 | 5];
  data.value.obfuscatorDummy = preset.dummy;
}

const isPortPinned = computed(
  () => globalStore.information?.obfuscatorPortPinned ?? false,
);

const _regenerateKey = useSubmit<{ key: string }>(
  '/api/admin/interface/regenerateObfuscatorKey',
  { method: 'post' },
  {
    revert: async (success) => {
      if (success) await refresh();
    },
    successMsg: t('admin.obfuscator.keyRegenerated'),
  },
);

async function regenerateKey() {
  await _regenerateKey(undefined);
}

const _regeneratePort = useSubmit<{ port: number }>(
  '/api/admin/interface/regenerateObfuscatorPort',
  { method: 'post' },
  {
    revert: async (success) => {
      if (success) await refresh();
    },
    successMsg: t('admin.obfuscator.portRegenerated'),
  },
);

async function regeneratePort() {
  await _regeneratePort(undefined);
}
```

### `information` API

Расширить `/api/admin/information` (или `/api/global`) флагом `obfuscatorPortPinned` — возвращает `Boolean(process.env.OBF_PORT)`. Используется для disable UI-поля `obfuscatorExtPort`.

## i18n

### Новые ключи

`src/i18n/locales/en.json` (и аналогично во всех остальных локалях):

```json
{
  "client": {
    "copyInstallLink": "Copy install command",
    "installLinkCopied": "Install command copied to clipboard",
    "installLinkFailed": "Failed to generate install link",
    "downloadPackage": "Download install package"
  },
  "admin": {
    "obfuscator": {
      "heading": "Obfuscator",
      "level": "Obfuscation level",
      "levelDesc": "Preset for key length and dummy padding. 1 — light, 5 — nightmare.",
      "level1": "1 — Light",
      "level2": "2 — Sufficient",
      "level3": "3 — Average",
      "level4": "4 — Above average",
      "level5": "5 — Nightmare",
      "extPort": "External UDP port",
      "extPortDesc": "Public port obfuscator listens on. Pinned if OBF_PORT env is set.",
      "key": "Obfuscator key",
      "keyDesc": "XOR key shared between server and all clients.",
      "regenerateKey": "Regenerate key",
      "keyRegenerated": "Obfuscator key regenerated",
      "regeneratePort": "Pick free port",
      "portRegenerated": "Obfuscator port changed",
      "masking": "Masking mode",
      "maskingDesc": "STUN wraps packets in STUN Binding messages. AUTO lets the obfuscator choose. NONE disables masking.",
      "idle": "Idle timeout (seconds)",
      "idleDesc": "Time after which an inactive client is removed from the session table.",
      "dummy": "Max dummy bytes",
      "dummyDesc": "Random padding prepended to each packet. Larger values increase entropy but also overhead.",
      "publicIpV4": "Server public IPv4",
      "publicIpV4Desc": "Used as target in client obfuscator config.",
      "publicIpV6": "Server public IPv6",
      "publicIpV6Desc": "Optional IPv6 target.",
      "clientWgLocalPort": "Client-side WG→obfuscator port",
      "clientWgLocalPortDesc": "Local port the WG client on the device sends to (localhost)."
    }
  }
}
```

Переводы для ru/de/fr/etc. — по той же структуре.

### Удаляемые ключи

Во всех локалях (`src/i18n/locales/*.json`):

| Ключ | Где использовался |
|------|-------------------|
| `client.otlDesc` | старый OneTimeLinkBtn title |
| `client.downloadConfig` | старый Config.vue title |

Поиск:

```bash
grep -rn "otlDesc\|downloadConfig" src/
```

После удаления — пусто.

## Удаляемые компоненты и страницы

```bash
git rm src/app/components/ClientCard/OneTimeLink.vue
git rm src/app/pages/clients/\[otl\].vue
```

Проверить отсутствие ссылок:

```bash
grep -rn "ClientCardOneTimeLink\|OneTimeLink\b" src/app/
```

Должно быть пусто (кроме `OneTimeLinkBtn.vue` — это новое имя кнопки, но сам компонент теперь копирует install-link).

### Переименование компонента (опционально)

Для чистоты можно переименовать `OneTimeLinkBtn.vue` → `InstallLinkBtn.vue`:

```bash
git mv src/app/components/ClientCard/OneTimeLinkBtn.vue \
       src/app/components/ClientCard/InstallLinkBtn.vue
```

Обновить импорт в `ClientCard.vue`:

```diff
-          <ClientCardOneTimeLinkBtn :client="client" />
+          <ClientCardInstallLinkBtn :client="client" />
```

Рекомендуется переименовать — устраняет рудимент в именах.

## Проверка фазы

```bash
pnpm dev
# Открыть http://localhost:51821, залогиниться
# Создать клиента
# Кликнуть OTL-кнопку → toast "Install command copied"
# Вставить в терминал: curl -sL http://host/api/install/<token> | sh
#   → должен вывести install.sh
# Кликнуть Download-кнопку → скачается phobos-<slug>.tar.gz
# Открыть tarball: tar tzf phobos-*.tar.gz
#   → видны все ожидаемые файлы
```

## Результат фазы

- Коммиты: `feat(ui): rewire ClientCard buttons (OTL→copy install, Download→tarball)` + `feat(ui): admin obfuscator settings page`.
- Затронуто: `src/app/components/ClientCard/**`, `src/app/pages/admin/interface.vue`, `src/i18n/locales/*.json`.
- UI синхронизирован с бэкендом.
