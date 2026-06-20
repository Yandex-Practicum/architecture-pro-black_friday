# mongo-sharding-repl

FastAPI-приложение и MongoDB Sharded Cluster с репликацией на каждом шарде: `pymongo-api` → `mongos-router` → `configSrv` + шарды `rs-shard1`, `rs-shard2` (по 3 реплики: master + 2 slave).  
БД `somedb`, коллекция `helloDoc`.

## DNS и порты (как на схемах)

| Сервис | DNS | Порт |
|--------|-----|------|
| mongos-router | `mongos-router` | 27020 |
| configSrv | `configSrv` | 27017 |
| shard1-1, shard1-2, shard1-3 | `shard1-1`, `shard1-2`, `shard1-3` | 27019 |
| shard2-1, shard2-2, shard2-3 | `shard2-1`, `shard2-2`, `shard2-3` | 27019 |

## Запуск

```shell
docker compose up -d --build
./scripts/init-sharding.sh
```

Если меняли порты или init падает с `ECONNREFUSED`, удалите старые данные и запустите заново:

```shell
docker compose down -v
docker compose up -d --build
./scripts/init-sharding.sh
```

## Настройка репликации для каждого шарда

Скрипт `./scripts/init-sharding.sh` автоматизирует все шаги ниже. Ниже — те же команды для ручной настройки.

### 1. Инициализация replica set для шарда rs-shard1

На primary-узле `shard1-1` создаём replica set из трёх членов:

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "rs-shard1",
  members: [
    { _id: 0, host: "shard1-1:27019" },
    { _id: 1, host: "shard1-2:27019" },
    { _id: 2, host: "shard1-3:27019" },
  ],
})
EOF
```

Проверка статуса replica set:

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet --eval 'rs.status().members.map(m => ({name: m.name, stateStr: m.stateStr}))'
```

Ожидаем 3 члена: один `PRIMARY`, два `SECONDARY`.

### 2. Инициализация replica set для шарда rs-shard2

```shell
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "rs-shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" },
  ],
})
EOF
```

Проверка:

```shell
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.length'
```

### 3. Добавление шардов с репликацией в кластер

После инициализации config server и перезапуска `mongos-router` добавляем шарды с полным списком реплик:

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
db.adminCommand({
  addShard: "rs-shard1/shard1-1:27019,shard1-2:27019,shard1-3:27019",
})
db.adminCommand({
  addShard: "rs-shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019",
})
db.adminCommand({ enableSharding: "somedb" })
db.adminCommand({
  shardCollection: "somedb.helloDoc",
  key: { _id: "hashed" },
})
EOF
```

### 4. Заполнение данными

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
use somedb
db.helloDoc.deleteMany({})
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```

## Проверка

Общее количество документов, распределение по шардам и количество реплик — через API:

```shell
curl http://localhost:8080/helloDoc/count
```

В ответе `/` смотрите:

- `documents_count` — общее количество (≥ 1000)
- `shards_documents_count` — документы на каждом шарде
- `shards_replicas_count` — количество реплик в каждом replica set (ожидается 3)

Через mongos-router:

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
db.adminCommand({ listShards: 1 })
EOF
```

Статус репликации на каждом шарде:

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet --eval 'rs.status().members.length'
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.length'
```

## Остановка

```shell
docker compose down      # остановить
docker compose down -v   # остановить и удалить данные
```
