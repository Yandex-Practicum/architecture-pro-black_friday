#!/bin/bash

set -euo pipefail

wait_for_mongod() {
  local service="$1"
  local port="$2"

  for _ in {1..60}; do
    result=$(docker compose exec -T "$service" mongosh --port "$port" --quiet --eval 'db.adminCommand({ ping: 1 }).ok' 2>/dev/null || true)
    if [[ "$result" == *"1"* ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Service $service did not respond on port $port in time" >&2
  echo "Hint: run 'docker compose down -v' and start again if init was interrupted" >&2
  return 1
}

wait_for_replica_set_primary() {
  local service="$1"
  local port="$2"

  for _ in {1..120}; do
    result=$(docker compose exec -T "$service" mongosh --port "$port" --quiet --eval 'try { rs.status().members.some((member) => member.stateStr === "PRIMARY") ? "true" : "false" } catch (error) { "false" }' 2>/dev/null || true)
    if [[ "$result" == *"true"* ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Replica set on $service did not elect a primary in time" >&2
  return 1
}

wait_for_replica_set() {
  local service="$1"
  local port="$2"
  local expected_members="$3"

  for _ in {1..90}; do
    result=$(docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "try { rs.status().members.length === $expected_members ? 'true' : 'false' } catch (error) { 'false' }" 2>/dev/null || true)
    if [[ "$result" == *"true"* ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Replica set on $service did not reach $expected_members members in time" >&2
  return 1
}

wait_for_mongos() {
  for _ in {1..60}; do
    result=$(docker compose exec -T mongos-router mongosh --port 27020 --quiet --eval 'db.adminCommand({ hello: 1 }).msg' 2>/dev/null || true)
    if [[ "$result" == *"isdbgrid"* ]]; then
      return 0
    fi
    sleep 1
  done

  echo "mongos-router did not become available in time" >&2
  return 1
}

wait_for_mongod configSrv 27017
wait_for_mongod shard1-1 27019
wait_for_mongod shard1-2 27019
wait_for_mongod shard1-3 27019
wait_for_mongod shard2-1 27019
wait_for_mongod shard2-2 27019
wait_for_mongod shard2-3 27019

docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
let initiated = false
try {
  initiated = rs.status().ok === 1
} catch (error) {
  initiated = false
}

if (!initiated) {
  rs.initiate({
    _id: "configReplSet",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27017" }],
  })
}
EOF

docker compose exec -T shard1-1 mongosh --port 27019 --quiet <<'EOF'
let initiated = false
try {
  initiated = rs.status().ok === 1
} catch (error) {
  initiated = false
}

if (!initiated) {
  rs.initiate({
    _id: "rs-shard1",
    members: [
      { _id: 0, host: "shard1-1:27019" },
      { _id: 1, host: "shard1-2:27019" },
      { _id: 2, host: "shard1-3:27019" },
    ],
  })
}
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<'EOF'
let initiated = false
try {
  initiated = rs.status().ok === 1
} catch (error) {
  initiated = false
}

if (!initiated) {
  rs.initiate({
    _id: "rs-shard2",
    members: [
      { _id: 0, host: "shard2-1:27019" },
      { _id: 1, host: "shard2-2:27019" },
      { _id: 2, host: "shard2-3:27019" },
    ],
  })
}
EOF

wait_for_replica_set_primary configSrv 27017
wait_for_replica_set_primary shard1-1 27019
wait_for_replica_set_primary shard2-1 27019
wait_for_replica_set shard1-1 27019 3
wait_for_replica_set shard2-1 27019 3

sleep 3
docker compose restart mongos-router
wait_for_mongos

docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
const shards = db.adminCommand({ listShards: 1 }).shards.map((shard) => shard._id)

if (!shards.includes("rs-shard1")) {
  db.adminCommand({
    addShard: "rs-shard1/shard1-1:27019,shard1-2:27019,shard1-3:27019",
  })
}

if (!shards.includes("rs-shard2")) {
  db.adminCommand({
    addShard: "rs-shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019",
  })
}

db.adminCommand({ enableSharding: "somedb" })

const configDb = db.getSiblingDB("config")
const collectionInfo = configDb.collections.findOne({ _id: "somedb.helloDoc" })
if (!collectionInfo) {
  db.adminCommand({
    shardCollection: "somedb.helloDoc",
    key: { _id: "hashed" },
  })
}
EOF

docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
use somedb
db.helloDoc.deleteMany({})
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
