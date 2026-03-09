# Проект mongo-sharding-repl

## Описание
Реализация шардирования MongoDB с **репликацией для каждого шарда**.  
Соответствует **шагу 2** схемы проектной работы.

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
| pymongo-api  | Приложение                          |

## Запуск проекта
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
--eval "db = db.getSiblingDB(\"somedb\"); db.createCollection(\"helloDoc\")"

docker compose exec -T mongos mongosh --port 27017 --quiet ^
--eval "sh.shardCollection(\"somedb.helloDoc\", { \"_id\": \"hashed\" })"
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

Количество документов на PRIMARY шарда 1

docker compose exec -T shard11 mongosh --port 27018 somedb --quiet ^
--eval "db.helloDoc.countDocuments()"
Количество документов на PRIMARY шарда 2

docker compose exec -T shard21 mongosh --port 27018 somedb --quiet ^
--eval "db.helloDoc.countDocuments()"
Количество документов на SECONDARY шарда 1 (с опцией чтения)

docker compose exec -T shard12 mongosh --port 27018 somedb --quiet ^
--eval "db.getMongo().setReadPref('secondary'); db.helloDoc.countDocuments()"
Проверка статуса репликации

REM Статус rs1
docker compose exec -T shard11 mongosh --port 27018 --quiet --eval "rs.status()"

REM Статус rs2
docker compose exec -T shard21 mongosh --port 27018 --quiet --eval "rs.status()"
Проверка распределения данных по шардам

docker compose exec -T mongos mongosh --port 27017 somedb --quiet ^
--eval "db.helloDoc.getShardDistribution()"
Доступ к приложению
После запуска приложение доступно по адресу:
http://localhost:8080

Что показывает приложение:

Общее количество документов в базе данных somedb (после ручного наполнения)

Проверка отказоустойчивости
1. Определите PRIMARY в rs1

docker compose exec -T shard11 mongosh --port 27018 --quiet --eval "rs.isMaster().primary"
2. Остановите PRIMARY (например, если это shard11)

docker stop shard11
3. Проверьте, что выбран новый PRIMARY

docker compose exec -T shard12 mongosh --port 27018 --quiet --eval "rs.isMaster().primary"
4. Проверьте, что данные доступны через mongos

docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "db.helloDoc.countDocuments()"
5. Запустите остановленный узел обратно

docker start shard11
Возможные проблемы и их решение
1. Ошибка "Cannot start a shardsvr as a standalone server"
Причина: Шарды должны работать как реплика-сеты.
Решение: Добавьте параметр --replSet в команду запуска шардов и выполните инициализацию репликации.

2. Ошибка "Could not find host matching read preference"
Причина: Не инициализирован configSrv или не добавлены шарды.
Решение: Выполнить шаги 1-5 из раздела "Инициализация репликации и шардирования".

3. Ошибка "no such command: 'shardCollection'"
Причина: Не включено шардирование для базы данных.
Решение: Выполнить sh.enableSharding("somedb") перед шардированием коллекции.

4. Приложение показывает 0 документов
Причина: Не выполнено наполнение тестовыми данными.
Решение: Выполнить команду из раздела "Наполнение тестовыми данными".

5. Ошибка подключения к mongos
Причина: mongos ещё не готов (стартует дольше других контейнеров).
Решение: Подождать 15-20 секунд и повторить команду.

Полный bat-скрипт для автоматизации
Сохраните как setup-repl.bat и запустите в cmd:


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

echo 8. Проверка результатов...
echo.
echo Общее количество документов:
docker compose exec -T mongos mongosh --port 27017 somedb --quiet --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 1 (Primary):
docker compose exec -T shard11 mongosh --port 27018 somedb --quiet --eval "db.helloDoc.countDocuments()"
echo.
echo Шард 2 (Primary):
docker compose exec -T shard21 mongosh --port 27018 somedb --quiet --eval "db.helloDoc.countDocuments()"

echo.
echo === ГОТОВО ===
pause
Остановка и очистка проекта

REM Остановка контейнеров
docker compose down

REM Полная очистка (включая volumes)
docker compose down -v
Структура проекта

mongo-sharding-repl/
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

Формат добавления шарда: {replSetName}/{host1:port,host2:port,host3:port}

База данных называется somedb, коллекция — helloDoc.

Для проверки secondary используется setReadPref('secondary').

Для проверки распределения документов используется хэшированный шардинг по полю _id.

