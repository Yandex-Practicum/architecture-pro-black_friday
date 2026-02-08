# mongo-sharding

MongoDB с шардированием (2 шарда) для онлайн-магазина "Мобильный мир".

## Архитектура

- **pymongo_api** — приложение (порт 8080)
- **mongos_router** — маршрутизатор MongoDB (порт 27017)
- **configSrv** — config server (порт 27019)
- **shard1** — первый шард (порт 27018)
- **shard2** — второй шард (порт 27018)

## Как запустить

### 1. Запуск контейнеров

```shell
docker compose up -d
```

### 2. Инициализация шардированного кластера

```shell
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт выполнит следующие шаги:
1. Инициализация Config Server Replica Set
2. Инициализация Shard1 Replica Set
3. Инициализация Shard2 Replica Set
4. Добавление шардов в кластер через mongos
5. Включение шардирования для БД `somedb` и коллекции `helloDoc`
6. Заполнение данными (1000 документов)
7. Проверка распределения данных по шардам

### Ручная инициализация (пошагово)

Если нужно выполнить шаги вручную:

**Инициализация Config Server:**
```shell
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF
```

**Инициализация Shard1:**
```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
```

**Инициализация Shard2:**
```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27018" }]
})
EOF
```

**Добавление шардов и шардирование коллекции:**
```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
EOF
```

**Заполнение данными:**
```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
```

## Как проверить

Откройте в браузере: http://localhost:8080

В JSON-ответе должно отображаться:
- `mongo_topology_type`: "Sharded"
- `collections.helloDoc.documents_count`: >= 1000
- `shards`: информация о двух шардах

### Проверка количества документов на каждом шарде

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

```shell
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```
