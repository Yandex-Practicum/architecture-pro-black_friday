
sh.addShard("rs-shard1/shard1:27018");
sh.addShard("rs-shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { title: "hashed" });
