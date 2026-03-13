# Проектная работа 4 спринт: Шардирование и репликация

## Описание

Реализация отказоустойчивой архитектуры для онлайн-магазина «Мобильный мир» с использованием:
- **Шардирование MongoDB** — распределение данных по 2 шардам
- **Репликация** — 3 реплики на каждый шард (1 PRIMARY + 2 SECONDARY)
- **Кеширование Redis** — ускорение повторных запросов

## Структура репозитория

```
├── mongo-sharding/           # Задание 2: только шардирование
├── mongo-sharding-repl/      # Задание 3: шардирование + репликация
├── sharding-repl-cache/      # Задание 4: шардирование + репликация + кеш (ФИНАЛЬНАЯ ВЕРСИЯ)
├── drawio/                   # Схемы архитектуры (draw.io)

```

## Запуск финального стенда (для ревьюера)

### Требования
- Docker Desktop
- Минимум 2 CPU и 4 Гб ОЗУ

### Шаг 1: Переход в директорию проекта

```bash
cd sharding-repl-cache
```

### Шаг 2: Запуск контейнеров

```bash
docker compose up -d
```

Проверить статус:
```bash
docker compose ps
```

Все 11 контейнеров должны быть в статусе **Up**.

### Шаг 3: Инициализация MongoDB

**Windows (PowerShell):**

```powershell
# Инициализация Config Server
docker compose exec -T configSrv mongosh --port 27019 --eval "rs.initiate({_id:'configRS',configsvr:true,members:[{_id:0,host:'configSrv:27019'}]})"

# Инициализация Shard 1 (3 реплики)
docker compose exec -T shard1-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard1RS',members:[{_id:0,host:'shard1-1:27018'},{_id:1,host:'shard1-2:27018'},{_id:2,host:'shard1-3:27018'}]})"

# Инициализация Shard 2 (3 реплики)
docker compose exec -T shard2-1 mongosh --port 27018 --eval "rs.initiate({_id:'shard2RS',members:[{_id:0,host:'shard2-1:27018'},{_id:1,host:'shard2-2:27018'},{_id:2,host:'shard2-3:27018'}]})"

# Ожидание выбора PRIMARY (15-20 секунд)
Start-Sleep -Seconds 20

# Добавление шардов в кластер
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018')"
docker compose exec -T mongos mongosh --port 27017 --eval "sh.addShard('shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018')"

# Включение шардирования БД
docker compose exec -T mongos mongosh --port 27017 --eval "sh.enableSharding('somedb')"

# Шардирование коллекции
docker compose exec -T mongos mongosh --port 27017 --eval "sh.shardCollection('somedb.helloDoc',{name:'hashed'})"
```

**Linux/Mac (bash):**

```bash
# Инициализация Config Server
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "configRS", configsvr: true, members: [{_id: 0, host: "configSrv:27019"}]})
EOF

# Инициализация Shard 1 (3 реплики)
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1RS", members: [{_id: 0, host: "shard1-1:27018"}, {_id: 1, host: "shard1-2:27018"}, {_id: 2, host: "shard1-3:27018"}]})
EOF

# Инициализация Shard 2 (3 реплики)
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard2RS", members: [{_id: 0, host: "shard2-1:27018"}, {_id: 1, host: "shard2-2:27018"}, {_id: 2, host: "shard2-3:27018"}]})
EOF

# Ожидание выбора PRIMARY (15-20 секунд)
sleep 20

# Добавление шардов в кластер
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF

# Включение шардирования БД
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF

# Шардирование коллекции
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", {"name": "hashed"})
EOF
```

### Шаг 4: Генерация тестовых данных

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

**Linux/Mac (bash):**
```bash
for i in $(seq 1 1000); do
  curl -s -X POST "http://localhost:8080/helloDoc/users" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"user_$i\",\"age\":$((RANDOM % 50 + 18))}" > /dev/null
done
echo "Создано 1000 документов"
```

### Шаг 5: Проверка

Откройте в браузере: http://localhost:8080

**Ожидаемый ответ:**
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
  "cache_enabled": true,
  "status": "OK"
}
```

### Проверка кеширования

```powershell
# Первый запрос (~1000 мс)
Measure-Command { Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" }

# Второй запрос (< 100 мс, из Redis)
Measure-Command { Invoke-RestMethod -Uri "http://localhost:8080/helloDoc/users" }
```

### Проверка репликации

```powershell
# Shard 1: должен показать 1 PRIMARY + 2 SECONDARY
docker compose exec -T shard1-1 mongosh --port 27018 --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"

# Shard 2: должен показать 1 PRIMARY + 2 SECONDARY
docker compose exec -T shard2-1 mongosh --port 27018 --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"
```

### Проверка распределения по шардам

```powershell
docker compose exec -T mongos mongosh --port 27017 --eval "db.getSiblingDB('somedb').helloDoc.getShardDistribution()"
```

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

## Порты сервисов

| Сервис      | Порт  | Назначение           |
|-------------|-------|----------------------|
| pymongo_api | 8080  | REST API приложения  |
| mongos      | 27017 | Query Router         |
| configSrv   | 27019 | Config Server        |
| shard1-1    | 27018 | Shard 1, Replica 1   |
| shard1-2    | 27021 | Shard 1, Replica 2   |
| shard1-3    | 27022 | Shard 1, Replica 3   |
| shard2-1    | 27020 | Shard 2, Replica 1   |
| shard2-2    | 27024 | Shard 2, Replica 2   |
| shard2-3    | 27025 | Shard 2, Replica 3   |
| redis       | 6379  | Redis Cache          |

## Схемы архитектуры

Файлы draw.io находятся в папке `img/`:
- `1Шардирование MongoDB.drawio` — схема шардирования
- `2Шардирование+Репликация.drawio` — схема с репликацией
- `3Шардирование+Репликация+Redis.drawio` — схема с кешированием
- `5Service Discovery и балансировка с API Gateway.drawio` — горизонтальное масштабирование
- `6CDN.drawio` — схема с CDN

## Документация API

После запуска доступна Swagger UI: http://localhost:8080/docs

## Остановка проекта

```bash
cd sharding-repl-cache
docker compose down
```