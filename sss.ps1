docker compose -f .\mongo-sharding.yaml exec -T shard1 mongosh --port 27018 --quiet @'
use somedb
db.helloDoc.countDocuments()
'@
pause