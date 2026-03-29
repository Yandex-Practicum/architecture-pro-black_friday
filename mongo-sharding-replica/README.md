# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Подключитесь к серверу конфигурации и сделайте инициализацию

```shell
docker exec -it configSrv mongosh --port 27017

rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
});
```

Инициализируйте шарды:

```shell
docker exec -it shard1 mongosh --port 27018

rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1_primary:27018" },
    { _id: 1, host: "shard1_secondary1:27018" },
    { _id: 2, host: "shard1_secondary2:27018" }
  ]
});

docker exec -it shard2 mongosh --port 27019

rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2_primary:27019" },
    { _id: 1, host: "shard2_secondary1:27019" },
    { _id: 2, host: "shard2_secondary2:27019" }
  ]
});
```

Инцициализируйте роутер и наполните его тестовыми данными:

```shell
docker exec -it mongos_router mongosh --port 27020

> sh.addShard( "shard1/shard1:27018");
> sh.addShard( "shard2/shard2:27019");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

> use somedb

> for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})

> db.helloDoc.countDocuments() 
> exit();
```

## Как проверить
Количество документов на каждом шарде
```shell
db.helloDoc.getShardDistribution()
```

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs