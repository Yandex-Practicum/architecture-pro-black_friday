
# mongo-sharding-repl

Инструкция по запуску и инициализации MongoDB шардирования с репликацией.

Эта директория содержит `compose.yaml`, где развернуты:

- 1 x config server: `configSrv` (порт 27017)
- 2 шарда: `shard1` и `shard2`, каждый реализован как replica set из 3 членов:
  - shard1: `shard1a`, `shard1b`, `shard1c` (внутренний порт 27018)
  - shard2: `shard2a`, `shard2b`, `shard2c` (внутренний порт 27019)
- mongos роутер: `mongos_router` (порт 27020)
- простое API-приложение `pymongo_api` (доступно на порту 8080 на хосте)

Ключевые порты (хост:контейнер) по умолчанию:

- 8080 -> pymongo_api (API)
- 27017 -> configSrv
- 27018 -> shard1a (shard1b/1c проброшены на 27021/27022 соответственно)
- 27019 -> shard2a (shard2b/2c проброшены на 27023/27024 соответственно)
- 27020 -> mongos_router

1) Запустить контейнеры из директории mongo-sharding-repl

```bash
docker compose -f compose.yaml up -d
```

2) Инициализировать Replica Set для config server

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({_id: 'config_server', members: [{_id: 0, host: 'configSrv:27017'}]})
rs.status()
EOF
```

3) Инициализировать Replica Set для каждого шарда

Shard1 (выполняется на одном из членов, например на `shard1a`):

```bash
docker compose exec -T shard1a mongosh --port 27018 --quiet <<'EOF'
rs.initiate({_id: 'shard1', members: [
  {_id: 0, host: 'shard1a:27018'},
  {_id: 1, host: 'shard1b:27018'},
  {_id: 2, host: 'shard1c:27018'}
]})
rs.status()
EOF
```

Shard2:

```bash
docker compose exec -T shard2a mongosh --port 27019 --quiet <<'EOF'
rs.initiate({_id: 'shard2', members: [
  {_id: 0, host: 'shard2a:27019'},
  {_id: 1, host: 'shard2b:27019'},
  {_id: 2, host: 'shard2c:27019'}
]})
rs.status()
EOF
```

4) Зарегистрировать шарды в `mongos`

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
// проверить соединение
sh.status()

// добавить шарды (указываем replica-set name и адреса членов)
sh.addShard('shard1/shard1a:27018,shard1b:27018,shard1c:27018')
sh.addShard('shard2/shard2a:27019,shard2b:27019,shard2c:27019')

// проверить
sh.status()
EOF
```

5) Включить шардирование для БД и коллекции

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.enableSharding('somedb')
sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})
sh.status()
EOF
```

6) Заполнить коллекцию данными

Используйте подготовленный скрипт:

```bash
./scripts/mongo-init.sh
```

Скрипт вставляет 2000 документов через `mongos` — это гарантирует распределение чанков между шардами.

7) Проверка

- API-приложение доступно по адресу http://localhost:8080/ — в корне JSON с топологией, коллекциями и информацией о шардах.
- Проверить общее количество документов:

```bash
curl http://localhost:8080/helloDoc/count
```

- Посчитать документы на шарде 1 (например, `shard1a`):

```bash
docker compose exec -T shard1a mongosh --port 27018 --quiet <<'EOF'
use somedb
print('shard1 member count documents =', db.helloDoc.countDocuments())
EOF
```