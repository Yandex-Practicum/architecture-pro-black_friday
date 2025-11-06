#!/bin/bash

# Проверка наполнения базы данных:
docker exec -it router mongosh --port 27020 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

# Проверка наполнения шарда 1:
docker exec -it shard-1 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

# Проверка наполнения шарда 2:
docker exec -it shard-2 mongosh --port 27019 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF