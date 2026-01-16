#!/bin/bash

# Ждем, пока контейнеры проснутся окончательно
echo "⏳ Waiting for Mongo nodes to start..."
sleep 5

# 1. Инициализация Config Server
echo "🛠 Initializing Config Server..."
docker compose exec -T configSrv mongosh --port 27017 --eval '
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27017" }]
  })
'

# 2. Инициализация Shard 1
echo "🛠 Initializing Shard 1..."
docker compose exec -T shard1 mongosh --port 27018 --eval '
  rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
  })
'

# 3. Инициализация Shard 2
echo "🛠 Initializing Shard 2..."
docker compose exec -T shard2 mongosh --port 27019 --eval '
  rs.initiate({
    _id: "shard2",
    members: [{ _id: 0, host: "shard2:27019" }]
  })
'

# Даем время на выборы лидеров
echo "⏳ Waiting for replica sets to stabilize..."
sleep 15

# 4. Настройка роутера (Mongos)
echo "🔗 Connecting shards to Mongos..."
docker compose exec -T mongos mongosh --port 27020 --eval '
  sh.addShard("shard1/shard1:27018");
  sh.addShard("shard2/shard2:27019");
'

# 5. Включение шардинга для БД
echo "📦 Enabling sharding for database 'somedb'..."
docker compose exec -T mongos mongosh --port 27020 --eval '
  sh.enableSharding("somedb");
  // Создаем коллекцию и шардируем её по хешу поля "name" (для равномерности)
  db.createCollection("somedb.helloDoc");
  sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
'

echo "✅ Cluster initialized successfully!"
