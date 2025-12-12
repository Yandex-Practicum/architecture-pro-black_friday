#!/bin/bash
# Добавление шардов в кластер через Router

docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard("shard1_rs/shard1:27018")
sh.addShard("shard2_rs/shard2:27019")

// Включаем шардирование для базы данных
sh.enableSharding("somedb")

// Создаём коллекцию с шард-ключом
sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
EOF
