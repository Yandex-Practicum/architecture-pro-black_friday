#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard("shard1/shard1a:27018,shard1b:27018,shard1c:27018")
sh.addShard("shard2/shard2a:27019,shard2b:27019,shard2c:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
EOF

