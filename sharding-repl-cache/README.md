# Проект sharding-repl-cache

## Описание
Реализация шардирования MongoDB с **репликацией для каждого шарда** и **кешированием через Redis**.  
Соответствует **шагу 3** схемы проектной работы.

В проекте используются следующие сервисы:

| Сервис       | Назначение                          |
|--------------|-------------------------------------|
| configSrv    | Конфигурационный сервер (1 узел)    |
| shard11      | Шард 1 - узел 1 (Primary/Secondary) |
| shard12      | Шард 1 - узел 2 (Secondary)         |
| shard13      | Шард 1 - узел 3 (Secondary)         |
| shard21      | Шард 2 - узел 1 (Primary/Secondary) |
| shard22      | Шард 2 - узел 2 (Secondary)         |
| shard23      | Шард 2 - узел 3 (Secondary)         |
| mongos       | Роутер (точка входа для приложения) |
| redis        | Кеш (in-memory хранилище)           |
| pymongo-api  | Приложение с поддержкой кеширования |

## Требования к данным
Приложение ожидает в коллекции `helloDoc` документы со следующей структурой:

{
  "_id": ObjectId,
  "name": "string",
  "age": number,
  "email": "string"
}
Запуск проекта
bash
docker compose up -d
Инициализация репликации и шардирования
Все команды выполняются в Windows cmd (DOS).

1. Инициализация конфигурационного сервера

docker compose exec -T configSrv mongosh --port 27019 --quiet ^
--eval "rs.initiate({ _id: \"configSrv\", configsvr: true, members: [{ _id: 0, host: \"configSrv:27019\" }] })"
2. Инициализация реплика-сета для шарда 1 (rs1)

docker compose exec -T shard11 mongosh --port 27018 --quiet ^
--eval "rs.initiate({ _id: \"rs1\", members: [{ _id: 0, host: \"shard11:27018\" }, { _id: 1, host: \"shard12:27018\" }, { _id: 2, host: \"shard13:27018\" }] })"
3. Инициализация реплика-сета для шарда 2 (rs2)

docker compose exec -T shard21 mongosh --port 27018 --quiet ^
--eval "rs.initiate({ _id: \"rs2\", members: [{ _id: 0, host: \"shard21:27018\" }, { _id: 1, host: \"shard22:27018\" }, { _id: 2, host: \"shard23:27018\" }] })"
4. Ожидание выбора Primary (30 секунд)

timeout /t 30
5. Добавление шардов в кластер через mongos

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.addShard(\"rs1/shard11:27018,shard12:27018,shard13:27018\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.addShard(\"rs2/shard21:27018,shard22:27018,shard23:27018\")"
6. Проверка статуса шардирования

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.status()"
7. Включение шардирования для базы данных и коллекции

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.enableSharding(\"somedb\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "db.getSiblingDB(\"somedb\").createCollection(\"helloDoc\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.shardCollection(\"somedb.helloDoc\", { \"_id\": \"hashed\" })"
Наполнение тестовыми данными

docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "
var firstNames = ['John', 'Jane', 'Bob', 'Alice', 'Mike', 'Emma', 'David', 'Sarah', 'Tom', 'Lisa'];
var lastNames = ['Smith', 'Johnson', 'Brown', 'Taylor', 'Wilson', 'Davis', 'Miller', 'Jones', 'Garcia', 'Rodriguez'];
for (var i = 1; i <= 1000; i++) {
  var firstName = firstNames[Math.floor(Math.random() * firstNames.length)];
  var lastName = lastNames[Math.floor(Math.random() * lastNames.length)];
  db.helloDoc.insert({
    name: firstName + ' ' + lastName,
    age: Math.floor(Math.random() * 50) + 18,
    email: firstName.toLowerCase() + '.' + lastName.toLowerCase() + i + '@example.com'
  });
}
print('Добавлено 1000 документов с полями name, age, email');
"
Проверка работы приложения
Общее количество документов

curl http://localhost:8080
Или откройте в браузере: http://localhost:8080

Проверка структуры данных

docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "db.helloDoc.findOne()"
Проверка кеширования эндпоинта /helloDoc/users
Первый запрос (без кеша, обращение к MongoDB)

curl -w "\nВремя: %{time_total} сек\n" http://localhost:8080/helloDoc/users
Ожидаем: ~200-500 мс

Второй запрос (с кешем)

curl -w "\nВремя: %{time_total} сек\n" http://localhost:8080/helloDoc/users
Ожидаем: < 100 мс

Третий запрос (с кешем)

curl -w "\nВремя: %{time_total} сек\n" http://localhost:8080/helloDoc/users
Проверка заголовков кеша

curl -I http://localhost:8080/helloDoc/users
Должны увидеть заголовки:

X-Cache: HIT или MISS

X-Query-Time (при MISS)

Проверка формата ответа

curl http://localhost:8080/helloDoc/users | python -m json.tool
Должен быть JSON вида:

json
{
  "users": [
    {
      "_id": "...",
      "age": 25,
      "name": "John Smith"
    }
  ]
}
Проверка репликации
Статус репликации rs1

docker compose exec -T shard11 mongosh --port 27018 --quiet --eval "rs.status()"
Статус репликации rs2

docker compose exec -T shard21 mongosh --port 27018 --quiet --eval "rs.status()"
Чтение со secondary

docker compose exec -T shard12 mongosh --port 27018 somedb --quiet ^
--eval "db.getMongo().setReadPref('secondary'); db.helloDoc.countDocuments()"
Проверка распределения данных по шардам

docker compose exec -T mongos mongosh --port 27017 somedb --quiet ^
--eval "db.helloDoc.getShardDistribution()"
Проверка кеша в Redis
Просмотр ключей кеша

docker compose exec redis redis-cli --scan --pattern "users:*"
Статистика Redis

docker compose exec redis redis-cli info stats | findstr "keyspace_hits keyspace_misses"
Проверка отказоустойчивости
1. Определите PRIMARY в rs1

docker compose exec -T shard11 mongosh --port 27018 --quiet --eval "rs.isMaster().primary"
2. Остановите PRIMARY (например, если это shard11)

docker stop shard11
timeout /t 10
3. Проверьте, что выбран новый PRIMARY

docker compose exec -T shard12 mongosh --port 27018 --quiet --eval "rs.isMaster().primary"
4. Проверьте, что данные доступны через приложение

curl http://localhost:8080
curl -I http://localhost:8080/helloDoc/users
5. Запустите остановленный узел обратно

docker start shard11
Полный bat-скрипт для автоматизации
Сохраните как setup-cache.bat и запустите в cmd:


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

echo 7. Заполнение данными (1000 документов с name, age, email)...
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "var firstNames = ['John','Jane','Bob','Alice','Mike','Emma','David','Sarah','Tom','Lisa']; var lastNames = ['Smith','Johnson','Brown','Taylor','Wilson','Davis','Miller','Jones','Garcia','Rodriguez']; for (var i = 1; i <= 1000; i++) { var firstName = firstNames[Math.floor(Math.random() * firstNames.length)]; var lastName = lastNames[Math.floor(Math.random() * lastNames.length)]; db.helloDoc.insert({ name: firstName + ' ' + lastName, age: Math.floor(Math.random() * 50) + 18, email: firstName.toLowerCase() + '.' + lastName.toLowerCase() + i + '@example.com' }); } print('Добавлено 1000 документов');"

echo 8. Проверка приложения...
echo Общее количество документов:
curl -s http://localhost:8080
echo.
echo 9. Проверка кеширования эндпоинта /helloDoc/users...
echo.
echo --- Первый запрос (без кеша) ---
curl -w "Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo --- Второй запрос (с кешем) ---
curl -w "Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo --- Третий запрос (с кешем) ---
curl -w "Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul

echo.
echo 10. Проверка заголовков кеша:
curl -I http://localhost:8080/helloDoc/users 2>nul | findstr "X-Cache"

echo.
echo === ГОТОВО ===
pause
Скрипт для тестирования производительности
Сохраните как benchmark.bat:


@echo off
chcp 65001 >nul
echo ========================================
echo    ТЕСТИРОВАНИЕ ПРОИЗВОДИТЕЛЬНОСТИ КЕША
echo ========================================
echo.

echo 1. Очистка кеша Redis...
docker compose exec redis redis-cli flushall
timeout /t 2

echo 2. Прогрев (первый запрос - без кеша)...
curl -s http://localhost:8080/helloDoc/users -o nul
echo.

echo 3. Тестовые запросы:
echo ------------------------
echo Запрос 1 (без кеша):
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo.
echo Запрос 2 (с кешем):
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo.
echo Запрос 3 (с кешем):
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo.
echo Запрос 4 (с кешем):
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo.
echo Запрос 5 (с кешем):
curl -w "  Время: %%{time_total} сек\n" -s http://localhost:8080/helloDoc/users -o nul
echo.

echo ------------------------
echo.
echo 4. Проверка заголовков:
curl -I http://localhost:8080/helloDoc/users 2>nul | findstr "X-Cache"
echo.
echo 5. Статистика Redis:
docker compose exec redis redis-cli info stats | findstr "keyspace_hits keyspace_misses"
echo.
pause
Остановка и очистка проекта

REM Остановка контейнеров
docker compose down

REM Полная очистка (включая volumes)
docker compose down -v
Структура проекта

sharding-repl-cache/
├── api_app/               # Директория с приложением (НЕ ИЗМЕНЯТЬ)
│   ├── Dockerfile
│   └── app.py
├── compose.yaml           # Docker Compose файл
├── setup-cache.bat        # Скрипт автоматической настройки
├── benchmark.bat          # Скрипт тестирования производительности
└── README.md              # Данный файл
Примечания
Все команды рассчитаны на Windows cmd (DOS)

Порт mongos: 27017, шардов: 27018, configSrv: 27019, Redis: 6379

Коллекция для кеширования: helloDoc

Эндпоинт с кешированием: GET /helloDoc/users

Формат ответа: {"users": [{"_id": "...", "age": 0, "name": "..."}]}

Ограничение результатов: 1000 документов

Время жизни кеша (TTL): 60 секунд

Заголовки ответа: X-Cache (HIT/MISS) и X-Query-Time