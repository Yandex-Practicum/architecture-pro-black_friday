# MongoDB Sharding

Стенд для задания 2: один `pymongo-api`, один `mongos`, один `configsvr` и два шарда MongoDB без репликации.

## Запуск

```shell
docker compose up -d
bash scripts/mongo-init.sh
```

Скрипт выполняет следующие шаги:

1. Инициализирует replica set конфигурационных серверов `configReplSet`.
2. Добавляет два шарда: `shard1:27018` и `shard2:27018`.
3. Включает шардирование базы `somedb`.
4. Шардирует коллекцию `somedb.helloDoc` по хешированному ключу `_id`.
5. Загружает 1000 документов.
6. Печатает общее количество документов и количество документов на каждом шарде.

## Проверка

```shell
curl http://localhost:8080
curl http://localhost:8080/helloDoc/count
```

Проверить распределение документов можно вручную:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

Swagger доступен на `http://localhost:8080/docs`.
