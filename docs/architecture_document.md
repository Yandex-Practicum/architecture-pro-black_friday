# Архитектурный документ: MongoDB и Cassandra для онлайн-магазина "Мобильный мир"

---

## Содержание

1. [Задание 7: Проектирование схем коллекций для шардирования](#задание-7)
2. [Задание 8: Выявление и устранение горячих шардов](#задание-8)
3. [Задание 9: Настройка чтения с реплик и консистентность](#задание-9)
4. [Задание 10: Миграция на Cassandra](#задание-10)

---

# Задание 7

## Проектирование схем коллекций для шардирования данных

### Обзор коллекций

| Коллекция | Назначение | Основные операции |
|-----------|------------|-------------------|
| **orders** | Заказы клиентов | Создание, поиск по user_id, статус |
| **products** | Каталог товаров | Поиск по категории, обновление остатков |
| **carts** | Корзины пользователей | CRUD, слияние гостевой корзины |

### Схемы коллекций

#### orders

```javascript
{
  _id: ObjectId,
  user_id: ObjectId,
  order_date: ISODate,
  items: [{ product_id: ObjectId, name: String, quantity: Number, price: Decimal128 }],
  status: String,  // "pending" | "paid" | "shipped" | "delivered"
  total_amount: Decimal128,
  geo_zone: String
}
```

#### products

```javascript
{
  _id: ObjectId,
  name: String,
  category: String,
  price: Decimal128,
  stock: { moscow: Number, spb: Number, ekb: Number },
  attributes: { color: String, size: String, brand: String }
}
```

#### carts

```javascript
{
  _id: ObjectId,
  user_id: ObjectId,
  session_id: String,
  items: [{ product_id: ObjectId, quantity: Number }],
  status: String,  // "active" | "ordered" | "abandoned"
  created_at: ISODate,
  updated_at: ISODate,
  expires_at: ISODate  // TTL
}
```

### Выбор Shard Keys

| Коллекция | Shard Key | Тип | Обоснование |
|-----------|-----------|-----|-------------|
| **orders** | `{user_id: 1, _id: 1}` | Compound Range | История заказов пользователя на одном шарде |
| **products** | `{category: 1, _id: 1}` | Compound Range | Товары категории локальны для запросов каталога |
| **carts** | `{_id: "hashed"}` | Hashed | Равномерное распределение разнородных корзин |

### Команды MongoDB

```javascript
// Включение шардирования
sh.enableSharding("mobile_world")

// orders
db.orders.createIndex({ user_id: 1, _id: 1 })
sh.shardCollection("mobile_world.orders", { user_id: 1, _id: 1 })

// products
db.products.createIndex({ category: 1, _id: 1 })
sh.shardCollection("mobile_world.products", { category: 1, _id: 1 })

// carts
sh.shardCollection("mobile_world.carts", { _id: "hashed" })
```

### Риски и митигация

| Риск | Митигация |
|------|-----------|
| Hotspot на категории "electronics" | Hashed suffix или pre-splitting |
| Jumbo chunks для активных пользователей | Compound key с _id |
| Scatter-gather для корзин | Индексы на session_id и user_id |

---

# Задание 8

## Выявление и устранение горячих шардов

### Проблема

Категория "Электроника" генерирует 70% запросов → перегрузка одного шарда.

### Метрики мониторинга

| Метрика | Порог алерта | Команда |
|---------|--------------|---------|
| **opcounters** | Разница > 50% | `db.adminCommand({ serverStatus: 1 }).opcounters` |
| **chunks count** | Разница > 20% | `db.products.getShardDistribution()` |
| **globalLock.activeClients** | > 100 | `db.serverStatus().globalLock` |
| **replication lag** | > 10 сек | `rs.printSecondaryReplicationInfo()` |

### Скрипт диагностики

```javascript
function checkChunkBalance(namespace) {
  const chunks = db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: namespace } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).toArray();
  
  chunks.forEach(s => {
    const pct = (s.count / chunks.reduce((sum, x) => sum + x.count, 0) * 100).toFixed(1);
    print(`${s._id}: ${s.count} chunks (${pct}%)`);
  });
}
```

### Механизмы устранения

#### 1. Pre-splitting популярных категорий

```javascript
sh.splitAt("mobile_world.products", { category: "electronics", _id: ObjectId("400000000000000000000000") })
sh.moveChunk("mobile_world.products", { category: "electronics", _id: ObjectId("400000000000000000000000") }, "shard2")
```

#### 2. Изменение Shard Key на hashed

```javascript
sh.shardCollection("mobile_world.products_v2", { category: 1, _id: "hashed" })
```

#### 3. Zone Sharding

```javascript
sh.addShardTag("shard1", "electronics_zone_1")
sh.addShardTag("shard2", "electronics_zone_2")
sh.addTagRange("mobile_world.products", 
  { category: "electronics", _id: MinKey },
  { category: "electronics", _id: ObjectId("800000000000000000000000") },
  "electronics_zone_1"
)
```

#### 4. Настройка балансировщика

```javascript
db.getSiblingDB("config").settings.save({ _id: "chunksize", value: 64 })
sh.startBalancer()
```

### Алерты (Prometheus)

```yaml
- alert: ShardImbalance
  expr: (max(mongodb_chunks_total) - min(mongodb_chunks_total)) / avg(mongodb_chunks_total) > 0.3
  for: 10m
```

---

# Задание 9

## Настройка чтения с реплик и консистентность

### Сводная таблица Read Preference

| Коллекция | Операция | Read Preference | Допустимая задержка | Риск при eventual |
|-----------|----------|-----------------|---------------------|-------------------|
| **products** | Каталог | `secondaryPreferred` | 10 сек | Низкий |
| **products** | Остатки | **`primary`** | 0 | **Overselling** |
| **orders** | Статус | `primaryPreferred` | 2 сек | Устаревший статус |
| **orders** | История | `secondaryPreferred` | 60 сек | Низкий |
| **orders** | Аналитика | `secondary` | 5 мин | Нет |
| **carts** | Активная | **`primary`** | 0 | **Потеря товаров** |
| **carts** | Слияние | **`primary`** | 0 | **Race condition** |

### Обоснование

**Primary обязателен для:**
- **Остатки товаров** — риск продажи отсутствующего товара
- **Корзины** — пользователь ожидает мгновенную реакцию UI
- **Проверка перед оплатой** — финансовые риски

**Secondary допустим для:**
- **Каталог** — описания/цены меняются редко
- **История заказов** — старые данные не меняются
- **Аналитика** — не требует real-time

### Примеры кода

```javascript
// Остатки — только primary
db.products.findOne({ _id: productId }, { stock: 1 }).readPref("primary")

// Каталог — secondaryPreferred
db.products.find({ category: "electronics" })
  .readPref("secondaryPreferred", [{ maxStalenessSeconds: 10 }])

// Корзина — только primary
db.carts.findOne({ user_id: userId, status: "active" }).readPref("primary")
```

### Настройка maxStalenessSeconds

| Тип данных | maxStalenessSeconds |
|------------|---------------------|
| Критичные | primary (не применимо) |
| Оперативные | 2-5 |
| Справочные | 10-30 |
| Аналитические | 60-300 |

---

# Задание 10

## Миграция на Cassandra

### 10.1 Анализ данных для миграции

| Сущность | Паттерн | Рекомендация | Обоснование |
|----------|---------|--------------|-------------|
| products | Update-heavy | **MongoDB** | Частые обновления остатков |
| orders (активные) | ACID нужен | **MongoDB** | Транзакции при оформлении |
| **order_history** | Append-only | **Cassandra** ✓ | Write-once, read по user_id |
| carts | Update-heavy | **MongoDB** | Strong consistency для UX |
| **user_sessions** | Write-heavy, TTL | **Cassandra** ✓ | Eventual OK, высокая нагрузка |
| **product_views** | Append-only | **Cassandra** ✓ | Аналитика, time-series |
| **click_events** | Append-only | **Cassandra** ✓ | Огромный объём записи |

### 10.2 Модель данных Cassandra

#### order_history

```sql
CREATE TABLE mobile_world.order_history (
    user_id UUID,
    year_month TEXT,
    order_date TIMESTAMP,
    order_id UUID,
    items LIST<FROZEN<order_item>>,
    total_amount DECIMAL,
    status TEXT,
    PRIMARY KEY ((user_id, year_month), order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC);
```

| Компонент | Значение | Почему |
|-----------|----------|--------|
| Partition Key | `(user_id, year_month)` | Ограничение размера партиции |
| Clustering Key | `order_date DESC` | Новые заказы первыми |

#### user_sessions

```sql
CREATE TABLE mobile_world.user_sessions (
    session_id UUID PRIMARY KEY,
    user_id UUID,
    created_at TIMESTAMP,
    last_activity TIMESTAMP,
    data MAP<TEXT, TEXT>
) WITH default_time_to_live = 86400;
```

#### product_views

```sql
CREATE TABLE mobile_world.product_views (
    product_id UUID,
    view_date DATE,
    view_time TIMESTAMP,
    view_id TIMEUUID,
    user_id UUID,
    PRIMARY KEY ((product_id, view_date), view_time, view_id)
) WITH CLUSTERING ORDER BY (view_time DESC);
```

### 10.3 Стратегии обеспечения целостности

| Таблица | Hinted Handoff | Read Repair | Anti-Entropy | Consistency Level |
|---------|----------------|-------------|--------------|-------------------|
| order_history | ✅ | 10% | Weekly | `LOCAL_QUORUM` |
| user_sessions | ✅ | 0% | — | `LOCAL_ONE` |
| product_views | ✅ | 5% | Monthly | `LOCAL_ONE` |
| click_events | ✅ | 0% | — | `ANY` |

#### Обоснование выбора

**order_history — LOCAL_QUORUM + Read Repair 10%**
- История важна для пользователя, нужна консистентность
- Еженедельный repair для полной синхронизации

**user_sessions — LOCAL_ONE, без Read Repair**
- Latency критична (каждый запрос)
- TTL 24 часа — данные автоматически удаляются
- Потеря сессии = повторный логин (приемлемо)

**click_events — ANY, без Read Repair**
- Write-only workload, максимальная производительность
- TTL 7 дней, данные быстро устаревают

### Гибридная архитектура

```
┌─────────────────────────────┐   ┌─────────────────────────────┐
│         MongoDB             │   │         Cassandra           │
│    (Strong Consistency)     │   │    (High Availability)      │
├─────────────────────────────┤   ├─────────────────────────────┤
│ • products (остатки)        │   │ • order_history             │
│ • orders (активные)         │   │ • user_sessions             │
│ • carts                     │   │ • product_views             │
│                             │   │ • click_events              │
└─────────────────────────────┘   └─────────────────────────────┘
```

---

## Итоговая таблица решений

| Аспект | Решение | Обоснование |
|--------|---------|-------------|
| Shard Key orders | `{user_id: 1, _id: 1}` | Локальность истории пользователя |
| Shard Key products | `{category: 1, _id: 1}` | Локальность каталога |
| Shard Key carts | `{_id: "hashed"}` | Равномерное распределение |
| Hotspot mitigation | Pre-splitting + Zone Sharding | Распределение "electronics" |
| Read остатков | Primary only | Избежание overselling |
| Read каталога | SecondaryPreferred | Разгрузка primary |
| Cassandra для | Sessions, History, Events | Write-heavy, eventual OK |

---

## Метрики мониторинга

| Метрика | Инструмент | Порог |
|---------|------------|-------|
| Chunks per shard | MongoDB | Разница > 20% |
| Replication lag | MongoDB | > 10 сек |
| Opcounters | Prometheus | Разница > 50% |
| Cassandra write latency | Prometheus | p99 > 50ms |
| Session creation rate | Application | Аномальный рост |

---

## Действия при проблемах

| Проблема | Действие |
|----------|----------|
| Горячий шард | Pre-split + moveChunk |
| Высокий replication lag | Проверить сеть, увеличить oplog |
| Overselling | Проверить read preference |
| Cassandra partition hotspot | Пересмотреть partition key |

