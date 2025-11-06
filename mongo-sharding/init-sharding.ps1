# Инициализация сервера конфигураций
Write-Host "Инициализация config сервера..."
docker exec -i configSrv mongosh --port 27017 --eval "
rs.initiate({
  _id : 'config_server',
  configsvr: true,
  members: [
    { _id : 0, host : 'configSrv:27017' }
  ]
});
exit();
"

Start-Sleep -Seconds 10

# Инициализация шарда 1
Write-Host "Инициализация шарда 1..."
docker exec -i shard-1 mongosh --port 27018 --eval "
rs.initiate({
  _id : 'shard-1',
  members: [
    { _id : 0, host : 'shard-1:27018' }
  ]
});
exit();
"

Start-Sleep -Seconds 10

# Инициализация шарда 2
Write-Host "Инициализация шарда 2..."
docker exec -i shard-2 mongosh --port 27019 --eval "
rs.initiate({
  _id : 'shard-2',
  members: [
    { _id : 0, host : 'shard-2:27019' }
  ]
});
exit();
"

Start-Sleep -Seconds 10

# Инициализация маршрутизатора (роутера)
Write-Host "Настройка роутера и включение шардинга..."
docker exec -i router mongosh --port 27020 --eval "
sh.addShard('shard-1/shard-1:27018');
sh.addShard('shard-2/shard-2:27019');
sh.enableSharding('somedb');
sh.shardCollection('somedb.helloDoc', { 'name': 'hashed' });
db = db.getSiblingDB('somedb'); // use somedb;
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insert({ age: i, name: 'ly' + i });
}
db.helloDoc.countDocuments();
exit();
"

Write-Host "Инициализация шардинга завершена."