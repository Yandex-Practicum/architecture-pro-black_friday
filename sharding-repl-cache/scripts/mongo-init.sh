#!/bin/bash

###
# Инициализируем бд
###

echo "Waiting for MongoDB instances to start..."
sleep 10

# Config Server
echo "Initializing config server replica set..."
docker exec -it configsvr1 mongosh --port 27019 --eval 'rs.initiate({_id:"configReplSet",configsvr:true,members:[{_id:0,host:"configsvr1:27019"},{_id:1,host:"configsvr2:27019"},{_id:2,host:"configsvr3:27019"}]})'

# Shard 1
echo "Initializing shard1 replica set..."
docker exec -it shard1a mongosh --port 27018 --eval 'rs.initiate({_id:"shard1",members:[{_id:0,host:"shard1a:27018"},{_id:1,host:"shard1b:27018"},{_id:2,host:"shard1c:27018"}]})'


# Shard 2
echo "Initializing shard2 replica set..."
docker exec -it shard2a mongosh --port 27018 --eval 'rs.initiate({_id:"shard2",members:[{_id:0,host:"shard2a:27018"},{_id:1,host:"shard2b:27018"},{_id:2,host:"shard2c:27018"}]})'

echo "Waiting for replica sets to initialize..."
sleep 30

echo "Adding shards to mongos..."
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard1/shard1a:27018,shard1b:27018,shard1c:27018")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard2/shard2a:27018,shard2b:27018,shard2c:27018")'

docker exec -it mongos mongosh --port 27017 --eval 'sh.enableSharding("somedb")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.shardCollection("somedb.helloDoc", {name: "hashed"})'

docker compose exec -T mongos mongosh <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

