#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T router-01 mongosh somedb <<EOF
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
