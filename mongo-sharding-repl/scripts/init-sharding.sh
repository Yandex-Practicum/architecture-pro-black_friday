#!/bin/bash

echo "=========================================="
echo "Initializing MongoDB Sharding Cluster with Replication"
echo "=========================================="

# Wait for services to be ready
echo "Waiting for MongoDB services to start..."
sleep 15

# Step 1: Initialize Config Server Replica Set
echo ""
echo "Step 1: Initializing Config Server Replica Set (3 replicas)..."
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "repl-configSrv1:27017" },
    { _id: 1, host: "repl-configSrv2:27017" },
    { _id: 2, host: "repl-configSrv3:27017" }
  ]
});
EOF

echo "Waiting for config replica set to elect primary..."
sleep 10

# Step 2: Initialize Shard 1 Replica Set (3 replicas)
echo ""
echo "Step 2: Initializing Shard 1 Replica Set (3 replicas)..."
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "repl-shard1-1:27018", priority: 2 },
    { _id: 1, host: "repl-shard1-2:27018", priority: 1 },
    { _id: 2, host: "repl-shard1-3:27018", priority: 1 }
  ]
});
EOF

echo "Waiting for shard1 replica set to elect primary..."
sleep 10

# Step 3: Initialize Shard 2 Replica Set (3 replicas)
echo ""
echo "Step 3: Initializing Shard 2 Replica Set (3 replicas)..."
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "repl-shard2-1:27019", priority: 2 },
    { _id: 1, host: "repl-shard2-2:27019", priority: 1 },
    { _id: 2, host: "repl-shard2-3:27019", priority: 1 }
  ]
});
EOF

echo "Waiting for shard2 replica set to elect primary..."
sleep 10

# Step 4: Add Shards to the Cluster
echo ""
echo "Step 4: Adding shards to the cluster..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/repl-shard1-1:27018,repl-shard1-2:27018,repl-shard1-3:27018");
sh.addShard("shard2ReplSet/repl-shard2-1:27019,repl-shard2-2:27019,repl-shard2-3:27019");
EOF

echo "Waiting for shards to be added..."
sleep 5

# Step 5: Enable Sharding on Database
echo ""
echo "Step 5: Enabling sharding on database 'somedb'..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF

# Step 6: Shard the Collection
echo ""
echo "Step 6: Sharding collection 'helloDoc' on key '_id' (hashed)..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" });
EOF

# Step 7: Display Cluster Status
echo ""
echo "=========================================="
echo "Sharding with Replication initialization complete!"
echo "=========================================="
echo ""
echo "Cluster Status:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF

echo ""
echo "Config Server Replica Set Status:"
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.status();
EOF

echo ""
echo "Shard 1 Replica Set Status:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF

echo ""
echo "Shard 2 Replica Set Status:"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status();
EOF

echo ""
echo "=========================================="
echo "Setup completed successfully!"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Config Servers: 3 replicas (repl-configSrv1, repl-configSrv2, repl-configSrv3)"
echo "- Shard 1: 3 replicas (repl-shard1-1, repl-shard1-2, repl-shard1-3)"
echo "- Shard 2: 3 replicas (repl-shard2-1, repl-shard2-2, repl-shard2-3)"
echo "- Total: 9 MongoDB instances + 1 mongos router"