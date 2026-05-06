# Критерии приёмки и последовательность коммитов

## 13 коммитов

| № | Тип | Сообщение | Фаза |
|---|-----|-----------|------|
| 1 | chore | `relocate phobos obfuscator and templates into src tree` | 0 |
| 2 | feat(docker) | `s6-overlay supervision for node + wg-obfuscator` | 1 |
| 3 | feat(db) | `add obfuscator fields to interface, rename oneTimeLink to installLink` | 2 |
| 4 | feat(server) | `Obfuscator utility and service lifecycle` | 3 |
| 5 | feat(server) | `PhobosPackage tarball builder with in-memory cache` | 4 |
| 6 | refactor(wg) | `client endpoint via loopback obfuscator` | 5 |
| 7 | feat(api) | `install token endpoints and client package download` | 6 |
| 8 | feat(api) | `admin obfuscator configuration and regenerate routes` | 6 |
| 9 | feat(ui) | `rewire ClientCard buttons (OTL→copy install, Download→tarball)` | 8 |
| 10 | feat(ui) | `admin obfuscator settings page` | 8 |
| 11 | chore | `purge legacy oneTimeLink flow and stale i18n` | 10 |
| 12 | docs | `rewrite README for integrated product` | 9 |
| 13 | chore | `final purge — no legacy references` | 10 |

## Зависимости между коммитами

```
1 ─► 2 ─► 3 ─► 4 ─► 5 ─► 6 ─► 7 ─► 8 ─► 9 ─► 10 ─► 11 ─► 12 ─► 13
         │    │    │    │              ▲              ▲
         │    │    │    └──────────────┘              │
         │    │    └─────────────────────────────────►│
         │    └──────────────────────────────────────►│
         └──────────────────────────────────────────►│
```

Пояснения:
- `3` (схема БД) — фундамент для `4, 5, 7, 8`.
- `4` (Obfuscator) — требуется `7, 8` (API-ручки админа).
- `5` (PhobosPackage) — требуется `7` (endpoints install).
- `6` (wgHelper) — независим от 4/5, но нужен `5` для корректного содержимого клиентского `.conf` в tarball'е.
- `9, 10` (UI) — после 7, 8 (API готово).
- `11-13` — в самом конце, когда все фазы завершены.

## Детализация затрагиваемых файлов по коммитам

### Commit 1: relocate phobos

```
renames:
  Phobos/wg-obfuscator/       → src/phobos-obfuscator/
  Phobos/client/templates/    → src/server/phobos/templates/
deletes:
  Phobos/server/
  Phobos/docs/
  Phobos/README.md
  Phobos/CLAUDE.md
  Phobos/phobos-deploy.sh
```

### Commit 2: s6-overlay

```
modified:
  Dockerfile
  docker-compose.yml
  docker-compose.dev.yml
added:
  docker/s6-rc.d/user/contents.d/node
  docker/s6-rc.d/user/contents.d/wg-obfuscator
  docker/s6-rc.d/node/type
  docker/s6-rc.d/node/run
  docker/s6-rc.d/node/finish
  docker/s6-rc.d/node/dependencies.d/base
  docker/s6-rc.d/wg-obfuscator/type
  docker/s6-rc.d/wg-obfuscator/run
  docker/s6-rc.d/wg-obfuscator/finish
  docker/s6-rc.d/wg-obfuscator/dependencies.d/base
```

### Commit 3: db schema

```
modified:
  src/server/database/repositories/interface/schema.ts
  src/server/database/repositories/interface/types.ts
  src/server/database/repositories/client/schema.ts
  src/server/database/schema.ts
  src/server/utils/Database.ts
added:
  src/server/database/repositories/installLink/schema.ts
  src/server/database/repositories/installLink/service.ts
  src/server/database/repositories/installLink/types.ts
  src/server/database/migrations/NNNN_<name>.sql  (автогенерация)
deleted:
  src/server/database/repositories/oneTimeLink/schema.ts
  src/server/database/repositories/oneTimeLink/service.ts
  src/server/database/repositories/oneTimeLink/types.ts
```

### Commit 4: Obfuscator utility

```
added:
  src/server/utils/Obfuscator.ts
modified:
  src/server/utils/types.ts          (OBFUSCATOR_DEBUG)
  src/server/plugins/<startup>.ts    (Obfuscator.Startup)
  Dockerfile                          (ENV DEBUG=...,Obfuscator)
```

### Commit 5: PhobosPackage

```
added:
  src/server/utils/PhobosPackage.ts
modified:
  src/package.json                   (+tar-stream, +@types/tar-stream)
  src/pnpm-lock.yaml
```

### Commit 6: wgHelper refactor

```
modified:
  src/server/utils/wgHelper.ts
  src/test/unit/wgHelper.spec.ts
```

### Commit 7: install endpoints + package download

```
added:
  src/server/api/client/[clientId]/generateInstallLink.post.ts
  src/server/api/client/[clientId]/package.tar.gz.get.ts
  src/server/api/install/[token]/index.get.ts
  src/server/api/install/[token]/package.tar.gz.get.ts
deleted:
  src/server/api/client/[clientId]/generateOneTimeLink.post.ts
  src/server/api/client/[clientId]/configuration.get.ts
  src/app/pages/clients/[otl].vue
```

### Commit 8: admin obfuscator endpoints

```
modified:
  src/server/api/admin/interface/index.post.ts
added:
  src/server/api/admin/interface/regenerateObfuscatorKey.post.ts
  src/server/api/admin/interface/regenerateObfuscatorPort.post.ts
```

### Commit 9: ClientCard rewiring

```
modified:
  src/app/components/ClientCard/ClientCard.vue
  src/app/components/ClientCard/OneTimeLinkBtn.vue  (→ InstallLinkBtn.vue если переименовали)
  src/app/components/ClientCard/Config.vue
  src/app/utils/types.ts                             (LocalClient без oneTimeLink)
  src/app/stores/clientsStore.ts                     (если была логика OTL)
deleted:
  src/app/components/ClientCard/OneTimeLink.vue
```

### Commit 10: admin UI

```
modified:
  src/app/pages/admin/interface.vue
  src/server/api/admin/general.get.ts               (добавляется obfuscatorPortPinned)
```

### Commit 11: i18n + stale cleanup

```
modified:
  src/i18n/locales/*.json                            (все локали)
```

### Commit 12: docs

```
modified:
  README.md
  CHANGELOG.md
deleted:
  docs/* (всё, относящееся к OTL/configuration-download)
```

### Commit 13: final purge

```
mixed:
  — любые последние точечные удаления, обнаруженные финальными грепами
  — зачистка orphan-иконок в src/app/components/Icons/
  — удаление неиспользуемых утилит, если такие остались
```

## Критерии приёмки (финальные)

### Функциональные

1. `docker compose up` — образ стартует; оба service'а (`node`, `wg-obfuscator`) supervised; healthcheck зелёный.
2. Первый вход в UI → setup → создание admin-аккаунта → интерфейс автоматически создан с obfuscator-параметрами.
3. Создание клиента → карточка показывает: `Switch, Edit, QRCode, Config, OneTimeLinkBtn`.
4. Клик по OTL-кнопке → toast `"Install command copied"`, буфер обмена содержит:
   ```
   curl -sL http://<origin>/api/install/<token> | sh
   ```
5. Выполнение этой команды на тестовом Linux-клиенте → скачивается tarball, распаковывается, запускается `install-router.sh`, устанавливается `wg-obfuscator` и настраивается WG. Ручное подключение успешно.
6. Клик по Download → скачивается `phobos-<slug>.tar.gz`.
7. Клик по QR → показывает WG-конфиг в QR.
8. Админ → Interface → Obfuscator: меняет level, key regenerate, masking → после сохранения:
   - `/etc/wg-obfuscator.conf` обновлён.
   - `wg-obfuscator` перезапущен (`s6-svstat` показывает свежий uptime).
   - Свежий пакет скачивается по install-link (содержит новые параметры).

### Нефункциональные

9. `pnpm tsc --noEmit` — без ошибок.
10. `pnpm lint` — без warnings/errors.
11. `pnpm test` — все тесты зелёные, покрытие новых модулей > 70%.
12. Все грепы из Phase 10 — пустые.
13. `docker image ls` — размер образа увеличен не более чем на 30 МБ (multi-arch бинари + templates).

### Безопасность

14. Публичный WG-порт 51820 не открыт наружу (`nmap <host> -p 51820 -sU` → filtered/closed).
15. Публичный obfuscator-порт 51822 (или заданный) открыт.
16. Без валидного токена `/api/install/<rand>` → 404; с истёкшим токеном → 410.
17. `/api/client/:id/package.tar.gz` без аутентификации → 401.

### Документация

18. README содержит актуальный quickstart без упоминаний старого OTL-флоу.
19. CHANGELOG содержит breaking-секцию.
20. `plan/` каталог удалён после релиза (или остаётся как исторический документ — на усмотрение).

## Rollback-план

В случае критической регрессии — revert commits 1-13 как единый range:

```bash
git revert --no-commit <first>..<last>
git commit -m "revert: rollback Phobos merge"
```

Альтернатива: сохранить отдельный `release/pre-phobos` тег перед 1-м коммитом и при необходимости `git reset --hard release/pre-phobos`.

## Окончание проекта слияния

После мерджа 13 коммитов в `main`:
- Тэг `v<X.Y.Z>` с breaking change notice.
- Релиз в GHCR с новым образом.
- Каталог `/root/wg-easy/plan/` можно оставить в репозитории (как исторический документ) либо удалить коммитом `chore: drop merge-plan artifacts` — решение пользователя.
