# Запускаем все контейнеры

```shell
docker compose up -d
```


# Подключитесь к серверу конфигурации и сделайте инициализацию
```shell
docker compose exec -T  configSrv mongosh --port 27017 --quiet <<EOF

rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
EOF
``` 

#  Инициализируйте шард-1 и создаём набор реплик для шарде-1
```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1", members: [
{_id: 0, host: "shard1:27018"},
{_id: 1, host: "shard1_rep1:27021"},
{_id: 2, host: "shard1_rep2:27022"}
]})
EOF
```
#  Инициализируйте шард-2 и создаём набор реплик для шарде-2
```shell
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "shard2", members: [
{_id: 0, host: "shard2:27019"},
{_id: 1, host: "shard2_rep1:27023"},
{_id: 2, host: "shard2_rep2:27024"}
]})
EOF
```
 

# Инцициализируйте роутер  
```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF

sh.addShard("shard1/shard1:27018,shard1_rep1:27021,shard1_rep2:27022");
sh.addShard("shard2/shard2:27019,shard2_rep1:27023,shard2_rep2:27024");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );
use somedb

for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});
EOF  
``` 


#  Отображение количества документов на шарде-1
```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
``` 

#  Отображение количества документов на шарде-2
```shell
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

