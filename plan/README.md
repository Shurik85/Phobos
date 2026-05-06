# Техническая документация слияния Phobos → wg-easy

Набор документов, детализирующих план `/root/wg-easy/MERGE_PLAN.md` до уровня конкретных контрактов, сигнатур, форматов файлов и последовательности правок.

## Статус реализации

Все 10 фаз выполнены — см. [PROGRESS.md](./PROGRESS.md) с отметками и списком отклонений от плана.

## Порядок чтения

| # | Документ | Фаза из MERGE_PLAN | Содержание |
|---|----------|-------------------|------------|
| 1 | [architecture.md](./architecture.md) | — | Целевая архитектура, компоненты, потоки данных |
| 2 | [phase-00-repository.md](./phase-00-repository.md) | 0 | Реорганизация дерева, перемещения, удаления |
| 3 | [phase-01-docker.md](./phase-01-docker.md) | 1 | Dockerfile, s6-overlay, docker-compose |
| 4 | [phase-02-database.md](./phase-02-database.md) | 2 | Схема БД, миграция, `installLink` |
| 5 | [phase-03-obfuscator.md](./phase-03-obfuscator.md) | 3 | `Obfuscator` сервис, формат конфига |
| 6 | [phase-04-package.md](./phase-04-package.md) | 4 | `PhobosPackage`, состав tarball'а, install.sh |
| 7 | [phase-05-wg-helper.md](./phase-05-wg-helper.md) | 5 | Изменения генератора WG-конфигов |
| 8 | [phase-06-api.md](./phase-06-api.md) | 6 | REST endpoints, Zod-схемы |
| 9 | [phase-07-lifecycle.md](./phase-07-lifecycle.md) | 7 | Запуск, setup-флоу, инвалидация кэша |
| 10 | [phase-08-ui.md](./phase-08-ui.md) | 8 | ClientCard, админ-страница, i18n |
| 11 | [phase-09-cleanup.md](./phase-09-cleanup.md) | 9, 10 | Вспомогательное + полная зачистка рудиментов |
| 12 | [acceptance-and-commits.md](./acceptance-and-commits.md) | — | Критерии приёмки, последовательность 13 коммитов |

## Терминология

| Термин | Значение |
|--------|----------|
| **Obfuscator** | C-демон `wg-obfuscator`, UDP-прокси с STUN-маскировкой и XOR-обфускацией |
| **Install-link** | Токен-ссылка на установочный скрипт клиента (замена OneTimeLink) |
| **Phobos-package** | tar.gz с WG-конфигом, obfuscator-конфигом, multi-arch бинарями и платформенными установщиками |
| **s6-overlay** | Супервизор процессов для контейнера, заменяет `dumb-init` |
| **Loopback-WG** | WireGuard-сервер, слушающий публичный порт, но принимающий только с 127.0.0.1 |

## Ключевые ссылки в исходниках

| Путь | Описание |
|------|----------|
| `src/server/database/repositories/` | Drizzle-репозитории (схема + prepared statements) |
| `src/server/utils/WireGuard.ts` | Управление WG-интерфейсом |
| `src/server/utils/wgHelper.ts` | Генерация WG-конфигов |
| `src/server/api/` | Nitro REST endpoints |
| `src/app/components/ClientCard/` | UI кнопок клиента |
| `src/app/pages/admin/interface.vue` | Админ-страница интерфейса |
| `src/i18n/locales/` | Файлы локализации |
| `Phobos/wg-obfuscator/` | C-исходники и multi-arch бинари (после Фазы 0 → `src/phobos-obfuscator/`) |
| `Phobos/client/templates/` | Shell-шаблоны (после Фазы 0 → `src/server/phobos/templates/`) |
