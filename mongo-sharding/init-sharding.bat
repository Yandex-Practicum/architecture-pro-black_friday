@echo off
chcp 65001 >nul
echo === НАСТРОЙКА ШАРДИРОВАНИЯ ===
echo.

echo 1. Пересоздание контейнеров с полной очисткой...
docker compose down -v
timeout /t 3

echo 2. Запуск контейнеров...
docker compose up -d
echo Ожидание 30 секунд...
timeout /t 30

echo 3. Инициализация configSrv...
docker compose exec configSrv mongosh --port 27019 --eval "rs.initiate({_id:'configSrv', configsvr:true, members:[{_id:0, host:'configSrv:27019'}]})"
timeout /t 5

echo 4. Инициализация репликации для шардов...
echo Инициализация rs1 (shard1)...
docker compose exec shard1 mongosh --port 27018 --eval "rs.initiate({_id:'rs1', members:[{_id:0, host:'shard1:27018'}]})"

echo Инициализация rs2 (shard2)...
docker compose exec shard2 mongosh --port 27018 --eval "rs.initiate({_id:'rs2', members:[{_id:0, host:'shard2:27018'}]})"
timeout /t 10

echo 5. Добавление шардов в кластер...
docker compose exec mongos mongosh --port 27017 --eval "sh.addShard('rs1/shard1:27018')"
if %errorlevel% neq 0 (
    echo Ошибка при добавлении shard1, пробуем еще раз через 5 секунд...
    timeout /t 5
    docker compose exec mongos mongosh --port 27017 --eval "sh.addShard('rs1/shard1:27018')"
)

docker compose exec mongos mongosh --port 27017 --eval "sh.addShard('rs2/shard2:27018')"
if %errorlevel% neq 0 (
    echo Ошибка при добавлении shard2, пробуем еще раз через 5 секунд...
    timeout /t 5
    docker compose exec mongos mongosh --port 27017 --eval "sh.addShard('rs2/shard2:27018')"
)

echo 6. Проверка статуса шардов...
docker compose exec mongos mongosh --port 27017 --eval "sh.status()"

echo 7. Настройка шардирования...
docker compose exec mongos mongosh --port 27017 --eval "sh.enableSharding('somedb')"
docker compose exec mongos mongosh --port 27017 --eval "db.getSiblingDB('somedb').createCollection('helloDoc')"
docker compose exec mongos mongosh --port 27017 --eval "sh.shardCollection('somedb.helloDoc', {_id:'hashed'})"

echo 8. Заполнение данными...
docker compose exec mongos mongosh --port 27017 somedb --eval "for(i=1;i<=1000;i++){db.helloDoc.insert({name:'doc'+i, value:i})}"

echo 9. Проверка результатов...
echo.
echo Общее количество документов:
docker compose exec mongos mongosh --port 27017 somedb --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 1:
docker compose exec shard1 mongosh --port 27018 somedb --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 2:
docker compose exec shard2 mongosh --port 27018 somedb --eval "db.helloDoc.countDocuments()"

echo.
echo === ГОТОВО ===
pause