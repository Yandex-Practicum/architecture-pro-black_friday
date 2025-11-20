#!/bin/bash

###
# Инициализируем redis
###
 docker exec -it redis_1 sh -c 'echo "yes" | redis-cli --cluster create 173.17.0.41:6379   173.17.0.42:6379   173.17.0.43:6379   173.17.0.44:6379   173.17.0.45:6379   173.17.0.46:6379 --cluster-replicas 1'
