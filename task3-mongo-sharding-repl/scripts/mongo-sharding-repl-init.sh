#!/bin/bash
set -euo pipefail

echo "=== Инициализация репликации и шардинга MongoDB (mongo-sharding-repl) ==="

########################################
# 1. Инициализация configReplSet
########################################
echo "-> Проверяем / инициализируем configReplSet на configsvr1..."

docker compose exec -T configsvr1 mongosh --port 27019 --quiet <<'EOF'
let status;
try {
  status = rs.status();
} catch (e) {
  status = null;
}

if (!status || status.ok !== 1) {
  print("configReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "configReplSet",
    configsvr: true,
    members: [
      { _id: 0, host: "configsvr1:27019" },
      { _id: 1, host: "configsvr2:27019" },
      { _id: 2, host: "configsvr3:27019" }
    ]
  });
} else {
  print("configReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 2. Инициализация shard1ReplSet
########################################
echo "-> Проверяем / инициализируем shard1ReplSet на shard1-1..."

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
let status;
try {
  status = rs.status();
} catch (e) {
  status = null;
}

if (!status || status.ok !== 1) {
  print("shard1ReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "shard1ReplSet",
    members: [
      { _id: 0, host: "shard1-1:27018" },
      { _id: 1, host: "shard1-2:27018" },
      { _id: 2, host: "shard1-3:27018" }
    ]
  });
} else {
  print("shard1ReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 3. Инициализация shard2ReplSet
########################################
echo "-> Проверяем / инициализируем shard2ReplSet на shard2-1..."

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<'EOF'
let status;
try {
  status = rs.status();
} catch (e) {
  status = null;
}

if (!status || status.ok !== 1) {
  print("shard2ReplSet: ещё не инициализирован, выполняем rs.initiate()...");
  rs.initiate({
    _id: "shard2ReplSet",
    members: [
      { _id: 0, host: "shard2-1:27018" },
      { _id: 1, host: "shard2-2:27018" },
      { _id: 2, host: "shard2-3:27018" }
    ]
  });
} else {
  print("shard2ReplSet: уже инициализирован, пропускаем.");
}
EOF

########################################
# 4. Регистрация шардов и шардирование БД / коллекции
########################################
echo "-> Настраиваем шардирование через mongos..."

docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
const cfg = db.getSiblingDB("config");

// 4.1. Добавляем shard1ReplSet при необходимости
if (cfg.shards.find({ _id: "shard1ReplSet" }).count() === 0) {
  print("Добавляем шард shard1ReplSet...");
  sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018");
} else {
  print("Шард shard1ReplSet уже добавлен, пропускаем.");
}

// 4.2. Добавляем shard2ReplSet при необходимости
if (cfg.shards.find({ _id: "shard2ReplSet" }).count() === 0) {
  print("Добавляем шард shard2ReplSet...");
  sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018");
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

// 4.4. Шардируем коллекцию somedb.helloDoc, если ещё не зашардирована
if (cfg.collections.find({ _id: "somedb.helloDoc" }).count() === 0) {
  print("Шардируем коллекцию somedb.helloDoc по _id (hashed)...");
  sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
} else {
  print("Коллекция somedb.helloDoc уже зашардирована, пропускаем.");
}

print("Краткий статус шардирования:");
sh.status();
EOF

echo "=== Инициализация репликации и шардинга завершена ==="