#!/bin/bash

###
# Заполняем шардированную коллекцию тестовыми данными
###

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.deleteMany({})
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
