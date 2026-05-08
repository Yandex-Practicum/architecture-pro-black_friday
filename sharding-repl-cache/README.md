# MongoDB Sharding, Replica Sets And Redis Cache

Финальный стенд для заданий 2-4: `pymongo-api`, `mongos`, `configsvr`, два шардированных replica set по три узла и Redis для кеширования эндпоинта `/helloDoc/users`.

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

## Проверка приложения

```shell
curl http://localhost:8080
curl http://localhost:8080/helloDoc/count
```

В ответе корневого эндпоинта должны быть:

- `mongo_topology_type: "Sharded"`;
- `mongo_is_mongos: true`;
- `collections.helloDoc.documents_count` не меньше `1000`;
- `shards` с двумя replica set: `shard1rs` и `shard2rs`;
- `cache_enabled: true`.

## Проверка шардов и реплик

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.adminCommand({ listShards: 1 }).shards"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status().members.length"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "rs.status().members.length"
```

Количество документов на каждом шарде:

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

## Проверка Redis-кеша

Первый запрос к `/helloDoc/users` специально выполняется около секунды, потому что приложение делает задержку перед чтением из MongoDB. Повторный запрос должен вернуться из Redis быстрее 100 мс.

```shell
curl -o /dev/null -s -w "first: %{time_total}s\n" http://localhost:8080/helloDoc/users
curl -o /dev/null -s -w "second: %{time_total}s\n" http://localhost:8080/helloDoc/users
```

Swagger доступен на `http://localhost:8080/docs`.
