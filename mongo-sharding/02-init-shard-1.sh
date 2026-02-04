#!/usr/bin/env bash
set -euo pipefail

echo "[shard1] rs.initiate(shard1)"

docker exec -i shard1 mongosh --quiet --port 27018 <<'JS'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
JS

echo "[shard1] done"
