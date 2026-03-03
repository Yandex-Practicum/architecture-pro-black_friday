#!/bin/bash

echo "🚀 Loading data into Sharded Cluster via Mongos..."

# ФИКС: Указываем 'somedb' в вызове, убираем 'use' из eval
docker compose exec -T mongos mongosh --port 27020 somedb --quiet --eval '
  db.helloDoc.deleteMany({}); 
  
  print("Writing 1000 documents...");
  for(var i = 0; i < 1000; i++) {
    db.helloDoc.insertOne({age:i, name:"ly"+i})
  }
  
  print("Done! Total documents: " + db.helloDoc.countDocuments());
'

echo "✅ Data loaded!"