# Задание 4: MongoDB Sharding + Replication + Redis Caching

Полная реализация: шардирование, репликация и кеширование.

## Состав

- **3 Config Servers** (replica set: configReplSet)
- **2 Shards** с репликацией:
  - Shard 1: 3 ноды (shard1-1, shard1-2, shard1-3)
  - Shard 2: 3 ноды (shard2-1, shard2-2, shard2-3)
- **1 Mongos** Router
- **1 Redis** Cache
- **1 API приложение** (pymongo-api)

**Итого: 12 контейнеров**

## Запуск

```bash
cd sharding-repl-cache

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
  "cache_enabled": true,
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

## Тестирование кеширования

```bash
# Запустить автоматический тест производительности
./scripts/test-cache.sh
```

**Ожидаемый результат:**
- Первый запрос: ~1.0-1.2 секунды (без кеша)
- Второй запрос: <0.1 секунды (из кеша) ✅
- Третий запрос: <0.1 секунды (из кеша) ✅
- Ускорение: ~20x

## Остановка

```bash
docker compose down
```

## Документация

См. [tasks/TASK4_SUMMARY.md](../tasks/TASK4_SUMMARY.md) и [tasks/TASK4_CACHING_SETUP.md](../tasks/TASK4_CACHING_SETUP.md)

