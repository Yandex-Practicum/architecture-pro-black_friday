#!/bin/bash

# Инициализация сервера конфигураций:
docker compose exec -it configSrv mongosh --port 27017 <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
exit();
EOF


# Инициализация шарда 1 (3 реплики)
docker exec -it shard-1-master mongosh --port 27018 <<EOF
rs.initiate(
    {
      _id : "shard-1",
      members: [
        { _id : 0, host : 'shard-1-master:27018' },
        { _id : 1, host : 'shard-1-replica-1:27021'},
        { _id : 2, host : 'shard-1-replica-2:27022'}
      ]
    }
);
exit();
EOF

# Инициализация шарда 2 (3 реплики)
docker exec -it shard-2-master mongosh --port 27019 <<EOF
rs.initiate(
    {
      _id : "shard-2",
      members: [
        { _id : 0, host : 'shard-2-master:27019' },
        { _id : 1, host : 'shard-2-replica-1:27023'},
        { _id : 2, host : 'shard-2-replica-2:27024'}
      ]
    }
  );
exit();
EOF


#Инициализация маршрутизатора (роутера)
docker exec -it router mongosh --port 27020 <<EOF
sh.addShard( "shard-1/shard-1-master:27018");
sh.addShard( "shard-2/shard-2-master:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})
db.helloDoc.countDocuments()
exit();
EOF
