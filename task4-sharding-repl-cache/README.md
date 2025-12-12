# sharding-repl-cache
## Репликация + Шардирование + Redis-кеширование + pymongo-api

Этот проект реализует **второй вариант схемы** (2 шарда, репликация) и добавляет **кеширование в Redis**:

- 2 шарда (shard1, shard2)
- Каждый шард — реплика-сет из 3 реплик
- 3 config-сервера (реплика-сет `configReplSet`)
- `mongos` — точка входа в кластер MongoDB
- `redis` — кеш запросов
- `pymongo-api` — приложение, использующее MongoDB и Redis
- БД: `somedb`
- Коллекция: `helloDoc`
- Эндпоинт с кешированием: `/helloDoc/users`

---

## 1. Структура кластера

### Config servers (`configReplSet`)
- configsvr1
- configsvr2
- configsvr3

### Шард 1 (`shard1ReplSet`)
- shard1-1
- shard1-2
- shard1-3

### Шард 2 (`shard2ReplSet`)
- shard2-1
- shard2-2
- shard2-3

### Маршрутизатор
- mongos (service name: `mongos`, container: `mongos-cache`)

### Redis
- redis (service name: `redis`, container: `redis-cache`)

### Приложение
- pymongo_api_cache (service name: `pymongo_api`)
  - `MONGODB_URL = mongodb://mongos:27017`
  - `MONGODB_DATABASE_NAME = somedb`
  - `REDIS_URL = redis://redis:6379`

---

## 2. Запуск проекта

Из директории `sharding-repl-cache`:

```bash
docker compose up -d --build
docker compose ps
```

Убедитесь, что сервисы `mongos`, `redis` и `pymongo_api` запущены.

---

## 3. Инициализация репликации и шардирования

Для настройки репликации и шардирования используем скрипт:

```bash
scripts/mongo-sharding-repl-init.sh
```

Сделать исполняемым (один раз):

```bash
chmod +x scripts/mongo-sharding-repl-init.sh
```

Запуск:

```bash
./scripts/mongo-sharding-repl-init.sh
```

Скрипт:

- инициализирует реплика-сет `configReplSet`
- инициализирует `shard1ReplSet` и `shard2ReplSet`
- добавляет шарды через `sh.addShard(...)`
- включает шардинг для БД `somedb`
- шардирует коллекцию `somedb.helloDoc` по `_id: "hashed"`

Повторный запуск безопасен — все операции idempotent.

---

## 4. Наполнение коллекции test-данными

Скрипт:

```bash
./scripts/mongo-init.sh
```

Внутри он выполняет вставку 1000 документов через `mongos`:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}
EOF
```

Проверка общего количества документов:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Ожидаем значение ≥ 1000.

---

## 5. Проверка распределения по шардам

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.aggregate([
  { \$collStats: { count: {} } }
]).pretty()
EOF
```

Вывод покажет количество документов на каждом шарде.

---

## 6. Проверка количества реплик

### Шард 1:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.length
EOF
```

### Шард 2:

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.length
EOF
```

### Config servers:

```bash
docker compose exec -T configsvr1 mongosh --port 27019 --quiet <<EOF
rs.status().members.length
EOF
```

Ожидаем значение `3` в каждом случае.

---

## 7. Проверка работы приложения и кеша Redis

Приложение доступно по адресу:

```text
http://localhost:8080
```

### 7.1. Общая информация по данным

Приложение должно отображать:

- Общее количество документов в `somedb.helloDoc` (≥ 1000)
- Количество реплик

### 7.2. Эндпоинт с кешированием: `/helloDoc/users`

Эндпоинт:

```text
GET http://localhost:8080/helloDoc/users
```

- Первый запрос — идёт в MongoDB, сохраняет результат в Redis.
- Повторные запросы — читают данные из Redis и выполняются значительно быстрее (< 100 мс).

#### Как замерить время

Вариант 1 — с помощью `curl`:

```bash
time curl -s http://localhost:8080/helloDoc/users > /dev/null
time curl -s http://localhost:8080/helloDoc/users > /dev/null
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

- Первый `time` обычно медленнее (>100 мс)
- Второй и последующие — заметно быстрее (<100 мс)

Вариант 2 — через DevTools браузера:

- Открыть вкладку **Network**
- Вызвать `/helloDoc/users` несколько раз
- Смотреть `Time` / `Duration` — второй и последующие запросы должны быть <100 мс
