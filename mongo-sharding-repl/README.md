# MongoDB Sharding with Replication

Проект с шардированием и репликацией MongoDB.

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

### Роутер и приложение
- **mongos_router** — Роутер MongoDB (порт 27020)
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

Скрипт выполняет:
- Инициализацию Config Server Replica Set (3 ноды)
- Инициализацию Shard 1 Replica Set (3 ноды)
- Инициализацию Shard 2 Replica Set (3 ноды)
- Добавление шардов в кластер через mongos
- Включение шардирования для базы `somedb`
- Шардирование коллекции `helloDoc` по полю `age` (hashed)

### 3. Заполнение данными

```bash
./scripts/init-data.sh
```

Вставляет 1000 тестовых документов.

### 4. Проверка работы

```bash
./scripts/check-shards.sh
```

Показывает:
- Статус шардирования
- Статус репликации каждого Replica Set
- Количество документов на каждом шарде
- Общее количество документов

## Проверка через API

Откройте в браузере: http://localhost:8080

Документация API: http://localhost:8080/docs

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

### Проверка статуса репликации

```bash
# Config Server
docker compose exec -T configSrv1 mongosh --port 27017 --quiet --eval "rs.status()"

# Shard 1
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status()"

# Shard 2
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "rs.status()"
```

## Остановка

```bash
docker compose down
```

Для удаления данных:

```bash
docker compose down -v
```
