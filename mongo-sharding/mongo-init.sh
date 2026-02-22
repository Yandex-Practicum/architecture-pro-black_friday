#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T mongodb1 mongosh <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

docker exec configSrv mongosh --port 27017 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"config_server",configsvr:true,members:[{_id:0,host:"configSrv:27017"}]}) }'