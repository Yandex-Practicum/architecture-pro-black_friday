#!/bin/bash

###
# Инициализируем бд и заполняем данными
###

docker compose exec -T mongos-router mongosh <<EOF
use somedb
// Создаем коллекцию helloDoc если её нет
if (db.getCollectionNames().indexOf("helloDoc") === -1) {
  db.createCollection("helloDoc");
}

// Заполняем коллекцию данными (≥ 1000 документов)
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "user" + i, created: new Date()});
}

// Выводим статистику
print("Total documents in helloDoc: " + db.helloDoc.countDocuments());
EOF

