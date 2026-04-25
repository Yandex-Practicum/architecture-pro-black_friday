# mongo-sharding

MongoDB с шардированием (2 шарда) для приложения «Мобильный мир».

## Архитектура

- **configSrv** — конфигурационный сервер (replica set `config_server`, порт 27019)
- **shard1** — первый шард (replica set `shard1`, порт 27018)
- **shard2** — второй шард (replica set `shard2`, порт 27018)
- **mongos_router** — маршрутизатор запросов (порт 27017)
- **pymongo_api** — приложение (порт 8080)

## Запуск

### 1. Запустить все сервисы

```bash
docker compose up -d
```

### 2. Дождаться запуска всех контейнеров

```bash
docker compose ps
```

Убедитесь, что все 5 сервисов в статусе `running`.

### 3. Инициализировать шардирование и заполнить данными

```bash
./scripts/init-sharding.sh
```

Скрипт выполняет:
1. Инициализацию replica set конфигурационного сервера
2. Инициализацию replica set для каждого шарда
3. Добавление шардов в маршрутизатор
4. Включение шардирования для БД `somedb`
5. Шардирование коллекции `helloDoc` по ключу `{ _id: "hashed" }`
6. Вставку 1000 тестовых документов
7. Проверку распределения данных по шардам

## Проверка

Откройте в браузере: http://localhost:8080

Приложение отобразит JSON с информацией о:
- Топологии MongoDB (тип: `Sharded`)
- Коллекциях и количестве документов (≥ 1000)
- Шардах и их хостах

### Проверка количества документов на каждом шарде

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Остановка

```bash
docker compose down -v
```
