# Проверка наполнения базы данных на роутере
Write-Host "Проверка количества документов в кластере (через router)..."
docker exec -i router mongosh --port 27020 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов в кластере: ' + count);
exit();
"

# Проверка наполнения шарда 1
Write-Host "Проверка количества документов на shard-1..."
docker exec -i shard-1 mongosh --port 27018 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-1: ' + count);
exit();
"

# Проверка наполнения шарда 2
Write-Host "Проверка количества документов на shard-2..."
docker exec -i shard-2 mongosh --port 27019 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-2: ' + count);
exit();
"