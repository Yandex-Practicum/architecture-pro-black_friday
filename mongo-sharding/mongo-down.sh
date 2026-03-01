#!/bin/bash

docker compose down
docker volume rm mongo-sharding_config-data mongo-sharding_shard1-data mongo-sharding_shard2-data
