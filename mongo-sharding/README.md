# MongoDB Sharding Project

Шардирование MongoDB с двумя шардами для проекта «Мобильный мир».

## Архитектура

```
pymongo_api (:8080)
      ↓
mongos (:27017) — Query Router
      ↓
configSrv (:27019) — Config Server
      ↓
┌─────────┴─────────┐
↓                   ↓
shard1 (:27018)   shard2 (:27020)
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

Все 5 контейнеров должны быть в статусе Up или running.

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

### Шаг 3: Инициализация Shard 1

**Linux/Mac (bash):**
```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1RS",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard1 mongosh --port 27018 --eval "rs.initiate({_id:'shard1RS',members:[{_id:0,host:'shard1:27018'}]})"
```

### Шаг 4: Инициализация Shard 2

**Linux/Mac (bash):**
```bash
docker compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2RS",
  members: [{ _id: 0, host: "shard2:27020" }]
})
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T shard2 mongosh --port 27020 --eval "rs.initiate({_id:'shard2RS',members:[{_id:0,host:'shard2:27020'}]})"
```

### Шаг 5: Ожидание выбора PRIMARY

Подождите 10-15 секунд, пока во всех replica set выберется PRIMARY.

### Шаг 6: Добавление шардов в кластер

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1RS/shard1:27018")
sh.addShard("shard2RS/shard2:27020")
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard1RS/shard1:27018')"
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard2RS/shard2:27020')"
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

Создайте не менее 1000 документов:

```bash
for i in $(seq 1 1000); do
  curl -s -X POST "http://localhost:8080/helloDoc/users" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"user_$i\",\"age\":$((RANDOM % 50 + 18))}" > /dev/null
done
echo "Создано 1000 документов"
```

Примечание: Если команда не работает в PowerShell, используйте альтернативный способ ниже.

Альтернатива для Windows PowerShell:

```powershell
1..1000 | ForEach-Object {
  $name = "user_$_"
  $age = Get-Random -Minimum 18 -Maximum 68
  $body = "{`"name`":`"$name`",`"age`":$age}"
  Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body | Out-Null
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
    "shard1": "shard1RS/shard1:27018",
    "shard2": "shard2RS/shard2:27020"
  },
  "collections": {
    "helloDoc": { "documents_count": 1000 }
  }
}
```

### Общее количество документов

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
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

Пример вывода:

```
Shard shard1RS at shard1RS/shard1:27018
  data : 512 docs (51.2%) 
Shard shard2RS at shard2RS/shard2:27020
  data : 488 docs (48.8%) 
Totals
  data : 1000 docs 
```

### Статус шардирования

**Linux/Mac (bash):**
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

**Windows (PowerShell):**
```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "sh.status()"
```

## Полный скрипт инициализации (Linux/Mac)

```bash
#!/bin/bash
set -e

echo "=== Инициализация MongoDB Sharding ==="

echo "[1/8] Запуск контейнеров..."
docker compose up -d --build

echo "[2/8] Инициализация Config Server..."
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "configRS", configsvr: true, members: [{_id: 0, host: "configSrv:27019"}]})
EOF

echo "[3/8] Инициализация Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1RS", members: [{_id: 0, host: "shard1:27018"}]})
EOF

echo "[4/8] Инициализация Shard 2..."
docker compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
rs.initiate({_id: "shard2RS", members: [{_id: 0, host: "shard2:27020"}]})
EOF

echo "[5/8] Ожидание выбора PRIMARY (15 секунд)..."
sleep 15

echo "[6/8] Добавление шардов..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1RS/shard1:27018")
sh.addShard("shard2RS/shard2:27020")
EOF

echo "[7/8] Включение шардирования БД..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF

echo "[8/8] Шардирование коллекции..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", {"name": "hashed"})
EOF

echo "=== Инициализация завершена! ==="
```

## Полный скрипт инициализации (Windows PowerShell)

```powershell
Write-Host "=== Инициализация MongoDB Sharding ===" -ForegroundColor Green

Write-Host "[1/8] Запуск контейнеров..." -ForegroundColor Yellow
docker compose up -d --build

Write-Host "[2/8] Инициализация Config Server..." -ForegroundColor Yellow
docker compose exec -T configSrv mongosh --port 27019 --eval "rs.initiate({_id:'configRS',configsvr:true,members:[{_id:0,host:'configSrv:27019'}]})"

Write-Host "[3/8] Инициализация Shard 1..." -ForegroundColor Yellow
docker compose exec -T shard1 mongosh --port 27018 --eval "rs.initiate({_id:'shard1RS',members:[{_id:0,host:'shard1:27018'}]})"

Write-Host "[4/8] Инициализация Shard 2..." -ForegroundColor Yellow
docker compose exec -T shard2 mongosh --port 27020 --eval "rs.initiate({_id:'shard2RS',members:[{_id:0,host:'shard2:27020'}]})"

Write-Host "[5/8] Ожидание выбора PRIMARY (15 секунд)..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "[6/8] Добавление шардов..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard1RS/shard1:27018')"
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard2RS/shard2:27020')"

Write-Host "[7/8] Включение шардирования БД..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.enableSharding('somedb')"

Write-Host "[8/8] Шардирование коллекции..." -ForegroundColor Yellow
docker compose exec -T mongos mongosh --port 27017 --eval "sh.shardCollection('somedb.helloDoc',{name:'hashed'})"

Write-Host "=== Инициализация завершена! ===" -ForegroundColor Green
```

## Остановка проекта

```bash
docker compose down
```

## Порты сервисов

| Сервис      | Порт  | Назначение       |
|-------------|-------|------------------|
| pymongo_api | 8080  | REST API приложения |
| mongos      | 27017 | Query Router     |
| shard1      | 27018 | Shard 1          |
| configSrv   | 27019 | Config Server    |
| shard2      | 27020 | Shard 2          |

## Документация API

После запуска доступна Swagger UI: http://localhost:8080/docs

