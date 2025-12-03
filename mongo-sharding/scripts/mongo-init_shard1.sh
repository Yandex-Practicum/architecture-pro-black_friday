#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T shard1 mongosh --port 27018 <<EOF
rs.initiate({ _id : "shard1", members: [{ _id : 0, host : "shard1:27018" }]})
EOF

