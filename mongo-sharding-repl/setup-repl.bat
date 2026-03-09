@echo off
chcp 65001 >nul
echo === НАСТРОЙКА РЕПЛИКАЦИИ И ШАРДИРОВАНИЯ ===
echo.

echo 1. Запуск контейнеров...
docker compose up -d
echo Ожидание 30 секунд...
timeout /t 30

echo 2. Инициализация configSrv...
docker compose exec -T configSrv mongosh --port 27019 --quiet --eval "rs.initiate({ _id: 'configSrv', configsvr: true, members: [{ _id: 0, host: 'configSrv:27019' }] })"
timeout /t 5

echo 3. Инициализация rs1...
docker compose exec -T shard11 mongosh --port 27018 --quiet --eval "rs.initiate({ _id: 'rs1', members: [{ _id: 0, host: 'shard11:27018' }, { _id: 1, host: 'shard12:27018' }, { _id: 2, host: 'shard13:27018' }] })"
timeout /t 10

echo 4. Инициализация rs2...
docker compose exec -T shard21 mongosh --port 27018 --quiet --eval "rs.initiate({ _id: 'rs2', members: [{ _id: 0, host: 'shard21:27018' }, { _id: 1, host: 'shard22:27018' }, { _id: 2, host: 'shard23:27018' }] })"
timeout /t 30

echo 5. Добавление шардов...
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('rs1/shard11:27018,shard12:27018,shard13:27018')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('rs2/shard21:27018,shard22:27018,shard23:27018')"
timeout /t 5

echo 6. Настройка шардирования...
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.enableSharding('somedb')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.getSiblingDB('somedb').createCollection('helloDoc')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.shardCollection('somedb.helloDoc', { '_id': 'hashed' })"

echo 7. Заполнение данными...
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "for (var i = 1; i <= 1000; i++) { db.helloDoc.insert({ name: 'doc' + i, value: i }) }"

echo 8. Проверка...
echo Общее количество документов:
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "db.helloDoc.countDocuments()"
echo.
echo === ГОТОВО ===
pause