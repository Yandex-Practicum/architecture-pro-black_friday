#!/bin/bash

echo "=========================================="
echo "Initializing MongoDB Sharding Cluster"
echo "=========================================="

# Wait for services to be ready
echo "Waiting for MongoDB services to start..."
sleep 10

# Step 1: Initialize Config Server Replica Set
echo ""
echo "Step 1: Initializing Config Server Replica Set..."
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
});
EOF

echo "Waiting for config replica set to elect primary..."
sleep 5

# Step 2: Initialize Shard 1 Replica Set
echo ""
echo "Step 2: Initializing Shard 1 Replica Set..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
EOF

echo "Waiting for shard1 replica set to elect primary..."
sleep 5

# Step 3: Initialize Shard 2 Replica Set
echo ""
echo "Step 3: Initializing Shard 2 Replica Set..."
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
});
EOF

echo "Waiting for shard2 replica set to elect primary..."
sleep 5

# Step 4: Add Shards to the Cluster
echo ""
echo "Step 4: Adding shards to the cluster..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018");
sh.addShard("shard2ReplSet/shard2:27019");
EOF

echo "Waiting for shards to be added..."
sleep 3

# Step 5: Enable Sharding on Database
echo ""
echo "Step 5: Enabling sharding on database 'somedb'..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF

# Step 6: Shard the Collection
echo ""
echo "Step 6: Sharding collection 'helloDoc' on key '_id'..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" });
EOF

# Step 7: Display Cluster Status
echo ""
echo "=========================================="
echo "Sharding initialization complete!"
echo "=========================================="
echo ""
echo "Cluster Status:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF

echo ""
echo "=========================================="
echo "Setup completed successfully!"
echo "=========================================="
