#!/bin/bash
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<EOF
use somedb
db.helloDoc.countDocuments() 
EOF