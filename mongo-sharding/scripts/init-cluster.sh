
#!/bin/bash
set -e

# Config Server
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{_id: 0, host: "configSrv:27017"}]
  });
}
EOF

# Shard 1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "shard1",
    members: [{_id: 0, host: "shard1:27018"}]
  });
}
EOF

# Shard 2
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "shard2",
    members: [{_id: 0, host: "shard2:27019"}]
  });
}
EOF

echo "MongoDB nodes initialized"
