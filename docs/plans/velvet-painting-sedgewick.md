# План: Исправление багов конфигурации + развёртывание на VPS

## Context

Клиент не подключается к серверу после установки пакета. Причина — два конкретных бага в исходном коде, которые приводят к несоответствию конфигурации клиента и сервера.

---

## Баги, найденные в исходном коде

### Баг 1 — КРИТИЧЕСКИЙ: `detectPublicIpV4()` возвращает IP контейнера, а не VPS

**Файл:** `src/server/utils/Obfuscator.ts:53–63`

```typescript
async detectPublicIpV4(): Promise<string> {
  const route = await exec('ip route');
  const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
  // ...
  const out = await exec(`ip -4 addr show dev ${iface} scope global`);
  const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
  return ip;
}
```

**Почему ломается:** docker-compose использует bridge-сеть `wg` с подсетью `10.42.42.0/24`. Контейнер получает статический IP `10.42.42.42`. Команда `ip route` внутри контейнера показывает маршрут через `eth0` с IP `10.42.42.42`. Именно это значение записывается в `serverPublicIpV4`.

В клиентском пакете `wg-obfuscator.conf` получает:
```
target = 10.42.42.42:51822   ← внутренний IP, недоступен из интернета!
```
Вместо:
```
target = 217.60.186.63:51822  ← публичный IP VPS
```

Рукопожатия нет, потому что клиент стучится в никуда.

**Исправление:** В `Obfuscator.Startup()` перед вызовом `detectPublicIpV4()` проверять env-переменную `WG_HOST` (или `SERVER_PUBLIC_IP`). Также исправить саму `detectPublicIpV4()` — добавить fallback через внешний HTTP-сервис (`curl ifconfig.me`) если `ip addr` вернул RFC-1918 адрес.

```typescript
// Новая логика detectPublicIpV4():
async detectPublicIpV4(): Promise<string> {
  // 1. Сначала проверить env
  const envIp = process.env.WG_HOST;
  if (envIp && /^\d+\.\d+\.\d+\.\d+$/.test(envIp)) return envIp;

  // 2. ip addr через default route
  const route = await exec('ip route');
  const iface = route.match(/^default.+dev\s+(\S+)/m)?.[1];
  if (iface) {
    const out = await exec(`ip -4 addr show dev ${iface} scope global`);
    const ip = out.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/)?.[1];
    if (ip && !isPrivateIp(ip)) return ip;
  }

  // 3. Fallback: внешний сервис
  const pub = await exec('curl -sf --max-time 5 https://api.ipify.org').catch(() => '');
  if (pub && /^\d+\.\d+\.\d+\.\d+$/.test(pub)) return pub;

  throw new Error('Cannot detect public IPv4. Set WG_HOST env variable.');
}
```

Добавить вспомогательную функцию:
```typescript
function isPrivateIp(ip: string): boolean {
  return /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)/.test(ip);
}
```

В `docker-compose.yml` добавить:
```yaml
environment:
  - OBF_PORT=${OBF_PORT:-51822}
  - WG_HOST=${WG_HOST:-}       # ← добавить
```

---

### Баг 2 — ВЫСОКИЙ: Отсутствует `await` при сохранении AmneziaWG заголовков

**Файл:** `src/server/utils/WireGuard.ts:227`

```typescript
wgInterface.h1 = String(h1)!;
wgInterface.h2 = String(h2)!;
wgInterface.h3 = String(h3)!;
wgInterface.h4 = String(h4)!;

Database.interfaces.update(wgInterface);  // ← MISSING await!
```

**Почему ломается:** Параметры H1–H4 (случайные числа для AmneziaWG обфускации) обновляются в памяти и применяются к запускаемому WireGuard интерфейсу. Но в базу данных они могут **не успеть записаться** до перехода к следующим операциям.

При перезапуске контейнера:
1. `h1 === '0'` (в БД старое значение) → генерируются НОВЫЕ случайные H1–H4
2. WireGuard стартует с новыми заголовками
3. Все существующие клиенты имеют в своих `.conf` файлах **старые** H1–H4
4. Рукопожатие невозможно → туннель не поднимается

**Исправление:** Добавить `await`:
```typescript
await Database.interfaces.update(wgInterface);  // ← добавить await
```

---

## Критические файлы

| Файл | Строки | Что менять |
|---|---|---|
| `src/server/utils/Obfuscator.ts` | 53–63, 105–148 | `detectPublicIpV4()` + проверка `WG_HOST` в `Startup()` |
| `src/server/utils/WireGuard.ts` | 227 | Добавить `await` |
| `docker-compose.yml` | 13 | Добавить `WG_HOST` env |

---

## Развёртывание на VPS (root@217.60.186.63)

### Шаг 1: Исправить баги (до деплоя)

Применить два исправления выше к исходному коду.

### Шаг 2: Подключиться к VPS и добавить SSH-ключ

```bash
# Сгенерировать ключ (если нет)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Подключиться с паролем и добавить ключ
ssh-copy-id -i ~/.ssh/id_rsa.pub root@217.60.186.63
# Пароль: OLy=uAilfDBq3vyHl8
```

Или через SSH вручную:
```bash
ssh root@217.60.186.63
# Выполнить на сервере:
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "<публичный ключ>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Шаг 3: Установить Docker на VPS

```bash
apt update && apt install -y docker.io docker-compose-plugin
systemctl enable docker && systemctl start docker
```

### Шаг 4: Скопировать проект и развернуть (без SSL)

```bash
# Скопировать проект на VPS
rsync -avz --exclude='.git' --exclude='node_modules' --exclude='.output' \
  /root/wg-easy/ root@217.60.186.63:/opt/wg-easy/

# На VPS:
cd /opt/wg-easy
WG_HOST=217.60.186.63 OBF_PORT=51822 docker compose up -d --build
```

### Шаг 5: Проверить, что контейнер запустился

```bash
docker compose logs -f wg-easy
docker compose ps
```

Web UI будет доступен на `http://217.60.186.63:80`.

---

## Проверка после деплоя

### На сервере

```bash
# Обфускатор слушает нужный порт
ss -ulnp | grep 51822

# WireGuard поднялся
docker exec wg-easy wg show

# IP в БД корректный (должен быть 217.60.186.63)
docker exec wg-easy sqlite3 /app/server/data/db.sqlite \
  "SELECT server_public_ip_v4, obfuscator_ext_port, obfuscator_key FROM interfaces_table;"
```

### После первичной инициализации (пользователь создаёт клиента)

```bash
# Скачать клиентский пакет и распаковать
tar xzf phobos-*.tar.gz
cat phobos-*/wg-obfuscator.conf
# Проверить: target = 217.60.186.63:51822  ← должен быть публичный IP

cat phobos-*/*.conf
# Проверить: Endpoint = 127.0.0.1:13255  ← локальный обфускатор
```

---

## Порядок выполнения

1. Исправить `WireGuard.ts:227` — добавить `await` (1 строка)
2. Исправить `Obfuscator.ts` — добавить `isPrivateIp()` + обновить `detectPublicIpV4()` + добавить проверку `WG_HOST` в `Startup()`
3. Обновить `docker-compose.yml` — добавить `WG_HOST` env
4. SSH на VPS → добавить RSA ключ
5. Скопировать проект → запустить `docker compose up -d --build` с `WG_HOST=217.60.186.63`
6. Уведомить пользователя → он проводит инициализацию через Web UI
