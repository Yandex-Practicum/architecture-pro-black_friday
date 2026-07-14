# sharding-repl-cache

Финальный стенд: шардированный MongoDB (2 шарда × 3 реплики) + Redis-кеш + pymongo-api.
Это директория, которую проверяет ревьюер.

## Как поднять

```shell
cd sharding-repl-cache
docker compose up -d
./scripts/mongo-init.sh
```

## Как проверить

- Приложение: http://localhost:8080 (и http://localhost:8080/docs)
- Общий count: `curl -s http://localhost:8080/helloDoc/count` (`>= 1000`)
- Количество реплик и документов на шардах — см. `mongo-sharding-repl/README.md` (те же команды).
- Кеш: JSON на `http://localhost:8080/` содержит `"cache_enabled": true`.
- Ускорение повторного запроса (первый вызов ~1 сек, повторный — < 100 мс):

```shell
time curl -s http://localhost:8080/helloDoc/users > /dev/null
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

## Остановить и очистить

```shell
docker compose down -v
```
