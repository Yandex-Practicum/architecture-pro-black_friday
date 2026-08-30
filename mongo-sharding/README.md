# mongo-sharding

## Запуск

Запустите контейнеры:

```shell
docker compose up -d --build
```

## Инициализация шардирования

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

Затем инициализируйте первый шард:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
})
EOF
```

Инициализируйте второй шард:

```shell
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
})
EOF
```

Подождите несколько секунд, чтобы replica set успели перейти в рабочее состояние, и добавьте шарды в кластер:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
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

Количество документов можно проверить и через MongoDB:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```
