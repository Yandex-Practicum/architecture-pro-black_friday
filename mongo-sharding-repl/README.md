# mongo-sharding-repl

Шардированный MongoDB-кластер (2 шарда), у каждого шарда — replica set из 3 узлов.

## Как поднять

```shell
cd mongo-sharding-repl
docker compose up -d
./scripts/mongo-init.sh
```

## Как проверить

Общее количество документов: `curl -s http://localhost:8080/helloDoc/count` (`>= 1000`).

Количество документов на каждом шарде (можно достучаться до любого члена replica set,
`rs.secondaryOk()` разрешает читать с secondary):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.secondaryOk()
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.secondaryOk()
use somedb
db.helloDoc.countDocuments()
EOF
```

Количество реплик на каждом шарде:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval 'rs.status().members.length'
```

Ожидается `3` для каждого шарда.

## Остановить и очистить

```shell
docker compose down -v
```
