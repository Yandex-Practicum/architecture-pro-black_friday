# pymongo-api — MongoDB: шардирование, репликация, кеширование

## Структура проекта

```
├── api_app/                    # Исходное приложение (FastAPI + Motor)
├── compose.yaml                # Исходный docker compose (1 MongoDB + приложение)
├── scripts/mongo-init.sh       # Скрипт заполнения БД
│
├── mongo-sharding/             # Задание 2: шардирование (2 шарда)
├── mongo-sharding-repl/        # Задание 3: шардирование + репликация (по 3 реплики)
├── sharding-repl-cache/        # Задание 4: шардирование + репликация + Redis-кеш
│
├── Task 1.1 - Sharding.svg  # Задание 1, этап 1: схема шардирования
├── Task 1.2 - Replication.svg  # Задание 1, этап 2: схема репликации
├── Task 1.3 - Caching.svg   # Задание 1, этап 3: схема кеширования
├── Task 1.4 - Service Discovery.svg  # Задание 5: API Gateway + Consul
├── Task 1.5 - CDN.svg       # Задание 6: CDN
│
├── Task 7 - Sharding Design.md   # Задание 7: проектирование коллекций
├── Task 8 - Hot Shards.md        # Задание 8: горячие шарды
├── Task 9 - Read Preferences.md  # Задание 9: чтение с реплик
├── Task 10 - Cassandra.md        # Задание 10: Cassandra
```

---

## Схемы архитектуры

### Этап 1 — Шардирование

![Шардирование](Task%201.1%20Sharding.svg)

### Этап 2 — Репликация

![Репликация](Task%201.2%20Replication.svg)

### Этап 3 — Кеширование

![Кеширование](Task%201.3%20Caching%20Diagram.svg)

### Этап 4 — Service Discovery + API Gateway

![Service Discovery](Task%201.4%20Service%20Discovery.svg)

### Этап 5 — CDN

![CDN](Task%201.5%20CDN.drawio.svg)

---

## Как поднять финальный стенд (sharding-repl-cache)

Финальная реализация — `sharding-repl-cache/`: шардированный кластер MongoDB с репликацией и Redis-кешированием.

### 1. Перейти в директорию

```bash
cd sharding-repl-cache
```

### 2. Поднять контейнеры

```bash
docker compose up -d
```

Будет запущено 11 контейнеров:
- `configsvr1`, `configsvr2`, `configsvr3` — Config Server Replica Set
- `shard1-1`, `shard1-2`, `shard1-3` — Shard 1 Replica Set
- `shard2-1`, `shard2-2`, `shard2-3` — Shard 2 Replica Set
- `mongos_router` — маршрутизатор запросов
- `redis` — кеш
- `pymongo_api` — приложение

### 3. Инициализировать кластер

```bash
bash scripts/mongo-init.sh
```

Скрипт выполняет:
1. Инициализацию Replica Set для Config Server (3 узла)
2. Инициализацию Replica Set для Shard 1 (3 узла)
3. Инициализацию Replica Set для Shard 2 (3 узла)
4. Добавление шардов в кластер через mongos
5. Включение шардирования для БД `somedb`
6. Шардирование коллекции `helloDoc` по полю `age` (hashed)
7. Вставку 1000 тестовых документов

### 4. Проверить работу

```bash
# Статус приложения — покажет шарды, реплики, кеш
curl http://localhost:8080/

# Количество документов
curl http://localhost:8080/helloDoc/count

# Первый запрос — медленный (~1 сек, данные из MongoDB)
time curl http://localhost:8080/helloDoc/users

# Повторный запрос — быстрый (данные из Redis-кеша, TTL 60 сек)
time curl http://localhost:8080/helloDoc/users
```

Дополнительные проверки:

```bash
# Статус Replica Set для shard1
docker compose exec shard1-1 mongosh --port 27017 --eval "rs.status()"

# Статус Replica Set для shard2
docker compose exec shard2-1 mongosh --port 27017 --eval "rs.status()"

# Распределение данных по шардам
docker compose exec mongos_router mongosh --port 27017 --eval "use somedb; db.helloDoc.getShardDistribution()"
```

### 5. Остановка

```bash
docker compose down -v
```

---

## Промежуточные стенды

### Задание 2 — только шардирование

```bash
cd mongo-sharding
docker compose up -d
bash scripts/mongo-init.sh
curl http://localhost:8080/
```

### Задание 3 — шардирование + репликация

```bash
cd mongo-sharding-repl
docker compose up -d
bash scripts/mongo-init.sh
curl http://localhost:8080/
```

---

## Доступные эндпоинты

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/` | Статус: топология, шарды, реплики, кеш |
| GET | `/{collection}/count` | Количество документов в коллекции |
| GET | `/{collection}/users` | Список пользователей (кешируется 60 сек) |
| GET | `/{collection}/users/{name}` | Поиск пользователя по имени |
| POST | `/{collection}/users` | Создание пользователя |

Swagger: http://localhost:8080/docs
