# Проектная работа: онлайн-магазин «Мобильный мир»

Проект по настройке шардирования, репликации и кеширования MongoDB для повышения производительности и отказоустойчивости.

## Структура репозитория

```
├── api_app/                    # Исходное приложение pymongo-api
├── scripts/                    # Скрипты для исходного приложения
├── mongo-sharding/             # Задание 2: шардирование (2 шарда)
├── mongo-sharding-repl/        # Задание 3: шардирование + репликация
├── sharding-repl-cache/        # Задание 4: шардирование + репликация + Redis кеш
├── task1.drawio                # Задания 1, 5, 6: архитектурные схемы (5 вариантов)
├── architecture-document.md    # Задания 7-10: архитектурный документ
└── README.md                   # Этот файл
```

## Быстрый старт (финальная версия — sharding-repl-cache)

Для проверки финальной реализации MongoDB с шардированием, репликацией и кешированием:

### 1. Запуск проекта

```shell
cd sharding-repl-cache
docker compose up -d
```

Проверьте, что все сервисы запущены:
```shell
docker compose ps
```

### 2. Инициализация кластера

```shell
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт автоматически:
- Инициализирует Config Server Replica Set
- Инициализирует Shard1 Replica Set (3 реплики: shard1-1, shard1-2, shard1-3)
- Инициализирует Shard2 Replica Set (3 реплики: shard2-1, shard2-2, shard2-3)
- Добавляет шарды в кластер через mongos
- Включает шардирование для БД `somedb` и коллекции `helloDoc` (shard key: `{ "age": "hashed" }`)
- Вставляет 1000 тестовых документов
- Проверяет распределение данных и статус реплик

### 3. Проверка

Откройте в браузере: **http://localhost:8080**

В JSON-ответе должно отображаться:
- `mongo_topology_type`: "Sharded"
- `collections.helloDoc.documents_count`: >= 1000
- `shards`: информация о двух шардах (shard1, shard2)
- `cache_enabled`: true

### 4. Проверка кеширования

```shell
# Первый запрос (~1 сек — данные из MongoDB)
curl -w '\nВремя: %{time_total}s\n' http://localhost:8080/helloDoc/users

# Второй запрос (< 100мс — данные из кеша Redis)
curl -w '\nВремя: %{time_total}s\n' http://localhost:8080/helloDoc/users
```

### 5. Проверка распределения по шардам

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "use somedb; db.helloDoc.countDocuments()"
```

```shell
docker compose exec -T shard2-1 mongosh --port 27018 --quiet --eval "use somedb; db.helloDoc.countDocuments()"
```

### 6. Проверка реплик

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status().members.forEach(function(m) { print(m.name + ' - ' + m.stateStr) })"
```

## Архитектура финального решения

- **pymongo_api** — приложение (`kazhem/pymongo_api:1.0.0`, порт 8080)
- **mongos_router** — маршрутизатор MongoDB (порт 27017)
- **configSrv** — config server (порт 27019)
- **shard1-1, shard1-2, shard1-3** — первый шард, replica set из 3 нод (порт 27018)
- **shard2-1, shard2-2, shard2-3** — второй шард, replica set из 3 нод (порт 27018)
- **redis** — Redis для кеширования запросов (порт 6379)

## Документация API

Swagger: http://localhost:8080/docs

## Требования

- Docker и Docker Compose
- Минимум 2 CPU и 4 ГБ ОЗУ
