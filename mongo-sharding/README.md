# mongo-sharding

Приложение `pymongo-api` и шардированный кластер MongoDB:

| Сервис          | Роль                                   | Порт  |
|-----------------|----------------------------------------|-------|
| `configSrv`     | сервер конфигурации (replica set `config_server`) | 27017 |
| `shard1`        | 1-й шард (replica set `shard1`)        | 27018 |
| `shard2`        | 2-й шард (replica set `shard2`)        | 27019 |
| `mongos_router` | роутер `mongos`                        | 27020 |
| `pymongo_api`   | приложение, ходит в MongoDB через `mongos_router` | 8080  |

БД — `somedb`, коллекция — `helloDoc`, ключ шардирования — `{ name: "hashed" }`.

## Как запустить

Все команды выполняются из директории `mongo-sharding`.

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем шардирование и заполняем MongoDB данными (скрипт выполняет все шаги из раздела ниже автоматически):

```shellconfigsvr
./scripts/mongo-init.sh
```

## Шаги инициализации шардирования (вручную)

1. Инициализируем сервер конфигурации:

```shell
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF
```

2. Инициализируем шарды:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
})
EOF
```

3. Добавляем шарды в роутер, включаем шардирование БД и коллекции:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF
```

4. Заполняем коллекцию тестовыми данными через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
db.helloDoc.countDocuments()
EOF
```

## Как проверить

Общее количество документов (через роутер) — 1000:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Количество документов на каждом шарде (в сумме 1000, например 492 и 508):

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Откройте в браузере http://localhost:8080 — в ответе будут `"mongo_topology_type": "Sharded"`, список шардов в поле `shards` и `"documents_count": 1000` для `helloDoc`.

Если проект запущен на виртуальной машине, узнайте её белый IP (`curl --silent http://ifconfig.me`) и откройте `http://<ip виртуальной машины>:8080`.

## Доступные эндпоинты

Список доступных эндпоинтов, swagger: http://localhost:8080/docs

## Остановка

```shell
docker compose down -v
```
