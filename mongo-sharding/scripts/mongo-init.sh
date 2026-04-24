#!/bin/bash

###
# Инициализируем бд
###

sleep 10

echo "Initializing config server replica set..."
docker exec -it configsvr mongosh --port 27019 --eval 'rs.initiate({_id:"configReplSet",configsvr:true,members:[{_id:0,host:"configsvr:27019"}]})'

echo "Initializing shard1 replica set..."
docker exec -it shard1 mongosh --port 27018 --eval 'rs.initiate({_id:"shard1",members:[{_id:0,host:"shard1:27018"}]})'

echo "Initializing shard2 replica set..."
docker exec -it shard2 mongosh --port 27018 --eval 'rs.initiate({_id:"shard2",members:[{_id:0,host:"shard2:27018"}]})'

echo "Waiting for replica sets to initialize..."
sleep 30

echo "Adding shards to mongos..."
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard1/shard1:27018")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard2/shard2:27018")'

docker exec -it mongos mongosh --port 27017 --eval 'sh.enableSharding("somedb")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.shardCollection("somedb.helloDoc", {name: "hashed"})'

docker compose exec -T mongos mongosh <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

