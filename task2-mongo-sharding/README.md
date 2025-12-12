# mongo-sharding / pymongo-api

## Состав инфраструктуры (первый вариант схемы)

После запуска `docker compose` поднимаются следующие сервисы:

- `configsvr` — config server MongoDB (реплика-сет `configReplSet`, один инстанс).
- `shard1` — первый шард MongoDB (реплика-сет `shard1ReplSet`, один инстанс).
- `shard2` — второй шард MongoDB (реплика-сет `shard2ReplSet`, один инстанс).
- `mongos` — маршрутизатор MongoDB, через него ходит приложение.
- `pymongo_api` — FastAPI‑приложение, обращается в MongoDB через `mongos`.

База данных: `somedb`  
Коллекция: `helloDoc`

---

## 1. Запуск проекта

```bash
docker compose up -d --build
```

Дождитесь, пока все контейнеры будут в статусе `healthy` / `running`:

```bash
docker compose ps
```

---

## 2. Инициализация шардинга MongoDB

Ниже приведены команды, которые нужно выполнить **один раз** после первого запуска кластера.

### 2.1. Инициализация config server (configReplSet)

```bash
docker compose exec -T configsvr mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configsvr:27019" }
  ]
})
EOF
```

Проверить состояние реплика‑сета:

```bash
docker compose exec -T configsvr mongosh --port 27019 --quiet <<EOF
rs.status()
EOF
```

### 2.2. Инициализация shard1 (shard1ReplSet)

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
})
EOF
```

### 2.3. Инициализация shard2 (shard2ReplSet)

```bash
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27018" }
  ]
})
EOF
```

### 2.4. Регистрация шардов и включение шардинга для БД

Делаем всё через маршрутизатор `mongos`:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
// Добавляем шарды (реплика‑сеты) в кластер
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27018")

// Включаем шардинг для базы somedb
sh.enableSharding("somedb")

// Шардируем коллекцию somedb.helloDoc по _id (hashed)
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
EOF
```

Проверка конфигурации шардов:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

---
 ### Скрипт, который инициализирует шардинг (все что в п2)
```bash
./scripts/mongo-sharding-repl-init.sh
```
---

## 3. Наполнение коллекции `helloDoc` тестовыми данными

Для вставки ≥ 1000 документов воспользуемся вспомогательным скриптом `scripts/mongo-init.sh`:

```bash
bash scripts/mongo-init.sh
```

Внутри он выполняет примерно такие команды:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}
EOF
```

После выполнения можно убедиться, что документы записались:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

---

## 4. Проверка работы приложения

После инициализации шардирования и наполнения БД:

1. Убедитесь, что все контейнеры работают:

   ```bash
   docker compose ps
   ```

2. Откройте в браузере:

   ```
   http://localhost:8080
   ```
