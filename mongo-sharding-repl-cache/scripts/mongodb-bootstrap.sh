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
        { _id : 0, host : "storage-rs01-01:27017" },
        { _id : 1, host : "storage-rs01-02:27017" },
        { _id : 2, host : "storage-rs01-03:27017" }
    ]
});
EOF
)
BOOTSTRAP_SHARD_02=$(cat <<EOF
rs.initiate({
    _id : "rs02",
    members: [
        { _id : 0, host : "storage-rs02-01:27017" },
        { _id : 1, host : "storage-rs02-02:27017" },
        { _id : 2, host : "storage-rs02-03:27017" }
    ]
});
EOF
)
BOOTSTRAP_ROUTERS=$(cat <<EOF
sh.addShard("rs01/storage-rs01-01:27017,storage-rs01-02:27017,storage-rs01-03:27017");
sh.addShard("rs02/storage-rs02-01:27017,storage-rs02-02:27017,storage-rs02-03:27017");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name : 'hashed' });
sh.shardCollection("somedb.carts", { owner_id: 'hashed' });
sh.shardCollection("somedb.orders", { user_id: 'hashed' });
sh.shardCollection("somedb.products", { locality: 1, category: 1, price: 1 });
use somedb;
db.carts.createIndex(
    {
        owner_id: 1,
        status: 1
    },
    {
        unique: true,
        partialIndexExpression: {
            status: { $eq: 'active' }
        }
    }
);
db.orders.createIndex({ user_id: 1 });
db.products.createIndex({ locality: 1, sku: 1 }, { unique: true });
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
echo $BOOTSTRAP_SHARD_01 | mongosh --quiet --host storage-rs01-01 --port 27017

echo "Bootstrap shard-02"
echo $BOOTSTRAP_SHARD_02 | mongosh --quiet --host storage-rs02-01 --port 27017

for((i=1; i<10; i++))
do
    echo $BOOTSTRAP_ROUTERS | mongosh --host router-01 --port 27017
    if [ $? -eq 0 ]
    then
        echo "Bootstraped routers"
        break
    fi
    echo "Pause..."
    sleep 1
done
