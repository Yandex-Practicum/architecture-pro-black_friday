# Архитектурный документ: Настройка чтения с реплик и консистентность

## 1. Анализ операций и требований к консистентности

### 1.1 Коллекция `products`

| Операция чтения | Частота | Требования к консистентности | Риск при устаревших данных |
|-----------------|---------|------------------------------|----------------------------|
| Поиск товаров по категориям и фильтрация по цене | Очень высокая | Низкая | Пользователь видит устаревший ассортимент, но это не критично |
| Описание товара на странице продукта | Высокая | Средняя | Устаревшая цена или характеристики могут ввести в заблуждение |
| Проверка остатка товара в геозоне | Высокая | Высокая | Продажа товара, которого нет в наличии |

### 1.2 Коллекция `orders`

| Операция чтения | Частота | Требования к консистентности | Риск при устаревших данных |
|-----------------|---------|------------------------------|----------------------------|
| Поиск истории заказов пользователя | Средняя | Низкая | Пользователь не видит последний заказ сразу |
| Отображение статуса заказа | Высокая | Высокая | Пользователь видит неверный статус (например, "в обработке" вместо "отправлен") |
| Проверка статуса для службы поддержки | Низкая | Высокая | Оператор даёт неверную информацию клиенту |

### 1.3 Коллекция `carts`

| Операция чтения | Частота | Требования к консистентности | Риск при устаревших данных |
|-----------------|---------|------------------------------|----------------------------|
| Получение текущей корзины пользователя | Очень высокая | Очень высокая | Пользователь видит неактуальный состав корзины, может добавить дубликат |
| Получение корзины гостя | Высокая | Очень высокая | Гость теряет добавленные товары |
| Проверка корзины при оформлении заказа | Высокая | Абсолютная | Оформление заказа с неверным составом |

---

## 2. Допустимая задержка репликации

| Коллекция | Тип операций | Допустимая задержка | Обоснование |
|-----------|--------------|---------------------|-------------|
| **products** | Поиск и фильтрация | 5-10 секунд | Пользователь может не увидеть только что добавленный товар, но это не критично |
| **products** | Описание товара | 1-2 секунды | Цена и описание должны быть актуальными, небольшая задержка допустима |
| **products** | Проверка остатков | < 500 мс | Продажа последнего экземпляра требует точных данных |
| **orders** | История заказов | 5-10 секунд | Пользователь не ждёт мгновенного появления заказа в истории |
| **orders** | Статус заказа | < 1 секунды | Пользователь активно отслеживает статус |
| **carts** | Все операции | < 100 мс | Корзина должна быть строго консистентной |

---

## 3. Стратегия чтения: Primary vs Secondary

| Коллекция | Операция | Источник чтения | Обоснование |
|-----------|----------|-----------------|-------------|
| **products** | Поиск по категориям с фильтрацией | **SECONDARY** | Высокая нагрузка, низкие требования к консистентности |
| **products** | Получение описания товара | **SECONDARY** | Допустима небольшая задержка |
| **products** | Проверка остатков | **PRIMARY** | Критично для бизнес-логики (избежать overselling) |
| **products** | Обновление остатков | **PRIMARY** | Запись всегда идёт на primary |
| **orders** | История заказов | **SECONDARY** | Некритично, можно читать с реплик |
| **orders** | Текущий статус заказа | **PRIMARY** | Пользователь должен видеть актуальный статус |
| **orders** | Создание заказа | **PRIMARY** | Запись всегда на primary |
| **carts** | Получение корзины | **PRIMARY** | Строгая консистентность критична |
| **carts** | Добавление/удаление товаров | **PRIMARY** | Запись всегда на primary |
| **carts** | Слияние корзин | **PRIMARY** | Транзакционность критична |

---

## 4. Таблица итоговых настроек

| Коллекция | Операция | Read Preference | Read Concern | Write Concern | Допустимая задержка |
|-----------|----------|-----------------|--------------|---------------|---------------------|
| **products** | Поиск по категориям | `secondary` | `local` | - | 5-10 сек |
| **products** | Описание товара | `secondary` | `local` | - | 1-2 сек |
| **products** | Проверка остатков | `primary` | `linearizable` | - | < 500 мс |
| **products** | Обновление остатков | - | - | `majority` | - |
| **orders** | История заказов | `secondary` | `local` | - | 5-10 сек |
| **orders** | Статус заказа | `primary` | `linearizable` | - | < 1 сек |
| **orders** | Создание заказа | - | - | `majority` | - |
| **carts** | Получение корзины | `primary` | `linearizable` | - | < 100 мс |
| **carts** | Обновление корзины | - | - | `majority` | - |
| **carts** | Слияние корзин | - | - | `majority` | - |

---

## 5. Прямые команды для настройки (mongosh)

### 5.1 Для интерактивных запросов

```javascript
// Чтение с secondary (поиск по категориям)
db.getMongo().setReadPref('secondary')
db.products.find({ category: "electronics" })

// Чтение с primary (проверка остатков)
db.getMongo().setReadPref('primary')
db.products.findOne({ _id: ObjectId("...") }, { stock: 1 })

// Чтение статуса заказа с primary
db.getMongo().setReadPref('primary')
db.orders.findOne({ _id: ObjectId("...") }, { status: 1 })

// Чтение истории заказов с secondary
db.getMongo().setReadPref('secondary')
db.orders.find({ user_id: 12345 }).sort({ order_date: -1 })

// Чтение корзины всегда с primary
db.getMongo().setReadPref('primary')
db.carts.findOne({ user_id: 12345, status: "active" })
```

### 5.2 Для конкретных запросов (без глобальной установки)

```javascript
// Поиск товаров с secondary
db.products.find({ category: "electronics" }).readPref("secondary")

// Проверка остатков с primary
db.products.findOne({ _id: ObjectId("...") }).readPref("primary")

// Статус заказа с primary
db.orders.findOne({ _id: ObjectId("...") }).readPref("primary")

// История заказов с secondary
db.orders.find({ user_id: 12345 }).readPref("secondary").sort({ order_date: -1 })

// Корзина с primary
db.carts.findOne({ user_id: 12345, status: "active" }).readPref("primary")
```

### 5.3 Настройки write concern

```javascript
// Вставка заказа с подтверждением от большинства
db.orders.insertOne(orderData, { writeConcern: { w: "majority" } })

// Обновление остатков товара
db.products.updateOne(
  { _id: ObjectId("...") },
  { $inc: { "stock.msk": -1 } },
  { writeConcern: { w: "majority" } }
)

// Обновление корзины
db.carts.updateOne(
  { user_id: 12345, status: "active" },
  { $push: { items: { product_id: ObjectId("..."), quantity: 1 } } },
  { writeConcern: { w: "majority" } }
)
```

### 5.4 Read concern для строгой консистентности

```javascript
// Линеаризуемое чтение для критичных операций
db.products.findOne(
  { _id: ObjectId("...") },
  { stock: 1 }
).readConcern("linearizable").readPref("primary")

db.orders.findOne(
  { _id: ObjectId("...") },
  { status: 1 }
).readConcern("linearizable").readPref("primary")

db.carts.findOne(
  { user_id: 12345, status: "active" }
).readConcern("linearizable").readPref("primary")
```

---

## 6. Мониторинг задержки репликации

```javascript
// Проверка задержки репликации
db.adminCommand({ replSetGetStatus: 1 }).members.forEach(member => {
  print(`${member.name}: ${member.optimeDate}`);
});

// Проверка отставания secondary
db.adminCommand({ replSetGetStatus: 1 }).members
  .filter(m => m.stateStr === "SECONDARY")
  .forEach(s => {
    print(`Secondary ${s.name}: отставание ${s.optimeDate - s.primaryOptimeDate}ms`);
  });
```

---

## 7. Полный скрипт настройки для Windows (с учетом compose.yaml)

```batch
@echo off
chcp 65001 >nul
title Полная настройка MongoDB с 1000 товаров

echo ============================================================
echo    ПОЛНАЯ НАСТРОЙКА MONGODB С 1000 ТОВАРОВ
echo ============================================================
echo.

REM Проверка наличия docker-compose
where docker-compose >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] docker-compose не найден. Убедитесь, что Docker установлен.
    pause
    exit /b 1
)

REM Проверка запущенных контейнеров
echo Проверка доступности mongos...
docker compose ps mongos | findstr "Up" >nul
if %errorlevel% neq 0 (
    echo [ERROR] mongos не запущен. Запустите контейнеры командой:
    echo docker compose up -d
    pause
    exit /b 1
)
echo [OK] mongos доступен
echo.

REM ============================================================
REM Создание JS файла построчно с экранированием
REM ============================================================
echo Создание setup.js...

if exist setup.js del setup.js

echo // Полный скрипт настройки MongoDB > setup.js
echo // ============================================== >> setup.js
echo. >> setup.js
echo // 1. Подключение к базе данных >> setup.js
echo db = db.getSiblingDB('mobile_mir'); >> setup.js
echo. >> setup.js
echo // 2. Очистка существующих коллекций >> setup.js
echo db.products.drop(); >> setup.js
echo db.orders.drop(); >> setup.js
echo db.carts.drop(); >> setup.js
echo. >> setup.js
echo // 3. Создание коллекций >> setup.js
echo db.createCollection('products'); >> setup.js
echo db.createCollection('orders'); >> setup.js
echo db.createCollection('carts'); >> setup.js
echo. >> setup.js
echo // 4. Настройка шардирования >> setup.js
echo sh.enableSharding('mobile_mir'); >> setup.js
echo sh.shardCollection('mobile_mir.products', { category: 1, _id: 1 }); >> setup.js
echo sh.shardCollection('mobile_mir.orders', { user_id: 'hashed', _id: 1 }); >> setup.js
echo sh.shardCollection('mobile_mir.carts', { user_id: 1, session_id: 1, _id: 1 }); >> setup.js
echo. >> setup.js
echo // 5. Создание индексов >> setup.js
echo db.products.createIndex({ category: 1, price: 1 }); >> setup.js
echo db.products.createIndex({ name: 1 }); >> setup.js
echo db.orders.createIndex({ user_id: 1, order_date: -1 }); >> setup.js
echo db.orders.createIndex({ status: 1, order_date: 1 }); >> setup.js
echo db.orders.createIndex({ geo_zone: 1, order_date: -1 }); >> setup.js
echo db.carts.createIndex({ user_id: 1, status: 1 }); >> setup.js
echo db.carts.createIndex({ session_id: 1, status: 1 }); >> setup.js
echo db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 }); >> setup.js
echo. >> setup.js
echo // 6. Генерация 1000 товаров >> setup.js
echo var products = []; >> setup.js
echo var categories = ['electronics','audio','books','home','sports','toys','clothing','tools']; >> setup.js
echo for (var i = 1; i ^<= 1000; i++) { >> setup.js
echo   var cat = categories[Math.floor(Math.random() * categories.length)]; >> setup.js
echo   products.push({ >> setup.js
echo     name: 'Товар ' + i, >> setup.js
echo     category: cat, >> setup.js
echo     price: Math.floor(Math.random() * 90000) + 1000, >> setup.js
echo     stock: { msk: Math.floor(Math.random() * 100) + 10, spb: Math.floor(Math.random() * 80) + 5 } >> setup.js
echo   }); >> setup.js
echo   if (i %% 100 == 0) { >> setup.js
echo     db.products.insertMany(products); >> setup.js
echo     products = []; >> setup.js
echo     print('Добавлено ' + i + ' товаров'); >> setup.js
echo   } >> setup.js
echo } >> setup.js
echo if (products.length ^> 0) { db.products.insertMany(products); } >> setup.js
echo. >> setup.js
echo // 7. Создание заказов >> setup.js
echo var p = db.products.find().toArray(); >> setup.js
echo for (var i = 0; i ^< 20; i++) { >> setup.js
echo   var prod = p[Math.floor(Math.random() * p.length)]; >> setup.js
echo   db.orders.insertOne({ >> setup.js
echo     user_id: 1000 + i, >> setup.js
echo     order_date: new Date(), >> setup.js
echo     geo_zone: 'msk', >> setup.js
echo     status: 'new', >> setup.js
echo     items: [{ >> setup.js
echo       product_id: prod._id, >> setup.js
echo       name: prod.name, >> setup.js
echo       price: prod.price, >> setup.js
echo       quantity: 1, >> setup.js
echo       category: prod.category >> setup.js
echo     }], >> setup.js
echo     total_amount: prod.price >> setup.js
echo   }); >> setup.js
echo } >> setup.js
echo print('Заказы созданы'); >> setup.js
echo. >> setup.js
echo // 8. Создание корзин >> setup.js
echo for (var i = 0; i ^< 10; i++) { >> setup.js
echo   var prod = p[Math.floor(Math.random() * p.length)]; >> setup.js
echo   db.carts.insertOne({ >> setup.js
echo     session_id: 'sess_' + i, >> setup.js
echo     status: 'active', >> setup.js
echo     items: [{ product_id: prod._id, quantity: 1 }], >> setup.js
echo     created_at: new Date(), >> setup.js
echo     updated_at: new Date(), >> setup.js
echo     expires_at: new Date(Date.now() + 7*24*60*60*1000) >> setup.js
echo   }); >> setup.js
echo } >> setup.js
echo print('Корзины созданы'); >> setup.js
echo. >> setup.js
echo // 9. Итоговая статистика >> setup.js
echo var totalProducts = db.products.countDocuments(); >> setup.js
echo var totalOrders = db.orders.countDocuments(); >> setup.js
echo var totalCarts = db.carts.countDocuments(); >> setup.js
echo print('========================================'); >> setup.js
echo print('Товаров: ' + totalProducts); >> setup.js
echo print('Заказов: ' + totalOrders); >> setup.js
echo print('Корзин: ' + totalCarts); >> setup.js
echo print('========================================'); >> setup.js

echo [OK] setup.js создан
dir setup.js | find "setup.js"
echo.

REM ============================================================
REM Копирование и запуск скрипта
REM ============================================================
echo Копирование файла в контейнер...
docker compose cp setup.js mongos:/setup.js

echo.
echo Запуск скрипта в MongoDB...
echo ============================================================
docker compose exec mongos mongosh --port 27017 /setup.js
echo ============================================================
echo.

REM ============================================================
REM Удаление временного файла
REM ============================================================
echo Удаление временного файла...
del setup.js
echo.

REM ============================================================
REM Проверка списка шардов
REM ============================================================
echo 6. Проверка списка шардов...
echo.
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db.adminCommand({ listShards: 1 }).shards.forEach(function(shard) { print(shard._id + ': ' + shard.host); });"
echo.

REM ============================================================
REM Проверка распределения шардов
REM ============================================================
echo 7. Проверка распределения шардов...
echo.
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.status()" | findstr "shard"
echo.

REM ============================================================
REM Демонстрация различных типов запросов (исправленная версия)
REM ============================================================
echo 8. Демонстрация запросов с разными read preference...
echo.

echo --- Запрос 1: Поиск товаров (secondary) ---
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db = db.getSiblingDB('mobile_mir'); db.getMongo().setReadPref('secondary'); db.products.find({ category: 'electronics' }, { name: 1, price: 1 }).limit(3).forEach(printjson);"
echo.

echo --- Запрос 2: Проверка остатков (primary) ---
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db = db.getSiblingDB('mobile_mir'); db.getMongo().setReadPref('primary'); db.products.findOne({}, { name: 1, stock: 1 });"
echo.

echo --- Запрос 3: История заказов (secondary) ---
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db = db.getSiblingDB('mobile_mir'); db.getMongo().setReadPref('secondary'); db.orders.find({ user_id: 1001 }).sort({ order_date: -1 }).limit(1).forEach(printjson);"
echo.

echo --- Запрос 4: Корзина пользователя (primary) ---
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db = db.getSiblingDB('mobile_mir'); db.getMongo().setReadPref('primary'); db.carts.findOne({ session_id: 'sess_0', status: 'active' });"
echo.

REM ============================================================
REM Итоговая информация
REM ============================================================
echo ============================================================
echo    НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО
echo ============================================================
echo.
echo Краткая инструкция по использованию:
echo ----------------------------------------
echo 1. Для поиска товаров (secondary):
echo    db.getMongo().setReadPref('secondary'); db.products.find({ category: "electronics" })
echo.
echo 2. Для проверки остатков (primary):
echo    db.getMongo().setReadPref('primary'); db.products.findOne({ _id: ObjectId("...") }, { stock: 1 })
echo.
echo 3. Для статуса заказа (primary):
echo    db.getMongo().setReadPref('primary'); db.orders.findOne({ _id: ObjectId("...") }, { status: 1 })
echo.
echo 4. Для истории заказов (secondary):
echo    db.getMongo().setReadPref('secondary'); db.orders.find({ user_id: 12345 }).sort({ order_date: -1 })
echo.
echo 5. Для корзины (primary):
echo    db.getMongo().setReadPref('primary'); db.carts.findOne({ user_id: 12345, status: "active" })
echo.
echo 6. Для проверки списка шардов:
echo    db.adminCommand({ listShards: 1 })
echo.

pause
```

---

## 8. Обоснование выбора

### 8.1 Почему secondary для поиска товаров?

- **Нагрузка:** Поиск по категориям — самая частая операция (70% запросов)
- **Консистентность:** Пользователю не критично увидеть товар, добавленный 5 секунд назад
- **Производительность:** Разгружаем primary для критичных операций

### 8.2 Почему primary для проверки остатков?

- **Бизнес-риск:** Продажа товара, которого нет в наличии, ведёт к:
  - Невозможности выполнить заказ
  - Потере доверия клиентов
  - Дополнительным затратам на компенсации
- **Решение:** Читаем с primary с `linearizable` read concern

### 8.3 Почему primary для статуса заказа?

- **Пользовательский опыт:** Клиент активно отслеживает статус
- **Бизнес-логика:** Статус влияет на следующие действия (оплата, отмена)
- **Решение:** Читаем с primary, допустимая задержка < 1 секунды

### 8.4 Почему primary для корзины?

- **Критичность:** Корзина — основа для заказа
- **Параллельные изменения:** Пользователь может одновременно работать с корзиной в разных вкладках
- **Решение:** Только primary с `linearizable` read concern

---

## 9. Заключение

Предложенная стратегия чтения обеспечивает:
1. **Максимальную производительность** для некритичных операций
2. **Строгую консистентность** для критичных бизнес-операций
3. **Баланс нагрузки** между primary и secondary
4. **Защиту от бизнес-рисков** (overselling, неверный статус)

Допустимые задержки репликации обоснованы бизнес-логикой и техническими требованиями каждой операции.