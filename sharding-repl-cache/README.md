# Задание 4: шардирование, репликация, Redis-кеш

База на стеке из [mongo-sharding-repl](../mongo-sharding-repl/README.md), плюс **Redis** для [fastapi-cache2](https://github.com/long2ice/fastapi-cache) на эндпоинте `GET /{collection_name}/users`.

- Имя проекта Compose: **`sharding-repl-cache`**
- Кеш: **`REDIS_URL: redis://redis:6379`** (сервис [redis](compose.yaml) в сети `app-network`)

## Запуск

```bash
cd sharding-repl-cache
docker-compose up -d --build
chmod +x init-sharding.sh
./init-sharding.sh
```


## Проверка задания

1. [http://localhost:8080/](http://localhost:8080/) — `cache_enabled: true` (после успешного старта с `REDIS_URL`), `replica_member_counts`, `collections.helloDoc.documents_count` ≥ 1000.
2. **Кеш** на `GET /cache_demo/users` (коллекция `cache_demo` в `somedb` заполняется в [init-sharding.sh](./init-sharding.sh) документами `name` / `age`):
   - первый запрос: ~1+ с (в обработчике `time.sleep(1)` + MongoDB);
   - **второй** и далее (пока кеш в Redis жив): **< 100 мс** по `time_total` у `curl` / во вкладке «Сеть» в браузере.

Пример:

```bash
curl -s -o /dev/null -w "1: %{time_total}\n" http://localhost:8080/cache_demo/users
curl -s -o /dev/null -w "2: %{time_total}\n" http://localhost:8080/cache_demo/users
```

Во втором числе слева от десятичной точки должен остаться **0** (десятки миллисекунд) при нормальной среде.

3. `helloDoc` содержит сид-поля `n` / `t` — **не** подходят схеме `UserModel` в `/helloDoc/users`; для проверки кеша используйте **`/cache_demo/users`**, как в примере.

## Сбой: Redis unhealthy

Убедитесь, что `redis-cli` в контейнере `redis` отвечает на `ping` (см. `healthcheck` в [compose.yaml](./compose.yaml)). Либо временно замените `condition: service_healthy` на `service_started` у `pymongo_api` → `redis`.

## Сеть Docker

Как в предыдущих заданиях: при `Pool overlaps` смените `subnet` в [compose.yaml](./compose.yaml).
