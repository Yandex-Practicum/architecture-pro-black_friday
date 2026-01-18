rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2_primary:27019", priority: 2 },
    { _id: 1, host: "shard2_secondary1:27019" },
    { _id: 2, host: "shard2_secondary2:27019" }
  ]
})