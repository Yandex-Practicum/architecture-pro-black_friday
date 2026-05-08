# MongoDB Sharding With Replica Sets

Стенд для задания 3: один `pymongo-api`, один `mongos`, один `configsvr`, два шарда и по три реплики в каждом шарде.

## Запуск

```shell
docker compose up -d
bash scripts/mongo-init.sh
```

Скрипт выполняет следующие шаги:

1. Инициализирует `configReplSet`.
2. Инициализирует replica set `shard1rs` из `shard1-1`, `shard1-2`, `shard1-3`.
3. Инициализирует replica set `shard2rs` из `shard2-1`, `shard2-2`, `shard2-3`.
4. Добавляет оба replica set как шарды.
5. Включает шардирование базы `somedb`.
6. Шардирует коллекцию `somedb.helloDoc` по хешированному ключу `_id`.
7. Загружает 1000 документов.
8. Печатает количество документов на шардах и количество реплик.

## Проверка

```shell
curl http://localhost:8080
curl http://localhost:8080/helloDoc/count
```

Проверить состав replica set:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status().members.map(m => m.name)"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "rs.status().members.map(m => m.name)"
```

Проверить распределение документов:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

Swagger доступен на `http://localhost:8080/docs`.
