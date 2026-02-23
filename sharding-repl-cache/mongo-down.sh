#!/bin/bash

docker compose down
docker volume rm mongo-sharding-repl_config-data mongo-sharding-repl_shard1-1-data mongo-sharding-repl_shard1-2-data \
  mongo-sharding-repl_shard1-3-data mongo-sharding-repl_shard2-1-data mongo-sharding-repl_shard2-2-data \
  mongo-sharding-repl_shard2-3-data
