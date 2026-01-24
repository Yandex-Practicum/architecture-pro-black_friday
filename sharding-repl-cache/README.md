# MongoDB Sharding with Replication and Redis Cache - Проект "Мобильный мир"

Этот проект реализует полный стек для высоконагруженного интернет-магазина "Мобильный мир":
- **Шардирование MongoDB** - для распределения нагрузки
- **Репликация** - для отказоустойчивости  
- **Redis кеширование** - для максимальной производительности

## Архитектура

### Config Servers Replica Set (3 реплики)
- `cache-configSrv1` (Primary) - порт 27017
- `cache-configSrv2` (Secondary) - порт 27017
- `cache-configSrv3` (Secondary) - порт 27017

### Shard 1 Replica Set (3 реплики)
- `cache-shard1-1` (Primary) - порт 27018
- `cache-shard1-2` (Secondary) - порт 27018
- `cache-shard1-3` (Secondary) - порт 27018

### Shard 2 Replica Set (3 реплики)
- `cache-shard2-1` (Primary) - порт 27019
- `cache-shard2-2` (Secondary) - порт 27019
- `cache-shard2-3` (Secondary) - порт 27019

### Другие компоненты
- **Mongos Router** (1 шт): `cache-mongos` - маршрутизатор запросов к шардам
- **Redis Cache** (1 шт): `cache-redis` - кеш для часто запрашиваемых данных
- **API Application**: `cache-pymongo_api` - FastAPI приложение (порт 8082)

**Итого**: 9 инстансов MongoDB + 1 mongos + 1 Redis + 1 API = 12 контейнеров

### База данных и коллекции
- **База данных**: `somedb`
- **Коллекция**: `helloDoc`
- **Shard Key**: `_id` (hashed)
- **Cache TTL**: 60 секунд для эндпоинта `/users`

## Преимущества архитектуры

1. **Высокая производительность** - шардирование + кеширование
2. **Отказоустойчивость** - репликация всех компонентов
3. **Быстрый отклик** - кешированные запросы выполняются < 100мс
4. **Масштабируемость** - можно добавить больше шардов и реплик
5. **Автоматическое восстановление** - при падении узла система продолжает работать

## Как запустить проект

### Шаг 1: Запуск контейнеров

Запустите все сервисы:

```bash
docker compose up -d
```

Дождитесь запуска всех контейнеров (примерно 15-20 секунд). Проверьте статус:

```bash
docker compose ps
```

Все 12 контейнеров должны быть в состоянии "running".

### Шаг 2: Инициализация шардирования с репликацией

После запуска контейнеров инициализируйте кластер:

```bash
chmod +x scripts/init-sharding.sh
./scripts/init-sharding.sh
```

#### Что делает скрипт:
1. Инициализирует Config Server Replica Set (3 узла)
2. Инициализирует Shard 1 Replica Set (3 узла)
3. Инициализирует Shard 2 Replica Set (3 узла)
4. Добавляет шарды в кластер
5. Настраивает шардирование для базы `somedb` и коллекции `helloDoc`
6. Выводит статус всех replica set'ов

### Шаг 3: Заполнение базы данными

Загрузите тестовые данные (1500 документов):

```bash
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

### Шаг 4: Тестирование производительности кеширования

Запустите тест производительности:

```bash
chmod +x scripts/test-cache-performance.sh
./scripts/test-cache-performance.sh
```

Скрипт выполнит 4 запроса к эндпоинту `/somedb/users` и покажет разницу во времени выполнения:
- **Первый запрос** - данные берутся из MongoDB (~1-2 секунды)
- **Последующие запросы** - данные берутся из Redis cache (< 100мс)

## Как проверить работу

### Проверка через веб-интерфейс

#### Локальная машина:
Откройте в браузере: **http://localhost:8082**

Вы увидите:
- Топологию MongoDB (Sharded)
- Список шардов
- Количество документов
- Primary и Secondary узлы
- Статус кеширования (**cache_enabled: true**)

#### Виртуальная машина:
```bash
curl --silent http://ifconfig.me
```
Откройте: http://<ip виртуальной машины>:8082

### API документация

Swagger: **http://localhost:8082/docs**

### Проверка кеширования

#### Первый запрос (без кеша):
```bash
time curl http://localhost:8082/helloDoc/users
```

#### Второй запрос (с кешем):
```bash
time curl http://localhost:8082/helloDoc/users
```

Второй запрос должен быть значительно быстрее (< 100мс).

#### Статус Redis:
```bash
docker compose exec -T redis redis-cli INFO stats
```

#### Ключи в Redis:
```bash
docker compose exec -T redis redis-cli KEYS "api:cache:*"
```

#### Посмотреть значение кеша:
```bash
docker compose exec -T redis redis-cli GET "api:cache:/somedb/users"
```

#### Очистить кеш:
```bash
docker compose exec -T redis redis-cli FLUSHALL
```

### Проверка MongoDB кластера

#### Статус кластера:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

#### Количество документов:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Распределение по шардам:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

#### Статус Shard 1 Replica Set:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

#### Статус Shard 2 Replica Set:
```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status();
EOF
```

## Тестирование производительности

### Автоматический тест

Запустите автоматический тест производительности:

```bash
./scripts/test-cache-performance.sh
```

### Ручное тестирование с помощью curl

#### Измерение времени запроса:
```bash
curl -w "\nTotal time: %{time_total}s\n" http://localhost:8082/helloDoc/users -o /dev/null -s
```

#### Множественные запросы:
```bash
for i in {1..5}; do
  echo "Request $i:"
  curl -w "Time: %{time_total}s\n" http://localhost:8082/helloDoc/users -o /dev/null -s
  echo ""
done
```

### Тестирование с помощью Apache Bench (ab)

Если установлен Apache Bench:

```bash
# 100 запросов, 10 одновременно
ab -n 100 -c 10 http://localhost:8082/helloDoc/users
```

### Ожидаемые результаты

- **Первый запрос (без кеша)**: 1000-2000 мс
- **Повторные запросы (с кешем)**: < 100 мс
- **Ускорение**: 10-20x

## Тестирование отказоустойчивости

### Тест 1: Остановка Redis

```bash
docker compose stop cache-redis
```

Приложение продолжит работать, но без кеширования. Запросы будут медленнее.

```bash
curl http://localhost:8082/
# cache_enabled: false
```

Запустите Redis обратно:
```bash
docker compose start cache-redis
```

### Тест 2: Остановка Secondary узла MongoDB

```bash
docker compose stop cache-shard1-2
```

Система продолжит работать без проблем:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Запустите обратно:
```bash
docker compose start cache-shard1-2
```

### Тест 3: Остановка Primary узла

```bash
docker compose stop cache-shard1-1
```

Произойдет автоматический failover - один из Secondary станет Primary:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Запустите обратно:
```bash
docker compose start cache-shard1-1
```

## Мониторинг

### Статус всех контейнеров:
```bash
docker compose ps
```

### Логи API:
```bash
docker compose logs -f pymongo_api
```

### Логи Redis:
```bash
docker compose logs -f redis
```

### Мониторинг Redis в реальном времени:
```bash
docker compose exec redis redis-cli MONITOR
```

### Статистика Redis:
```bash
docker compose exec redis redis-cli INFO
```

### Количество ключей в Redis:
```bash
docker compose exec redis redis-cli DBSIZE
```

## Настройка кеширования

Кеширование настраивается в коде приложения (`api_app/app.py`):

```python
# TTL кеша - 60 секунд
@cache(expire=60 * 1)
async def list_users(collection_name: str):
    ...
```

Для изменения TTL измените значение `expire` и пересоберите контейнер:

```bash
docker compose up -d --build pymongo_api
```

## Остановка проекта

### Остановка всех сервисов:
```bash
docker compose down
```

### Полная очистка (включая volumes):
```bash
docker compose down -v
```

## Устранение неполадок

### Проблема: Кеш не работает

**Проверка 1**: Убедитесь, что Redis запущен
```bash
docker compose ps redis
```

**Проверка 2**: Проверьте переменную окружения
```bash
docker compose exec pymongo_api env | grep REDIS
```

Должно быть: `REDIS_URL=redis://redis:6379`

**Проверка 3**: Проверьте статус на главной странице
```bash
curl http://localhost:8082/ | grep cache_enabled
```

Должно быть: `"cache_enabled": true`

**Проверка 4**: Проверьте, что Redis принимает подключения
```bash
docker compose exec redis redis-cli PING
```

Должен вернуть: `PONG`

### Проблема: Медленные запросы даже с кешем

**Решение 1**: Очистите кеш и попробуйте снова
```bash
docker compose exec redis redis-cli FLUSHALL
curl http://localhost:8082/helloDoc/users  # Первый запрос
curl http://localhost:8082/helloDoc/users  # Должен быть быстрым
```

**Решение 2**: Проверьте логи приложения
```bash
docker compose logs pymongo_api | tail -50
```

**Решение 3**: Проверьте нагрузку на MongoDB
```bash
docker compose exec mongos mongosh --quiet <<EOF
db.currentOp()
EOF
```

### Проблема: Контейнеры не запускаются

**Решение**: Убедитесь, что порты 8082 и 6379 не заняты

```bash
lsof -i :8082
lsof -i :6379
```

**Примечание**: Проект использует префикс `cache-` для имен контейнеров, поэтому может работать одновременно с другими проектами.

### Проблема: Redis теряет данные при перезапуске

**Решение**: Убедитесь, что persistence включен (уже настроено в compose.yaml)

```bash
docker compose exec redis redis-cli CONFIG GET appendonly
```

Должно быть: `appendonly yes`

## Полезные команды

### Redis команды:

```bash
# Информация о памяти
docker compose exec redis redis-cli INFO memory

# Список всех ключей
docker compose exec redis redis-cli KEYS "*"

# TTL конкретного ключа
docker compose exec redis redis-cli TTL "api:cache:/somedb/users"

# Удалить конкретный ключ
docker compose exec redis redis-cli DEL "api:cache:/somedb/users"

# Статистика попаданий в кеш
docker compose exec redis redis-cli INFO stats | grep keyspace
```

### MongoDB команды:

```bash
# Список всех баз данных
docker compose exec mongos mongosh --quiet <<EOF
show dbs
EOF

# Информация о шардах
docker compose exec mongos mongosh --quiet <<EOF
use admin
db.adminCommand({ listShards: 1 })
EOF

# Статус балансировщика
docker compose exec mongos mongosh --quiet <<EOF
sh.isBalancerRunning()
EOF
```

## Производительность для "Черной пятницы"

Эта архитектура обеспечивает:

### Пропускная способность:
- **Без кеша**: ~50-100 запросов/сек к MongoDB
- **С кешем**: ~1000-5000 запросов/сек из Redis
- **Ускорение**: 10-50x для повторяющихся запросов

### Латентность:
- **Первый запрос**: 1-2 секунды (MongoDB с шардированием)
- **Кешированный запрос**: < 100 мс (Redis)
- **Снижение латентности**: 10-20x

### Отказоустойчивость:
- Выдерживает падение 1 узла в каждом replica set
- Автоматический failover за 10-20 секунд
- Работает даже при падении Redis (без кеша)

### Масштабируемость:
- Можно добавить больше шардов
- Можно добавить больше реплик
- Можно настроить Redis Cluster для высоконагруженных систем

## Рекомендации для продакшена

1. **Мониторинг**:
   - Настройте Prometheus + Grafana для мониторинга
   - Следите за hit rate Redis
   - Мониторьте latency MongoDB

2. **Резервное копирование**:
   - Настройте автоматические бэкапы MongoDB
   - Реплицируйте данные в разные зоны доступности

3. **Безопасность**:
   - Включите аутентификацию для MongoDB
   - Настройте пароль для Redis
   - Используйте TLS для соединений

4. **Оптимизация**:
   - Настройте индексы для часто используемых запросов
   - Увеличьте память для Redis при необходимости
   - Используйте read preference для чтения из Secondary

5. **Кеш-стратегия**:
   - Увеличьте TTL для статичных данных
   - Уменьшите TTL для часто меняющихся данных
   - Используйте cache invalidation при обновлении данных
