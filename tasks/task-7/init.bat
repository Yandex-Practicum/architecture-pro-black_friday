@echo off
chcp 65001 >nul
title Создание и запуск setup.js для MongoDB

echo =====================================================
echo    СОЗДАНИЕ И ЗАПУСК setup.js
echo =====================================================
echo.

REM Проверка запущенных контейнеров
echo Проверка доступности mongos...
docker compose ps mongos | findstr "Up" >nul
if %errorlevel% neq 0 (
    echo [ERROR] mongos не запущен. Запустите сначала docker compose up -d
    pause
    exit /b 1
)
echo [OK] mongos доступен
echo.

REM Удаляем старый файл если есть
if exist setup.js del setup.js

REM Создание JS файла с экранированием спецсимволов
echo Создание setup.js...

echo // Скрипт настройки MongoDB для интернет-магазина > setup.js
echo // ============================================== >> setup.js
echo. >> setup.js
echo // 1. Включение шардирования для базы данных >> setup.js
echo sh.enableSharding('mobile_mir'); >> setup.js
echo. >> setup.js
echo // 2. Создание коллекций >> setup.js
echo db = db.getSiblingDB('mobile_mir'); >> setup.js
echo db.createCollection('products'); >> setup.js
echo db.createCollection('orders'); >> setup.js
echo db.createCollection('carts'); >> setup.js
echo print('Коллекции созданы'); >> setup.js
echo. >> setup.js
echo // 3. Настройка шардирования для коллекций >> setup.js
echo sh.shardCollection('mobile_mir.products', { category: 1, _id: 1 }); >> setup.js
echo sh.shardCollection('mobile_mir.orders', { user_id: 'hashed', _id: 1 }); >> setup.js
echo sh.shardCollection('mobile_mir.carts', { user_id: 1, session_id: 1, _id: 1 }); >> setup.js
echo print('Шардирование настроено'); >> setup.js
echo. >> setup.js
echo // 4. Создание индексов для products >> setup.js
echo db.products.createIndex({ category: 1, price: 1 }); >> setup.js
echo db.products.createIndex({ name: 1 }); >> setup.js
echo. >> setup.js
echo // 5. Создание индексов для orders >> setup.js
echo db.orders.createIndex({ user_id: 1, order_date: -1 }); >> setup.js
echo db.orders.createIndex({ status: 1, order_date: 1 }); >> setup.js
echo db.orders.createIndex({ geo_zone: 1, order_date: -1 }); >> setup.js
echo. >> setup.js
echo // 6. Создание индексов для carts >> setup.js
echo db.carts.createIndex( >> setup.js
echo   { user_id: 1, status: 1 }, >> setup.js
echo   { partialFilterExpression: { status: 'active' } } >> setup.js
echo ); >> setup.js
echo db.carts.createIndex( >> setup.js
echo   { session_id: 1, status: 1 }, >> setup.js
echo   { partialFilterExpression: { status: 'active' } } >> setup.js
echo ); >> setup.js
echo db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 }); >> setup.js
echo print('Индексы созданы'); >> setup.js
echo. >> setup.js
echo // 7. Добавление тестовых товаров >> setup.js
echo var electronicsCount = db.products.countDocuments({ category: 'electronics' }); >> setup.js
echo var audioCount = db.products.countDocuments({ category: 'audio' }); >> setup.js
echo var booksCount = db.products.countDocuments({ category: 'books' }); >> setup.js
echo var homeCount = db.products.countDocuments({ category: 'home' }); >> setup.js
echo. >> setup.js
echo if (electronicsCount == 0) { >> setup.js
echo   db.products.insertMany([ >> setup.js
echo     { >> setup.js
echo       name: 'Смартфон X', >> setup.js
echo       category: 'electronics', >> setup.js
echo       price: 29990, >> setup.js
echo       stock: { msk: 50, spb: 30, ekb: 25, kld: 15 }, >> setup.js
echo       attributes: { color: 'black', size: '6.1"' } >> setup.js
echo     }, >> setup.js
echo     { >> setup.js
echo       name: 'Ноутбук Pro', >> setup.js
echo       category: 'electronics', >> setup.js
echo       price: 89990, >> setup.js
echo       stock: { msk: 20, spb: 15, ekb: 10, kld: 5 }, >> setup.js
echo       attributes: { color: 'silver', size: '15"' } >> setup.js
echo     }, >> setup.js
echo     { >> setup.js
echo       name: 'Планшет Lite', >> setup.js
echo       category: 'electronics', >> setup.js
echo       price: 15990, >> setup.js
echo       stock: { msk: 35, spb: 25, ekb: 15, kld: 8 }, >> setup.js
echo       attributes: { color: 'gray', size: '10"' } >> setup.js
echo     } >> setup.js
echo   ]); >> setup.js
echo   print('Добавлена электроника'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo if (audioCount == 0) { >> setup.js
echo   db.products.insertMany([ >> setup.js
echo     { >> setup.js
echo       name: 'Наушники Bluetooth', >> setup.js
echo       category: 'audio', >> setup.js
echo       price: 4990, >> setup.js
echo       stock: { msk: 100, spb: 80, ekb: 60, kld: 40 }, >> setup.js
echo       attributes: { color: 'white', type: 'wireless' } >> setup.js
echo     }, >> setup.js
echo     { >> setup.js
echo       name: 'Колонка портативная', >> setup.js
echo       category: 'audio', >> setup.js
echo       price: 2990, >> setup.js
echo       stock: { msk: 70, spb: 50, ekb: 40, kld: 20 }, >> setup.js
echo       attributes: { color: 'black', waterproof: true } >> setup.js
echo     } >> setup.js
echo   ]); >> setup.js
echo   print('Добавлено аудио'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo if (booksCount == 0) { >> setup.js
echo   db.products.insertMany([ >> setup.js
echo     { >> setup.js
echo       name: 'Программирование на Python', >> setup.js
echo       category: 'books', >> setup.js
echo       price: 1200, >> setup.js
echo       stock: { msk: 200, spb: 150, ekb: 100, kld: 50 }, >> setup.js
echo       attributes: { author: 'Лутц', pages: 800 } >> setup.js
echo     }, >> setup.js
echo     { >> setup.js
echo       name: 'Алгоритмы и структуры данных', >> setup.js
echo       category: 'books', >> setup.js
echo       price: 1500, >> setup.js
echo       stock: { msk: 150, spb: 120, ekb: 80, kld: 30 }, >> setup.js
echo       attributes: { author: 'Кормен', pages: 1200 } >> setup.js
echo     } >> setup.js
echo   ]); >> setup.js
echo   print('Добавлены книги'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo if (homeCount == 0) { >> setup.js
echo   db.products.insertMany([ >> setup.js
echo     { >> setup.js
echo       name: 'Чайник электрический', >> setup.js
echo       category: 'home', >> setup.js
echo       price: 2500, >> setup.js
echo       stock: { msk: 80, spb: 60, ekb: 40, kld: 20 }, >> setup.js
echo       attributes: { material: 'plastic', volume: '1.8L' } >> setup.js
echo     }, >> setup.js
echo     { >> setup.js
echo       name: 'Микроволновая печь', >> setup.js
echo       category: 'home', >> setup.js
echo       price: 5500, >> setup.js
echo       stock: { msk: 40, spb: 30, ekb: 20, kld: 10 }, >> setup.js
echo       attributes: { power: '700W', volume: '20L' } >> setup.js
echo     } >> setup.js
echo   ]); >> setup.js
echo   print('Добавлены товары для дома'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo // 8. Добавление тестового заказа >> setup.js
echo var ordersCount = db.orders.countDocuments(); >> setup.js
echo if (ordersCount == 0) { >> setup.js
echo   var product = db.products.findOne({ name: 'Смартфон X' }); >> setup.js
echo   db.orders.insertOne({ >> setup.js
echo     user_id: 1001, >> setup.js
echo     order_date: new Date(), >> setup.js
echo     geo_zone: 'msk', >> setup.js
echo     status: 'new', >> setup.js
echo     items: [{ >> setup.js
echo       product_id: product._id, >> setup.js
echo       name: product.name, >> setup.js
echo       price: product.price, >> setup.js
echo       quantity: 1, >> setup.js
echo       category: product.category >> setup.js
echo     }], >> setup.js
echo     total_amount: product.price, >> setup.js
echo     created_at: new Date(), >> setup.js
echo     updated_at: new Date() >> setup.js
echo   }); >> setup.js
echo   print('Добавлен тестовый заказ'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo // 9. Добавление тестовой корзины >> setup.js
echo var activeCartsCount = db.carts.countDocuments({ status: 'active' }); >> setup.js
echo if (activeCartsCount == 0) { >> setup.js
echo   var product = db.products.findOne({ name: 'Наушники Bluetooth' }); >> setup.js
echo   db.carts.insertOne({ >> setup.js
echo     session_id: 'test_session_123', >> setup.js
echo     status: 'active', >> setup.js
echo     items: [{ product_id: product._id, quantity: 1, added_at: new Date() }], >> setup.js
echo     created_at: new Date(), >> setup.js
echo     updated_at: new Date(), >> setup.js
echo     expires_at: new Date(Date.now() + 7*24*60*60*1000) >> setup.js
echo   }); >> setup.js
echo   print('Добавлена тестовая корзина'); >> setup.js
echo } >> setup.js
echo. >> setup.js
echo // 10. Итоговая статистика >> setup.js
echo print('========================================'); >> setup.js
echo print('Товаров в базе: ' + db.products.countDocuments()); >> setup.js
echo print('Заказов в базе: ' + db.orders.countDocuments()); >> setup.js
echo print('Корзин в базе: ' + db.carts.countDocuments()); >> setup.js
echo print('========================================'); >> setup.js
echo. >> setup.js
echo // 11. Проверка распределения по категориям >> setup.js
echo print('\nТовары по категориям:'); >> setup.js
echo db.products.aggregate([ >> setup.js
echo   { $group: { _id: '$category', count: { $sum: 1 } } } >> setup.js
echo ]).forEach(printjson); >> setup.js
echo. >> setup.js
echo // 12. Проверка статуса шардирования >> setup.js
echo print('\nСтатус шардирования:'); >> setup.js
echo sh.status(); >> setup.js

echo [OK] setup.js создан
dir setup.js | find "setup.js"
echo.

echo Копирование файла в контейнер...
docker compose cp setup.js mongos:/setup.js

echo.
echo Запуск скрипта в MongoDB...
echo =====================================================
docker compose exec mongos mongosh --port 27017 /setup.js
echo =====================================================
echo.

echo Удаление временного файла...
rem ь del setup.js

echo.
echo =====================================================
echo    НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО
echo =====================================================
echo.
echo Для проверки выполните:
echo   docker compose exec mongos mongosh --port 27017
echo   use mobile_mir
echo   db.products.find().pretty()
echo.
pause