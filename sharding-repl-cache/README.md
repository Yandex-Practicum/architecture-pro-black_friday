# MongoDB Sharding with Replication and Redis Cache

Проект с шардированием, репликацией MongoDB и кэшированием Redis.

## Архитектура

### Config Server Replica Set (3 ноды)
- **configSrv1** — Config Server (primary)
- **configSrv2** — Config Server (secondary)
- **configSrv3** — Config Server (secondary)

### Shard 1 Replica Set (3 ноды)
- **shard1-1** — Primary (порт 27018)
- **shard1-2** — Secondary (порт 27018)
- **shard1-3** — Secondary (порт 27018)

### Shard 2 Replica Set (3 ноды)
- **shard2-1** — Primary (порт 27018)
- **shard2-2** — Secondary (порт 27018)
- **shard2-3** — Secondary (порт 27018)

### Роутер, кэш и приложение
- **mongos_router** — Роутер MongoDB (порт 27020)
- **redis** — Redis кэш (порт 6379)
- **pymongo_api** — API приложение (порт 8080)

## Быстрый старт

### 1. Запуск контейнеров

```bash
docker compose up -d
```

### 2. Инициализация шардирования и репликации

```bash
./scripts/init-sharding.sh
```

### 3. Заполнение данными

```bash
./scripts/init-data.sh
```

### 4. Проверка работы

```bash
./scripts/check-shards.sh
```

## Проверка кэширования

Кэширование работает для эндпоинта `/{collection_name}/users`.

### Тест производительности

Первый запрос (без кэша, ~1 сек из-за time.sleep в коде):
```bash
time curl http://localhost:8080/helloDoc/users
```

Второй запрос (из кэша, <100 мс):
```bash
time curl http://localhost:8080/helloDoc/users
```

### Проверка через браузер

1. Откройте: http://localhost:8080/helloDoc/users
2. Первый запрос займёт ~1 секунду
3. Обновите страницу — ответ придёт мгновенно (<100 мс)

### Проверка статуса кэша

На главной странице http://localhost:8080 в ответе:
```json
{
  "cache_enabled": true,
  ...
}
```

## API

- Главная страница: http://localhost:8080
- Документация Swagger: http://localhost:8080/docs
- Список пользователей (с кэшем): http://localhost:8080/helloDoc/users

## Ручная инициализация

### Инициализация Config Server Replica Set

```bash
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
})
EOF
```

### Инициализация Shard 1 Replica Set

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF
```

### Инициализация Shard 2 Replica Set

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF
```

### Добавление шардов в кластер

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF
```

### Включение шардирования

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb")
use somedb
db.helloDoc.createIndex({ "age": "hashed" })
sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
EOF
```

### Заполнение данными

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "user" + i})
}
EOF
```

## Остановка

```bash
docker compose down
```

Для удаления данных:

```bash
docker compose down -v
```
