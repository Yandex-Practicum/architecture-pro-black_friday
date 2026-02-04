#!/usr/bin/env bash
set -euo pipefail

echo "[configSrv] rs.initiate(config_server)"

docker exec -i configSrv mongosh --quiet --port 27017 <<'JS'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
});
JS

echo "[configSrv] done"
