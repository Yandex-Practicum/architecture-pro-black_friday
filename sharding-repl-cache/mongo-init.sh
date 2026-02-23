#!/bin/bash

docker compose up -d

wait_ping () {
  local container="$1"
  local port="$2"
  until docker exec "$container" mongosh --port "$port" --quiet --eval 'db.adminCommand("ping").ok' | grep -q '^1$'; do
    sleep 1
  done
}

echo 'Waiting for configSrv and shards to become health...'
wait_ping configSrv 27017
wait_ping shard1-1 27018
wait_ping shard1-2 27018
wait_ping shard1-3 27018
wait_ping shard2-1 27019
wait_ping shard2-2 27019
wait_ping shard2-3 27019

echo 'Initializing configsvr...'
docker exec configSrv mongosh --port 27017 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"config_server",configsvr:true,members:[{_id:0,host:"configSrv:27017"}]}) }'

echo 'Initializing replication for shard1...'
docker exec shard1-1 mongosh --port 27018 --quiet --eval '
try { rs.status() } catch(e) {
  rs.initiate({
    _id:"shard1",
    members:[
      {_id:0, host:"shard1-1:27018"},
      {_id:1, host:"shard1-2:27018"},
      {_id:2, host:"shard1-3:27018"}
    ]
  })
}
'

echo 'Initializing replication for shard2...'
docker exec shard2-1 mongosh --port 27019 --quiet --eval '
try { rs.status() } catch(e) {
  rs.initiate({
    _id:"shard2",
    members:[
      {_id:0, host:"shard2-1:27019"},
      {_id:1, host:"shard2-2:27019"},
      {_id:2, host:"shard2-3:27019"}
    ]
  })
}
'

echo 'Waiting for router to become health...'
wait_ping mongos_router 27020

echo 'Initializing router...'
docker exec mongos_router mongosh --port 27020 --quiet --eval '
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2/shard2-2:27019,shard2-2:27019,shard2-3:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });
'

echo 'Inserting data into DB...'
docker exec mongos_router mongosh --port 27020 --quiet --eval '
const dbx = db.getSiblingDB("somedb");
for (let i = 0; i < 1000; i++) dbx.helloDoc.insertOne({age:i, name:"ly"+i});
print("inserted:", dbx.helloDoc.countDocuments());
'
