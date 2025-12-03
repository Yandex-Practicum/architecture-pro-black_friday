#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T shard1a mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1a:27018" },
    { _id: 1, host: "shard1b:27018" },
    { _id: 2, host: "shard1c:27018" }
  ]
})
EOF

