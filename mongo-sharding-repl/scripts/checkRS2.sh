#!/bin/bash
docker compose exec -T shard2_1 mongosh --port 27021 --quiet <<EOF
rs.status().members.map(
    m=>(
        {
            name:m.name,
            state:m.stateStr,
            health:m.health
        }
    )
);
EOF