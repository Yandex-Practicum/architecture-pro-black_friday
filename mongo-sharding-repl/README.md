# mongo-sharding-repl

## Запуск

Запустите контейнеры:

```shell
docker compose up -d --build
```

## Инициализация репликации и шардирования

Сначала инициализируйте config server:

```shell
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
})
EOF
```

Инициализируйте replica set для первого шарда:

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

Инициализируйте replica set для второго шарда:

```shell
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
})
EOF
```

Подождите несколько секунд, чтобы replica set успели выбрать primary, и добавьте шарды в кластер:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019")
EOF
```

Включите шардирование для базы `somedb` и коллекции `helloDoc`:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
use somedb
db.helloDoc.createIndex({ age: "hashed" })
sh.shardCollection("somedb.helloDoc", { age: "hashed" })
EOF
```

Заполните коллекцию тестовыми данными:

```shell
./scripts/mongo-init.sh
```

## Проверка

Откройте приложение:

```text
http://localhost:8080
```

В ответе должны быть:

- `mongo_topology_type: Sharded`
- `collections.helloDoc.documents_count` со значением не меньше `1000`
- `collections.helloDoc.shards` с количеством документов по каждому шарду
- `shard_replicas`, где у `shard1` и `shard2` указано по `3` реплики

Проверить распределение документов можно и через MongoDB:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```

Проверить состояние реплик можно так:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.map(member => ({ name: member.name, state: member.stateStr }))
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status().members.map(member => ({ name: member.name, state: member.stateStr }))
EOF
```
