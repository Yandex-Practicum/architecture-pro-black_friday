# mongo-sharding

Инструкция по запуску и инициализации MongoDB шардирования.

Проект содержит сервисы `configSrv` (config server), два шарда `shard1` и `shard2` (каждый — replica set в конфигурации), роутер `mongos_router` и простое приложение `pymongo_api`.


1. Запускаем контейнеры в директории mongo-sharding

```bash
docker compose -f compose.yaml up -d
```

2. Инициализируем replica set конфигурационного сервера

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({_id: 'config_server', members: [{_id: 0, host: 'configSrv:27017'}]})
rs.status()
EOF
```

3. Инициализируем replica set для каждого шарда

Shard1:

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({_id: 'shard1', members: [{_id: 0, host: 'shard1:27018'}]})
rs.status()
EOF
```

Shard2:

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({_id: 'shard2', members: [{_id: 0, host: 'shard2:27019'}]})
rs.status()
EOF
```

4. Подключиться к mongos и зарегистрировать шарды (addShard)

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
// проверить соединение
sh.status()

// добавить шарды (используем имя replica set/host:port)
sh.addShard('shard1/shard1:27018')
sh.addShard('shard2/shard2:27019')

// проверить
sh.status()
EOF
```

5. Включаем шардирование для БД и коллекции

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
// Включаем шардирование DB
sh.enableSharding('somedb')

// Шардируем коллекцию somedb.helloDoc по хешированному ключу _id
sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})

// Посмотреть статус
sh.status()
EOF
```

6. Заполняем коллекцию (пример: 2000 документов)

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
for (let i=0;i<2000;i++) {
  db.helloDoc.insertOne({_id: i, value: 'hello_'+i})
}
print('done')
EOF
```

7. Проверяем — общее количество и по каждому шару

Общее количество (через mongos):

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
print('total=', db.helloDoc.countDocuments())
EOF
```

Количество на каждом шарде — подключаемся к инстансам шардов напрямую и считаем:

Shard1 (порт 27018):

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb
print('shard1=', db.helloDoc.countDocuments())
EOF
```

Shard2 (порт 27019):

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
use somedb
print('shard2=', db.helloDoc.countDocuments())
EOF
```

Также можно посмотреть распределение чанков:

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.status()
EOF
```
