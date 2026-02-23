#!/bin/bash

docker compose down
docker volume rm sharding-repl-cache_config-data sharding-repl-cache_shard1-1-data sharding-repl-cache_shard1-2-data \
  sharding-repl-cache_shard1-3-data sharding-repl-cache_shard2-1-data sharding-repl-cache_shard2-2-data \
  sharding-repl-cache_shard2-3-data sharding-repl-cache_redis-data
