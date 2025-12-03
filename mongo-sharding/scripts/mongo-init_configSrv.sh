#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate({ _id : "config_server", configsvr: true, members: [ { _id : 0, host : "configSrv:27017" } ] } )
EOF

