@echo off
echo Подготовка MongoDB...

REM Проверяем, запущен ли контейнер
docker ps | findstr "mongodb1" >nul
if %errorlevel% neq 0 (
    echo Запуск контейнеров...
    docker compose up -d
    echo Ожидание 5 секунд...
    timeout /t 5
)

REM Выполняем инициализацию
echo Инициализация базы данных somedb...
docker compose exec -T mongodb1 mongosh --eval ^
"db = db.getSiblingDB('somedb'); ^
print('База somedb ' + (db.getName())); ^
print('Очистка коллекции helloDoc...'); ^
db.helloDoc.deleteMany({}); ^
print('Вставка 1000 документов...'); ^
for(var i = 0; i ^< 1000; i++) { ^
    db.helloDoc.insertOne({age: i, name: 'ly' + i}); ^
} ^
print('Итого документов: ' + db.helloDoc.countDocuments());"

echo.
echo Готово. API доступно на http://localhost:8080