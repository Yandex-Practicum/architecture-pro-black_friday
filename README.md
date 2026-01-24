# Проектная работа 4 спринта - "Мобильный мир"

Проект высоконагруженного интернет-магазина "Мобильный мир" с подготовкой к "Черной пятнице".

## Структура проекта

```
architecture-pro-black_friday/
├── api_app/                    # Исходное приложение (PoC)
├── mongo-sharding/             # Задание 2: Шардирование MongoDB
├── mongo-sharding-repl/        # Задание 3: Шардирование + Репликация
├── sharding-repl-cache/        # Задание 4: Финальная реализация (Шардирование + Репликация + Redis Cache)
└── tasks/
    ├── task_1/                 # Задание 1: Архитектурные схемы (3 варианта)
    ├── task_5/                 # Задание 5: API Gateway + Consul
    └── task_6/                 # Задание 6: CDN
```

## Задания

### ✅ Задание 1: Планирование
Архитектурные схемы в папке `/tasks/task_1/`:
- **Вариант 1**: Шардирование (2 шарда)
- **Вариант 2**: Шардирование + Репликация (3 реплики на шард)
- **Вариант 3**: Шардирование + Репликация + Redis Cache

### ✅ Задание 2: Шардирование
Директория: `/mongo-sharding/`
- 2 шарда MongoDB
- Config Server Replica Set
- Mongos Router

### ✅ Задание 3: Репликация
Директория: `/mongo-sharding-repl/`
- 2 шарда с репликацией (3 реплики на каждый шард)
- Config Server Replica Set (3 узла)
- Автоматический failover

### ✅ Задание 4: Кеширование
Директория: `/sharding-repl-cache/` ⭐ **Финальная реализация**
- 2 шарда с репликацией (3 реплики на каждый шард)
- Config Server Replica Set (3 узла)
- Redis Cache для ускорения повторных запросов
- Кешированные запросы < 100мс

### ✅ Задание 5: API Gateway и Service Discovery
Архитектурная схема в папке `/tasks/task_5/`:
- Consul Cluster (3 узла)
- API Gateway для балансировки
- 3 инстанса API приложения
- Горизонтальное масштабирование

### ✅ Задание 6: CDN
Архитектурная схема в папке `/tasks/task_6/`:
- CDN узлы в 3 регионах (Europe, Asia, Americas)
- Origin Server для статического контента
- Глобальная доставка контента

---

## 🚀 Быстрый старт финальной реализации

### Требования

- Docker и Docker Compose
- Минимум 8 GB RAM
- 10 GB свободного места на диске

### Шаг 1: Запуск инфраструктуры

Перейдите в директорию финальной реализации:

```bash
cd sharding-repl-cache
```

Запустите все контейнеры:

```bash
docker compose up -d
```

Это запустит **12 контейнеров**:
- 3 Config Server (cache-configSrv1, cache-configSrv2, cache-configSrv3)
- 6 Shard Replicas (cache-shard1-1/2/3, cache-shard2-1/2/3)
- 1 Mongos Router (cache-mongos)
- 1 Redis Cache (cache-redis)
- 1 API Application (cache-pymongo_api)

Проверьте статус контейнеров:

```bash
docker compose ps
```

Все контейнеры должны быть в состоянии **"running"**.

### Шаг 2: Инициализация MongoDB кластера

Подождите 15-20 секунд после запуска контейнеров, затем инициализируйте кластер:

```bash
chmod +x scripts/init-sharding.sh
./scripts/init-sharding.sh
```

Скрипт выполнит:
1. Инициализацию Config Server Replica Set (3 узла)
2. Инициализацию Shard 1 Replica Set (3 узла)
3. Инициализацию Shard 2 Replica Set (3 узла)
4. Добавление шардов в кластер
5. Настройку шардирования для базы `somedb` и коллекции `helloDoc`
6. Вывод статуса кластера

**Ожидаемый результат**: В конце выполнения вы увидите статус кластера со всеми шардами и репликами.

### Шаг 3: Заполнение базы данными

Загрузите тестовые данные (1500 документов):

```bash
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

**Ожидаемый результат**: 
```
Total documents inserted: 1500
Shard distribution showing documents across shard1 and shard2
```

### Шаг 4: Проверка работы приложения

#### Веб-интерфейс

**Локальная машина:**
```
http://localhost:8082
```

**Виртуальная машина:**
```bash
# Узнайте IP виртуальной машины
curl --silent http://ifconfig.me

# Откройте в браузере
http://<ip-адрес>:8082
```

**Что вы увидите на главной странице:**
```json
{
  "mongo_topology_type": "Sharded",
  "mongo_replicaset_name": null,
  "mongo_db": "somedb",
  "mongo_nodes": [...],
  "collections": {
    "helloDoc": {
      "documents_count": 1500
    }
  },
  "shards": {
    "shard1ReplSet": "cache-shard1-1:27018,cache-shard1-2:27018,cache-shard1-3:27018",
    "shard2ReplSet": "cache-shard2-1:27019,cache-shard2-2:27019,cache-shard2-3:27019"
  },
  "cache_enabled": true,
  "status": "OK"
}
```

#### API документация (Swagger)

```
http://localhost:8082/docs
```

### Шаг 5: Тестирование кеширования

Запустите автоматический тест производительности:

```bash
chmod +x scripts/test-cache-performance.sh
./scripts/test-cache-performance.sh
```

**Ожидаемые результаты:**
```
Request 1 (no cache):    1000-2000 ms  ← Первый запрос к MongoDB
Request 2 (cached):      20-50 ms      ← Из Redis cache ✓
Request 3 (cached):      20-50 ms      ← Из Redis cache ✓
Request 4 (cached):      20-50 ms      ← Из Redis cache ✓

Cache speedup: 20-40x faster
```

---

## 🔍 Проверка настроек MongoDB

### Проверка шардирования

Статус кластера:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

Вы увидите:
- Список шардов (shard1ReplSet, shard2ReplSet)
- Базы данных с включенным шардингом
- Коллекции с шард-ключами
- Распределение chunks между шардами

### Проверка репликации

**Config Server Replica Set:**

```bash
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.status();
EOF
```

**Shard 1 Replica Set:**

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

**Shard 2 Replica Set:**

```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status();
EOF
```

Вы увидите:
- Список всех членов replica set
- Роли: PRIMARY, SECONDARY
- Состояние здоровья каждого узла
- Задержку репликации (replication lag)

### Проверка распределения данных

Количество документов в каждом шарде:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

**Ожидаемый результат:**
```
Shard shard1ReplSet at ...
  data: ~750 documents
Shard shard2ReplSet at ...
  data: ~750 documents
```

### Проверка кеширования Redis

Ключи в Redis:

```bash
docker compose exec redis redis-cli KEYS "*"
```

Статистика Redis:

```bash
docker compose exec redis redis-cli INFO stats
```

---

## 📊 Основные эндпоинты API

| Эндпоинт | Описание | Кеширование |
|----------|----------|-------------|
| `GET /` | Информация о кластере | Нет |
| `GET /helloDoc/count` | Количество документов | Нет |
| `GET /helloDoc/users` | Список пользователей (до 1000) | **Да** (60 сек) |
| `GET /helloDoc/users/{name}` | Поиск пользователя по имени | Нет |
| `POST /helloDoc/users` | Создание нового пользователя | Нет |

### Примеры запросов

**Получить информацию о кластере:**
```bash
curl http://localhost:8082/
```

**Количество документов:**
```bash
curl http://localhost:8082/helloDoc/count
```

**Список пользователей (кешируется):**
```bash
curl http://localhost:8082/helloDoc/users
```

**Найти пользователя:**
```bash
curl http://localhost:8082/helloDoc/users/User_1
```

---

## 🧪 Тестирование отказоустойчивости

### Тест 1: Остановка Secondary узла

```bash
docker compose stop cache-shard1-2
```

Проверьте статус - кластер продолжит работать:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Запустите обратно:
```bash
docker compose start cache-shard1-2
```

### Тест 2: Остановка Primary узла (автоматический failover)

```bash
docker compose stop cache-shard1-1
```

Подождите 10-20 секунд. Проверьте - один из Secondary станет Primary:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

### Тест 3: Остановка Redis (graceful degradation)

```bash
docker compose stop cache-redis
```

Приложение продолжит работать, но без кеширования:
```bash
curl http://localhost:8082/ | grep cache_enabled
# "cache_enabled": false
```

---

## 🛑 Остановка проекта

Остановить все сервисы:

```bash
docker compose down
```

Полная очистка (включая данные):

```bash
docker compose down -v
```

---

## 📋 Технические характеристики

### Архитектура

- **MongoDB**: 2 Sharded Replica Sets (3 узла каждый) + Config RS (3 узла)
- **Redis**: 1 инстанс с persistence
- **API**: FastAPI с async Motor driver
- **Shard Key**: `_id` (hashed) - равномерное распределение
- **Cache TTL**: 60 секунд для эндпоинта `/users`

### Производительность

- **Без кеша**: 1000-2000 мс (запрос к sharded MongoDB)
- **С кешем**: < 100 мс (запрос к Redis) ✓
- **Ускорение**: 10-40x для повторяющихся запросов
- **Capacity**: Готов к Black Friday нагрузкам

### Отказоустойчивость

- ✓ Выдерживает падение 1 узла в каждом replica set
- ✓ Автоматический failover за 10-20 секунд
- ✓ Работает даже без Redis (graceful degradation)
- ✓ Нулевое время простоя при обновлениях

---

## 📚 Дополнительная информация

### Подробная документация

Детальные инструкции и troubleshooting в каждой директории:
- `/mongo-sharding/README.md`
- `/mongo-sharding-repl/README.md`
- `/sharding-repl-cache/README.md` ⭐

### Архитектурные схемы

Все схемы в формате draw.io находятся в папке `/tasks/`

### Порты

| Сервис | Порт | Назначение |
|--------|------|------------|
| API | 8082 | HTTP API |
| Redis | 6379 | Cache |
| Mongos | 27017 | MongoDB Router |
| Shards | 27018, 27019 | Data nodes |

---

## ❓ Troubleshooting

### Проблема: Контейнеры не запускаются

**Решение**: Проверьте, что порты свободны:
```bash
lsof -i :8082
lsof -i :6379
```

### Проблема: Ошибка при инициализации

**Решение**: Убедитесь, что все контейнеры запущены:
```bash
docker compose ps
```

Если какие-то не running, проверьте логи:
```bash
docker compose logs <service-name>
```

### Проблема: "Items count: 0"

**Решение**: Запустите скрипт заполнения данными:
```bash
./scripts/mongo-init.sh
```

### Проблема: Кеш не работает

**Решение**: Проверьте переменную окружения:
```bash
docker compose exec pymongo_api env | grep REDIS_URL
```

Должно быть: `REDIS_URL=redis://redis:6379`

---

## 👨‍💻 Разработка

### Запуск в development mode

```bash
docker compose up
# без флага -d для просмотра логов в реальном времени
```

### Просмотр логов

```bash
docker compose logs -f pymongo_api
docker compose logs -f redis
docker compose logs -f mongos
```

---

## 📞 Контакты

Проект выполнен в рамках 4 спринта курса "Архитектура высоконагруженных систем".

**Проект**: Интернет-магазин "Мобильный мир"  
**Цель**: Подготовка к "Черной пятнице" с использованием MongoDB sharding, replication и Redis caching.
