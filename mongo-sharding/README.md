# Задание 2: MongoDB Sharding

Базовое шардирование без репликации и кеширования.

## Состав

- **3 Config Servers** (configSrv1, configSrv2, configSrv3)
- **2 Shards** (shard1, shard2) - по одной ноде
- **1 Mongos** Router
- **1 API приложение** (pymongo-api)

**Итого: 7 контейнеров**

## Запуск

```bash
cd mongo-sharding

# 1. Запуск контейнеров
docker compose up -d

# 2. Подождать 10-15 секунд для инициализации

# 3. Инициализация шардирования
./scripts/init-sharding.sh

# 4. Проверка
curl http://127.0.0.1:8080 | jq
```

## Ожидаемый результат

```json
{
  "mongo_topology_type": "Sharded",
  "total_documents": 1000,
  "shard_distribution": {
    "shard1": {...},
    "shard2": {...}
  }
}
```

## Остановка

```bash
docker compose down
```

## Документация

См. [tasks/TASK2_SUMMARY.md](../tasks/TASK2_SUMMARY.md) и [tasks/TASK2_SHARDING_SETUP.md](../tasks/TASK2_SHARDING_SETUP.md)

