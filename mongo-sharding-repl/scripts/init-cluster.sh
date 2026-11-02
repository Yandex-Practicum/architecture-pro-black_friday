
#!/bin/bash
set -e

# Config Server
docker compose exec -T configsrv mongosh --port 27017 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [
      {_id: 0, host: "configsrv:27017"}
    ]
  });
}
EOF

# Shard 1 Replica Set
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "shard1",
    members: [
      {_id: 0, host: "shard1-1:27018"},
      {_id: 1, host: "shard1-2:27018"},
      {_id: 2, host: "shard1-3:27018"}
    ]
  });
}
EOF

# Shard 2 Replica Set
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<'EOF'
if (!db.getSiblingDB("local").system.replset.findOne()) {
  rs.initiate({
    _id: "shard2",
    members: [
      {_id: 0, host: "shard2-1:27019"},
      {_id: 1, host: "shard2-2:27019"},
      {_id: 2, host: "shard2-3:27019"}
    ]
  });
}
EOF

echo "Replica Sets initialized"
