#!/bin/bash
set -e

echo "=== MongoDB Sharded Cluster init ==="

# 1. Config Server Replica Set
echo "Инициализация Config Server Replica Set..."
docker exec -it configSrv mongosh --port 27019 --eval '
rs.initiate({
  _id: "configRS",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27019" }
  ]
})
'
sleep 3

# 2. Shard 1 Replica Set
echo "Инициализация Replica Set для shard1..."
docker exec -it shard1_primary mongosh --port 27018 --eval '
rs.initiate({
  _id: "shard1RS",
  members: [
    { _id: 0, host: "shard1_primary:27018" },
    { _id: 1, host: "shard1_secondary1:27028" },
    { _id: 2, host: "shard1_secondary2:27038" }
  ]
})
'
sleep 5

# 3. Shard 2 Replica Set
echo "Инициализация Replica Set для shard2..."
docker exec -it shard2_primary mongosh --port 27118 --eval '
rs.initiate({
  _id: "shard2RS",
  members: [
    { _id: 0, host: "shard2_primary:27118" },
    { _id: 1, host: "shard2_secondary1:27128" },
    { _id: 2, host: "shard2_secondary2:27138" }
  ]
})
'
sleep 5

# 4. Подключаем шарды к mongos
echo "Подключаем shard1RS к mongos..."
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("shard1RS/shard1_primary:27018")
'
sleep 2

echo "Подключаем shard2RS к mongos..."
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("shard2RS/shard2_primary:27118")
'
sleep 3

# 5. Включаем шардирование
echo "Включаем шардирование базы и коллекции..."
docker compose exec -T mongos mongosh --host mongos --port 27017 <<'EOF'
sh.enableSharding("somedb");
use somedb;
db.helloDoc.createIndex({ _id: "hashed" });
sh.shardCollection(
  "somedb.helloDoc",
  { _id: "hashed" }
);
sh.status();
EOF

# 6. Заполняем данные
echo "Заполняем тестовыми данными..."
docker compose exec -T mongos mongosh --host mongos --port 27017 <<'EOF'
use somedb;
for (let i = 0; i < 2000; i++) {
  db.helloDoc.insertOne({
    age: i,
    name: "ly" + i,
    created_at: new Date()
  });
}
db.helloDoc.getShardDistribution();
EOF

echo "=== Готово. Шардированный кластер инициализирован ==="
