rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1_primary:27018", priority: 2 },
    { _id: 1, host: "shard1_secondary1:27018" },
    { _id: 2, host: "shard1_secondary2:27018" }
  ]
})