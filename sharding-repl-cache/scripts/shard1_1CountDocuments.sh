#!/bin/bash
docker compose exec -T shard1_1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF