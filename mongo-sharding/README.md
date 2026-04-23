# mongo-sharding

MongoDB с шардированием (2 шарда + config server + mongos router).

## Архитектура

pymongo_api → mongos:27020 → configSrv:27017 (configRs)
                           → shard1:27018 (shard1Rs)
                           → shard2:27019 (shard2Rs)

## Запуск

```bash
docker compose up -d
```

Дождитесь старта всех контейнеров (~10 сек), затем:

```bash
./scripts/mongo-init.sh
```

## Проверка

Приложение: http://localhost:8080

Ответ должен содержать:
- `"mongo_is_mongos": true`
- `"shards"` с двумя шардами
- `"collections.helloDoc.documents_count"` ≥ 1000

Проверка распределения:
```bash
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```