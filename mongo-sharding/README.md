# mongo-sharding

Стенд с шардированным кластером MongoDB: 2 шарда, 1 config server, 1 mongos router и инстанс `pymongo_api`.

## Топология

| Сервис          | Образ                                  | Назначение                                      | Внутр. порт |
| --------------- | -------------------------------------- | ----------------------------------------------- | ----------- |
| `configSrv`     | `dh-mirror.gitverse.ru/mongo:latest`   | Конфиг-сервер кластера (replSet `config_server`) | 27019       |
| `shard1`        | `dh-mirror.gitverse.ru/mongo:latest`   | Шард 1 (replSet `shard1`)                       | 27018       |
| `shard2`        | `dh-mirror.gitverse.ru/mongo:latest`   | Шард 2 (replSet `shard2`)                       | 27018       |
| `mongos_router` | `dh-mirror.gitverse.ru/mongo:latest`   | Маршрутизатор запросов                          | 27017       |
| `pymongo_api`   | `kazhem/pymongo_api:1.0.0`             | Клиентское приложение (FastAPI)                 | 8080        |

Шардируется коллекция `somedb.helloDoc` с шард-ключом `{ name: "hashed" }` — это даёт примерно равномерное распределение 1000 тестовых документов между двумя шардами.

## Как запустить

```shell
docker compose up -d
./scripts/init-sharding.sh
```

Скрипт сделает:
1. `rs.initiate` для `configSrv`, `shard1`, `shard2`.
2. Добавит шарды в кластер через `mongos` (`sh.addShard`).
3. Включит шардирование БД и коллекции (`sh.enableSharding`, `sh.shardCollection`).
4. Зальёт 1000 документов в `somedb.helloDoc` через `mongos`.
5. Распечатает количество документов в каждом шарде.

После завершения скрипта приложение доступно на http://localhost:8080.
В корневом ответе появится поле `shards` с именами обоих шардов и `mongo_is_mongos: true`.

## Полезные команды

Подсчитать документы напрямую на каждом шарде:

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

Посмотреть распределение чанков и статус шардирования:

```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

Остановить и удалить стенд вместе с данными:

```shell
docker compose down -v
```
