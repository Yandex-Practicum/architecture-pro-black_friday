#!/bin/bash
# Инициализация Config Server Replica Set

docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate({
  _id: "config_rs",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
})
EOF
