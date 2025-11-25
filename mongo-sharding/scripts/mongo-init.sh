#!/bin/bash

###
# Инициализируем бд
###

# Config server
docker compose exec -T config mongosh --port 27017 --quiet <<EOF
try {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [
      { _id: 0, host: "config:27017" }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') {
    throw e;
  }
  print("Config server already initialized");
}
EOF

until docker compose exec -T config mongosh --quiet --port 27017 --eval "db.hello().isWritablePrimary" | grep true; do sleep 2; done

# Shard1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
try {
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "shard1:27018" }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') {
    throw e;
  }
  print("Shard1 already initialized");
}
EOF

until docker compose exec -T shard1 mongosh --quiet --port 27018 --eval "db.hello().isWritablePrimary" | grep true; do sleep 2; done

# Shard2
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
try {
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "shard2:27019" }
    ]
  });
} catch (e) {
  if (e.codeName !== 'AlreadyInitialized') {
    throw e;
  }
  print("Shard2 already initialized");
}
EOF

until docker compose exec -T shard2 mongosh --quiet --port 27019 --eval "db.hello().isWritablePrimary" | grep true; do sleep 2; done

# Даем время на полную инициализацию
sleep 10

# Добавляем шарды через mongos
docker compose exec -T router mongosh --port 27020 --quiet <<EOF
// Добавляем шарды с проверкой
try {
  sh.addShard("shard1/shard1:27018");
} catch (e) {
  print("Shard1 might be already added: " + e);
}

try {
  sh.addShard("shard2/shard2:27019");
} catch (e) {
  print("Shard2 might be already added: " + e);
}

// Включаем шардирование для базы данных
sh.enableSharding("somedb");

// Создаем коллекцию и шардируем ее
db.adminCommand({
  shardCollection: "somedb.helloDoc",
  key: { "name": "hashed" }
});

// Тестовые данные
use somedb

try {
  for(var i = 0; i < 1000; i++) {
    db.helloDoc.insert({age: i, name: "ly" + i});
  }
  print("Inserted " + db.helloDoc.countDocuments() + " documents");
} catch (e) {
  print("Insert error: " + e);
}

// Проверяем распределение
try {
  db.helloDoc.getShardDistribution();
} catch (e) {
  print("Distribution check error: " + e);
}
EOF