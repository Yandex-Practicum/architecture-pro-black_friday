# «Мобильный мир» — pymongo-api

Проект по повышению отказоустойчивости и производительности онлайн-магазина «Мобильный мир».

## Структура репозитория

```
├── compose.yaml                 # Исходный стенд (1 MongoDB + 1 приложение)
├── api_app/                     # Исходный код приложения
├── mongo-sharding/              # Задание 2: шардирование (2 шарда)
├── mongo-sharding-repl/         # Задание 3: шардирование + репликация
├── sharding-repl-cache/         # Задание 4: шардирование + репликация + кеш Redis
├── architecture-schemas.drawio  # Задания 1, 5, 6: схемы архитектуры (5 диаграмм)
├── architecture-document.md     # Задания 7–10: архитектурный документ
└── scripts/                     # Скрипт инициализации исходного стенда
```

## Быстрый старт (финальная версия — sharding-repl-cache)

### Требования

- Docker и Docker Compose
- Минимум 2 CPU и 4 ГБ ОЗУ

### 1. Запуск

```bash
cd sharding-repl-cache
docker compose up -d
```

### 2. Проверка статуса контейнеров

```bash
docker compose ps
```

Убедитесь, что все 14 сервисов в статусе `running`:
- `configSrv1`, `configSrv2`, `configSrv3` — конфигурационный сервер (replica set)
- `shard1-1`, `shard1-2`, `shard1-3` — шард 1 (replica set)
- `shard2-1`, `shard2-2`, `shard2-3` — шард 2 (replica set)
- `mongos_router` — маршрутизатор
- `redis` — кеш
- `pymongo_api` — приложение

### 3. Инициализация MongoDB и загрузка данных

```bash
./scripts/init-sharding-repl-cache.sh
```

Скрипт автоматически:
- Инициализирует replica set конфигурационного сервера (3 члена)
- Инициализирует replica set для каждого шарда (по 3 члена)
- Добавляет шарды в маршрутизатор
- Включает шардирование для БД `somedb`
- Шардирует коллекцию `helloDoc` по ключу `{ _id: "hashed" }`
- Вставляет 1000 тестовых документов
- Проверяет распределение данных и статус реплик

### 4. Проверка

Откройте в браузере: http://localhost:8080

Приложение отобразит JSON с информацией:
- `mongo_topology_type`: `Sharded`
- `collections.helloDoc.documents_count`: ≥ 1000
- `shards`: два шарда с хостами
- `cache_enabled`: `true`

### 5. Проверка кеширования

```bash
# Первый запрос (~1 секунда, данные из MongoDB)
time curl -s http://localhost:8080/helloDoc/users > /dev/null

# Второй запрос (<100 мс, данные из Redis-кеша)
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

### 6. Проверка количества документов на шардах

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

### 7. Проверка статуса репликации

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.map(m => ({name: m.name, state: m.stateStr}))
EOF
```

## Остановка

```bash
docker compose down -v
```

## Доступные эндпоинты

- http://localhost:8080 — статус MongoDB (топология, шарды, реплики, кеш)
- http://localhost:8080/docs — Swagger документация API
- http://localhost:8080/helloDoc/users — список пользователей (кешируется)
- http://localhost:8080/helloDoc/count — количество документов

## Исходный стенд (без шардирования)

```bash
# В корне репозитория
docker compose up -d
./scripts/mongo-init.sh
```
