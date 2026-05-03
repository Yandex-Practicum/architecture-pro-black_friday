# MongoDB Sharding + Replication

Шардированный кластер MongoDB с репликацией. Каждый шард и config server — replica set из 3 узлов.

## Архитектура

- **mongos_router** — маршрутизатор запросов
- **configsvr1, configsvr2, configsvr3** — config server replica set (`configReplSet`)
- **shard1-1, shard1-2, shard1-3** — Shard 1 replica set (`shard1ReplSet`)
- **shard2-1, shard2-2, shard2-3** — Shard 2 replica set (`shard2ReplSet`)
- **pymongo_api** — приложение (FastAPI + Motor)

Всего 10 контейнеров: 9 узлов MongoDB + приложение.

## Запуск

### 1. Поднять контейнеры

```bash
docker compose up -d
```

### 2. Инициализировать кластер

```bash
bash scripts/mongo-init.sh
```

Скрипт выполняет:
1. Инициализацию replica set для config server (3 узла: configsvr1, configsvr2, configsvr3)
2. Инициализацию replica set для shard1 (3 узла: shard1-1, shard1-2, shard1-3)
3. Инициализацию replica set для shard2 (3 узла: shard2-1, shard2-2, shard2-3)
4. Добавление обоих шардов в кластер через mongos
5. Включение шардирования для БД `somedb`
6. Шардирование коллекции `helloDoc` по полю `age` (hashed)
7. Заполнение коллекции 1000 тестовыми документами

### 3. Проверить работу

```bash
# Статус приложения (покажет шарды, реплики, primary/secondary)
curl http://localhost:8080/

# Количество документов
curl http://localhost:8080/helloDoc/count

# Статус replica set для shard1
docker compose exec shard1-1 mongosh --port 27017 --eval "rs.status()"

# Статус replica set для shard2
docker compose exec shard2-1 mongosh --port 27017 --eval "rs.status()"

# Распределение данных по шардам
docker compose exec mongos_router mongosh --port 27017 --eval "use somedb; db.helloDoc.getShardDistribution()"
```

## Настройка репликации для каждого шарда

Репликация настраивается через `rs.initiate()` на одном из узлов каждого шарда.
При добавлении шарда в кластер указывается имя replica set и все его члены:

```javascript
// Пример для shard1
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27017" },
    { _id: 1, host: "shard1-2:27017" },
    { _id: 2, host: "shard1-3:27017" }
  ]
})

// Добавление шарда в кластер (через mongos)
sh.addShard("shard1ReplSet/shard1-1:27017,shard1-2:27017,shard1-3:27017")
```

MongoDB автоматически выбирает Primary в каждом replica set. При падении Primary происходит автоматическое переизбрание (failover).

## Остановка

```bash
docker compose down -v
```
