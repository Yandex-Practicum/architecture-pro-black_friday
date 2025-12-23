# Задание 3: MongoDB Sharding + Replication

Шардирование с репликацией (без кеширования).

## Состав

- **3 Config Servers** (replica set: configReplSet)
- **2 Shards** с репликацией:
  - Shard 1: 3 ноды (shard1-1, shard1-2, shard1-3)
  - Shard 2: 3 ноды (shard2-1, shard2-2, shard2-3)
- **1 Mongos** Router
- **1 API приложение** (pymongo-api)

**Итого: 11 контейнеров**

## Запуск

```bash
cd mongo-sharding-repl

# 1. Запуск контейнеров
docker compose up -d

# 2. Подождать 15-20 секунд для инициализации

# 3. Инициализация репликации и шардирования
./scripts/init-replication.sh

# 4. Проверка
curl http://127.0.0.1:8080 | jq
```

## Ожидаемый результат

```json
{
  "mongo_topology_type": "Sharded",
  "total_documents": 1000,
  "shard_distribution": {
    "shard1": {
      "replica_count": 3,
      ...
    },
    "shard2": {
      "replica_count": 3,
      ...
    }
  }
}
```

## Тестирование Failover

```bash
# Остановить primary ноду одного из шардов
docker compose stop shard1-1

# Через 10-30 секунд MongoDB автоматически выберет новый Primary
# Приложение продолжит работать

# Запустить ноду обратно
docker compose start shard1-1
```

## Остановка

```bash
docker compose down
```

## Документация

См. [tasks/TASK3_SUMMARY.md](../tasks/TASK3_SUMMARY.md) и [tasks/TASK3_REPLICATION_SETUP.md](../tasks/TASK3_REPLICATION_SETUP.md)

