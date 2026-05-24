# План: пресеты обфускатора (multi-instance)

## Контекст

Сейчас в PhobosWG один обфускатор-инстанс на весь сервер: его параметры (`ext_port`, `key`, `masking`, `idle`, `dummy`, `client_wg_local_port`) хранятся прямо в `interfaces_table.wg0`, единственный s6-longrun `wg-obfuscator` запускается с CLI-флагами из `/run/wg-obfuscator.args`, и **все клиенты** делят один и тот же транспорт. Это исключает сценарии, когда отдельные клиенты или группы должны ходить через обфускатор с другим ключом/маскингом/портом — например, чтобы изолировать профили на одном и том же WG-интерфейсе, или иметь резервный профиль для обхода блокировок другим способом.

Цель: ввести понятие **«пресет обфускатора»**. Один пресет — независимый листенер обфускатора с собственными параметрами. Всегда есть один default-пресет (его используют все клиенты, у которых явно не выбран другой). Админ может создавать дополнительные пресеты и привязывать к ним отдельных клиентов через UI. Внутри контейнера N инстансов поднимаются **одним процессом** `wg-obfuscator --config /run/wg-obfuscator.conf` — бинарник `phobos-obfuscator/config.c:152-162` уже умеет: на каждой следующей `[section]` он делает `fork()`, и child становится отдельным listener'ом со своими параметрами. Это native-фича, не наш хак.

## Архитектурные решения (согласованы)

- **Lifecycle**: один s6-сервис, fork-multi-instance бинарника по `[section]`-секциям в `wg-obfuscator.conf`.
- **Порты наружу**: статичный диапазон `51822-51921:51822-51921/udp` в `docker-compose.yml`. Каждый пресет аллоцирует свой порт из диапазона; при создании пресета Node выбирает свободный (или принимает указанный в UI).
- **Удаление пресета с привязанными клиентами**: FK `client.preset_id` с `ON DELETE SET NULL`. Клиенты с `preset_id IS NULL` автоматически используют default.
- **Состав пресета**: `name`, `ext_port`, `key`, `masking`, `idle`, `dummy`, `client_wg_local_port`, `is_default`.
- **Default-пресет нельзя удалить.** Любой другой пресет можно «продвинуть» в default через отдельный endpoint (транзакция: snimaем флаг со старого, ставим на новый).

---

## Часть 1. Схема БД и миграция

**Новая таблица** `obfuscator_presets_table` (`src/server/database/repositories/obfuscatorPreset/schema.ts` — новый репозиторий, по аналогии с существующими в `repositories/interface/`):

```sql
CREATE TABLE obfuscator_presets_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  is_default INTEGER NOT NULL DEFAULT 0,    -- 0/1
  ext_port INTEGER NOT NULL UNIQUE,         -- 51822..51921
  key TEXT NOT NULL,
  masking TEXT NOT NULL DEFAULT 'STUN',     -- STUN|AUTO|NONE
  idle INTEGER NOT NULL DEFAULT 300,
  dummy INTEGER NOT NULL DEFAULT 10,
  client_wg_local_port INTEGER NOT NULL DEFAULT 13255,
  created_at TEXT DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  updated_at TEXT DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
CREATE UNIQUE INDEX uq_default_preset ON obfuscator_presets_table (is_default) WHERE is_default = 1;
```

**Связь client → preset** (`src/server/database/repositories/client/schema.ts`):

```ts
presetId: integer('preset_id').references(() => obfuscatorPreset.id, { onDelete: 'set null' }),
```

(nullable, без `notNull` → null означает «использовать default»)

**Очистка `interfaces_table`** — recreate-table-pattern (как в существующей миграции `0003_breezy_colossus.sql`): новая таблица без полей `obfuscator_ext_port`, `obfuscator_key`, `obfuscator_masking`, `obfuscator_idle`, `obfuscator_dummy`, `client_wg_local_port`, `server_public_ip_v4`, `server_public_ip_v6` (последние два — оставить, они нужны для `serverEndpoint` клиента); copy → drop → rename. Zero-waste: эти поля переезжают в пресеты целиком.

**Миграция** `src/server/database/migrations/0009_obfuscator_presets.sql`:
1. CREATE TABLE obfuscator_presets_table.
2. CREATE UNIQUE INDEX uq_default_preset (partial).
3. INSERT into obfuscator_presets_table (id=1, name='default', is_default=1, ext_port, key, masking, idle, dummy, client_wg_local_port) SELECT соответствующих значений FROM interfaces_table WHERE name='wg0'.
4. ALTER TABLE clients_table ADD COLUMN preset_id INTEGER REFERENCES obfuscator_presets_table(id) ON DELETE SET NULL.
5. Recreate-table для `interfaces_table` без obfuscator-полей (как в `0003`).
6. Запись в `migrations/meta/_journal.json` нового entry с tag `0009_obfuscator_presets`.

---

## Часть 2. Backend lifecycle

### `src/server/utils/Obfuscator.ts` — переработать

Заменить single-iface API на preset-based API. Сохранить функции `generateKey`, `detectPublicIpV4`, `detectPublicIpV6`, `findFreePort` (расширить — выбор только из 51822–51921, исключая уже занятые в БД).

Новые методы:

- `buildSection(preset, wgPort): string` — генерит одну `[preset-<id>]` секцию для конфиг-файла. `source-lport=preset.ext_port`, `target=127.0.0.1:<wgPort>`, остальное из preset.
- `buildConfigFile(presets, wgPort): string` — конкатенирует N секций. Сохраняет в `/run/wg-obfuscator.conf`.
- `applyAll(): Promise<void>` — читает все пресеты из БД + WG port из `interfaces_table.wg0`, генерирует config, пишет в `/run/wg-obfuscator.conf`, вызывает `restart()`.
- `restart()`: `s6-svc -r /run/service/wg-obfuscator` (как сейчас).
- `Startup(): Promise<void>` — initial: убеждается, что в БД есть `is_default=1` пресет (создаёт, если нет); затем applyAll.
- `buildClientObfConf(preset, serverIpV4): string` — формирует `[instance]`-блок для клиента, используя `preset.client_wg_local_port`, `preset.ext_port`, `preset.key`, `preset.masking`, `preset.idle`, `preset.dummy`. **Заменяет текущий `buildClientObfConf(iface)`**.

Удалить методы `buildArgs`, `writeArgs` — больше не нужны (CLI-режим уходит).

### s6-сервис

**`docker/s6-rc.d/wg-obfuscator/run`** — переписать:

```sh
#!/command/with-contenv sh
while [ ! -s /run/wg-obfuscator.conf ]; do
  sleep 1
done
exec setsid /usr/local/bin/wg-obfuscator --config /run/wg-obfuscator.conf
```

`setsid` создаёт новую process-group/session → весь дерево fork-child'ов окажется под одним pgid.

**`docker/s6-rc.d/wg-obfuscator/finish`** — добавить cleanup fork-child'ов:

```sh
#!/command/with-contenv sh
pkill -f '/usr/local/bin/wg-obfuscator' 2>/dev/null
exit 0
```

s6-svc -d/-r отправит SIGTERM родителю; finish добежит SIGTERM до всех зомби. Без этого fork-child'ы остаются orphans.

### `docker-compose.yml`

- Удалить `OBF_PORT` env (не нужен — порты пресетов в БД).
- Заменить `"${OBF_PORT:-51822}:${OBF_PORT:-51822}/udp"` на `"51822-51921:51822-51921/udp"` (диапазон из 100 портов).

### `deploy.sh`

- Убрать `OBF_PORT` из шапки и `.env`.
- Баннер — упоминание «UDP 51822–51921 (range)» вместо одного порта.

---

## Часть 3. API

### Новые endpoint'ы CRUD пресетов

`src/server/api/admin/obfuscator-presets/` — по существующему паттерну `src/server/api/admin/interface/`:

- `index.get.ts` — список всех пресетов с count клиентов на каждом (для UI).
- `index.post.ts` — создать пресет. Принимает `name`, опционально `ext_port` (если не указан — `findFreePort` из диапазона), `key` (опц.; auto-generate если нет), `masking`, `idle`, `dummy`, `client_wg_local_port`. После INSERT — `Obfuscator.applyAll()`.
- `[id].get.ts` / `[id].post.ts` — детали и update.
- `[id].delete.ts` — удалить. 400 если `is_default = 1`. После DELETE — `Obfuscator.applyAll()`. Клиенты с этим preset_id автоматически получат NULL благодаря `ON DELETE SET NULL`.
- `[id]/set-default.post.ts` — транзакционно: `UPDATE all SET is_default=0; UPDATE this SET is_default=1;`. После — `applyAll()`.
- `[id]/regenerate-key.post.ts` и `[id]/regenerate-port.post.ts` — по аналогии с существующими `regenerateObfuscatorKey.post.ts` / `regenerateObfuscatorPort.post.ts` в `interface/`.

Все через `definePermissionEventHandler('admin', 'any', ...)`.

### Изменения в клиент-эндпоинтах

- **`src/server/database/repositories/client/types.ts`** — `ClientCreateSchema` принимает опциональный `presetId: number | null` (default `null`). `ClientUpdateSchema` — то же.
- **`src/server/api/client/index.post.ts`** — пробрасывает `presetId` в `ClientService.create`.
- **`src/server/database/repositories/client/service.ts`** — `create()` сохраняет `presetId` (или null).
- **`src/server/utils/WireGuard.ts`** — `getClientFullConfig({ clientId })`: после получения клиента сделать `Database.obfuscatorPresets.getForClient(client)` — возвращает либо его пресет, либо default; передать в `Obfuscator.buildClientObfConf(preset, serverIp)`. Использовать new helper в `obfuscatorPreset/service.ts`:
  ```ts
  async getForClient(client) {
    return client.presetId
      ? this.get(client.presetId)
      : this.getDefault();
  }
  ```

---

## Часть 4. UI

### Новая страница `src/app/pages/admin/obfuscator-presets.vue`

Структура аналогична `src/app/pages/admin/interface.vue` (для консистентности): `FormElement` + `FormGroup` на каждый пресет в списке. Карточки с полями: name (read-only для default), ext_port, key (с кнопкой regenerate), masking (dropdown), idle, dummy, client_wg_local_port. У не-default: кнопки `Set as default` и `Delete`. Сверху списка кнопка `Add preset`.

При создании: модальное окно (`BaseDialog`) с формой; на submit POST `/api/admin/obfuscator-presets`.

Использовать существующие `Form*`-компоненты (`FormNumberField`, `FormTextField`, `FormHeading`, etc.).

### Sidebar админки

`src/app/pages/admin/index.vue` (или layout `admin.vue`) — добавить ссылку «Obfuscator presets» рядом с существующими «Interface», «Config», «Hooks».

### Удалить obfuscator-секцию из `/admin/interface.vue`

В `src/app/pages/admin/interface.vue` сейчас группа «admin.obfuscator.heading» с 8 полями + 2 кнопки regenerate. Целиком удалить (вместе с i18n-ключами `admin.obfuscator.*` если они больше нигде).

### Форма клиента — выбор пресета

Найти `ClientCreateDialog` / `ClientForm` в `src/app/components/Clients/` (где-то по аналогии с `QRCodeDialog.vue` / `ConfigDialog.vue` — точное имя выясняется при имплементации). Добавить `<select>` или `BaseSelect`:
- Опция `null` → «Use default preset»
- Список из `useFetch('/api/admin/obfuscator-presets')` с пометкой какой default.

Аналогично в форме редактирования клиента.

### Badge на карточке клиента

`src/app/components/ClientCard/*.vue` — рядом с именем клиента бейдж с именем используемого пресета (default — без бейджа или серый «default»; кастомный — цветной).

---

## Часть 5. i18n

Новые ключи в `src/i18n/locales/en.json` и `ru.json`:

- `admin.obfuscatorPresets.title`, `.desc`, `.add`, `.default`, `.setAsDefault`, `.deleteConfirm`, `.cannotDeleteDefault`, `.regenerateKey`, `.regeneratePort`, `.nameLabel`, `.extPortLabel`, `.keyLabel`, `.maskingLabel`, `.idleLabel`, `.dummyLabel`, `.clientLocalPortLabel`.
- `client.presetLabel`, `client.presetUseDefault`.
- Удалить старые `admin.obfuscator.*` ключи, которые жили в `interface.vue` (если они не используются нигде кроме него).

Для краткости — основные локали (en, ru) обновляются вручную; остальные 19 локалей пусть подтянутся при следующей итерации перевода.

---

## Затрагиваемые файлы (сводно)

**Создать**:
- `src/server/database/repositories/obfuscatorPreset/{schema.ts,types.ts,service.ts}`
- `src/server/database/migrations/0009_obfuscator_presets.sql`
- `src/server/api/admin/obfuscator-presets/{index.get.ts,index.post.ts,[id].get.ts,[id].post.ts,[id].delete.ts,[id]/set-default.post.ts,[id]/regenerate-key.post.ts,[id]/regenerate-port.post.ts}`
- `src/app/pages/admin/obfuscator-presets.vue`

**Изменить**:
- `src/server/database/repositories/client/{schema.ts,types.ts,service.ts}` — добавить `preset_id`.
- `src/server/database/repositories/interface/{schema.ts,types.ts,service.ts}` — убрать obfuscator-поля и регенераторы.
- `src/server/database/schema.ts` — зарегистрировать новый репозиторий.
- `src/server/database/sqlite.ts` — DBService инициализирует `obfuscatorPresets`-сервис.
- `src/server/database/migrations/meta/_journal.json` — entry 0009.
- `src/server/utils/Obfuscator.ts` — переписать (см. Часть 2).
- `src/server/utils/WireGuard.ts:178` — `getClientFullConfig` использует preset клиента.
- `src/server/api/client/index.post.ts`, `[clientId].post.ts` — пробросить presetId.
- `docker/s6-rc.d/wg-obfuscator/run` и `finish` — `setsid` + `pkill`.
- `docker-compose.yml` — port-range, убрать OBF_PORT.
- `deploy.sh` — убрать OBF_PORT.
- `src/app/pages/admin/interface.vue` — убрать obfuscator-блок.
- Форма клиента в `src/app/components/Clients/*` — поле выбора пресета.
- `src/app/components/ClientCard/*` — badge пресета.
- `src/i18n/locales/{en,ru}.json` — новые ключи + удаление старых.

**Удалить**:
- `src/server/api/admin/interface/regenerateObfuscatorKey.post.ts` — переедет в presets.
- `src/server/api/admin/interface/regenerateObfuscatorPort.post.ts` — то же.

---

## Verification

1. **Свежий деплой (миграция с нуля)**:
   - Билд образа из текущего исходника, `docker compose up -d`.
   - `docker exec phobos sqlite3 /etc/wireguard/phobos.db 'SELECT * FROM obfuscator_presets_table;'` — должна быть одна строка с `is_default=1`, `ext_port=51822`, валидный key.
   - `docker exec phobos cat /run/wg-obfuscator.conf` — одна секция `[preset-1]`.
   - `docker exec phobos ps -ef | grep wg-obfuscator | grep -v grep` — ровно один процесс (нет fork'а при одной секции).

2. **Создание пресета**:
   - В UI `/admin/obfuscator-presets` → Add preset → name=«alt», masking=AUTO, dummy=4.
   - После сохранения `cat /run/wg-obfuscator.conf` — две секции, разные `source-lport`/`key`.
   - `ps -ef | grep wg-obfuscator | grep -v grep` — **два** процесса (родитель + 1 fork).

3. **Привязка клиента**:
   - Создать клиента, выбрать пресет «alt».
   - Скачать конфиг → блок `[instance]` ссылается на `ext_port` пресета «alt» (не default).
   - На самом клиенте wg-obfuscator должен через этот порт пробивать туннель.

4. **Удаление кастомного пресета**:
   - С UI удалить «alt».
   - В БД у клиента, который был привязан, `preset_id = NULL`.
   - Скачать конфиг этого клиента заново — теперь использует параметры default.
   - `/run/wg-obfuscator.conf` снова одна секция, процессов снова один.

5. **set-as-default**:
   - Создать «alt», нажать «Set as default». В таблице `is_default` переключился.
   - Клиенты с `preset_id IS NULL` теперь скачивают конфиг с параметрами «alt».

6. **Защита default**:
   - DELETE `/api/admin/obfuscator-presets/<default_id>` → 400 with «Cannot delete default preset».

7. **Защита диапазона портов**:
   - Попытаться создать пресет с `ext_port=80` → 400 (вне диапазона).
   - Создать пресет с `ext_port=51822` когда он уже занят default → 409 (unique).

8. **Восстановление после рестарта контейнера**:
   - `docker compose restart phobos` — после старта `applyAll()` восстанавливает `/run/wg-obfuscator.conf`, все instance'ы поднимаются.

9. **Cleanup fork-child'ов**:
   - С двумя пресетами `s6-svc -d /run/service/wg-obfuscator` — `ps -ef | grep wg-obfuscator` пусто. `s6-svc -u` — снова два процесса. Без `setsid+pkill` зомби бы остались.

10. **Type-check**:
    - `cd src && pnpm typecheck` — без ошибок.
    - `cd src && pnpm lint` — без новых warnings.
