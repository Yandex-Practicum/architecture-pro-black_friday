#!/bin/bash

echo "=========================================="
echo "Populating MongoDB with test data"
echo "=========================================="

# Insert 1000+ documents into the helloDoc collection
echo ""
echo "Inserting documents into somedb.helloDoc collection..."

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb

// Clear existing data
db.helloDoc.deleteMany({});

// Insert 1500 documents
var docs = [];
for (var i = 1; i <= 1500; i++) {
  docs.push({
    name: "User_" + i,
    age: Math.floor(Math.random() * 60) + 18,
    email: "user" + i + "@example.com",
    createdAt: new Date(),
    index: i
  });
  
  // Insert in batches of 100
  if (i % 100 === 0) {
    db.helloDoc.insertMany(docs);
    docs = [];
  }
}

// Insert remaining documents
if (docs.length > 0) {
  db.helloDoc.insertMany(docs);
}

print("Total documents inserted: " + db.helloDoc.countDocuments());
EOF

echo ""
echo "=========================================="
echo "Checking data distribution across shards"
echo "=========================================="

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF

echo ""
echo "=========================================="
echo "Data population completed!"
echo "=========================================="
