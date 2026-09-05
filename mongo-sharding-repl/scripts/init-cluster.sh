#!/usr/bin/env bash
set -euo pipefail

wait_mongo() {
  local service="$1" port="$2" check="${3:-}"
  [[ -n "$check" ]] || check='db.adminCommand({ping:1}).ok'
  for _ in $(seq 1 90); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet \
      --eval "print(Boolean($check))" 2>/dev/null | grep -q true; then
      return
    fi
    sleep 2
  done
  echo "MongoDB service $service is not ready" >&2
  exit 1
}

init_rs() {
  local service="$1" port="$2" config="$3"
  if ! docker compose exec -T "$service" mongosh --port "$port" --quiet \
    --eval 'try { quit(rs.status().ok === 1 ? 0 : 1) } catch (e) { quit(1) }'; then
    docker compose exec -T "$service" mongosh --port "$port" --quiet \
      --eval "rs.initiate($config)"
  fi
}

docker compose up -d

wait_mongo config-srv 27019
for service in shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3; do
  wait_mongo "$service" 27018
done

init_rs config-srv 27019 '{_id:"config-rs",configsvr:true,members:[{_id:0,host:"config-srv:27019"}]}'
init_rs shard1-1 27018 '{_id:"shard1-rs",members:[{_id:0,host:"shard1-1:27018"},{_id:1,host:"shard1-2:27018"},{_id:2,host:"shard1-3:27018"}]}'
init_rs shard2-1 27018 '{_id:"shard2-rs",members:[{_id:0,host:"shard2-1:27018"},{_id:1,host:"shard2-2:27018"},{_id:2,host:"shard2-3:27018"}]}'

wait_mongo config-srv 27019 'db.hello().isWritablePrimary'
wait_mongo shard1-1 27018 'db.hello().isWritablePrimary'
wait_mongo shard2-1 27018 'db.hello().isWritablePrimary'
wait_mongo mongos 27017

docker compose exec -T mongos mongosh --quiet --eval '
  const shards = db.adminCommand({listShards:1}).shards.map(s => s._id);
  if (!shards.includes("shard1-rs")) sh.addShard("shard1-rs/shard1-1:27018,shard1-2:27018,shard1-3:27018");
  if (!shards.includes("shard2-rs")) sh.addShard("shard2-rs/shard2-1:27018,shard2-2:27018,shard2-3:27018");
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
