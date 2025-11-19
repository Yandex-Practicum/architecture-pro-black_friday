#!/bin/bash

echo "configSrv"
./mongo-init_configSrv.sh || exit 1 && echo "error configSrv"

echo "shard2"
./mongo-init_shard2.sh || exit 1 && echo "error shard2"
echo "shard1"
./mongo-init_shard1.sh || exit 1 && echo "error shard1"
echo "mongos_router"
./mongo-init_mongos_router.sh || exit 1 && echo "error mongo_router"

echo "init"
./mongo-init.sh || exit 1 && echo "error init"