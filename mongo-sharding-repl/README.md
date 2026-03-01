# Настройка репликации

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

Подключаемся к контейнеру shard1_1:

```
docker exec -it shard1_1 mongosh --port 27018
```

Создаём набор реплик rs1 в командной оболочке mongosh:

```
> rs.initiate(
    {
      _id : "rs1",
      members: [
        { _id : 0, host : "shard1_1:27018" },
        { _id : 1, host : "shard1_2:27019" },
        { _id : 2, host : "shard1_3:27020" },
      ]
    }
);
> exit();
```
Подключаемся к контейнеру shard2_1:

```
docker exec -it shard2_1 mongosh --port 27021
```

Создаём набор реплик rs2 в командной оболочке mongosh:

```
> rs.initiate(
    {
      _id : "rs2",
      members: [
        { _id : 0, host : "shard2_1:27021" },
        { _id : 1, host : "shard2_2:27022" },
        { _id : 2, host : "shard2_3:27023" },
      ]
    }
);
> exit();
```

Инцициализируйте роутер и наполните его тестовыми данными:

```
docker exec -it mongos_router mongosh --port 27024

> sh.addShard( "rs1/shard1_1:27018,shard1_2:27019,shard1_3:27020");
> sh.addShard( "rs2/shard2_1:27021,shard2_2:27022,shard2_3:27023");

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
docker exec -it shard1_1 mongosh --port 27018

> use somedb;
> db.helloDoc.countDocuments();
> exit();
```

Получится результат — 492 документа.

Сделайте проверку на втором шарде:

```
docker exec -it shard2_1 mongosh --port 27021

> use somedb;
> db.helloDoc.countDocuments();
> exit();
```

Получится результат — 508 документов.

Проверка сета rs1:

```
docker compose exec -T shard1_1 mongosh --port 27018

> rs.status().members.map(
    m=>(
        {
            name:m.name,
            state:m.stateStr,
            health:m.health
        }
    )
);
> exit();
```

Проверка сета rs2:

```
docker compose exec -T shard2_1 mongosh --port 27021

> rs.status().members.map(
    m=>(
        {
            name:m.name,
            state:m.stateStr,
            health:m.health
        }
    )
);
> exit();
```