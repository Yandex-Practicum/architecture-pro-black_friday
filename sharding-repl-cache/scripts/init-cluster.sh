#!/bin/bash

set -e

echo "===> Initiate cfg RS";
mongosh --host configSrv-1:27017 --eval "
  rs.initiate({
    _id: \"cfgReplSet\",
    configsvr: true,
    members: [
      { _id: 0, host: \"configSrv-1:27017\" },
      { _id: 1, host: \"configSrv-2:27017\" },
      { _id: 2, host: \"configSrv-3:27017\" }
    ]
  })
";
echo "===> Wait cfg RS PRIMARY";
until mongosh --host configSrv-1:27017 --quiet --eval "rs.isMaster().ismaster" | grep -q true; do sleep 2; done;

echo "===> Initiate shard1RS (3-member replica set)";
mongosh --port 27018 --host shard1-1 --eval "
  rs.initiate({
    _id: \"shard1RS\",
    members: [
      { _id: 0, host: \"shard1-1:27018\" },
      { _id: 1, host: \"shard1-2:27018\" },
      { _id: 2, host: \"shard1-3:27018\" }
    ]
  })
";
echo "===> Wait shard1RS PRIMARY";
until mongosh --port 27018 --host shard1-1 --quiet --eval "rs.isMaster().ismaster" | grep -q true; do sleep 2; done;

echo "===> Initiate shard2RS (3-member replica set)";
mongosh --port 27018 --host shard2-1 --eval "
  rs.initiate({
    _id: \"shard2RS\",
    members: [
      { _id: 0, host: \"shard2-1:27018\" },
      { _id: 1, host: \"shard2-2:27018\" },
      { _id: 2, host: \"shard2-3:27018\" }
    ]
  })
";
echo "===> Wait shard2RS PRIMARY";
until mongosh --port 27018 --host shard2-1 --quiet --eval "rs.isMaster().ismaster" | grep -q true; do sleep 2; done;

echo "===> Add shards to mongos";
until mongosh --host mongos-router --quiet --eval "db.adminCommand({ping:1}).ok" | grep -q 1; do sleep 2; done;
mongosh --host mongos-router --eval "
  sh.addShard(\"shard1RS/shard1-1:27018\");
  sh.addShard(\"shard2RS/shard2-1:27018\");
  sh.enableSharding(\"somedb\");
  sh.enableSharding(\"config\");
  sh.shardCollection(\"config.system.sessions\", { _id: 1 });
  db.getSiblingDB(\"config\").system.sessions.createIndex(
    { lastUse: 1 }, { expireAfterSeconds: 1800 }
  );

  // создаём тестовую БД и коллекцию
  db = db.getSiblingDB(\"somedb\");
  db.createCollection(\"helloDoc\");
  // Шардируем коллекцию helloDoc по полю _id для равномерного распределения
  sh.shardCollection(\"somedb.helloDoc\", { _id: \"hashed\" });
";
echo "===> Cluster initialization complete";

