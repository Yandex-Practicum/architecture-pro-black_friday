# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Инициализируем кластер

### Config Server
```shell
docker exec -it config1 mongosh --eval 'rs.initiate({
  _id: "config_server", 
  configsvr: true, 
  members: [
    {_id: 0, host: "config1:27017"}, 
    { _id: 1, host: "config2:27017"}, 
    { _id: 2, host: "config3:27017" }
]})'
```

### Шарды
```shell
docker exec -it shard1_primary mongosh --port 27018 --eval 'rs.initiate({
  _id: "shard1", 
  members: [
    {_id: 0, host: "shard1_primary:27018", priority: 2}, 
    {_id: 1, host: "shard1_secondary1:27018"}, 
    {_id: 2, host: "shard1_secondary2:27018"}
]})'
docker exec -it shard2_primary mongosh --port 27019 --eval 'rs.initiate({
    _id: "shard2",
    members: [
      {_id: 0, host: "shard2_primary:27019", priority: 2}, 
      {_id: 1, host: "shard2_secondary1:27019" }, 
      {_id: 2, host: "shard2_secondary2:27019"}
]})'
```

### Добавление шардов в кластер
```shell
docker exec -it query_router mongosh --port 27020 --eval '
  sh.addShard("shard1/shard1_primary:27018,shard1_secondary1:27018,shard1_secondary2:27018");
  sh.addShard("shard2/shard2_primary:27019,shard2_secondary1:27019,shard2_secondary2:27019");
  sh.enableSharding("somedb");
  sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })'
```

## Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

## Проверим mongodb
```shell
docker exec -it query_router mongosh --port 27020

// Переключиться на базу данных
use somedb

// Найти документы
db.helloDoc.find()

// Проверить распределение коллекции по шардам
db.helloDoc.getShardDistribution()

quit
```