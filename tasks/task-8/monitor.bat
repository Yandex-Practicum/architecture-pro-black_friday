@echo off
echo === МОНИТОРИНГ ШАРДОВ ===
echo.
echo 1. Список шардов:
docker compose exec -T mongos mongosh --port 27017 --eval "db.adminCommand({ listShards: 1 }).shards.forEach(s => print(s._id))"
echo.
echo 2. Распределение чанков:
docker compose exec -T mongos mongosh --port 27017 --eval "db.getSiblingDB('config').chunks.aggregate([{ $group: { _id: '$shard', count: { $sum: 1 } } }]).forEach(c => print(c._id + ': ' + c.count))"
echo.
echo 3. Популярность категорий:
docker compose exec -T mongos mongosh --port 27017 --eval "db = db.getSiblingDB('mobile_mir'); db.products.aggregate([{ $group: { _id: '$category', count: { $sum: 1 } } }]).forEach(c => print(c._id + ': ' + c.count))"
pause