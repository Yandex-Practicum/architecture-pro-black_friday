# sharding-repl-cache

FastAPI-приложение, MongoDB Sharded Cluster с репликацией на каждом шарде и Redis-кеш (master + replica):  
`pymongo-api` → `mongos-router` + `redis-1` → `configSrv` + шарды `rs-shard1`, `rs-shard2` (по 3 реплики) + `redis-2` (replica of `redis-1`).  
БД `somedb`, коллекция `helloDoc`. Кеширование включено для `/<collection_name>/users`.

## DNS и порты (как на схемах)

| Сервис | DNS | Порт |
|--------|-----|------|
| mongos-router | `mongos-router` | 27020 |
| configSrv | `configSrv` | 27017 |
| shard1-1, shard1-2, shard1-3 | `shard1-1`, `shard1-2`, `shard1-3` | 27019 |
| shard2-1, shard2-2, shard2-3 | `shard2-1`, `shard2-2`, `shard2-3` | 27019 |
| redis-1 (master) | `redis-1` | 6379 |
| redis-2 (replica) | `redis-2` | 6379 |

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

## Проверка кеширования

Первый запрос выполняется ~1 с (есть `time.sleep(1)` в обработчике). Повторные запросы должны быть заметно быстрее:

```shell
time curl -s http://localhost:8080/helloDoc/users > /dev/null
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

В ответе `/` поле `cache_enabled` должно быть `true`.

## Проверка MongoDB

```shell
curl http://localhost:8080/helloDoc/count
```

В ответе `/` смотрите:

- `documents_count` — общее количество (≥ 1000)
- `shards_documents_count` — документы на каждом шарде
- `shards_replicas_count` — количество реплик в каждом replica set (ожидается 3)
- `cache_enabled` — `true`

## Остановка

```shell
docker compose down      # остановить
docker compose down -v   # остановить и удалить данные
```
