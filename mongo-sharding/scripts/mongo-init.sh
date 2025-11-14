#!/bin/bash

###
# Инициализируем бд и заполняем данными
###

docker compose exec -T mongos-router mongosh <<EOF
use somedb

if (db.getCollectionNames().indexOf("helloDoc") === -1) { db.createCollection("helloDoc"); }

for(var i = 0; i < 1000; i++) { db.helloDoc.insertOne({age: i, name: "user" + i}); }

print("Total documents in helloDoc: " + db.helloDoc.countDocuments());
EOF

