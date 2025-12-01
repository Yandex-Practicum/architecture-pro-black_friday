#!/bin/bash
set -euo pipefail
  
# Wait for the config server replica set to elect a primary
echo "Waiting for config server replica set to elect a primary..."
until mongosh --host rs-config-server/configsvr01:27017,configsvr02:27017,configsvr03:27017 --eval 'rs.status().members.some(m => m.stateStr === "PRIMARY")' | grep -q 'true'; do
  sleep 5
done

# Wait for each shard's replica set to elect a primary
for shard in 1 2 3; do
  replica_set="rs-shard-0${shard}"
  host_prefix="shard0${shard}"
  echo "Waiting for ${replica_set} to elect a primary..."
  until mongosh --host ${replica_set}/${host_prefix}-a:27017,${host_prefix}-b:27017,${host_prefix}-c:27017 --eval 'rs.status().members.some(m => m.stateStr === "PRIMARY")' | grep -q 'true'; do
    sleep 5
  done
done

# Start mongos in the background
echo "Starting mongos..."
mongos --port 27017 --configdb rs-config-server/configsvr01:27017,configsvr02:27017,configsvr03:27017 --bind_ip_all &

# Wait for mongos to become available
echo "Waiting for mongos to start..."
until mongosh --port 27017 --eval 'db.adminCommand({ping: 1})' &> /dev/null; do
  sleep 5
done

# Add the shards using the provided commands
echo "Adding shards..."
mongosh --port 27017 <<EOF
sh.addShard("rs-shard-01/shard01-a:27017")
sh.addShard("rs-shard-01/shard01-b:27017")
sh.addShard("rs-shard-01/shard01-c:27017")
sh.addShard("rs-shard-02/shard02-a:27017")
sh.addShard("rs-shard-02/shard02-b:27017")
sh.addShard("rs-shard-02/shard02-c:27017")
sh.addShard("rs-shard-03/shard03-a:27017")
sh.addShard("rs-shard-03/shard03-b:27017")
sh.addShard("rs-shard-03/shard03-c:27017")

use somedb
// Используем insertOne, так как insert() устарел, и для асинхронной операции в цикле
for(var i = 0; i < 1000; i++) db.somedb.insertOne({age:i, name:"ly"+i})

var count = db.somedb.countDocuments();
print("Документов добавлено: " + count);

if (count === 1000) {
    print("🚀 Кластер успешно инициирован и протестирован!");
} else {
    print("💔 ОШИБКА: Добавлено неправильное количество документов: " + count);
}
EOF


# Keep the mongos process running in the foreground
wait