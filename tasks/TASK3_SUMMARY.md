# Задание 3: Репликация - Итоговая сводка

> 🔄 Полное описание выполнения Задания 3  
> 🏠 [← Вернуться к README](../README.md)

## ✅ Задача

Настроить репликацию для каждого шарда согласно второй схеме из планирования:
- Расширить Shard 1 до 3 реплик
- Расширить Shard 2 до 3 реплик
- Модифицировать `compose.yaml`
- Создать скрипт автоматической инициализации
- Обеспечить отображение информации о репликах в API

## ✅ Что было сделано

### 1. Модифицирован compose.yaml

**Имя проекта:** `mongo-sharding-repl`

**Инфраструктура (11 контейнеров):**

#### Config Servers Replica Set (3)
```yaml
configSrv1, configSrv2, configSrv3
- Порт: 27019
- replSet: configReplSet
- Роли: 1 Primary + 2 Secondary
```

#### Shard 1 Replica Set (3 реплики)
```yaml
shard1-1, shard1-2, shard1-3
- Порт: 27018
- replSet: shard1ReplSet
- Роли: 1 Primary + 2 Secondary
```

#### Shard 2 Replica Set (3 реплики)
```yaml
shard2-1, shard2-2, shard2-3
- Порт: 27018
- replSet: shard2ReplSet
- Роли: 1 Primary + 2 Secondary
```

#### Mongos Router (1)
```yaml
mongos
- Порт: 27017
- Подключается ко всем replica sets
```

#### Application (1)
```yaml
pymongo-api
- Порт: 8080
- Подключается через mongos
```

### 2. Создан скрипт автоматической инициализации

**Файл:** `scripts/init-replication.sh`

**Выполняемые шаги:**

#### Шаг 1: Config Server Replica Set
```bash
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" },
    { _id: 2, host: "configSrv3:27019" }
  ]
});
```

#### Шаг 2: Shard 1 Replica Set (3 реплики)
```bash
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
```

#### Шаг 3: Shard 2 Replica Set (3 реплики)
```bash
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
});
```

#### Шаг 4: Добавление шардов с репликами
```bash
sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018");
```

#### Шаг 5-7: Шардирование и данные
- Включение шардирования для `somedb`
- Создание коллекции `helloDoc` с shard key `{ _id: "hashed" }`
- Загрузка 1000 документов

#### Шаг 8: Проверка статуса репликации
```bash
rs.status()  # для каждого replica set
```

#### Шаг 9: Проверка распределения данных
```bash
db.helloDoc.getShardDistribution()
```

### 3. API уже поддерживает репликацию

API автоматически определяет:
- `mongo_replicaset_name` - имя replica set
- `mongo_primary_host` - адрес Primary ноды
- `mongo_secondary_hosts` - список Secondary нод
- `replica_status` - полный статус репликации

## 🚀 Как запустить и проверить

### Быстрый старт

```bash
# Перейти в директорию проекта
cd mongo-sharding-repl

# 1. Запуск контейнеров (11 шт)
docker compose up -d

# 2. Инициализация (подождите 15 сек после запуска)
./scripts/init-replication.sh

# 3. Проверка
curl http://127.0.0.1:8080 | jq
```

### Что должно получиться

```json
{
  "mongo_topology_type": "Sharded",
  "mongo_replicaset_name": null,              // null для mongos
  "mongo_db": "somedb",
  "mongo_nodes": [
    ["mongos:27017"]
  ],
  "mongo_primary_host": null,                 // null для mongos
  "mongo_secondary_hosts": [],                // [] для mongos
  "mongo_is_mongos": true,
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1ReplSet": "shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018",
    "shard2ReplSet": "shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018"
  },
  "shard_distribution": {
    "helloDoc": {
      "shard1ReplSet": { "count": 500 },
      "shard2ReplSet": { "count": 500 }
    }
  },
  "status": "OK"
}
```

### Подробная проверка

#### 1. Проверка контейнеров
```bash
docker compose ps
# Должно быть 11 контейнеров в статусе running:
# configSrv1, configSrv2, configSrv3
# shard1-1, shard1-2, shard1-3
# shard2-1, shard2-2, shard2-3
# mongos, pymongo-api
```

#### 2. Проверка topology
```bash
curl -s http://127.0.0.1:8080 | jq '.mongo_topology_type'
# Ожидается: "Sharded"
```

#### 3. Проверка шардов с репликами
```bash
curl -s http://127.0.0.1:8080 | jq '.shards'
# Ожидается:
# {
#   "shard1ReplSet": "shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018",
#   "shard2ReplSet": "shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018"
# }
```

#### 4. Проверка статуса Shard 1 Replica Set
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - " + m.stateStr);
});
EOF
```

**Ожидается:**
```
shard1-1:27018 - PRIMARY
shard1-2:27018 - SECONDARY
shard1-3:27018 - SECONDARY
```

#### 5. Проверка статуса Shard 2 Replica Set
```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - " + m.stateStr);
});
EOF
```

**Ожидается:**
```
shard2-1:27018 - PRIMARY
shard2-2:27018 - SECONDARY
shard2-3:27018 - SECONDARY
```

#### 6. Проверка количества документов
```bash
curl -s http://127.0.0.1:8080 | jq '.collections.helloDoc.documents_count'
# Ожидается: 1000
```

#### 7. Проверка распределения по шардам
```bash
curl -s http://127.0.0.1:8080 | jq '.shard_distribution'
```

#### 8. Тест failover (необязательно)

Остановим Primary ноду Shard 1:
```bash
docker compose stop shard1-1
sleep 10
```

Проверим, что одна из Secondary стала Primary:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - " + m.stateStr);
});
EOF
```

Запустим обратно:
```bash
docker compose start shard1-1
```

## ✅ Соответствие требованиям ревьюера

### ✓ Проект запускается
```bash
docker compose up -d
```
**Результат:** 11 контейнеров в статусе running

### ✓ Настройка выполняется без ошибок
```bash
./scripts/init-replication.sh
```
**Результат:** Все 9 шагов завершаются успешно

### ✓ Приложение показывает общее количество документов
```bash
curl -s http://127.0.0.1:8080 | jq '.collections.helloDoc.documents_count'
```
**Результат:** 1000

### ✓ Приложение показывает количество в каждом шарде
```bash
curl -s http://127.0.0.1:8080 | jq '.shard_distribution.helloDoc'
```
**Результат:** Распределение между shard1ReplSet и shard2ReplSet

### ✓ Приложение показывает количество реплик
```bash
curl -s http://127.0.0.1:8080 | jq '.shards'
```
**Результат:**
```json
{
  "shard1ReplSet": "shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018",
  "shard2ReplSet": "shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018"
}
```

Видно, что в каждом шарде по 3 реплики!

## 📊 Архитектура

### Компоненты

| Компонент | Количество | Порт | Назначение |
|-----------|------------|------|------------|
| Config Servers | 3 | 27019 | Метаданные (replica set) |
| Shard 1 Replicas | 3 | 27018 | Данные (replica set) |
| Shard 2 Replicas | 3 | 27018 | Данные (replica set) |
| Mongos Router | 1 | 27017 | Маршрутизация |
| API Application | 1 | 8080 | HTTP API |
| **Всего** | **11** | | |

### Replica Sets

1. **configReplSet** (3 ноды)
   - configSrv1 (Primary)
   - configSrv2 (Secondary)
   - configSrv3 (Secondary)

2. **shard1ReplSet** (3 ноды)
   - shard1-1 (Primary)
   - shard1-2 (Secondary)
   - shard1-3 (Secondary)

3. **shard2ReplSet** (3 ноды)
   - shard2-1 (Primary)
   - shard2-2 (Secondary)
   - shard2-3 (Secondary)

### Преимущества

- ✅ **Отказоустойчивость**: При падении любой ноды кластер продолжает работу
- ✅ **Automatic Failover**: Автоматическое переизбрание Primary при сбое
- ✅ **Read Scaling**: Возможность чтения с Secondary нод
- ✅ **Горизонтальное масштабирование**: Данные распределены между шардами
- ✅ **Высокая доступность**: Нет single point of failure

## 🔧 Устранение проблем

### Проблема: Контейнеры не запускаются

```bash
docker compose down -v
docker compose up -d
```

### Проблема: Replica set не инициализируется

Увеличьте время ожидания в скрипте:
```bash
# В init-replication.sh изменить sleep 15 на sleep 30
```

### Проблема: Нода не становится Primary

Проверьте статус:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Принудительная переконфигурация:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
cfg = rs.conf();
cfg.members[0].priority = 2;
rs.reconfig(cfg);
EOF
```

## ✅ Критерии выполнения

- [x] Все 11 контейнеров запущены
- [x] Config servers в replica set (3 ноды)
- [x] Shard 1 в replica set (3 ноды)
- [x] Shard 2 в replica set (3 ноды)
- [x] Оба шарда добавлены в кластер
- [x] Коллекция `helloDoc` шардирована
- [x] В коллекции ≥1000 документов
- [x] Документы распределены между шардами
- [x] API показывает количество реплик в каждом шарде
- [x] `mongo_topology_type` = "Sharded"
- [x] Replica sets работают корректно

## 📚 Связанная документация

- 🔧 [TASK3_REPLICATION_SETUP.md](TASK3_REPLICATION_SETUP.md) - подробная настройка
- 📖 [TASK1_PLANNING.md](TASK1_PLANNING.md) - планирование (Схема 2)
- 📊 [diagrams/ARCHITECTURE.md](../diagrams/ARCHITECTURE.md) - схема 2
- 🏠 [README.md](../README.md) - главная страница

## ✅ Статус

**Задание 3 выполнено на 100%**

Все требования ревьюера соблюдены:
- ✅ Проект запускается (11 контейнеров)
- ✅ Настройка проходит без ошибок
- ✅ Приложение показывает количество документов (≥1000)
- ✅ Приложение показывает распределение по шардам
- ✅ Приложение показывает количество реплик (по 3 на каждый шард)

**Готово к проверке!**

