# mongo-sharding-repl

## Как запустить

1. Запускаем mongodb-кластер и приложение. Для этого из каталога, в котором размещен данный файл выполнить:

```shell
docker compose up -d
```

2. Подключиться к серверу конфигурации и сделать инициализацию:

```bash
docker exec -it configSrv1 mongosh --port 27017

> rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
            { _id: 0, host: "configSrv1:27017" },
            { _id: 1, host: "configSrv2:27017" },
            { _id: 2, host: "configSrv3:27017" }
          ]
  }
);
> exit();
```

3. Инициализировать шарды:

```bash
docker exec -it shard1_node1 mongosh --port 27022

> rs.initiate({
          _id: "shard1",
          members: [
            { _id: 0, host: "shard1_node1:27022" },
            { _id: 1, host: "shard1_node2:27023" },
            { _id: 2, host: "shard1_node3:27024" }
          ]
});
> exit();

docker exec -it shard2_node1 mongosh --port 27025

> rs.initiate({
          _id: "shard2",
          members: [
            { _id: 0, host: "shard2_node1:27025" },
            { _id: 1, host: "shard2_node2:27026" },
            { _id: 2, host: "shard2_node3:27027" }
          ]
});
> exit();
```

4. Инцициализировать роутер 1, и наполнить через него тестовыми данными:

```bash
docker exec -it mongos_router1 mongosh --port 27020

> sh.addShard("shard1/shard1_node1:27022,shard1_node2:27023,shard1_node3:27024");
> sh.addShard("shard2/shard2_node1:27025,shard2_node2:27026,shard2_node3:27027");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

> use somedb

> for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})

> db.helloDoc.countDocuments() 
> exit();
```

5. Аналогично можно инициализировать второй роутер:
```bash
docker exec -it mongos_router2 mongosh --port 27021

> sh.addShard("shard1/shard1_node1:27022,shard1_node2:27023,shard1_node3:27024");
> sh.addShard("shard2/shard2_node1:27025,shard2_node2:27026,shard2_node3:27027");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

> use somedb

> db.helloDoc.countDocuments() 
> exit();
```

