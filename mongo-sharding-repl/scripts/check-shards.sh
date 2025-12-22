#!/bin/bash

echo "=== Проверка статуса шардирования и репликации ==="

echo ""
echo ">>> Статус шардов в кластере:"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.status()
EOF

echo ""
echo ">>> Статус репликации Config Server:"
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " - " + m.stateStr))
EOF

echo ""
echo ">>> Статус репликации Shard 1:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " - " + m.stateStr))
EOF

echo ""
echo ">>> Статус репликации Shard 2:"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " - " + m.stateStr))
EOF

echo ""
echo ">>> Количество документов в Shard 1 (primary):"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo ">>> Количество документов в Shard 2 (primary):"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo ">>> Общее количество документов (через mongos):"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
