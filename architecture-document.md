# Архитектурный документ — «Мобильный мир»

## Задание 7. Проектирование схем коллекций для шардирования данных

### 7.1 Коллекция `orders` (заказы)

**Схема документа:**

```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": ISODate,
  "items": [
    {
      "product_id": ObjectId,
      "name": "Смартфон X",
      "quantity": 2,
      "price": 29990
    }
  ],
  "status": "pending" | "confirmed" | "shipped" | "delivered" | "cancelled",
  "total": 59980,
  "geo_zone": "moscow"
}
```

**Шард-ключ:** `{ user_id: "hashed" }`

**Стратегия шардирования:** Hashed Sharding

**Обоснование:**
- **Равномерное распределение:** хеширование `user_id` гарантирует равномерное распределение данных между шардами, даже если активность пользователей неравномерна.
- **Поддержка основных операций:** поиск истории заказов конкретного пользователя (`db.orders.find({ user_id: ... })`) направляется на конкретный шард, что обеспечивает высокую производительность.
- **Масштабирование записи:** при массовом создании заказов во время распродажи записи равномерно распределяются между шардами, что предотвращает перегрузку одного узла.

**Команда создания:**

```javascript
sh.shardCollection("somedb.orders", { "user_id": "hashed" })
```

**Индексы:**

```javascript
db.orders.createIndex({ "user_id": 1, "created_at": -1 })
db.orders.createIndex({ "status": 1 })
```

---

### 7.2 Коллекция `products` (товары)

**Схема документа:**

```json
{
  "_id": ObjectId,
  "name": "Смартфон X",
  "category": "electronics",
  "price": 29990,
  "stock": {
    "moscow": 50,
    "ekaterinburg": 30,
    "kaliningrad": 10
  },
  "attributes": {
    "color": "black",
    "size": "6.1 inch"
  }
}
```

**Шард-ключ:** `{ category: 1, _id: 1 }`

**Стратегия шардирования:** Range-Based Sharding (составной ключ)

**Обоснование:**
- **Поддержка поиска по категориям:** запросы `db.products.find({ category: "electronics" })` направляются на конкретный шард или ограниченное число шардов, что ускоряет фильтрацию.
- **Составной ключ с `_id`** добавляет кардинальность, чтобы документы внутри одной категории распределялись между чанками и не создавали «горячих» шардов.
- **Фильтрация по диапазону цен:** после попадания на нужный шард фильтрация по цене выполняется локально.

**Риски:** популярные категории (например, «Электроника») могут создать непропорциональную нагрузку. Для решения этой проблемы см. задание 8.

**Команда создания:**

```javascript
sh.shardCollection("somedb.products", { "category": 1, "_id": 1 })
```

**Индексы:**

```javascript
db.products.createIndex({ "category": 1, "price": 1 })
db.products.createIndex({ "name": "text" })
```

---

### 7.3 Коллекция `carts` (корзины)

**Схема документа:**

```json
{
  "_id": ObjectId,
  "user_id": ObjectId | null,
  "session_id": "sess_abc123",
  "items": [
    {
      "product_id": ObjectId,
      "quantity": 2
    }
  ],
  "status": "active" | "ordered" | "abandoned",
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate
}
```

**Шард-ключ:** `{ _id: "hashed" }`

**Стратегия шардирования:** Hashed Sharding

**Обоснование:**
- **Равномерное распределение:** корзины создаются массово (особенно гостевые), хеширование `_id` гарантирует равномерное распределение записей.
- **Высокая кардинальность:** `_id` уникален для каждого документа, что обеспечивает максимально равномерное распределение чанков.
- **TTL-индекс:** для автоматической очистки старых корзин используется `expires_at`, который работает независимо от стратегии шардирования.

**Команда создания:**

```javascript
sh.shardCollection("somedb.carts", { "_id": "hashed" })
```

**Индексы:**

```javascript
db.carts.createIndex({ "user_id": 1, "status": 1 })
db.carts.createIndex({ "session_id": 1, "status": 1 })
db.carts.createIndex({ "expires_at": 1 }, { expireAfterSeconds: 0 })
```

---

## Задание 8. Выявление и устранение «горячих» шардов

### 8.1 Метрики мониторинга

#### Метрики уровня шардов

| Метрика | Команда / источник | Пороговое значение |
|---------|-------------------|-------------------|
| Количество операций на шард | `db.serverStatus().opcounters` на каждом шарде | Разница > 30% между шардами |
| Распределение данных | `db.helloDoc.getShardDistribution()` | Разница объёма > 25% |
| Количество чанков на шард | `sh.status()` | Неравномерное распределение чанков |
| CPU / RAM / Disk IO | Мониторинг контейнеров (Prometheus, Grafana) | CPU > 80%, RAM > 85% |
| Latency операций | `db.serverStatus().opLatencies` | p99 > 100ms |
| Количество подключений | `db.serverStatus().connections` | Неравномерное между шардами |

#### Пример получения метрик

```javascript
// Проверка распределения данных по шардам
use somedb
db.products.getShardDistribution()

// Статус шардирования
sh.status()

// Счётчики операций на конкретном шарде
db.serverStatus().opcounters

// Задержки операций
db.serverStatus().opLatencies
```

#### Мониторинг с помощью mongotop и mongostat

```bash
# Мониторинг активности коллекций
docker compose exec -T shard1-1 mongotop --port 27018

# Статистика операций в реальном времени
docker compose exec -T shard1-1 mongostat --port 27018
```

### 8.2 Механизмы обнаружения дисбаланса

```javascript
// Скрипт для обнаружения дисбаланса чанков
function detectHotShards() {
    const status = sh.status();
    const shardStats = {};

    db.adminCommand({ listShards: 1 }).shards.forEach(shard => {
        const conn = new Mongo(shard.host);
        const serverStatus = conn.getDB("admin").serverStatus();
        shardStats[shard._id] = {
            opcounters: serverStatus.opcounters,
            connections: serverStatus.connections.current
        };
    });

    // Сравнение нагрузки между шардами
    const totalOps = Object.values(shardStats).map(s =>
        s.opcounters.query + s.opcounters.insert + s.opcounters.update
    );
    const avgOps = totalOps.reduce((a, b) => a + b) / totalOps.length;
    totalOps.forEach((ops, i) => {
        if (ops > avgOps * 1.3) {
            print(`WARNING: Shard ${Object.keys(shardStats)[i]} is HOT (${ops} ops vs avg ${avgOps})`);
        }
    });
}
```

### 8.3 Меры устранения дисбаланса

#### 1. Ручное перемещение чанков

```javascript
// Переместить чанк с горячего шарда на менее загруженный
sh.moveChunk("somedb.products",
  { category: "electronics" },
  "shard2"
)
```

#### 2. Разделение крупных чанков

```javascript
// Разделить большой чанк, содержащий популярную категорию
sh.splitAt("somedb.products",
  { category: "electronics", _id: ObjectId("64a...") }
)
```

#### 3. Использование зон (tag-aware sharding)

Для равномерного распределения популярных категорий по шардам:

```javascript
// Добавить теги шардам
sh.addShardTag("shard1", "zone_a")
sh.addShardTag("shard2", "zone_b")

// Распределить категории по зонам
sh.addTagRange("somedb.products",
  { category: "electronics", _id: MinKey },
  { category: "electronics", _id: ObjectId("80000000...") },
  "zone_a"
)
sh.addTagRange("somedb.products",
  { category: "electronics", _id: ObjectId("80000000...") },
  { category: "electronics", _id: MaxKey },
  "zone_b"
)
```

#### 4. Смена стратегии шардирования

Если range-based шардирование приводит к постоянным горячим шардам, рассмотреть переход на hashed:

```javascript
// Для новой коллекции
sh.shardCollection("somedb.products_v2", { "category": "hashed" })
// Мигрировать данные из products в products_v2
```

#### 5. Настройка балансировщика

```javascript
// Установить окно балансировки (чтобы не мешать пиковой нагрузке)
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)

// Уменьшить размер чанка для более гранулярного распределения
use config
db.settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 32 } },
  { upsert: true }
)
```

---

## Задание 9. Настройка чтения с реплик и консистентность

### 9.1 Таблица операций чтения

#### Коллекция `products`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Просмотр каталога (листинг товаров по категории) | `secondaryPreferred` | Допустима небольшая задержка в отображении. Снижает нагрузку на primary. |
| Фильтрация по цене | `secondaryPreferred` | Аналитический запрос, не критичен к актуальности. |
| Отображение карточки товара | `secondaryPreferred` | Описание и атрибуты редко меняются. |
| Проверка остатков при оформлении заказа | **`primary`** | Критично: устаревшие данные могут привести к продаже отсутствующего товара. |
| Обновление остатков (списание) | **`primary`** | Запись — всегда на primary. |

#### Коллекция `orders`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Создание заказа | **`primary`** | Запись + немедленное чтение для подтверждения. |
| Просмотр статуса заказа (пользователем) | `secondaryPreferred` | Задержка 1–3 сек допустима, статус меняется нечасто. |
| История заказов пользователя | `secondary` | Исторические данные, eventual consistency допустима. |
| Административная панель (список всех заказов) | `secondary` | Аналитика, не требует мгновенной актуальности. |
| Изменение статуса заказа | **`primary`** | Запись — всегда на primary. |

#### Коллекция `carts`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Получение активной корзины | **`primary`** | Пользователь ожидает видеть актуальное содержимое корзины. |
| Добавление/удаление товара | **`primary`** | Запись + немедленное чтение результата. |
| Слияние гостевой корзины с пользовательской | **`primary`** | Транзакционная операция, требует строгой консистентности. |
| Отметка корзины как заказанной | **`primary`** | Критическая операция, должна быть атомарной. |
| Очистка старых корзин (TTL) | `secondary` | Фоновый процесс, не критичен к актуальности. |

### 9.2 Допустимая задержка репликации

| Категория данных | Допустимая задержка | Обоснование |
|-----------------|---------------------|-------------|
| Остатки товаров (для каталога) | 1–3 секунды | Небольшое расхождение не критично для просмотра, но проверка при покупке — только с primary. |
| Статус заказа | 2–5 секунд | Статус обновляется редко, пользователь может подождать. |
| История заказов | 5–10 секунд | Исторические данные, не требуют мгновенной актуальности. |
| Корзина | **Не допускается** (только primary) | Пользователь должен видеть актуальное состояние корзины. |

### 9.3 Конфигурация Read Preference в приложении

```python
from pymongo import ReadPreference

# Для каталога товаров
products_catalog = db.get_collection(
    "products",
    read_preference=ReadPreference.SECONDARY_PREFERRED
)

# Для проверки остатков при покупке
products_stock = db.get_collection(
    "products",
    read_preference=ReadPreference.PRIMARY
)

# Для корзины — всегда primary
carts = db.get_collection(
    "carts",
    read_preference=ReadPreference.PRIMARY
)

# Для истории заказов
orders_history = db.get_collection(
    "orders",
    read_preference=ReadPreference.SECONDARY
)
```

### 9.4 Мониторинг задержки репликации

```javascript
// Проверка задержки репликации на secondary
rs.status().members.filter(m => m.stateStr === "SECONDARY").forEach(m => {
    const lag = (rs.status().members[0].optimeDate - m.optimeDate) / 1000;
    print(`${m.name}: replication lag = ${lag} seconds`);
})

// Настройка алертов при превышении допустимой задержки
// (в системе мониторинга, например Prometheus + AlertManager)
```

---

## Задание 10. Миграция на Cassandra

### 10.1 Анализ данных для миграции

#### Критически важные данные с точки зрения целостности и скорости

| Сущность | Целостность | Скорость записи | Скорость чтения | Паттерн доступа |
|----------|-------------|-----------------|-----------------|-----------------|
| Заказы (orders) | Высокая | Высокая (пик при распродажах) | Средняя | Запись + поиск по user_id |
| Товары (products) | Высокая | Средняя (обновления остатков) | Очень высокая | Чтение по категориям, фильтрация |
| Корзины (carts) | Средняя | Очень высокая | Высокая | Частые CRUD, TTL |
| История заказов | Средняя | Append-only | Средняя | Чтение по user_id + time range |
| Сессии | Низкая | Высокая | Высокая | Key-value, TTL |

#### Рекомендации по миграции в Cassandra

**Подходят для Cassandra:**

1. **Корзины (carts)** — высокая скорость записи, TTL для автоочистки, ключ доступа чётко определён (session_id или user_id). Cassandra оптимальна для workload с частыми обновлениями и автоматическим удалением по TTL.

2. **История заказов** — append-only данные с time-series паттерном. Кластерный ключ по `created_at DESC` обеспечивает эффективную выборку последних заказов.

3. **Пользовательские сессии** — key-value паттерн с TTL, идеально подходит для Cassandra. Высокая скорость записи, не требует сложных запросов.

**Остаются в MongoDB:**

1. **Товары (products)** — сложные запросы с фильтрацией по множеству атрибутов, агрегациями, текстовым поиском. MongoDB лучше подходит для гибких запросов. Cassandra требует денормализации под каждый запрос, что чрезмерно усложнит модель.

2. **Активные заказы (текущий статус)** — требуют транзакционного обновления статуса и остатков. MongoDB обеспечивает более простую модель консистентности для таких операций.

### 10.2 Концептуальная модель данных в Cassandra

#### Таблица `orders_by_user` (история заказов)

```sql
CREATE TABLE orders_by_user (
    user_id     UUID,
    created_at  TIMESTAMP,
    order_id    UUID,
    items       LIST<FROZEN<item_type>>,
    status      TEXT,
    total       DECIMAL,
    geo_zone    TEXT,
    PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC)
  AND default_time_to_live = 0
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 'compaction_window_size': 7, 'compaction_window_unit': 'DAYS'};

CREATE TYPE item_type (
    product_id  UUID,
    name        TEXT,
    quantity    INT,
    price       DECIMAL
);
```

**Partition key:** `user_id`
- Каждый пользователь — отдельная партиция.
- Обеспечивает быстрый доступ к истории заказов конкретного пользователя.
- Равномерное распределение: UUID хешируется consistent hashing, что гарантирует равномерное распределение по узлам.

**Clustering key:** `created_at DESC, order_id ASC`
- Заказы отсортированы по дате (новые первыми).
- `order_id` обеспечивает уникальность в рамках одной миллисекунды.

**Риски горячих партиций:** у «тяжёлых» пользователей (магазины-оптовики) может накапливаться много заказов. Решение: составной partition key `(user_id, year_month)` для разбиения крупных партиций по месяцам.

```sql
-- Альтернативная модель с bucket по месяцам
CREATE TABLE orders_by_user_monthly (
    user_id     UUID,
    year_month  TEXT,    -- "2026-04"
    created_at  TIMESTAMP,
    order_id    UUID,
    items       LIST<FROZEN<item_type>>,
    status      TEXT,
    total       DECIMAL,
    geo_zone    TEXT,
    PRIMARY KEY ((user_id, year_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

#### Таблица `carts_by_session` (корзины гостей)

```sql
CREATE TABLE carts_by_session (
    session_id  TEXT,
    cart_id     UUID,
    items       LIST<FROZEN<cart_item>>,
    status      TEXT,
    created_at  TIMESTAMP,
    updated_at  TIMESTAMP,
    PRIMARY KEY ((session_id), status)
) WITH default_time_to_live = 86400;  -- 24 часа TTL

CREATE TYPE cart_item (
    product_id  UUID,
    quantity    INT
);
```

**Partition key:** `session_id`
- Одна сессия = одна партиция.
- Быстрый поиск активной корзины по `{ session_id, status: "active" }`.
- Распределение равномерное, так как session_id — случайный идентификатор.

#### Таблица `carts_by_user` (корзины авторизованных пользователей)

```sql
CREATE TABLE carts_by_user (
    user_id     UUID,
    cart_id     UUID,
    items       LIST<FROZEN<cart_item>>,
    status      TEXT,
    created_at  TIMESTAMP,
    updated_at  TIMESTAMP,
    PRIMARY KEY ((user_id), status)
) WITH default_time_to_live = 604800;  -- 7 дней TTL
```

**Partition key:** `user_id`
- Быстрый поиск по `{ user_id, status: "active" }`.

#### Таблица `sessions` (пользовательские сессии)

```sql
CREATE TABLE sessions (
    session_id  TEXT,
    user_id     UUID,
    created_at  TIMESTAMP,
    last_active TIMESTAMP,
    data        MAP<TEXT, TEXT>,
    PRIMARY KEY ((session_id))
) WITH default_time_to_live = 3600;  -- 1 час TTL
```

**Partition key:** `session_id` — классический key-value доступ.

#### Минимизация влияния решардинга

Cassandra использует consistent hashing с виртуальными узлами (vnodes). При добавлении нового узла:
- Перемещается только ~1/N данных (где N — количество узлов).
- В отличие от MongoDB range-based шардирования, нет полного перераспределения.
- `num_tokens = 256` (по умолчанию) обеспечивает равномерное распределение.

### 10.3 Стратегии обеспечения целостности данных

#### Hinted Handoff

**Описание:** когда узел-получатель недоступен, координатор сохраняет запись (hint) локально и передаёт её, когда узел восстановится.

**Применение:**
| Сущность | Использование | Обоснование |
|----------|--------------|-------------|
| Корзины | **Да** | Допустима краткосрочная несогласованность; важнее скорость записи. Если узел упал на 30 сек, hint доставит данные после восстановления. |
| Сессии | **Да** | Короткоживущие данные, TTL обеспечивает автоочистку, потеря данных — не критична. |
| Заказы | **Да** | Как страховка, но не как основной механизм. |

**Настройка:**

```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа
hinted_handoff_throttle_in_kb: 1024
```

#### Read Repair

**Описание:** при чтении с нескольких реплик, если данные расходятся — автоматически обновляются устаревшие реплики.

**Применение:**
| Сущность | Использование | Обоснование |
|----------|--------------|-------------|
| Корзины | **Да** | При чтении корзины (CL=ONE для скорости) автоматически исправляются расхождения. Компромисс: небольшой overhead на чтение, но данные корректируются «на лету». |
| Заказы (история) | **Да** | При просмотре истории read repair исправляет расхождения без дополнительной нагрузки. |
| Сессии | **Нет** | Данные короткоживущие, repair не оправдан — TTL удалит их раньше. |

**Настройка:**

```
-- В CQL (per-table)
ALTER TABLE carts_by_session WITH read_repair = 'BLOCKING';
ALTER TABLE carts_by_user WITH read_repair = 'BLOCKING';
ALTER TABLE orders_by_user WITH read_repair = 'BLOCKING';
ALTER TABLE sessions WITH read_repair = 'NONE';
```

#### Anti-Entropy Repair

**Описание:** полное фоновое сравнение данных между репликами с помощью Merkle-деревьев. Гарантирует 100% согласованность.

**Применение:**
| Сущность | Использование | Обоснование |
|----------|--------------|-------------|
| Заказы (история) | **Да, еженедельно** | Критически важные финансовые данные. Полный repair гарантирует целостность для отчётности и аудита. |
| Корзины | **Да, ежедневно** | TTL-данные требуют согласованности tombstone-ов для корректной очистки. |
| Сессии | **Да, еженедельно** | Предотвращение накопления tombstone-ов. |

**Настройка и запуск:**

```bash
# Полный repair для таблицы заказов (запускать в maintenance window)
nodetool repair somedb orders_by_user --full

# Инкрементальный repair для корзин (ежедневно)
nodetool repair somedb carts_by_session

# Расписание для cron
# Ежедневно в 03:00 — инкрементальный repair корзин
0 3 * * * nodetool repair somedb carts_by_session
0 3 * * * nodetool repair somedb carts_by_user

# Еженедельно в воскресенье в 02:00 — полный repair заказов
0 2 * * 0 nodetool repair somedb orders_by_user --full
```

#### Сводная таблица стратегий

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy Repair | Consistency Level (Write/Read) |
|----------|---------------|-------------|--------------------|-----------------------------|
| Корзины (carts) | Да | BLOCKING | Ежедневно (инкрементальный) | Write: ONE / Read: ONE |
| Заказы (orders) | Да | BLOCKING | Еженедельно (полный) | Write: QUORUM / Read: ONE |
| Сессии (sessions) | Да | NONE | Еженедельно (инкрементальный) | Write: ONE / Read: ONE |

**Обоснование выбора Consistency Level:**
- **Корзины (CL=ONE/ONE):** приоритет — скорость. Потеря одного обновления корзины — допустима, пользователь может добавить товар повторно. Hinted Handoff + Read Repair компенсируют inconsistency.
- **Заказы (CL=QUORUM/ONE):** запись подтверждается большинством реплик, что гарантирует сохранность заказа. Чтение с одной реплики для скорости, read repair корректирует устаревшие данные.
- **Сессии (CL=ONE/ONE):** максимальная скорость. Данные эфемерные, потеря сессии — пользователь просто залогинится заново.
