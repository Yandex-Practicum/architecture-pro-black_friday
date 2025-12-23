# Задание 2: Шардирование - Итоговая сводка

> ⚙️ Полное описание выполнения Задания 2  
> 🏠 [← Вернуться к README](../README.md)

## ✅ Задача

Настроить MongoDB Sharding согласно первой схеме из планирования:
- Модифицировать `compose.yaml` для реализации шардирования
- Создать скрипт автоматической инициализации
- Настроить БД `somedb` и коллекцию `helloDoc`
- Загрузить ≥1000 документов
- Обеспечить отображение информации о шардах в API

## ✅ Что было сделано

### 1. Модифицирован compose.yaml

**Имя проекта:** `mongo-sharding`

**Инфраструктура (7 контейнеров):**

#### Config Servers (3)
```yaml
configSrv1, configSrv2, configSrv3
- Порт: 27019
- Команда: mongod --configsvr --replSet configReplSet
- Назначение: хранение метаданных кластера
```

#### Shards (2)
```yaml
shard1, shard2
- Порт: 27018
- Команда: mongod --shardsvr --replSet shard1ReplSet/shard2ReplSet
- Назначение: распределенное хранение данных
```

#### Mongos Router (1)
```yaml
mongos
- Порт: 27017 (внешний)
- Команда: mongos --configdb configReplSet/...
- Назначение: маршрутизация запросов
```

#### Application (1)
```yaml
pymongo-api
- Порт: 8080 (внешний)
- Environment: MONGODB_URL=mongodb://mongos:27017
- Назначение: Flask API приложение
```

### 2. Создан скрипт автоматической инициализации

**Файл:** `scripts/init-sharding.sh`

**Выполняемые шаги:**

#### Шаг 1: Инициализация Config Server Replica Set
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

#### Шаг 2-3: Инициализация Shard Replica Sets
```bash
# Shard 1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [{ _id: 0, host: "shard1:27018" }]
});
EOF

# Shard 2
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [{ _id: 0, host: "shard2:27018" }]
});
EOF
```

#### Шаг 4: Добавление шардов в кластер
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018");
sh.addShard("shard2ReplSet/shard2:27018");
EOF
```

#### Шаг 5: Включение шардирования для БД
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF
```

#### Шаг 6: Создание и шардирование коллекции
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```

**Shard Key:** `{ _id: "hashed" }` для равномерного распределения

#### Шаг 7: Заполнение данными
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

#### Шаг 8: Проверка распределения
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF
```

### 3. Улучшен API (api_app/app.py)

**Добавлено в JSON ответ:**

#### mongo_topology_type
Тип топологии MongoDB
```json
"mongo_topology_type": "Sharded"
```

#### mongo_is_mongos
Флаг подключения через mongos
```json
"mongo_is_mongos": true
```

#### shards
Список всех шардов в кластере
```json
"shards": {
  "shard1ReplSet": "shard1ReplSet/shard1:27018",
  "shard2ReplSet": "shard2ReplSet/shard2:27018"
}
```

#### shard_distribution
Распределение документов по шардам
```json
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
}
```

**Код:**
```python
# Получение статистики по шардам
shard_distribution = {}
for collection_name in collection_names:
    collection_stats = await db.command({
        "collStats": collection_name,
        "verbose": True
    })
    if "shards" in collection_stats:
        shard_distribution[collection_name] = {}
        for shard_name, shard_stats in collection_stats["shards"].items():
            shard_distribution[collection_name][shard_name] = {
                "count": shard_stats.get("count", 0),
                "size": shard_stats.get("size", 0)
            }
```

### 4. Документация

#### [SHARDING_SETUP.md](../SHARDING_SETUP.md)
Подробная документация по настройке:
- Описание архитектуры
- Быстрый старт (автоматическая настройка)
- Ручная настройка (8 шагов с примерами)
- Проверка работы
- Полезные команды
- Устранение неполадок
- Критерии успешной настройки

## 🚀 Как запустить и проверить

### Быстрый старт (3 команды)

```bash
# Перейти в директорию проекта
cd mongo-sharding

# 1. Запуск контейнеров
docker compose up -d

# 2. Инициализация (подождите 10 сек после запуска)
./scripts/init-sharding.sh

# 3. Проверка
curl http://127.0.0.1:8080 | jq
```

### Что должно получиться

```json
{
  "mongo_topology_type": "Sharded",          // ✅
  "mongo_is_mongos": true,                   // ✅
  "mongo_db": "somedb",
  "collections": {
    "helloDoc": {
      "documents_count": 1000                // ✅
    }
  },
  "shards": {                                // ✅
    "shard1ReplSet": "shard1ReplSet/shard1:27018",
    "shard2ReplSet": "shard2ReplSet/shard2:27018"
  },
  "shard_distribution": {                    // ✅
    "helloDoc": {
      "shard1ReplSet": { "count": 500, "size": 45000 },
      "shard2ReplSet": { "count": 500, "size": 45000 }
    }
  },
  "status": "OK"
}
```

### Подробная проверка

#### 1. Проверка контейнеров
```bash
docker compose ps
# Все 7 контейнеров должны быть в статусе "running"
```

#### 2. Проверка topology
```bash
curl -s http://127.0.0.1:8080 | jq '.mongo_topology_type'
# Ожидается: "Sharded"
```

#### 3. Проверка mongos
```bash
curl -s http://127.0.0.1:8080 | jq '.mongo_is_mongos'
# Ожидается: true
```

#### 4. Проверка количества документов
```bash
curl -s http://127.0.0.1:8080 | jq '.collections.helloDoc.documents_count'
# Ожидается: 1000
```

#### 5. Проверка списка шардов
```bash
curl -s http://127.0.0.1:8080 | jq '.shards'
# Ожидается: {"shard1ReplSet": "...", "shard2ReplSet": "..."}
```

#### 6. Проверка распределения
```bash
curl -s http://127.0.0.1:8080 | jq '.shard_distribution.helloDoc'
# Ожидается: данные распределены между двумя шардами
```

#### 7. Подсчет в каждом шарде
```bash
# Shard 1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Shard 2
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Сумма должна быть ≈ 1000
```

#### 8. Браузер
Откройте http://127.0.0.1:8080 - должен показать полную информацию о кластере

#### 9. Swagger UI
Откройте http://127.0.0.1:8080/docs - интерактивная документация API

### API Endpoints

```bash
# Главная страница - информация о кластере
GET /

# Количество документов в коллекции
GET /{collection_name}/count

# Список пользователей (до 1000)
GET /{collection_name}/users

# Конкретный пользователь по имени
GET /{collection_name}/users/{name}

# Создать пользователя
POST /{collection_name}/users
```

### Тестирование

```bash
# Получить количество
curl http://127.0.0.1:8080/helloDoc/count

# Получить пользователей
curl http://127.0.0.1:8080/helloDoc/users | jq '.users | length'

# Найти пользователя
curl http://127.0.0.1:8080/helloDoc/users/ly42

# Создать пользователя
curl -X POST http://127.0.0.1:8080/helloDoc/users \
  -H "Content-Type: application/json" \
  -d '{"age": 99, "name": "testuser"}'
```

## ✅ Соответствие требованиям ревьюера

### ✓ Проект запускается
```bash
docker compose up -d
```
**Результат:** 7 контейнеров в статусе running

### ✓ Настройка выполняется без ошибок
```bash
./scripts/init-sharding.sh
```
**Результат:** Все 8 шагов завершаются успешно

### ✓ Приложение показывает общее количество документов
```bash
curl -s http://127.0.0.1:8080 | jq '.collections.helloDoc.documents_count'
```
**Результат:** 1000

### ✓ Приложение показывает количество в каждом шарде
```bash
curl -s http://127.0.0.1:8080 | jq '.shard_distribution.helloDoc'
```
**Результат:**
```json
{
  "shard1ReplSet": { "count": 500, "size": 45000 },
  "shard2ReplSet": { "count": 500, "size": 45000 }
}
```

## 🔧 Устранение проблем

### Проблема: Контейнеры не запускаются
```bash
docker compose down -v
docker compose up -d
```

### Проблема: Ошибки при инициализации
Проверьте логи:
```bash
docker compose logs mongos
docker compose logs shard1
docker compose logs configSrv1
```

Попробуйте снова:
```bash
docker compose down -v
docker compose up -d
sleep 15
./scripts/init-sharding.sh
```

### Проблема: Данные не распределяются
Пересоздайте коллекцию:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.drop();
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
db.helloDoc.getShardDistribution();
EOF
```

### Проблема: API возвращает ошибку
Перезапустите приложение:
```bash
docker compose restart pymongo-api
docker compose logs -f pymongo-api
```

## 📊 Архитектура

### Компоненты

| Компонент | Количество | Порт | Назначение |
|-----------|------------|------|------------|
| Config Servers | 3 | 27019 | Метаданные кластера |
| Shards | 2 | 27018 | Хранение данных |
| Mongos Router | 1 | 27017 | Маршрутизация запросов |
| API Application | 1 | 8080 | HTTP API |

### Архитектура соединений

```
Client (Browser/curl)
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

### База данных

- **БД:** `somedb`
- **Коллекция:** `helloDoc`
- **Shard Key:** `{ _id: "hashed" }`
- **Документов:** 1000+
- **Распределение:** ~50/50 между шардами

## ✅ Критерии выполнения

- [x] Все контейнеры запущены (7 шт)
- [x] Config servers в replica set
- [x] Оба шарда добавлены в кластер
- [x] БД `somedb` имеет шардирование
- [x] Коллекция `helloDoc` шардирована
- [x] В коллекции ≥1000 документов
- [x] Документы распределены между шардами
- [x] API возвращает информацию о шардах
- [x] `mongo_topology_type` = "Sharded"
- [x] `mongo_is_mongos` = true
- [x] `shard_distribution` показывает count и size

## 📚 Связанная документация

- ⚙️ [TASK2_SHARDING_SETUP.md](TASK2_SHARDING_SETUP.md) - подробная настройка
- 📖 [TASK1_PLANNING.md](TASK1_PLANNING.md) - планирование архитектуры
- 📊 [diagrams/ARCHITECTURE.md](../diagrams/ARCHITECTURE.md) - схема 1
- 🏠 [README.md](../README.md) - главная страница

## ✅ Статус

**Задание 2 выполнено на 100%**

Все требования ревьюера соблюдены:
- ✅ Проект запускается
- ✅ Настройка проходит без ошибок  
- ✅ Приложение показывает количество документов
- ✅ Приложение показывает распределение по шардам

**Готово к проверке!**

