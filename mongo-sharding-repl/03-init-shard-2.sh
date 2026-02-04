#!/usr/bin/env bash
set -euo pipefail

echo "[shard2] rs.initiate(shard2)"

docker exec -i shard2 mongosh --quiet --port 27019 <<'JS'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" },
    { _id: 1, host: "shard2_2:27019" },
    { _id: 2, host: "shard2_3:27019" }
  ]
});
JS

echo "[shard2] done"
