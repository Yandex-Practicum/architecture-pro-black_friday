# gateway-consul

FastAPI-приложение в двух инстансах за **Apache APISIX** (API Gateway) с **HashiCorp Consul** (Service Discovery), MongoDB Sharded Cluster с репликацией и Redis-кеш:  
`клиент` → `apisix` → `pymongo_api_1`, `pymongo_api_2` → `mongos-router` + `redis-1` → `configSrv` + шарды `rs-shard1`, `rs-shard2` (по 3 реплики) + `redis-2`.  
БД `somedb`, коллекция `helloDoc`. Кеширование включено для `/<collection_name>/users`.

## DNS и порты (как на схемах)

| Сервис | DNS | Порт |
|--------|-----|------|
| APISIX Gateway | `apisix` | 9080 |
| APISIX Admin API | `apisix` | 9180 |
| Consul | `consul` | 8500 |
| pymongo-api (инстанс 1) | `pymongo_api_1` | 8080 |
| pymongo-api (инстанс 2) | `pymongo_api_2` | 8080 |
| mongos-router | `mongos-router` | 27020 |
| configSrv | `configSrv` | 27017 |
| shard1-1, shard1-2, shard1-3 | `shard1-1`, `shard1-2`, `shard1-3` | 27019 |
| shard2-1, shard2-2, shard2-3 | `shard2-1`, `shard2-2`, `shard2-3` | 27019 |
| redis-1 (master) | `redis-1` | 6379 |
| redis-2 (replica) | `redis-2` | 6379 |

## Эндпоинты (через APISIX, порт 9080)

| Метод | URL | Описание |
|-------|-----|----------|
| GET | `/health` | Liveness probe (без обращения к MongoDB) |
| GET | `/` | Статус приложения, MongoDB, шарды, кеш |
| GET | `/helloDoc/count` | Количество документов в коллекции |
| GET | `/helloDoc/users` | Список пользователей (кешируется) |
| GET | `/helloDoc/users/{name}` | Один пользователь по имени |
| POST | `/helloDoc/users` | Добавить пользователя |
| GET | `/docs` | Swagger UI |

## Запуск

```shell
docker compose up -d --build
./scripts/init.sh
```

Или по шагам:

```shell
docker compose up -d --build
./scripts/init-sharding.sh    # ~30–60 с, дождитесь «MongoDB sharding initialized.»
./scripts/init-gateway.sh     # проверит MongoDB, затем настроит Consul и APISIX
```

> **Важно:** не прерывайте `init-sharding.sh` (^C). Если прервали — `docker compose down -v` и запустите заново.

Если меняли порты или init падает с `ECONNREFUSED`, удалите старые данные и запустите заново:

```shell
docker compose down -v
```

> Если запущен `sharding-repl-cache` или другой стек с теми же именами контейнеров MongoDB — остановите его перед запуском.

## Проверка балансировки

Запросы идут через APISIX. В ответе `/` поле `instance_id` показывает, какой инстанс обработал запрос:

```shell
for i in $(seq 1 10); do
  curl -s http://localhost:9080/ | grep -o '"instance_id":"[^"]*"'
done
```

Ожидается чередование `pymongo_api_1` и `pymongo_api_2`.

## Проверка MongoDB

```shell
curl http://localhost:9080/helloDoc/count
curl http://localhost:9080/
```

В ответе `/` смотрите:

- `documents_count` — общее количество (≥ 1000)
- `shards_documents_count` — документы на каждом шарде
- `shards_replicas_count` — количество реплик в каждом replica set (ожидается 3)
- `cache_enabled` — `true`

## Проверка кеширования

Первый запрос выполняется ~1 с (есть `time.sleep(1)` в обработчике). Повторные запросы должны быть заметно быстрее:

```shell
docker compose exec redis-1 redis-cli FLUSHALL
time curl -s http://localhost:9080/helloDoc/users > /dev/null
time curl -s http://localhost:9080/helloDoc/users > /dev/null
```

## Consul

Список зарегистрированных инстансов FastAPI:

```shell
curl -s http://localhost:8500/v1/catalog/service/pymongo-api | python3 -m json.tool
```

## Остановка

```shell
docker compose down      # остановить
docker compose down -v   # остановить и удалить данные
```
