# mongo-sharding

FastAPI-приложение и MongoDB Sharded Cluster: `pymongo-api` → `mongos-router` → `configSrv` + шарды `rs-shard1`, `rs-shard2`.  
БД `somedb`, коллекция `helloDoc`.

## DNS и порты (как на схемах)

| Сервис | DNS | Порт |
|--------|-----|------|
| mongos-router | `mongos-router` | 27020 |
| configSrv | `configSrv` | 27017 |
| shard1-1, shard2-1, … | `shard1-1`, `shard2-1`, … | 27019 |

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

Скрипт инициализирует replica set'ы, добавляет шарды, включает sharding для `somedb.helloDoc` и записывает 1000 документов.

## Проверка

Общее количество и распределение по шардам — через API:

```shell
curl http://localhost:8080/helloDoc/count
curl http://localhost:8080/
```

В ответе `/` смотрите `documents_count` (≥ 1000) и `shards_documents_count` по каждому шарду.  
На отдельном шарде будет меньше 1000 — это нормально, данные распределены между двумя шардами.

Через mongos-router:

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```

На каждом шарде:

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Остановка

```shell
docker compose down      # остановить
docker compose down -v   # остановить и удалить данные
```
