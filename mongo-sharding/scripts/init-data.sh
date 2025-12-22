#!/bin/bash

echo ">>> Заполнение базы данных тестовыми данными (1000 документов)"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "user" + i})
}
print("Inserted 1000 documents")
EOF

echo ">>> Данные загружены!"

