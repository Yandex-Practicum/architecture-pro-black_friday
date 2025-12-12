#!/bin/bash
# Инициализация Shard 1 Replica Set

docker compose exec -T shard1 mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1_rs",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
})
EOF
