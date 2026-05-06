# Context

Интеграция автоматического обновления Let's Encrypt сертификатов (для домена и IP-адреса) в wg-easy по образцу `/root/3x-ui/source/x-ui.sh`. Текущий `CertService.ts` имеет баги (не импортирован `execSync`, нет `--reloadcmd`, нет `--upgrade --auto-upgrade`) и полностью отсутствует поддержка IP-сертификатов. acme.sh теряет состояние при перезапуске контейнера (нет persistent volume), порт 80 не проброшен.

---

# Plan

## 1. `src/server/utils/CertService.ts` — полная перезапись

- Добавить `execSync` в импорт из `node:child_process`
- Исправить `issueLetsEncrypt(domain)`:
  - Установка acme.sh **без** `--no-cron` (убрать флаг)
  - `--upgrade --auto-upgrade` после установки
  - `--reloadcmd "kill 1"` в `--installcert` → при автообновлении acme.sh будет убивать PID 1 → Docker перезапустит контейнер → node/run перечитает новый сертификат
  - Исправить переменную `name` (сейчас используется до объявления)
  - Все `execSync` заменить на `execFileSync` с массивом аргументов (безопаснее)
- Добавить `issueLetsEncryptIp(ip)`:
  - Флаги `--certificate-profile shortlived --days 6` (6-дневный сертификат, как в x-ui.sh)
  - Тот же `--reloadcmd "kill 1"`
  - Тот же `--upgrade --auto-upgrade`

Ключевая логика для обоих методов:
```
acme.sh --issue -d <host> --standalone --server letsencrypt [--certificate-profile shortlived --days 6] --httpport 80 --force
acme.sh --installcert -d <host> --fullchain-file <certPath> --key-file <keyPath> --reloadcmd "kill 1"
acme.sh --upgrade --auto-upgrade
storeCert / activateCert
```

Файл: `src/server/utils/CertService.ts`

## 2. `src/server/api/setup/tls.post.ts` — добавить режим `letsencrypt-ip`

- В Zod-схему добавить `z.object({ mode: z.literal('letsencrypt-ip') })` (без доп. полей — IP берётся из `userConfig.host`)
- В обработчик добавить ветку: `else if (body.mode === 'letsencrypt-ip') { await issueLetsEncryptIp(host); }`

Файл: `src/server/api/setup/tls.post.ts`

## 3. `src/app/pages/setup/5.vue` — добавить кнопку `letsencrypt-ip`

- В массив `modes` добавить: `{ value: 'letsencrypt-ip', label: t('setup.tls.letsencryptIp'), desc: t('setup.tls.letsencryptIpDesc') }`
- Тип `Mode` расширить: `'self-signed' | 'import' | 'letsencrypt' | 'letsencrypt-ip' | 'skip'`
- В теле `submit()` добавить кейс для `letsencrypt-ip`: `{ mode: 'letsencrypt-ip' }` (аналогично `self-signed`)

Файл: `src/app/pages/setup/5.vue`

## 4. i18n — добавить ключи для `letsencrypt-ip`

В `src/i18n/locales/en.json` и `src/i18n/locales/ru.json` в секцию `setup.tls` добавить:
- `letsencryptIp` — название кнопки
- `letsencryptIpDesc` — описание (shortlived 6-дневный сертификат для IP, автообновление)

Файлы: `src/i18n/locales/en.json`, `src/i18n/locales/ru.json`

## 5. `docker-compose.yml` — добавить порт 80 и volume для acme.sh

```yaml
volumes:
  acme_data:          # новый

services:
  wg-easy:
    ports:
      - "80:80"       # для HTTP-01 ACME challenge
    volumes:
      - acme_data:/root/.acme.sh   # персистентность состояния acme.sh
```

Файл: `docker-compose.yml`

## 6. s6 сервис `acme-renew` — ежедневный cron-запуск

Создать `docker/s6-rc.d/acme-renew/type` с содержимым `longrun`.

Создать `docker/s6-rc.d/acme-renew/run`:
```sh
#!/command/with-contenv sh
exec /bin/sh -c 'while true; do sleep 86400; ~/.acme.sh/acme.sh --cron --home ~/.acme.sh; done'
```

Создать `docker/s6-rc.d/user/contents.d/acme-renew` (пустой файл — регистрирует сервис в bundle).

Обновить `Dockerfile`: добавить `chmod +x` для `acme-renew/run`.

Файлы:
- `docker/s6-rc.d/acme-renew/type`
- `docker/s6-rc.d/acme-renew/run`
- `docker/s6-rc.d/user/contents.d/acme-renew`
- `Dockerfile`

## 7. Пересборка и деплой на VPS

```bash
rsync -av --exclude='.git' /root/wg-easy/ root@94.232.40.58:/root/wg-easy-deploy/
ssh root@94.232.40.58 "cd /root/wg-easy-deploy && docker build --no-cache -t wg-easy . && docker compose -f docker-compose.local.yml up -d"
```

---

# Verification

1. Открыть `http://94.232.40.58:51821/setup` → пройти до шага 5
2. Выбрать "Let's Encrypt для IP" → нажать "Сгенерировать"
3. Убедиться, что сервер перезапускается и открывается `https://94.232.40.58:51821/login`
4. Проверить через `docker exec wg-easy ~/.acme.sh/acme.sh --list`, что сертификат зарегистрирован с `--reloadcmd "kill 1"`
5. Проверить volume: `docker volume inspect wg-easy-deploy_acme_data` — данные присутствуют
6. Через 6 дней (или симуляцией `--renew-hook`) убедиться, что сертификат обновляется автоматически
