#!/bin/bash

docker compose up -d

until docker exec configSrv mongosh --port 27017 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
until docker exec shard1   mongosh --port 27018 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
until docker exec shard2   mongosh --port 27019 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done

docker exec configSrv mongosh --port 27017 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"config_server",configsvr:true,members:[{_id:0,host:"configSrv:27017"}]}) }'
docker exec shard1 mongosh --port 27018 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"shard1",members:[{_id:0,host:"shard1:27018"}]}) }'
docker exec shard2 mongosh --port 27019 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"shard2",members:[{_id:0,host:"shard2:27019"}]}) }'

until docker exec mongos_router mongosh --port 27020 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done

docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.addShard("shard1/shard1:27018");'
docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.addShard("shard2/shard2:27019");'
docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.enableSharding("somedb");'
docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });'

docker exec mongos_router mongosh --port 27020 --quiet --eval '
const dbx = db.getSiblingDB("somedb");
for (let i = 0; i < 1000; i++) dbx.helloDoc.insertOne({age:i, name:"ly"+i});
print("inserted:", dbx.helloDoc.countDocuments());
'