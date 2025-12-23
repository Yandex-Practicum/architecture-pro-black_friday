# Задание 2: Настройка MongoDB Sharding

> 🔧 Детальная документация по настройке шардирования  
> 🏠 [← Вернуться к README](../README.md) | 📋 [Итоговая сводка →](TASK2_SUMMARY.md) | 📊 [Схема →](../diagrams/ARCHITECTURE.md)

## Архитектура

Реализована первая схема из планирования:
- **1 Mongos Router** - маршрутизация запросов
- **3 Config Servers** - хранение метаданных кластера (configSrv1, configSrv2, configSrv3)
- **2 Shards** - распределенное хранение данных (shard1, shard2)
- **1 Application** - Flask API (pymongo-api)

## Быстрый старт

```bash
# Перейти в директорию проекта
cd mongo-sharding
```

### 1. Запуск контейнеров

```bash
docker compose up -d
```

### 2. Инициализация шардирования (автоматически)

```bash
./scripts/init-sharding.sh
```

Скрипт выполнит все необходимые шаги автоматически.

### 3. Проверка результата

```bash
curl http://127.0.0.1:8080
```

## Ручная настройка (пошагово)

Если нужна ручная настройка, выполните следующие шаги:

### Шаг 1: Инициализация Config Server Replica Set

```bash
docker compose exec -T configSrv1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" },
    { _id: 2, host: "configSrv3:27019" }
  ]
});
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

Подождите 5-10 секунд для завершения выборов в replica set.

### Шаг 2: Инициализация Shard 1 Replica Set

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

### Шаг 3: Инициализация Shard 2 Replica Set

```bash
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27018" }
  ]
});
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

### Шаг 4: Добавление шардов в кластер

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018");
sh.addShard("shard2ReplSet/shard2:27018");
EOF
```

**Ожидаемый результат:**
```json
{
  "shardAdded": "shard1ReplSet",
  "ok": 1
}
{
  "shardAdded": "shard2ReplSet",
  "ok": 1
}
```

### Шаг 5: Включение шардирования для БД

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

### Шаг 6: Создание и шардирование коллекции

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1, "collectionsharded": "somedb.helloDoc" }
```

**Примечание:** Используется хешированный ключ шардирования `{ _id: "hashed" }` для равномерного распределения данных.

### Шаг 7: Заполнение коллекции данными

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

**Результат:** Будет создано 1000 документов.

## Проверка работы

### 1. Проверка статуса шардов

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

### 2. Проверка распределения данных

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF
```

**Ожидаемый вывод:**
```
Shard shard1ReplSet at shard1ReplSet/shard1:27018
{
  data: '...',
  docs: 500,
  chunks: 2,
  ...
}
Shard shard2ReplSet at shard2ReplSet/shard2:27018
{
  data: '...',
  docs: 500,
  chunks: 2,
  ...
}
```

### 3. Проверка через API

```bash
curl http://127.0.0.1:8080 | jq
```

**Ожидаемый ответ (пример):**
```json
{
  "mongo_topology_type": "Sharded",
  "mongo_db": "somedb",
  "mongo_is_mongos": true,
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1ReplSet": "shard1ReplSet/shard1:27018",
    "shard2ReplSet": "shard2ReplSet/shard2:27018"
  },
  "shard_distribution": {
    "helloDoc": {
      "shard1ReplSet": {
        "count": 500,
        "size": 45000
      },
      "shard2ReplSet": {
        "count": 500,
        "size": 45000
      }
    }
  },
  "status": "OK"
}
```

### 4. Подсчет документов в каждом шарде

**Shard 1:**
```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Порты по умолчанию

| Компонент | Порт | Описание |
|-----------|------|----------|
| Mongos Router | 27017 | Точка входа для приложений |
| Config Servers | 27019 | Внутренний порт config servers |
| Shards | 27018 | Внутренний порт шардов |
| API Application | 8080 | HTTP API endpoint |

## Архитектура соединений

```
Client (curl/browser)
    ↓ HTTP (port 8080)
pymongo-api
    ↓ MongoDB Protocol (port 27017)
mongos (Query Router)
    ├─→ configSrv1:27019 (Metadata)
    ├─→ configSrv2:27019 (Metadata)
    ├─→ configSrv3:27019 (Metadata)
    ├─→ shard1:27018 (Data)
    └─→ shard2:27018 (Data)
```

## Устранение неполадок

### Проблема: Контейнеры не запускаются

**Решение:**
```bash
docker compose down -v
docker compose up -d
```

### Проблема: Шарды не добавляются

**Проверка:**
```bash
docker compose logs mongos
docker compose logs shard1
docker compose logs shard2
```

**Убедитесь, что:**
1. Все replica sets инициализированы
2. Прошло достаточно времени после инициализации (5-10 сек)

### Проблема: Данные не распределяются по шардам

**Причина:** Коллекция не была шардирована до вставки данных.

**Решение:**
1. Удалите коллекцию
2. Выполните шаг 6 (shardCollection)
3. Заново загрузите данные

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.drop();
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

## Полезные команды

### Список всех шардов
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
db.adminCommand({ listShards: 1 });
EOF
```

### Статус шардирования БД
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.stats();
EOF
```

### Статус конкретной коллекции
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.stats();
EOF
```

### Остановка проекта
```bash
docker compose down
```

### Полная очистка (включая данные)
```bash
docker compose down -v
```

## Критерии успешной настройки

- ✅ Все контейнеры запущены (6 контейнеров)
- ✅ Config servers в статусе replica set
- ✅ Оба шарда добавлены в кластер
- ✅ БД `somedb` имеет шардирование
- ✅ Коллекция `helloDoc` шардирована
- ✅ В коллекции ≥1000 документов
- ✅ Документы распределены между шардами
- ✅ API возвращает информацию о шардах и распределении
- ✅ `mongo_topology_type` = "Sharded"
- ✅ `mongo_is_mongos` = true

## Следующие шаги

После успешной настройки шардирования переходите к:
- 📖 Задание 3: Репликация
- 📊 [Схема 2: Шардирование + Репликация](../diagrams/ARCHITECTURE.md)

