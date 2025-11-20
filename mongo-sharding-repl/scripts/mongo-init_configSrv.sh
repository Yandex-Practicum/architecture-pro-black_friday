#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T configSrv1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
})
EOF

