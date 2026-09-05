#!/usr/bin/env bash
set -euo pipefail

wait_mongo() {
  local service="$1" port="$2" check="${3:-}"
  [[ -n "$check" ]] || check='db.adminCommand({ping:1}).ok'
  for _ in $(seq 1 60); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet \
      --eval "print(Boolean($check))" 2>/dev/null | grep -q true; then
      return
    fi
    sleep 2
  done
  echo "MongoDB service $service is not ready" >&2
  exit 1
}

docker compose up -d
wait_mongo config-srv 27019
wait_mongo shard1 27018
wait_mongo shard2 27018

if ! docker compose exec -T config-srv mongosh --port 27019 --quiet \
  --eval 'try { quit(rs.status().ok === 1 ? 0 : 1) } catch (e) { quit(1) }'; then
  docker compose exec -T config-srv mongosh --port 27019 --quiet --eval \
    'rs.initiate({_id:"config-rs",configsvr:true,members:[{_id:0,host:"config-srv:27019"}]})'
fi

wait_mongo config-srv 27019 'db.hello().isWritablePrimary'
wait_mongo mongos 27017

docker compose exec -T mongos mongosh --quiet --eval '
  const shards = db.adminCommand({listShards:1}).shards.map(s => s._id);
  if (!shards.includes("shard1")) sh.addShard("shard1:27018", "shard1");
  if (!shards.includes("shard2")) sh.addShard("shard2:27018", "shard2");
  sh.enableSharding("somedb");
  if (!db.getSiblingDB("config").collections.findOne({_id:"somedb.helloDoc"})) {
    sh.shardCollection("somedb.helloDoc", {name:"hashed"});
  }

  const collection = db.getSiblingDB("somedb").helloDoc;
  const operations = [];
  for (let i = 0; i < 1000; i++) {
    operations.push({updateOne:{
      filter:{name:`ly${i}`},
      update:{$setOnInsert:{name:`ly${i}`, age:i}},
      upsert:true
    }});
  }
  collection.bulkWrite(operations, {ordered:false});
  print(`total=${collection.countDocuments({})}`);
  collection.getShardDistribution();
'
