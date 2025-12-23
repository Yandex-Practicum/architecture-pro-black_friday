# Задание 3: Настройка Репликации для MongoDB Sharding

> 🔄 Детальная документация по настройке репликации для шардов  
> 🏠 [← Вернуться к README](../README.md) | 📋 [Итоговая сводка →](TASK3_SUMMARY.md) | 📊 [Схема →](../diagrams/ARCHITECTURE.md)

## Архитектура

Реализована вторая схема из планирования:
- **11 контейнеров** всего
- **3 Config Servers** в replica set
- **Shard 1 Replica Set** с 3 нодами (shard1-1, shard1-2, shard1-3)
- **Shard 2 Replica Set** с 3 нодами (shard2-1, shard2-2, shard2-3)
- **1 Mongos Router**
- **1 API Application**

## Быстрый старт

```bash
# Перейти в директорию проекта
cd mongo-sharding-repl
```

### 1. Запуск контейнеров

```bash
docker compose up -d
```

Будут запущены 11 контейнеров.

### 2. Инициализация репликации (автоматически)

```bash
./scripts/init-replication.sh
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

Подождите 5-10 секунд для завершения выборов.

### Шаг 2: Инициализация Shard 1 Replica Set

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

**Проверка статуса:**
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

### Шаг 3: Инициализация Shard 2 Replica Set

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
});
EOF
```

**Ожидаемый результат:**
```json
{ "ok": 1 }
```

**Проверка статуса:**
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

### Шаг 4: Добавление шардов с репликами в кластер

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018");
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

**Примечание:** Указываем все три ноды каждого replica set для высокой доступности.

### Шаг 5: Включение шардирования для БД

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF
```

### Шаг 6: Создание и шардирование коллекции

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```

### Шаг 7: Заполнение коллекции данными

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF
```

### Шаг 8: Проверка статуса репликации

#### Config Servers
```bash
docker compose exec -T configSrv1 mongosh --port 27019 --quiet <<EOF
rs.status();
EOF
```

#### Shard 1
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

#### Shard 2
```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

### Шаг 9: Проверка распределения данных

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF
```

## Проверка работы

### 1. Проверка статуса шардов с репликами

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

В выводе должны быть видны все три ноды каждого шарда:
```
shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018
shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018
```

### 2. Проверка членов Shard 1 Replica Set

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.conf().members.forEach(function(m) {
  print("_id: " + m._id + ", host: " + m.host);
});
EOF
```

### 3. Проверка членов Shard 2 Replica Set

```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.conf().members.forEach(function(m) {
  print("_id: " + m._id + ", host: " + m.host);
});
EOF
```

### 4. Проверка через API

```bash
curl -s http://127.0.0.1:8080 | jq '.shards'
```

**Ожидается:**
```json
{
  "shard1ReplSet": "shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018",
  "shard2ReplSet": "shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018"
}
```

Список реплик виден в host каждого шарда!

### 5. Подсчет документов в каждой реплике

#### Shard 1
```bash
# Primary
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Secondary (нужно разрешить чтение)
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
use somedb
db.getMongo().setReadPref('secondary')
db.helloDoc.countDocuments()
EOF
```

**Ожидается:** Одинаковое количество документов на всех репликах.

#### Shard 2
```bash
# Primary
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

# Secondary
docker compose exec -T shard2-2 mongosh --port 27018 --quiet <<EOF
use somedb
db.getMongo().setReadPref('secondary')
db.helloDoc.countDocuments()
EOF
```

## Тестирование отказоустойчивости

### Тест 1: Остановка Secondary ноды

Останавливаем одну из Secondary нод:
```bash
docker compose stop shard1-2
```

Проверяем, что кластер продолжает работать:
```bash
curl http://127.0.0.1:8080
```

Проверяем статус replica set:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - " + m.stateStr + " (health: " + m.health + ")");
});
EOF
```

Запускаем обратно:
```bash
docker compose start shard1-2
```

### Тест 2: Automatic Failover

Останавливаем Primary ноду:
```bash
docker compose stop shard1-1
```

Ждем 10-15 секунд для переизбрания:
```bash
sleep 15
```

Проверяем, что одна из Secondary стала новым Primary:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - " + m.stateStr);
});
EOF
```

**Ожидается:** Одна из нод (shard1-2 или shard1-3) теперь PRIMARY.

Проверяем, что приложение продолжает работать:
```bash
curl http://127.0.0.1:8080
```

Запускаем исходную Primary ноду обратно:
```bash
docker compose start shard1-1
```

Она присоединится как SECONDARY.

## Порты и доступ

| Сервис | Внутренний порт | Внешний порт | Доступ |
|--------|----------------|--------------|--------|
| configSrv1-3 | 27019 | - | Внутренний |
| shard1-1, shard1-2, shard1-3 | 27018 | - | Внутренний |
| shard2-1, shard2-2, shard2-3 | 27018 | - | Внутренний |
| mongos | 27017 | 27017 | Внешний |
| pymongo-api | 8080 | 8080 | Внешний |

## Архитектура соединений

```
Client
    ↓
pymongo-api:8080
    ↓
mongos:27017
    ├─→ Config Replica Set (configSrv1, configSrv2, configSrv3):27019
    │
    ├─→ Shard 1 Replica Set:27018
    │   ├─ shard1-1 (PRIMARY)
    │   ├─ shard1-2 (SECONDARY) ←─┐
    │   └─ shard1-3 (SECONDARY) ←─┤ Репликация
    │                              │
    └─→ Shard 2 Replica Set:27018  │
        ├─ shard2-1 (PRIMARY)      │
        ├─ shard2-2 (SECONDARY) ←──┤
        └─ shard2-3 (SECONDARY) ←──┘
```

## Устранение неполадок

### Проблема: Replica set не инициализируется

**Причина:** Контейнеры еще не полностью запустились.

**Решение:** Увеличьте время ожидания.
```bash
sleep 30
```

### Проблема: Нода застряла в STARTUP состоянии

**Проверка:**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

**Решение:** Перезапустите контейнер.
```bash
docker compose restart shard1-1
```

### Проблема: Не могу читать с Secondary

**Причина:** По умолчанию чтение с Secondary запрещено.

**Решение:** Установите read preference.
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
db.getMongo().setReadPref('secondary')
EOF
```

Или в приложении:
```python
client = MongoClient(read_preference=ReadPreference.SECONDARY_PREFERRED)
```

### Проблема: Долгая репликация

**Проверка отставания:**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.printSecondaryReplicationInfo();
EOF
```

### Проблема: Split brain

**Причина:** Сетевые проблемы между нодами.

**Решение:** Проверьте сетевую связность.
```bash
docker compose exec shard1-1 ping shard1-2
docker compose exec shard1-1 ping shard1-3
```

## Полезные команды

### Информация о replica set
```bash
# Конфигурация
rs.conf()

# Статус
rs.status()

# Отставание secondary
rs.printSecondaryReplicationInfo()

# Информация о replication lag
rs.printSlaveReplicationInfo()
```

### Управление replica set
```bash
# Добавить ноду
rs.add("hostname:port")

# Удалить ноду
rs.remove("hostname:port")

# Изменить приоритет
cfg = rs.conf()
cfg.members[0].priority = 2
rs.reconfig(cfg)

# Принудительный failover
rs.stepDown()
```

### Мониторинг
```bash
# Текущий Primary
rs.isMaster()

# Операции репликации
db.printReplicationInfo()

# Задержка репликации
rs.status().members.forEach(function(m) {
  print(m.name + " lag: " + (m.optimeDate ? (new Date() - m.optimeDate)/1000 : "N/A") + "s");
});
```

## Критерии успешной настройки

- ✅ Все 11 контейнеров запущены
- ✅ Config servers в replica set (3 ноды)
- ✅ Shard 1 в replica set (3 ноды: 1 PRIMARY + 2 SECONDARY)
- ✅ Shard 2 в replica set (3 ноды: 1 PRIMARY + 2 SECONDARY)
- ✅ Оба шарда добавлены с указанием всех реплик
- ✅ Коллекция `helloDoc` шардирована
- ✅ В коллекции ≥1000 документов
- ✅ Документы распределены между шардами
- ✅ API показывает список реплик в каждом шарде
- ✅ Replica sets работают корректно
- ✅ Failover работает автоматически

## Следующие шаги

После успешной настройки репликации переходите к:
- 📖 Задание 4: Кеширование (Redis)
- 📊 [Схема 3: Шардирование + Репликация + Кеширование](../diagrams/ARCHITECTURE.md)

## Связанная документация

- 📋 [TASK3_SUMMARY.md](TASK3_SUMMARY.md) - итоговая сводка
- 📖 [TASK1_PLANNING.md](TASK1_PLANNING.md) - планирование
- 🏠 [README.md](../README.md) - главная страница

