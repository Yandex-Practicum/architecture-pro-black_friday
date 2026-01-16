
sh.addShard("rs-shard1/shard1-1:27018");
sh.addShard("rs-shard1/shard1-2:27018");
sh.addShard("rs-shard1/shard1-3:27018");
sh.addShard("rs-shard2/shard2-1:27019");
sh.addShard("rs-shard2/shard2-2:27019");
sh.addShard("rs-shard2/shard2-3:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { title: "hashed" });
