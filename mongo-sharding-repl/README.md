# mongo-sharding-repl

Шардированный MongoDB: **mongos**, **config server replica set**, два шарда, **каждый шард — replica set из трёх узлов** (один primary и две secondary). Приложение **pymongo-api** подключается к **mongos**.

База: `somedb`, коллекция: `helloDoc`.

Образ MongoDB: `mongo:7` (Docker Hub). При необходимости замените на образ из методички.

Не поднимайте **mongos** до инициализации **configRS** и replica set на шардах — используйте скрипт ниже или пошаговую инструкцию.

## Запуск

Порты по умолчанию: **8080** (API), **27017** (mongos). Если параллельно запущен проект `mongo-sharding`, остановите его или измените проброс портов в `compose.yaml`.

Из каталога `mongo-sharding-repl`:

```shell
docker compose build
./scripts/init-cluster.sh
```

Проверка: `curl http://localhost:8080/` — общее число документов в `helloDoc`, `documents_per_shard`, список шардов и **`shard_replica_sets`** (число **members** и **secondaries** на шард).

## Репликация на каждом шарде (пошагово)

Порты внутри контейнеров: **27017**. Имена сервисов = hostname в сети Compose.

### 1. Поднять config-сервер и все узлы шардов

```shell
docker compose up -d mongo-config1 \
  shard1-1 shard1-2 shard1-3 \
  shard2-1 shard2-2 shard2-3
```

### 2. Инициализировать config server replica set

```shell
docker compose exec -T mongo-config1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "configRS",
  configsvr: true,
  members: [{ _id: 0, host: "mongo-config1:27017" }]
})
EOF
```

Подождать несколько секунд, при необходимости `rs.status()`.

### 3. Инициализировать replica set первого шарда (3 узла)

Команда выполняется на **первом** члене (`shard1-1`); в `members` перечислены все три хоста:

```shell
docker compose exec -T shard1-1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27017" },
    { _id: 1, host: "shard1-2:27017" },
    { _id: 2, host: "shard1-3:27017" }
  ]
})
EOF
```

Дождаться состояния **PRIMARY** / **SECONDARY** на узлах (`rs.status()` на `shard1-1`).

### 4. Инициализировать replica set второго шарда (3 узла)

```shell
docker compose exec -T shard2-1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27017" },
    { _id: 1, host: "shard2-2:27017" },
    { _id: 2, host: "shard2-3:27017" }
  ]
})
EOF
```

### 5. Запустить mongos и приложение

```shell
docker compose up -d mongos pymongo_api
```

### 6. Зарегистрировать шарды в кластере

В **addShard** указывается **имя replica set** и **все члены** через запятую:

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27017,shard1-2:27017,shard1-3:27017")
sh.addShard("shard2/shard2-1:27017,shard2-2:27017,shard2-3:27017")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
EOF
```

### 7. Загрузить данные (≥ 1000 документов)

```shell
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
var somedb = db.getSiblingDB("somedb");
var docs = [];
for (var i = 0; i < 1000; i++) {
  docs.push({ age: i, name: "ly" + i });
}
somedb.helloDoc.insertMany(docs);
print(somedb.helloDoc.countDocuments());
EOF
```

Пример проверки на узле шарда:

```shell
docker compose exec -T shard1-1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Примечание

Повторный запуск `init-cluster.sh` обычно безопасен: уже инициализированные RS не трогаем (`rs.status()`), повторный `addShard`/`shardCollection` игнорируется или обрабатывается, данные дозаполняются при счётчике `< 1000`.
