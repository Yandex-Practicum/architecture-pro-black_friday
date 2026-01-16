#!/bin/bash

echo "⏳ Waiting for Mongo nodes to start..."
sleep 10 # Увеличили время ожидания, так как контейнеров стало больше

# 1. Инициализация Config Server Replica Set
echo "🛠 Initializing Config Server Replica Set..."
docker compose exec -T configSrv1 mongosh --port 27017 --eval '
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [
      { _id: 0, host: "configSrv1:27017" },
      { _id: 1, host: "configSrv2:27017" },
      { _id: 2, host: "configSrv3:27017" }
    ]
  })
'

# 2. Инициализация Shard 1 Replica Set
echo "🛠 Initializing Shard 1 Replica Set..."
docker compose exec -T shard1-1 mongosh --port 27018 --eval '
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "shard1-1:27018" },
      { _id: 1, host: "shard1-2:27018" },
      { _id: 2, host: "shard1-3:27018" }
    ]
  })
'

# 3. Инициализация Shard 2 Replica Set
echo "🛠 Initializing Shard 2 Replica Set..."
docker compose exec -T shard2-1 mongosh --port 27019 --eval '
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "shard2-1:27019" },
      { _id: 1, host: "shard2-2:27019" },
      { _id: 2, host: "shard2-3:27019" }
    ]
  })
'

# Даем время на выборы лидеров (важно!)
echo "⏳ Waiting for replica sets to stabilize..."
sleep 20

# 4. Настройка роутера (Mongos)
# ВАЖНО: При добавлении шарда указываем имя реплика-сета и хотя бы один хост (лучше несколько)
echo "🔗 Connecting shards to Mongos..."
docker compose exec -T mongos mongosh --port 27020 --eval '
  sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
  sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
'

# 5. Включение шардинга для БД
echo "📦 Enabling sharding for database 'somedb'..."
docker compose exec -T mongos mongosh --port 27020 --eval '
  sh.enableSharding("somedb");
  db.createCollection("somedb.helloDoc");
  sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
'

echo "✅ Cluster initialized successfully!"