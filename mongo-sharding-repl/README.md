# Mongo Sharding Repl (Black Friday)

Шардированный кластер MongoDB с репликацией: 3 сервера конфигурации (CSRS), 2 роутера `mongos`, 2 шарда, каждый шард — replica set из 3 узлов (primary + 2 secondaries).


## Запуск

```bash
cd mongo-sharding-repl
docker compose up -d
```


## Инициализация (выполнять по порядку)

### 1. Инициировать replica set конфиг-серверов


```bash
docker exec -it configSrv1 mongosh --eval '
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [
      { _id: 0, host: "173.17.0.10:27017" },
      { _id: 1, host: "173.17.0.11:27017" },
      { _id: 2, host: "173.17.0.12:27017" }
    ]
  })'
```


```bash
docker exec -it configSrv1 mongosh --eval 'rs.status().members.map(m => m.name + " " + m.stateStr)'
```

Должен появиться один `PRIMARY` и два `SECONDARY`.

### 2. Инициировать replica set каждого шарда


```bash
# Shard 1 — replica set из 3 узлов
docker exec -it shard1a mongosh --eval '
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "173.17.0.30:27017" },
      { _id: 1, host: "173.17.0.32:27017" },
      { _id: 2, host: "173.17.0.33:27017" }
    ]
  })'

# Shard 2 — replica set из 3 узлов
docker exec -it shard2a mongosh --eval '
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "173.17.0.31:27017" },
      { _id: 1, host: "173.17.0.34:27017" },
      { _id: 2, host: "173.17.0.35:27017" }
    ]
  })'
```

Проверить, что в каждом шарде есть `PRIMARY` и два `SECONDARY`:

```bash
docker exec -it shard1a mongosh --eval 'rs.status().members.map(m => m.name + " " + m.stateStr)'
docker exec -it shard2a mongosh --eval 'rs.status().members.map(m => m.name + " " + m.stateStr)'
```

### 3. Подключить шарды к кластеру (через роутер)

```bash
docker exec -it router1 mongosh --eval 'sh.addShard("shard1/173.17.0.30:27017,173.17.0.32:27017,173.17.0.33:27017")'
docker exec -it router1 mongosh --eval 'sh.addShard("shard2/173.17.0.31:27017,173.17.0.34:27017,173.17.0.35:27017")'
```

Проверить, что шарды подключились:

```bash
docker exec -it router1 mongosh --eval 'sh.status()'
```

### 4. Включить шардирование базы и коллекции

```bash
# разрешить шардирование для БД somedb
docker exec -it router1 mongosh somedb --eval 'sh.enableSharding("somedb")'

# зашардировать коллекцию users
docker exec -it router1 mongosh somedb --eval 'sh.shardCollection("somedb.users", { "_id": "hashed" })'
```

## Проверка

API поднимается на `http://localhost:8081`

```bash
curl http://localhost:8081/
```
## Добавление документов

```bash
docker exec -it router1 mongosh somedb --eval 'use somedb for(var i = 0; i < N; i++) db.users.insert({age:i, name:"ly"+i})'
```

