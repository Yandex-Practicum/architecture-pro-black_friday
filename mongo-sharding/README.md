# MongoDB Sharding

Проект с настроенным шардированием MongoDB.

## Архитектура

- **configSrv** — Config Server (порт 27017)
- **shard1** — Шард 1 (порт 27018)
- **shard2** — Шард 2 (порт 27019)
- **mongos_router** — Роутер MongoDB (порт 27020)
- **pymongo_api** — API приложение (порт 8080)

## Быстрый старт

### 1. Запуск контейнеров

```bash
docker compose up -d
```

### 2. Инициализация шардирования

```bash
./scripts/init-sharding.sh
```

Скрипт выполняет:
- Инициализацию Config Server Replica Set
- Инициализацию Shard 1 и Shard 2 Replica Sets
- Добавление шардов в кластер через mongos
- Включение шардирования для базы `somedb`
- Создание хешированного индекса и шардирование коллекции `helloDoc` по полю `age`

### 3. Заполнение данными

```bash
./scripts/init-data.sh
```

Вставляет 1000 тестовых документов в коллекцию `helloDoc`.

### 4. Проверка работы

```bash
./scripts/check-shards.sh
```

Показывает:
- Статус шардирования
- Количество документов на каждом шарде
- Общее количество документов

## Проверка через API

Откройте в браузере: http://localhost:8080

Документация API: http://localhost:8080/docs

## Ручная инициализация (альтернатива скриптам)

### Инициализация Config Server

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF
```

### Инициализация Shard 1

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
```

### Инициализация Shard 2

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
})
EOF
```

### Добавление шардов в кластер

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
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

### Проверка количества документов на шардах

```bash
# Shard 1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Shard 2
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
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

