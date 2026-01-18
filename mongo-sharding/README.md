# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Инициализируем кластер

### Config Server
```shell
docker exec -it config_server mongosh --eval 'rs.initiate({
  _id: "config_server", 
  configsvr: true, 
  members: [
    {_id: 0, host: "config_server:27017"}
]})'
```

### Шарды
```shell
docker exec -it mongodb1 mongosh --port 27018 --eval 'rs.initiate({
  _id: "shard1", 
  members: [
    {_id: 0, host: "mongodb1:27018"}
]})'
docker exec -it mongodb2 mongosh --port 27019 --eval 'rs.initiate({
  _id: "shard2", 
  members: [
    {_id: 0, host: "mongodb2:27019"}
]})'
```

### Добавление шардов в кластер
```shell
docker exec -it query_router mongosh --port 27020 --eval '
  sh.addShard("shard1/mongodb1:27018");
  sh.addShard("shard2/mongodb2:27019");
  sh.enableSharding("somedb");
  sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })'
```

### Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

### Проверим mongodb
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