# Архитектурный документ: MongoDB и Cassandra
## Интернет-магазин "Мобильный мир"

---

## Задание 7. Проектирование схем коллекций для шардирования

### 7.1 Коллекция orders (Заказы)

**Схема коллекции:**
```javascript
{
  _id: ObjectId,
  order_id: String,           // Уникальный идентификатор заказа
  user_id: String,            // Идентификатор клиента
  created_at: ISODate,        // Дата и время оформления
  items: [                    // Список товаров
    {
      product_id: String,
      name: String,
      quantity: Number,
      price: Number
    }
  ],
  status: String,             // "pending", "paid", "shipped", "delivered", "cancelled"
  total_amount: Number,       // Общая сумма
  geo_zone: String            // Геозона: "msk", "spb", "ekb", "kln"
}
```

**Выбор шард-ключа:** `{ user_id: "hashed" }`

**Обоснование:**
- Основная операция - поиск истории заказов пользователя (по user_id)
- Hashed sharding обеспечивает равномерное распределение данных
- Избегаем hot spots: заказы распределяются равномерно по шардам
- Запросы по user_id направляются на конкретный шард (targeted queries)

**Команда создания:**
```javascript
sh.shardCollection("somedb.orders", { "user_id": "hashed" })
```

**Альтернатива:** Составной ключ `{ geo_zone: 1, created_at: 1 }` для range-запросов по регионам

---

### 7.2 Коллекция products (Товары)

**Схема коллекции:**
```javascript
{
  _id: ObjectId,
  product_id: String,         // Уникальный идентификатор товара
  name: String,               // Наименование
  category: String,           // Категория: "electronics", "audio", "appliances"
  geo_zone: String,           // Геозона доступности: "msk", "spb", "ekb", "kln"
  price: Number,              // Цена
  stock: Number,              // Остаток товара в данной геозоне
  attributes: {               // Дополнительные атрибуты
    color: String,
    size: String
  }
}
```

**Выбор шард-ключа:** `{ geo_zone: 1, category: 1, product_id: "hashed" }`

**Обоснование:**
- **geo_zone** — пользователи ищут товары в своём регионе, запросы локализуются на конкретные шарды
- **category** — внутри региона поиск по категориям эффективен (targeted queries)
- **product_id hashed** — равномерное распределение внутри гео+категории, предотвращает hot spots
- Типичный запрос `{ geo_zone: "msk", category: "electronics" }` попадает на один шард
- Обновления остатков (`stock`) локализованы в рамках геозоны
- Шарды можно привязать к физическим датацентрам в соответствующих регионах (zone sharding)

**Команда создания:**
```javascript
sh.shardCollection("somedb.products", { "geo_zone": 1, "category": 1, "product_id": "hashed" })
```

**Zone Sharding для гео-локализации:**
```javascript
// Привязка шардов к геозонам для минимизации latency
sh.addShardTag("shard1_rs", "msk")
sh.addShardTag("shard2_rs", "spb")
sh.addShardTag("shard3_rs", "ekb")

sh.addTagRange("somedb.products", { geo_zone: "msk", category: MinKey, product_id: MinKey },
                                   { geo_zone: "msk", category: MaxKey, product_id: MaxKey }, "msk")
sh.addTagRange("somedb.products", { geo_zone: "spb", category: MinKey, product_id: MinKey },
                                   { geo_zone: "spb", category: MaxKey, product_id: MaxKey }, "spb")
```

---

### 7.3 Коллекция carts (Корзины)

**Схема коллекции:**
```javascript
{
  _id: ObjectId,
  user_id: String,            // null для гостей
  session_id: String,         // ID сессии для гостей
  items: [
    {
      product_id: String,
      quantity: Number
    }
  ],
  status: String,             // "active", "ordered", "abandoned"
  created_at: ISODate,
  updated_at: ISODate,
  expires_at: ISODate         // TTL для автоочистки
}
```

**Выбор шард-ключа:** `{ session_id: "hashed" }`

**Обоснование:**
- Session_id уникален для каждой корзины - обеспечивает равномерное распределение
- Гостевые корзины ищутся по session_id - targeted query
- Пользовательские корзины можно искать через индекс на user_id
- TTL индекс на expires_at для автоматической очистки

**Команда создания:**
```javascript
sh.shardCollection("somedb.carts", { "session_id": "hashed" })
db.carts.createIndex({ "expires_at": 1 }, { expireAfterSeconds: 0 })
db.carts.createIndex({ "user_id": 1, "status": 1 })
```

---

## Задание 8. Выявление и устранение "горячих" шардов

### 8.1 Метрики мониторинга

| Метрика | Описание | Порог тревоги |
|---------|----------|---------------|
| `sh.status().shards` | Распределение чанков по шардам | Разница > 20% |
| `serverStatus().opcounters` | Операции чтения/записи на шарде | Разница > 2x между шардами |
| `serverStatus().locks` | Блокировки на коллекции | > 100ms ожидания |
| `currentOp()` | Долгие операции | > 1000ms |
| `db.collection.stats().avgObjSize` | Размер документов | Аномальный рост |
| CPU/Memory per shard | Системные ресурсы | > 80% утилизации |

**Команды мониторинга:**
```javascript
// Проверка распределения чанков
sh.status()

// Статистика операций по шардам
db.adminCommand({ serverStatus: 1 }).opcounters

// Проверка баланса
db.getSiblingDB("config").chunks.aggregate([
  { $group: { _id: "$shard", count: { $sum: 1 } } }
])
```

### 8.2 Механизмы устранения дисбаланса

**1. Ручная балансировка:**
```javascript
// Переместить чанк на другой шард
sh.moveChunk("somedb.products",
  { geo_zone: "msk", category: "electronics", product_id: MinKey },
  "shard2_rs"
)
```

**2. Настройка балансировщика:**
```javascript
// Включить балансировщик
sh.startBalancer()

// Настроить окно балансировки (ночное время)
db.settings.update(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)
```

**3. Добавление зон (Zone Sharding):**
```javascript
// Создать зону для горячей категории в конкретном регионе
sh.addShardTag("shard1_rs", "msk_electronics")
sh.addShardTag("shard2_rs", "msk_electronics")

// Привязать диапазон к зоне (распределить горячую категорию на 2 шарда)
sh.addTagRange(
  "somedb.products",
  { geo_zone: "msk", category: "electronics", product_id: MinKey },
  { geo_zone: "msk", category: "electronics", product_id: MaxKey },
  "msk_electronics"
)
```

**4. Разделение горячей категории:**
```javascript
// Добавить подкатегорию для более гранулярного распределения
sh.shardCollection("somedb.products_v2", {
  "geo_zone": 1,
  "category": 1,
  "subcategory": 1,
  "product_id": "hashed"
})
```

---

## Задание 9. Настройка чтения с реплик

### 9.1 Таблица операций чтения

| Коллекция | Операция | Read Preference | Обоснование |
|-----------|----------|-----------------|-------------|
| **products** | Каталог товаров | `secondaryPreferred` | Допустима задержка 1-2 сек, снижает нагрузку на primary |
| **products** | Страница товара | `secondaryPreferred` | Описание может быть слегка устаревшим |
| **products** | Проверка остатков при заказе | `primary` | Критично для избежания overselling |
| **orders** | История заказов пользователя | `secondaryPreferred` | Историческая информация, допустима задержка |
| **orders** | Статус текущего заказа | `primaryPreferred` | Пользователь ожидает актуальный статус |
| **orders** | Создание заказа | `primary` | Write concern: majority |
| **carts** | Получение корзины | `primary` | Критично для целостности корзины |
| **carts** | Добавление товара | `primary` | Write concern: majority |
| **carts** | Слияние корзин | `primary` | Атомарность операции |

### 9.2 Допустимая задержка репликации

| Коллекция | Максимальный replication lag | Обоснование |
|-----------|------------------------------|-------------|
| products (каталог) | 5 секунд | Цены/описания редко меняются |
| products (остатки) | 0 (primary only) | Риск продажи недоступного товара |
| orders | 2 секунды | История может быть немного устаревшей |
| carts | 0 (primary only) | Корзина должна быть всегда актуальной |

### 9.3 Настройка Read Preference в приложении

```python
# PyMongo пример
from pymongo import ReadPreference

# Каталог товаров - можно читать с secondary
products_catalog = db.products.with_options(
    read_preference=ReadPreference.SECONDARY_PREFERRED
)

# Остатки при оформлении заказа - только primary
def check_stock(product_id):
    return db.products.with_options(
        read_preference=ReadPreference.PRIMARY
    ).find_one({"product_id": product_id})

# Корзина - только primary
def get_cart(session_id):
    return db.carts.with_options(
        read_preference=ReadPreference.PRIMARY,
        read_concern=ReadConcern("majority")
    ).find_one({"session_id": session_id, "status": "active"})
```

---

## Задание 10. Миграция на Cassandra

### 10.1 Анализ данных для миграции

| Сущность | Критичность | Рекомендация | Обоснование |
|----------|-------------|--------------|-------------|
| **Корзины (carts)** | Высокая | Cassandra | Высокая скорость записи, TTL, масштабируемость |
| **История заказов** | Средняя | Cassandra | Append-only, геораспределение, eventual consistency OK |
| **Сессии пользователей** | Высокая | Cassandra | TTL, высокая скорость чтения/записи |
| **Заказы (активные)** | Критическая | MongoDB | Требуется strong consistency, транзакции |
| **Товары** | Критическая | MongoDB | Сложные запросы, фильтрация, агрегации |

**Вывод:** Мигрировать на Cassandra следует:
- Корзины (carts)
- Историю заказов (order_history)
- Пользовательские сессии (sessions)

### 10.2 Модель данных Cassandra

**Таблица: carts**
```cql
CREATE TABLE carts (
    session_id UUID,
    user_id UUID,
    product_id UUID,
    quantity INT,
    added_at TIMESTAMP,
    status TEXT,
    PRIMARY KEY ((session_id), added_at, product_id)
) WITH CLUSTERING ORDER BY (added_at DESC)
  AND default_time_to_live = 86400;  -- TTL 24 часа
```

**Partition key:** `session_id`
- Равномерное распределение по узлам (UUID случайный)
- Все товары одной корзины на одной партиции
- Эффективное чтение корзины целиком

**Clustering key:** `(added_at DESC, product_id)`
- Сортировка по времени добавления
- Уникальность товара в корзине

**Таблица: order_history**
```cql
CREATE TABLE order_history (
    user_id UUID,
    order_date DATE,
    order_id UUID,
    items LIST<FROZEN<item_type>>,
    total_amount DECIMAL,
    status TEXT,
    PRIMARY KEY ((user_id, order_date), order_id)
) WITH CLUSTERING ORDER BY (order_id DESC);

CREATE TYPE item_type (
    product_id UUID,
    name TEXT,
    quantity INT,
    price DECIMAL
);
```

**Partition key:** `(user_id, order_date)`
- Предотвращает "горячие" партиции (данные распределены по датам)
- Эффективный запрос истории за период
- Ограничивает размер партиции (~заказы за день)

**Таблица: sessions**
```cql
CREATE TABLE sessions (
    session_id UUID PRIMARY KEY,
    user_id UUID,
    created_at TIMESTAMP,
    last_activity TIMESTAMP,
    user_agent TEXT,
    ip_address TEXT
) WITH default_time_to_live = 3600;  -- TTL 1 час
```

### 10.3 Стратегии обеспечения целостности данных

| Сущность | Стратегия | Обоснование |
|----------|-----------|-------------|
| **carts** | Hinted Handoff + Read Repair | Низкая latency важнее consistency; данные временные (TTL) |
| **order_history** | Anti-Entropy Repair (ночью) | Историческая информация, допустима задержка; не критично для бизнес-операций |
| **sessions** | Hinted Handoff | Максимальная скорость; потеря сессии = повторный логин |

**Настройка Hinted Handoff:**
```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа
hinted_handoff_throttle_in_kb: 1024
```

**Настройка Read Repair:**
```cql
-- Для carts: read repair при чтении
ALTER TABLE carts WITH
  read_repair_chance = 0.1,        -- 10% запросов
  dclocal_read_repair_chance = 0.2; -- 20% локальных
```

**Anti-Entropy Repair (расписание):**
```bash
# Cron job для ночного repair
0 3 * * * nodetool repair order_history --full
```

### 10.4 Уровни консистентности

| Операция | Consistency Level | Обоснование |
|----------|-------------------|-------------|
| Запись в корзину | LOCAL_QUORUM | Баланс: низкая latency + durability |
| Чтение корзины | LOCAL_ONE | Скорость важнее; read repair компенсирует |
| Запись заказа в историю | QUORUM | Важность данных > latency |
| Чтение истории | LOCAL_ONE | Eventually consistent OK |
| Запись сессии | ONE | Максимальная скорость |
| Чтение сессии | LOCAL_ONE | Скорость > consistency |

### 10.5 Преимущества Cassandra для выбранных сущностей

1. **Корзины:**
   - Native TTL для автоочистки
   - Линейное масштабирование записи
   - Добавление узла не требует перебалансировки всех данных

2. **История заказов:**
   - Append-only модель идеальна для Cassandra
   - Геораспределение для локального доступа
   - Сжатие исторических данных

3. **Сессии:**
   - TTL из коробки
   - Высокая скорость чтения/записи
   - Leaderless = нет single point of failure

---

## Приложение: Команды и примеры

### MongoDB Sharding
```javascript
// Проверка статуса шардирования
sh.status()

// Распределение данных по шардам
db.orders.getShardDistribution()

// Добавление шарда
sh.addShard("shard3_rs/shard3a:27020,shard3b:27020,shard3c:27020")
```

### Cassandra CQL
```cql
-- Создание keyspace с репликацией
CREATE KEYSPACE mobile_world WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
};

-- Вставка в корзину
INSERT INTO carts (session_id, user_id, product_id, quantity, added_at, status)
VALUES (uuid(), null, uuid(), 2, toTimestamp(now()), 'active')
USING TTL 86400;

-- Чтение корзины
SELECT * FROM carts WHERE session_id = ? AND status = 'active';
```
