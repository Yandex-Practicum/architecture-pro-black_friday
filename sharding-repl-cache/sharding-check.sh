#!/bin/bash

# Проверка наполнения базы данных:
docker exec -it router mongosh --port 27020 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

# Проверка наполнения шарда 1:
docker exec -it shard-1-master mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-1-replica-1 mongosh --port 27021 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-1-replica-2 mongosh --port 27022 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

# Проверка наполнения шарда 2:
docker exec -it shard-2-master mongosh --port 27019 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-2-replica-1 mongosh --port 27023 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-2-replica-2 mongosh --port 27024 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

# Проверка кэша (Redis)
response=$(docker exec redis redis-cli ping 2>&1)

if [ "$response" = "PONG" ]; then
  echo "OK: Redis отвечает (PONG)"
  exit 0
else
  echo "ERROR: Redis не отвечает. Ответ: $response"
  exit 1
fi