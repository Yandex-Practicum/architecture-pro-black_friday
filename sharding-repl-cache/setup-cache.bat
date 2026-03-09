@echo off
chcp 65001 >nul
echo === НАСТРОЙКА ШАРДИРОВАНИЯ С КЕШИРОВАНИЕМ ===
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

echo 7. Заполнение данными (1000 документов с name, age и email)...
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "var firstNames = ['John', 'Jane', 'Bob', 'Alice', 'Mike', 'Emma', 'David', 'Sarah', 'Tom', 'Lisa']; var lastNames = ['Smith', 'Johnson', 'Brown', 'Taylor', 'Wilson', 'Davis', 'Miller', 'Jones', 'Garcia', 'Rodriguez']; for (var i = 1; i <= 1000; i++) { var firstName = firstNames[Math.floor(Math.random() * firstNames.length)]; var lastName = lastNames[Math.floor(Math.random() * lastNames.length)]; db.helloDoc.insert({ name: firstName + ' ' + lastName, age: Math.floor(Math.random() * 50) + 18, email: firstName.toLowerCase() + '.' + lastName.toLowerCase() + i + '@example.com' }); } print('Добавлено 1000 документов с полями name, age, email');"

echo 8. Проверка структуры данных...
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "print('Первые 3 документа:'); db.helloDoc.find({}, {_id:1, name:1, age:1, email:1}).limit(3).forEach(printjson)"
echo.

echo 9. Проверка приложения...
echo Общее количество документов:
curl -s http://localhost:8080
echo.
echo 10. Проверка кеширования эндпоинта /helloDoc/users...
echo.
echo --- Первый запрос (без кеша) ---
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo --- Второй запрос (с кешем) ---
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo --- Третий запрос (с кешем) ---
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul

echo.
echo 11. Проверка заголовков кеша:
curl -I http://localhost:8080/helloDoc/users 2>nul | findstr "X-Cache"
if errorlevel 1 echo Заголовок X-Cache не найден

echo.
echo 12. Проверка ключей в Redis:
docker compose exec redis redis-cli --scan --pattern "users:*" 2>nul | findstr /v "empty" || echo Ключи в Redis не найдены

echo.
echo === ГОТОВО ===
pause