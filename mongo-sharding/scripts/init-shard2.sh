#!/bin/bash
# Инициализация Shard 2 Replica Set

docker compose exec -T shard2 mongosh --port 27019 <<EOF
rs.initiate({
  _id: "shard2_rs",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
})
EOF
