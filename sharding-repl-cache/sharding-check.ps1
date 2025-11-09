# Проверка наполнения базы данных на роутере
Write-Host "Проверка количества документов в кластере (через router)..."
docker exec -i router mongosh --port 27020 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов в кластере: ' + count);
exit();
"

# Проверка наполнения шарда 1
Write-Host "Проверка количества документов на shard-1-master..."
docker exec -i shard-1-master mongosh --port 27018 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-1-master: ' + count);
exit();
"

Write-Host "Проверка количества документов на shard-1-replica-1..."
docker exec -i shard-1-replica-1 mongosh --port 27021 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-1-replica-1: ' + count);
exit();
"


Write-Host "Проверка количества документов на shard-1-replica-2..."
docker exec -i shard-1-replica-2 mongosh --port 27022 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-1-replica-2: ' + count);
exit();
"

# Проверка наполнения шарда 2
Write-Host "Проверка количества документов на shard-2-master..."
docker exec -i shard-2-master mongosh --port 27019 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-2-master: ' + count);
exit();
"

Write-Host "Проверка количества документов на shard-2-replica-1..."
docker exec -i shard-2-replica-1 mongosh --port 27023 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-2-replica-1: ' + count);
exit();
"

Write-Host "Проверка количества документов на shard-2-replica-2..."
docker exec -i shard-2-replica-2 mongosh --port 27024 --eval "
db = db.getSiblingDB('somedb');
count = db.helloDoc.countDocuments();
print('Количество документов на shard-2-replica-2: ' + count);
exit();
"

# Проверка кэша (Redis)
Write-Host "Проверка (Redis)..."
try {
    # Выполняем команду ping к Redis через docker-compose
    $response = docker exec -i redis redis-cli ping 2>&1 | ForEach-Object { $_.ToString().Trim() }
    if ($response -eq "PONG") {
        Write-Host "OK: Redis отвечает (PONG)"
        exit 0
    }
    else {
        Write-Host "ERROR: Redis не отвечает. Ответ: $response"
        exit 1
    }
}
catch {
    Write-Host "ERROR: Произошла ошибка при выполнении команды: $_"
    exit 1
}