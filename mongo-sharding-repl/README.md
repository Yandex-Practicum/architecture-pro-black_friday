# mongo-sharding-repl

MongoDB с шардированием (2 шарда) и репликацией (3 реплики на каждый шард) для онлайн-магазина "Мобильный мир".

## Архитектура

- **pymongo_api** — приложение (порт 8080)
- **mongos_router** — маршрутизатор MongoDB (порт 27017)
- **configSrv** — config server (порт 27019)
- **shard1-1, shard1-2, shard1-3** — первый шард, replica set из 3 нод (порт 27018)
- **shard2-1, shard2-2, shard2-3** — второй шард, replica set из 3 нод (порт 27018)

## Как запустить

### 1. Запуск контейнеров

```shell
docker compose up -d
```

### 2. Инициализация шардированного кластера с репликацией

```shell
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт выполнит следующие шаги:
1. Инициализация Config Server Replica Set
2. Инициализация Shard1 Replica Set (3 реплики: shard1-1, shard1-2, shard1-3)
3. Инициализация Shard2 Replica Set (3 реплики: shard2-1, shard2-2, shard2-3)
4. Добавление шардов в кластер через mongos
5. Включение шардирования для БД `somedb` и коллекции `helloDoc`
6. Заполнение данными (1000 документов)
7. Проверка распределения данных по шардам и статуса реплик

### Ручная инициализация (пошагово)

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

**Инициализация Shard1 Replica Set (3 реплики):**
```shell
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

**Инициализация Shard2 Replica Set (3 реплики):**
```shell
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

**Добавление шардов и шардирование коллекции:**
```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
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

### Проверка количества реплик

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - state: " + m.stateStr)
})
EOF
```

```shell
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - state: " + m.stateStr)
})
EOF
```

### Проверка количества документов на каждом шарде

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

```shell
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```
