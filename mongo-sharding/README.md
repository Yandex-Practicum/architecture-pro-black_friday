# mongo-sharding

Шардированный MongoDB-кластер (2 шарда) + pymongo-api.

## Как поднять

```shell
cd mongo-sharding
docker compose up -d
./scripts/mongo-init.sh
```

Скрипт инициализирует config server, оба шарда, добавляет их в кластер,
включает шардирование для `somedb.helloDoc` (хэш-ключ по `_id`) и
заполняет коллекцию 1000 документами.

## Как проверить

Приложение: http://localhost:8080 (JSON со статусом, `mongo_topology_type: "Sharded"`, списком `shards`).

Общее количество документов:

```shell
curl -s http://localhost:8080/helloDoc/count
```

Количество документов на каждом шарде:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Остановить и очистить

```shell
docker compose down -v
```
