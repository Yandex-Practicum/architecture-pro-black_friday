# sharding-repl-cache

Шардированный MongoDB с **репликацией на шардах** (по 3 узла), плюс **Redis** для кеша ответов эндпоинта **`GET /{collection_name}/users`**. Приложение **pymongo-api** подключается к **mongos** и к **Redis** (`REDIS_URL`).

База: `somedb`, коллекция: `helloDoc`.

Порты по умолчанию: **8080** (API), **27017** (mongos). Если параллельно запущены другие проекты из этого репозитория — остановите их или смените проброс портов.

## Запуск

Из каталога `sharding-repl-cache`:

```shell
docker compose build
./scripts/init-cluster.sh
```

Проверка данных: `curl -s http://localhost:8080/` — в ответе **`cache_enabled`: true**, счётчики **`helloDoc`**, **`documents_per_shard`**, **`shard_replica_sets`**.