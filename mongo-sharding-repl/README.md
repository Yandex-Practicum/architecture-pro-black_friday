# mongo-sharding-repl

MongoDB с шардированием (2 шарда) и репликацией (3 реплики на каждый шард).

## Запуск

```bash
docker compose up -d
```

## Инициализация

```bash
./scripts/mongo-init.sh
```

## Проверка

Приложение: http://localhost:8080

Ожидаемый результат на `/`:
- `mongo_topology_type: "Sharded"`
- В `collections.helloDoc.documents_count` — ≥ 1000
- В `shards` — два шарда: `shard1_rs`, `shard2_rs`

Статус реплик вручную:
```bash
docker compose exec shard1-1 mongosh --port 27018 --eval "rs.status()"
docker compose exec shard2-1 mongosh --port 27018 --eval "rs.status()"
```