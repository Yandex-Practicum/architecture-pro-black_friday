#!/bin/bash

echo 'Data seeding'
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
EOF
echo 'Seeding done'

echo 'Checking data'
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF