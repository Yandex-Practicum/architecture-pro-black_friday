#!/bin/bash
set -euo pipefail

echo "=== Инициализация шардинга MongoDB через docker compose ==="

########################################
# 1. Инициализация config server
########################################
echo "-> Проверяем / инициализируем configReplSet на configsvr..."

docker compose exec -T configsvr mongosh --port 27019 --quiet <<'EOF'
let st = null;
try {
  st = rs.status();
} catch (e) {
  st = null;
}

if (!st || st.ok !== 1) {
  print("configReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "configReplSet",
    configsvr: true,
    members: [
      { _id: 0, host: "configsvr:27019" }
    ]
  });
} else {
  print("configReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 2. Инициализация shard1ReplSet
########################################
echo "-> Проверяем / инициализируем shard1ReplSet на shard1..."

docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
let st = null;
try {
  st = rs.status();
} catch (e) {
  st = null;
}

if (!st || st.ok !== 1) {
  print("shard1ReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "shard1ReplSet",
    members: [
      { _id: 0, host: "shard1:27018" }
    ]
  });
} else {
  print("shard1ReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 3. Инициализация shard2ReplSet
########################################
echo "-> Проверяем / инициализируем shard2ReplSet на shard2..."

docker compose exec -T shard2 mongosh --port 27018 --quiet <<'EOF'
let st = null;
try {
  st = rs.status();
} catch (e) {
  st = null;
}

if (!st || st.ok !== 1) {
  print("shard2ReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "shard2ReplSet",
    members: [
      { _id: 0, host: "shard2:27018" }
    ]
  });
} else {
  print("shard2ReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 4. Подключение шардов и шардинг БД/коллекции
########################################
echo "-> Регистрируем шарды, включаем шардинг для somedb и коллекции helloDoc..."

docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
// Работаем в системной базе config
const cfg = db.getSiblingDB("config");

// 4.1. Добавляем шард shard1ReplSet, если его ещё нет
if (cfg.shards.find({ _id: "shard1ReplSet" }).count() === 0) {
  print("Добавляем шард: shard1ReplSet/shard1:27018");
  sh.addShard("shard1ReplSet/shard1:27018");
} else {
  print("Шард shard1ReplSet уже добавлен, пропускаем.");
}

// 4.2. Добавляем шард shard2ReplSet, если его ещё нет
if (cfg.shards.find({ _id: "shard2ReplSet" }).count() === 0) {
  print("Добавляем шард: shard2ReplSet/shard2:27018");
  sh.addShard("shard2ReplSet/shard2:27018");
} else {
  print("Шард shard2ReplSet уже добавлен, пропускаем.");
}

// 4.3. Включаем шардинг для БД somedb
const dbCfg = cfg.databases.findOne({ _id: "somedb" });

if (!dbCfg || !dbCfg.partitioned) {
  print("Включаем шардинг для БД somedb...");
  sh.enableSharding("somedb");
} else {
  print("Шардинг для БД somedb уже включён, пропускаем.");
}

// 4.4. Шардируем коллекцию somedb.helloDoc по _id (hashed)
if (cfg.collections.find({ _id: "somedb.helloDoc" }).count() === 0) {
  print("Шардируем коллекцию somedb.helloDoc по _id (hashed)...");
  sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
} else {
  print("Коллекция somedb.helloDoc уже зашардирована, пропускаем.");
}
EOF

echo "=== Инициализация шардинга завершена ==="