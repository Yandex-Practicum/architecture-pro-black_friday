#!/bin/bash

###
# Инициализируем replicaset'ы и наполняем БД
###

# 1. Инициализация config server
echo "=== Инициализация config_server ==="
docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate({
  _id: 'config_server',
  configsvr: true,
  members: [
    { _id: 0, host: 'configSrv:27017' }
  ]
});
EOF

# Ждём готовности
sleep 5

# 2. Инициализация shard1
echo "=== Инициализация shard1 ==="
docker compose exec -T shard1 mongosh --port 27018 <<EOF
rs.initiate({
  _id: 'shard1',
  members: [
    { _id: 0, host: 'shard1:27018' }
  ]
});
EOF

# Ждём готовности
sleep 5

# 3. Инициализация shard2
echo "=== Инициализация shard2 ==="
docker compose exec -T shard2 mongosh --port 27019 <<EOF
rs.initiate({
  _id: 'shard2',
  members: [
    { _id: 0, host: 'shard2:27019' }
  ]
});
EOF

# Ждём, пока шарды станут доступны
sleep 10

# 4. Добавляем шарды в mongos и включаем шардирование
echo "=== Подключение к mongos и настройка шардирования ==="
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
// Добавляем шарды
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");

// Включаем шардирование для базы
sh.enableSharding("somedb");

// Шардируем коллекцию по полю age (hashed)
sh.shardCollection("somedb.helloDoc", { "age": "hashed" });

// Проверяем статус
sh.status();
EOF

# 5. Вставка тестовых данных
echo "=== Вставка тестовых данных в somedb.helloDoc ==="
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
print("1000 документов вставлено в somedb.helloDoc");
EOF

# 6. Проверка распределения данных по шардам
echo "=== Проверка количества документов в каждом шарде ==="

echo "--- Проверка shard1 (shard1:27018) ---"
COUNT_SHARD1=$(docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
)
echo "Количество документов в shard1: $COUNT_SHARD1"

echo "--- Проверка shard2 (shard2:27019) ---"
COUNT_SHARD2=$(docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
)
echo "Количество документов в shard2: $COUNT_SHARD2"

# 7. Проверка через mongos (агрегированная картина)
echo "--- Проверка общего количества записей через mongos ---"
TOTAL_COUNT=$(docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
)
echo "Общее количество записей в кластере: $TOTAL_COUNT"

echo "Проверка завершена. Данные распределены между шардами."