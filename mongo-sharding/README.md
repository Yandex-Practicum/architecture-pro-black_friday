# Инициализация шардирования

> Все команды ниже можно вызвать, выполнив скрипт `_init.sh`.

Подключитесь к серверу конфигурации и сделайте инициализацию:

```
docker exec -it configSrv mongosh --port 27017

> rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
> exit();
```

Инициализируйте шарды:

```
docker exec -it shard1 mongosh --port 27018

> rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1:27018" },
      ]
    }
);
> exit();

docker exec -it shard2 mongosh --port 27019

> rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 1, host : "shard2:27019" }
      ]
    }
  );
> exit();
```

Инцициализируйте роутер и наполните его тестовыми данными:

```
docker exec -it mongos_router mongosh --port 27020

> sh.addShard( "shard1/shard1:27018");
> sh.addShard( "shard2/shard2:27019");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

> use somedb

> for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})

> db.helloDoc.countDocuments() 
> exit();
```

Получится результат — 1000 документов.

Сделайте проверку на шардах:

```
docker exec -it shard1 mongosh --port 27018

> use somedb;
> db.helloDoc.countDocuments();
> exit();
```

Получится результат — 492 документа.

Сделайте проверку на втором шарде:

```
docker exec -it shard2 mongosh --port 27019

> use somedb;
> db.helloDoc.countDocuments();
> exit();
```

Получится результат — 508 документов.