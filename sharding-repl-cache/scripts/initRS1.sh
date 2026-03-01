#!/bin/bash
docker compose exec -T shard1_1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
    {
      _id : "rs1",
      members: [
        { _id : 0, host : "shard1_1:27018" },
        { _id : 1, host : "shard1_2:27019" },
        { _id : 2, host : "shard1_3:27020" },
      ]
    }
);
EOF