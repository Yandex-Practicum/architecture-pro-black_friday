# sharding-repl-cache

Финальный стенд: шардирование + репликация + кеширование запросов через Redis.

- 2 шарда, каждый — replica-set из 3 узлов;
- config server — replica-set из 3 узлов;
- 1 `mongos` router;
- 1 инстанс `redis` для кеширования ответов `pymongo_api`;
- 1 инстанс `pymongo_api`, ходит в `mongos` и в `redis`.

## Топология

| Сервис                                   | Replica set     | Назначение                       | Внутр. порт |
| ---------------------------------------- | --------------- | -------------------------------- | ----------- |
| `configSrv1`, `configSrv2`, `configSrv3` | `config_server` | Метаданные кластера              | 27019       |
| `shard1-1`, `shard1-2`, `shard1-3`       | `shard1`        | Данные шарда 1                   | 27018       |
| `shard2-1`, `shard2-2`, `shard2-3`       | `shard2`        | Данные шарда 2                   | 27018       |
| `mongos_router`                          | —               | Маршрутизатор запросов           | 27017       |
| `redis`                                  | —               | Кеш ответов `pymongo_api`        | 6379        |
| `pymongo_api`                            | —               | Клиентское приложение            | 8080        |

Образы: `dh-mirror.gitverse.ru/mongo:latest` для всех узлов кластера, `dh-mirror.gitverse.ru/redis:latest` для кеша, `kazhem/pymongo_api:1.0.0` для приложения.

Шардируется коллекция `somedb.helloDoc` с шард-ключом `{ name: "hashed" }`.

Кеширование подключается через переменную окружения `REDIS_URL=redis://redis:6379`, которая передаётся в `pymongo_api`. Кешируется эндпоинт `/<collection_name>/users`.

## Как запустить

```shell
docker compose up -d
./scripts/init-sharding.sh
```

Скрипт сделает:
1. `rs.initiate` для `config_server` (3 узла: `configSrv1/2/3`).
2. `rs.initiate` для `shard1` (3 узла: `shard1-1/2/3`) и `shard2` (3 узла: `shard2-1/2/3`).
3. Подождёт выборы primary во всех реплика-сетах.
4. Через `mongos`: `sh.addShard` для обоих шардов (с полным составом реплика-сета), `sh.enableSharding("somedb")`, `sh.shardCollection("somedb.helloDoc", { name: "hashed" })`.
5. Зальёт 1000 документов в `somedb.helloDoc` через `mongos`.
6. Распечатает количество документов и количество реплик в каждом шарде.
7. Сделает три подряд запроса к `http://localhost:8080/helloDoc/users` и распечатает время каждого — первый запрос идёт в MongoDB, второй и третий — из Redis.

После завершения скрипта приложение доступно на http://localhost:8080.
В корневом ответе поле `shards` покажет имена реплика-сетов и их составы, например:
`"shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018"` — это и есть «3 реплики на шард».

## Проверка кеша

Эндпоинт `/<collection_name>/users` кеширует ответ в Redis. Замерить время можно так:

```shell
curl -s -o /dev/null -w "%{time_total}\n" http://localhost:8080/helloDoc/users
curl -s -o /dev/null -w "%{time_total}\n" http://localhost:8080/helloDoc/users
```

Первый вызов прогревает кеш (идёт в `mongos` → шард). Второй и последующие должны отдаваться из Redis быстрее 100 мс.

Посмотреть ключи в Redis:

```shell
docker compose exec -T redis redis-cli KEYS '*'
```

## Полезные команды

Статус шардирования и распределение чанков:

```shell
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

Состав и состояние реплика-сета (по любому узлу):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status()
EOF
```

Подсчитать документы напрямую на каждом шарде (через primary):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.secondaryOk()
use somedb
db.helloDoc.countDocuments()
EOF
```

Остановить стенд и удалить тома:

```shell
docker compose down -v
```
