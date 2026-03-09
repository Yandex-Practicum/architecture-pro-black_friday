# Проект mongo-sharding

## Описание
Реализация шардирования MongoDB для повышения производительности.  
В проекте используются следующие сервисы (соответствуют диаграмме):

| Сервис       | Назначение                          |
|--------------|-------------------------------------|
| configSrv    | Конфигурационный сервер             |
| shard1       | Первый шард (реплика-сет rs1)       |
| shard2       | Второй шард (реплика-сет rs2)       |
| mongos       | Роутер (точка входа для приложения) |
| pymongo-api  | Приложение                          |

## Запуск проекта
docker compose up -d

Инициализация шардирования
Все команды выполняются в Windows cmd (DOS).

1. Инициализация конфигурационного сервера
docker compose exec -T configSrv mongosh --port 27019 --quiet ^
--eval "rs.initiate({ _id: \"configSrv\", configsvr: true, members: [{ _id: 0, host: \"configSrv:27019\" }] })"

2. Инициализация репликации для шардов

REM Инициализация rs1 (shard1)
docker compose exec -T shard1 mongosh --port 27018 --quiet ^
--eval "rs.initiate({ _id: \"rs1\", members: [{ _id: 0, host: \"shard1:27018\" }] })"

REM Инициализация rs2 (shard2)
docker compose exec -T shard2 mongosh --port 27018 --quiet ^
--eval "rs.initiate({ _id: \"rs2\", members: [{ _id: 0, host: \"shard2:27018\" }] })"

3. Добавление шардов в кластер через mongos

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.addShard(\"rs1/shard1:27018\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.addShard(\"rs2/shard2:27018\")"
4. Включение шардирования для базы данных и коллекции

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.enableSharding(\"somedb\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "db = db.getSiblingDB(\"somedb\"); db.createCollection(\"helloDoc\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.shardCollection(\"somedb.helloDoc\", { \"_id\": \"hashed\" })"
5. Проверка статуса шардирования

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.status()"
Наполнение тестовыми данными
Приложение pymongo-api НЕ создаёт документы автоматически.
Необходимо выполнить ручное наполнение:


docker compose exec -T mongos mongosh --port 27017 somedb --quiet ^
--eval "use somedb; for (var i = 1; i <= 1000; i++) { db.helloDoc.insert({ name: \"doc\" + i, value: i }) }"
Проверка работы
Общее количество документов (через mongos)

docker compose exec -T mongos mongosh --port 27017 somedb --quiet ^
--eval "db.helloDoc.countDocuments()"
Ожидаемый результат: ≥ 1000

Количество документов на каждом шарде (прямое подключение)

REM Шард shard1
docker compose exec -T shard1 mongosh --port 27018 somedb --quiet ^
--eval "db.helloDoc.countDocuments()"

REM Шард shard2
docker compose exec -T shard2 mongosh --port 27018 somedb --quiet ^
--eval "db.helloDoc.countDocuments()"
Важно: Сумма документов на обоих шардах должна равняться общему количеству, полученному через mongos.

Проверка распределения данных по шардам

docker compose exec -T mongos mongosh --port 27017 somedb --quiet ^
--eval "db.helloDoc.getShardDistribution()"
Эта команда покажет, как именно документы распределены между шардами.

Доступ к приложению
После запуска приложение доступно по адресу:
http://localhost:8080

Что показывает приложение:

Общее количество документов в базе данных somedb (после ручного наполнения)

Возможные проблемы и их решение
1. Ошибка "Cannot start a shardsvr as a standalone server"
Причина: Шарды должны работать как реплика-сеты.
Решение: Добавьте параметр --replSet в команду запуска шардов и выполните инициализацию репликации.

2. Ошибка "Could not find host matching read preference"
Причина: Не инициализирован configSrv или не добавлены шарды.
Решение: Выполнить шаги 1-3 из раздела "Инициализация шардирования".

3. Ошибка "no such command: 'shardCollection'"
Причина: Не включено шардирование для базы данных.
Решение: Выполнить sh.enableSharding("somedb") перед шардированием коллекции.

4. Приложение показывает 0 документов
Причина: Не выполнено наполнение тестовыми данными.
Решение: Выполнить команду из раздела "Наполнение тестовыми данными".

5. Ошибка подключения к mongos
Причина: mongos ещё не готов (стартует дольше других контейнеров).
Решение: Подождать 15-20 секунд и повторить команду.

Остановка и очистка проекта

REM Остановка контейнеров
docker compose down

REM Полная очистка (включая volumes)
docker compose down -v
Полный набор команд для быстрого запуска (одним блоком)
Скопируйте и вставьте в cmd последовательно:


@echo off
chcp 65001 >nul
echo === НАСТРОЙКА ШАРДИРОВАНИЯ ===
echo.

echo 1. Запуск контейнеров...
docker compose up -d
echo Ожидание 30 секунд...
timeout /t 30

echo 2. Инициализация configSrv...
docker compose exec -T configSrv mongosh --port 27019 --quiet --eval "rs.initiate({ _id: 'configSrv', configsvr: true, members: [{ _id: 0, host: 'configSrv:27019' }] })"
timeout /t 5

echo 3. Инициализация репликации для шардов...
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "rs.initiate({ _id: 'rs1', members: [{ _id: 0, host: 'shard1:27018' }] })"
docker compose exec -T shard2 mongosh --port 27018 --quiet --eval "rs.initiate({ _id: 'rs2', members: [{ _id: 0, host: 'shard2:27018' }] })"
timeout /t 10

echo 4. Добавление шардов в кластер...
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('rs1/shard1:27018')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.addShard('rs2/shard2:27018')"
timeout /t 5

echo 5. Настройка шардирования...
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.enableSharding('somedb')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "db = db.getSiblingDB('somedb'); db.createCollection('helloDoc')"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval "sh.shardCollection('somedb.helloDoc', { '_id': 'hashed' })"

echo 6. Заполнение данными...
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "for (var i = 1; i <= 1000; i++) { db.helloDoc.insert({ name: 'doc' + i, value: i }) }"

echo 7. Проверка результатов...
echo.
echo Общее количество документов:
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 1:
docker compose exec -T shard1 mongosh --port 27018 somedb --quiet --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 2:
docker compose exec -T shard2 mongosh --port 27018 somedb --quiet --eval "db.helloDoc.countDocuments()"

echo.
echo === ГОТОВО ===
pause

Структура проекта

mongo-sharding/
├── api_app/               # Директория с приложением
│   ├── Dockerfile
│   └── ... (исходный код)
├── compose.yaml           # Docker Compose файл
└── README.md              # Данный файл
Примечания
Все команды в README рассчитаны на Windows cmd (DOS) с использованием символа продолжения строки ^.

Для Linux/Mac замените ^ на \ и REM на #.

Порт по умолчанию для mongos — 27017, для шардов — 27018, для configSrv — 27019.

Шарды обязательно должны работать как реплика-сеты (параметр --replSet).

Формат добавления шарда: {replSetName}/{host:port}

База данных называется somedb, коллекция — helloDoc.

Для проверки распределения документов используется хэшированный шардинг по полю _id.