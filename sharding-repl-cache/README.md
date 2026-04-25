# sharding-repl-cache

MongoDB с шардированием, репликацией и кешированием Redis для приложения «Мобильный мир».

## Архитектура

- **configSrv1, configSrv2, configSrv3** — конфигурационный сервер (replica set `config_server`, порт 27019)
- **shard1-1, shard1-2, shard1-3** — первый шард (replica set `shard1`, порт 27018)
- **shard2-1, shard2-2, shard2-3** — второй шард (replica set `shard2`, порт 27018)
- **mongos_router** — маршрутизатор запросов (порт 27017)
- **redis** — кеш Redis (порт 6379)
- **pymongo_api** — приложение (порт 8080)

Всего: 14 контейнеров.

## Запуск

### 1. Запустить все сервисы

```bash
docker compose up -d
```

### 2. Дождаться запуска всех контейнеров

```bash
docker compose ps
```

Убедитесь, что все 14 сервисов в статусе `running`.

### 3. Инициализировать шардирование, репликацию и заполнить данными

```bash
./scripts/init-sharding-repl-cache.sh
```

Скрипт выполняет:
1. Инициализацию replica set конфигурационного сервера (3 члена)
2. Инициализацию replica set для shard1 (3 члена)
3. Инициализацию replica set для shard2 (3 члена)
4. Добавление шардов в маршрутизатор
5. Включение шардирования для БД `somedb`
6. Шардирование коллекции `helloDoc` по ключу `{ _id: "hashed" }`
7. Вставку 1000 тестовых документов
8. Проверку распределения данных и статуса реплик
9. Проверку доступности Redis

## Проверка

### Основная информация

Откройте в браузере: http://localhost:8080

Приложение отобразит JSON с информацией о:
- Топологии MongoDB (тип: `Sharded`)
- Коллекциях и количестве документов (≥ 1000)
- Шардах и их хостах
- Статусе кеша (`cache_enabled: true`)

### Проверка количества документов на шардах

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

### Проверка статуса репликации

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.map(m => ({name: m.name, state: m.stateStr}))
EOF
```

### Проверка кеширования

Выполните запрос к эндпоинту `/helloDoc/users` дважды:

```bash
# Первый запрос (~ 1 секунда, данные из MongoDB)
time curl -s http://localhost:8080/helloDoc/users > /dev/null

# Второй запрос (< 100 мс, данные из кеша Redis)
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

Второй и последующие запросы должны выполняться значительно быстрее (< 100 мс), так как данные возвращаются из Redis-кеша.

## Остановка

```bash
docker compose down -v
```
