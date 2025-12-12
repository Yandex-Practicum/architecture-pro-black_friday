# mongo-sharding-repl
## Репликация + Шардирование MongoDB + приложение pymongo-api

Этот проект реализует **второй вариант схемы**:

- 2 шарда (shard1, shard2)
- каждый шард — **реплика-сет из 3 реплик**
- 3 config-сервера (configReplSet)
- mongos — точка входа в кластер
- приложение `pymongo-api`, подключённое к mongos
- БД: `somedb`
- Коллекция: `helloDoc`

---

# 1. Структура кластера

### Config servers (реплика-сет `configReplSet`)
- configsvr1
- configsvr2
- configsvr3

### Шард 1 (`shard1ReplSet`)
- shard1-1
- shard1-2
- shard1-3

### Шард 2 (`shard2ReplSet`)
- shard2-1
- shard2-2
- shard2-3

### Маршрутизатор
- mongos (service name: `mongos`)

### Приложение
- pymongo_api_repl  
  подключается к: `mongodb://mongos:27017`

---

# 2. Запуск проекта

```bash
docker compose up -d --build
docker compose ps
```

---

# 3. Инициализация репликации и шардирования

Скрипт:

```
scripts/mongo-sharding-repl-init.sh
```

Сделать исполняемым:

```bash
chmod +x scripts/mongo-sharding-repl-init.sh
```

Запуск:

```bash
./scripts/mongo-sharding-repl-init.sh
```

---

# 4. Наполнение коллекции test-данными

```bash
bash scripts/mongo-init.sh
```

Проверка:

```bash
docker compose exec -T mongos mongosh --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

---

# 5. Проверка распределения по шардам

```bash
docker compose exec -T mongos mongosh --quiet <<EOF
use somedb
db.helloDoc.aggregate([
  { $collStats: { count: {} } }
]).pretty()
EOF
```

---

# 6. Проверка количества реплик

### Шард 1:
```bash
docker compose exec -T shard1-1 mongosh --quiet <<EOF
rs.status().members.length
EOF
```

### Шард 2:
```bash
docker compose exec -T shard2-1 mongosh --quiet <<EOF
rs.status().members.length
EOF
```

### Config servers:
```bash
docker compose exec -T configsvr1 mongosh --quiet <<EOF
rs.status().members.length
EOF
```

---

# 7. Проверка работы приложения

Открыть:

```
http://localhost:8080
```
