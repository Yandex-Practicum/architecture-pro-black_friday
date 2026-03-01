#!/bin/bash
docker compose exec -T shard2_1 mongosh --port 27021 --quiet <<EOF
rs.initiate(
    {
      _id : "rs2",
      members: [
        { _id : 0, host : "shard2_1:27021" },
        { _id : 1, host : "shard2_2:27022" },
        { _id : 2, host : "shard2_3:27023" },
      ]
    }
);
EOF