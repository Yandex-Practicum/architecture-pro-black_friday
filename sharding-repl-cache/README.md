# MongoDB Sharding with Replication and Caching

Шардирование MongoDB с двумя шардами, репликацией (по 3 реплики на шард) и кешированием Redis для проекта «Мобильный мир».

## Архитектура

```
pymongo_api (:8080)
      ↓
mongos (:27017) — Query Router
      ↓
configSrv (:27019) — Config Server
      ↓
┌─────────────────────────┬─────────────────────────┐
↓                         ↓                         ↓
Shard 1 (Replica Set)     Shard 2 (Replica Set)
  - shard1-1:27018          - shard2-1:27018
  - shard1-2:27021          - shard2-2:27024
  - shard1-3:27022          - shard2-3:27025

redis (:6379) — Cache
```

## Запуск проекта

### Шаг 1: Запуск контейнеров

```bash
docker compose up -d --build
```

Проверить статус:

```bash
docker compose ps
```

Все 11 контейнеров должны быть в статусе Up или running.

### Шаг 2: Инициализация Config Server

**Linux/Mac (bash):**
```bash
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configRS",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T configSrv mongosh --port 27019 --eval "rs.initiate({_id:'configRS',configsvr:true,members:[{_id:0,host:'configSrv:27019'}]})"
```

### Шаг 3: Инициализация Shard 1 (Replica Set с 3 нодами)

**Linux/Mac (bash):**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1RS",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard1-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard1RS',members:[{_id:0,host:'shard1-1:27018'},{_id:1,host:'shard1-2:27018'},{_id:2,host:'shard1-3:27018'}]})"
```

### Шаг 4: Инициализация Shard 2 (Replica Set с 3 нодами)

**Linux/Mac (bash):**
```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2RS",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard2-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard2RS',members:[{_id:0,host:'shard2-1:27018'},{_id:1,host:'shard2-2:27018'},{_id:2,host:'shard2-3:27018'}]})"
```

### Шаг 5: Ожидание выбора PRIMARY

Подождите 15-20 секунд, пока во всех replica set выберется PRIMARY.

### Шаг 6: Добавление шардов в кластер

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018')"
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018')"
```

### Шаг 7: Включение шардирования для базы данных

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "sh.enableSharding('somedb')"
```

### Шаг 8: Настройка шардирования коллекции

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "sh.shardCollection('somedb.helloDoc',{name:'hashed'})"
```

### Шаг 9: Генерация тестовых данных

**Linux/Mac (bash):**
```bash
for i in $(seq 1 1000); do
  curl -s -X POST "http://localhost:8080/helloDoc/users" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"user_$i\",\"age\":$((RANDOM % 50 + 18))}" > /dev/null
done
echo "Создано 1000 документов"
```

**Windows (PowerShell):**
```powershell
1..1000 | ForEach-Object {
  $name = "user_$_"
  $age = Get-Random -Minimum 18 -Maximum 68
  $body = "{`"name`":`"$name`",`"age`":$age}"
  Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" -Method POST -ContentType "application/json" -Body $body | Out-Null
}
Write-Host "Создано 1000 документов"
```

## Проверка результатов

### Через API (браузер)

Откройте: http://localhost:8080/

Должен быть ответ:

```json
{
  "mongo_topology_type": "Sharded",
  "mongo_is_mongos": true,
  "shards": {
    "shard1RS": "shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018",
    "shard2RS": "shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018"
  },
  "collections": {
    "helloDoc": { "documents_count": 1000 }
  },
  "cache_enabled": true
}
```

### Проверка кеширования

Эндпоинт `/<collection_name>/users` кеширует результаты на 60 секунд.

**Первый запрос (без кеша):**
```powershell
Measure-Command { Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" }
```

Время: ~1 секунда (в коде есть `time.sleep(1)`).

**Второй запрос (из кеша):**
```powershell
Measure-Command { Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" }
```

Время: <100 мс (данные из Redis).

### Проверка реплик

**Статус реплик Shard 1:**

**Linux/Mac (bash):**
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.map(m => ({name: m.name, state: m.stateStr}))
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard1-1 mongosh --port 27018 --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"
```

**Статус реплик Shard 2:**

**Linux/Mac (bash):**
```bash
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.map(m => ({name: m.name, state: m.stateStr}))
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard2-1 mongosh --port 27018 --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"
```

### Распределение по шардам

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "db.getSiblingDB('somedb').helloDoc.getShardDistribution()"
```

## Остановка проекта

```bash
docker compose down
```

## Порты сервисов

| Сервис      | Внешний порт | Внутренний порт | Назначение           |
|-------------|--------------|-----------------|----------------------|
| pymongo_api | 8080         | 8080            | REST API приложения  |
| mongos      | 27017        | 27017           | Query Router         |
| configSrv   | 27019        | 27019           | Config Server        |
| shard1-1    | 27018        | 27018           | Shard 1, Replica 1   |
| shard1-2    | 27021        | 27018           | Shard 1, Replica 2   |
| shard1-3    | 27022        | 27018           | Shard 1, Replica 3   |
| shard2-1    | 27020        | 27018           | Shard 2, Replica 1   |
| shard2-2    | 27024        | 27018           | Shard 2, Replica 2   |
| shard2-3    | 27025        | 27018           | Shard 2, Replica 3   |
| redis       | 6379         | 6379            | Redis Cache          |

## Документация API

После запуска доступна Swagger UI: http://localhost:8080/docs

## Полный скрипт инициализации (Linux/Mac)

```bash
#!/bin/bash
set -e

echo "=== Инициализация MongoDB Sharding with Replication and Caching ==="

echo "[1/9] Запуск контейнеров..."
docker compose up -d --build

echo "[2/9] Инициализация Config Server..."
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "configRS", configsvr: true, members: [{_id: 0, host: "configSrv:27019"}]})
EOF

echo "[3/9] Инициализация Shard 1 (Replica Set)..."
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1RS", members: [{_id: 0, host: "shard1-1:27018"}, {_id: 1, host: "shard1-2:27018"}, {_id: 2, host: "shard1-3:27018"}]})
EOF

echo "[4/9] Инициализация Shard 2 (Replica Set)..."
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard2RS", members: [{_id: 0, host: "shard2-1:27018"}, {_id: 1, host: "shard2-2:27018"}, {_id: 2, host: "shard2-3:27018"}]})
EOF

echo "[5/9] Ожидание выбора PRIMARY (20 секунд)..."
sleep 20

echo "[6/9] Добавление шардов..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF

echo "[7/9] Включение шардирования БД..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF

echo "[8/9] Шардирование коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", {"name": "hashed"})
EOF

echo "=== Инициализация завершена! ==="
```

## Полный скрипт инициализации (Windows PowerShell)

```powershell
Write-Host "=== Инициализация MongoDB Sharding with Replication and Caching ===" -ForegroundColor Green

Write-Host "[1/9] Запуск контейнеров..." -ForegroundColor Yellow
docker compose up -d --build

Write-Host "[2/9] Инициализация Config Server..." -ForegroundColor Yellow
docker compose exec -T configSrv mongosh --port 27019 --eval "rs.initiate({_id:'configRS',configsvr:true,members:[{_id:0,host:'configSrv:27019'}]})"

Write-Host "[3/9] Инициализация Shard 1 (Replica Set)..." -ForegroundColor Yellow
docker compose exec -T shard1-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard1RS',members:[{_id:0,host:'shard1-1:27018'},{_id:1,host:'shard1-2:27018'},{_id:2,host:'shard1-3:27018'}]})"

Write-Host "[4/9] Инициализация Shard 2 (Replica Set)..." -ForegroundColor Yellow
docker compose exec -T shard2-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard2RS',members:[{_id:0,host:'shard2-1:27018'},{_id:1,host:'shard2-2:27018'},{_id:2,host:'shard2-3:27018'}]})"

Write-Host "[5/9] Ожидание выбора PRIMARY (20 секунд)..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

Write-Host "[6/9] Добавление шардов..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018')"
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018')"

Write-Host "[7/9] Включение шардирования БД..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.enableSharding('somedb')"

Write-Host "[8/9] Шардирование коллекции..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.shardCollection('somedb.helloDoc',{name:'hashed'})"

Write-Host "=== Инициализация завершена! ===" -ForegroundColor Green
```
