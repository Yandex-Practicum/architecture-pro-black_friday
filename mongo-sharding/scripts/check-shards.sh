#!/bin/bash

echo "=== Проверка статуса шардирования ==="

echo ""
echo ">>> Статус шардов в кластере:"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.status()
EOF

echo ""
echo ">>> Количество документов в Shard 1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo ">>> Количество документов в Shard 2:"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo ">>> Общее количество документов (через mongos):"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

