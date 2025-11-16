#!/bin/bash

###
# Инициализируем бд и заполняем коллекцию данными через mongos
###

docker compose -f compose.yaml exec -T mongos_router mongosh --port 27020 <<'EOF'
use somedb
for (let i=0;i<2000;i++) {
  db.helloDoc.insertOne({_id: i, value: 'hello_'+i})
}
print('done')
EOF
