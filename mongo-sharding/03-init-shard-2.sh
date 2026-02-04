#!/usr/bin/env bash
set -euo pipefail

echo "[shard2] rs.initiate(shard2)"

docker exec -i shard2 mongosh --quiet --port 27019 <<'JS'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 1, host: "shard2:27019" }
  ]
});
JS

echo "[shard2] done"
