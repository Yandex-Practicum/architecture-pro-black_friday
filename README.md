# Project 4: Black Friday Architecture

Репозиторий содержит решение проектной работы по отказоустойчивости и масштабированию PoC интернет-магазина «Мобильный мир».

## Состав решения

- `mongo-sharding` - задание 2, MongoDB sharding на двух шардах.
- `mongo-sharding-repl` - задание 3, sharding плюс replica set из трёх узлов на каждый shard.
- `sharding-repl-cache` - задания 2-4, финальный проверяемый стенд: sharding, replica set и Redis cache.
- `architecture-final.drawio` - схемы для заданий 1, 5 и 6. Финальная страница содержит CDN, API Gateway, Consul, несколько `pymongo-api`, Redis и MongoDB cluster.
- `docs/architecture.md` - архитектурный документ для заданий 7-10.

## Быстрый запуск финального стенда

Для проверки используется директория `sharding-repl-cache`.

```shell
cd sharding-repl-cache
docker compose up -d
bash scripts/mongo-init.sh
```

После инициализации приложение доступно на `http://localhost:8080`, Swagger - на `http://localhost:8080/docs`.

## Что поднимается в финальном стенде

- `pymongo_api` из образа `kazhem/pymongo_api:1.0.0`;
- `redis` для кеширования повторных запросов `/helloDoc/users`;
- `mongos` как router для шардированного MongoDB-кластера;
- `configsvr` как config server replica set `configReplSet`;
- `shard1rs`: `shard1-1`, `shard1-2`, `shard1-3`;
- `shard2rs`: `shard2-1`, `shard2-2`, `shard2-3`.

База данных называется `somedb`, коллекция - `helloDoc`. Init-скрипт шардирует коллекцию по `{ _id: "hashed" }` и загружает 1000 документов.

## Проверка

Проверить статус контейнеров:

```shell
docker compose ps
```

Проверить JSON приложения:

```shell
curl http://localhost:8080
curl http://localhost:8080/helloDoc/count
```

В корневом ответе должны быть `mongo_topology_type: "Sharded"`, `mongo_is_mongos: true`, `cache_enabled: true`, два shard replica set и коллекция `helloDoc` с количеством документов не меньше 1000.

Проверить шарды и реплики:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.adminCommand({ listShards: 1 }).shards"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status().members.length"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "rs.status().members.length"
```

Проверить кеш Redis:

```shell
curl -o /dev/null -s -w "first: %{time_total}s\n" http://localhost:8080/helloDoc/users
curl -o /dev/null -s -w "second: %{time_total}s\n" http://localhost:8080/helloDoc/users
```

Повторный запрос должен выполняться быстрее 100 мс.

## Остановка стенда

```shell
docker compose down
```

Если нужно удалить тома MongoDB и Redis:

```shell
docker compose down -v
```
