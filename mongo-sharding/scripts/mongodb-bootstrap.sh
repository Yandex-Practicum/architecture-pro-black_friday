#!/usr/bin/env bash

BOOTSTRAP_CONFIG_SERVER=$(cat <<EOF
rs.initiate({
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "config-server:27017" }
    ]
});
EOF
)

BOOTSTRAP_SHARD_01=$(cat <<EOF
rs.initiate({
    _id : "rs01",
    members: [
        { _id : 0, host : "mongodb-rs01-01:27017" }
    ]
});
EOF
)
BOOTSTRAP_SHARD_02=$(cat <<EOF
rs.initiate({
    _id : "rs02",
    members: [
        { _id : 0, host : "mongodb-rs02-01:27017" }
    ]
});
EOF
)
BOOTSTRAP_ROUTERS=$(cat <<EOF
sh.addShard("rs01/mongodb-rs01-01:27017");
sh.addShard("rs02/mongodb-rs02-01:27017");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });
EOF
)

for((i=1; i<10; i++))
do
    echo "Trying to bootstrap configuration server..."
    echo $BOOTSTRAP_CONFIG_SERVER | mongosh --quiet --host config-server --port 27017
    if [ $? -eq 0 ]
    then
        echo "Bootstraped configuration server"
        break
    fi
    echo "Pause..."
    sleep 1
done

echo "Bootstrap shard-01"
echo $BOOTSTRAP_SHARD_01 | mongosh --quiet --host mongodb-rs01-01 --port 27017

echo "Bootstrap shard-02"
echo $BOOTSTRAP_SHARD_02 | mongosh --quiet --host mongodb-rs02-01 --port 27017

for((i=1; i<10; i++))
do
    echo $BOOTSTRAP_ROUTERS | mongosh --host mongodb-router-01 --port 27017
    if [ $? -eq 0 ]
    then
        echo "Bootstraped routers"
        break
    fi
    echo "Pause..."
    sleep 1
done
