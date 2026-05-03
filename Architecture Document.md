# Архитектурный документ: шардирование, репликация, консистентность и Cassandra

Интернет-магазин «Мобильный мир» — MongoDB + Cassandra

---

## Оглавление

1. [Схемы коллекций MongoDB и выбор шард-ключей](#1-схемы-коллекций-mongodb-и-выбор-шард-ключей)
2. [Выявление и устранение горячих шардов](#2-выявление-и-устранение-горячих-шардов)
3. [Настройка чтения с реплик и консистентность](#3-настройка-чтения-с-реплик-и-консистентность)
4. [Cassandra: анализ данных, модель и стратегии целостности](#4-cassandra-анализ-данных-модель-и-стратегии-целостности)

---

## 1. Схемы коллекций MongoDB и выбор шард-ключей

### 1.1. Коллекция `orders`

**Схема документа:**

```json
{
  "_id": ObjectId("..."),
  "customer_id": "cust_100500",
  "created_at": ISODate("2026-04-30T12:00:00Z"),
  "items": [
    { "product_id": "prod_1", "name": "Смартфон X", "quantity": 1, "price": 49990 },
    { "product_id": "prod_2", "name": "Чехол Y", "quantity": 2, "price": 990 }
  ],
  "status": "delivered",
  "total": 51970,
  "geo_zone": "moscow"
}
```

**Шард-ключ: `{ customer_id: "hashed" }`** — хэшированное шардирование

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `customer_id` hashed | Равномерное распределение; история клиента — targeted query | Запросы по `geo_zone` / `status` — scatter-gather |
| `geo_zone` | Локальность по региону | Низкая кардинальность — перекос данных |
| `_id` hashed | Идеальная равномерность записи | Все бизнес-запросы — scatter-gather |
| `{ geo_zone, customer_id }` | Targeted по региону и клиенту | Неравномерное распределение между геозонами |

**Обоснование:**
- **Запись** — равномерно по шардам, нет hot spot при массовом создании заказов (Black Friday).
- **История клиента** (`customer_id`) — targeted query на один шард.
- **Статус заказа** по `_id` — targeted (mongos знает шард).
- Компромисс: аналитика по `geo_zone` / `status` — scatter-gather, допустимо.

**Команды:**

```javascript
sh.enableSharding("mobilnyimir")
sh.shardCollection("mobilnyimir.orders", { customer_id: "hashed" })

db.orders.createIndex({ customer_id: 1, created_at: -1 })
db.orders.createIndex({ status: 1 })
```

### 1.2. Коллекция `products`

**Схема документа:**

```json
{
  "_id": ObjectId("..."),
  "name": "Смартфон X",
  "category": "electronics",
  "price": 49990,
  "stock": {
    "moscow": 120,
    "ekaterinburg": 50,
    "kaliningrad": 30
  },
  "attributes": {
    "color": "black",
    "size": "6.1 inch"
  }
}
```

**Шард-ключ: `{ category: 1, _id: 1 }`** — ranged шардирование по составному ключу

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `{ category, _id }` compound | Поиск по категории — targeted; `_id` даёт кардинальность | Популярная категория может создать hot shard |
| `_id` hashed | Равномерная запись | Поиск по категории — scatter-gather |
| `category` hashed | Равномерность по категориям | Хэш ломает диапазонные запросы |
| `price` | Range по цене targeted | Очень неравномерное распределение |

**Обоснование:**
- **Поиск по категории** — targeted, все товары категории на одном шарде.
- **Фильтрация по цене** внутри категории — данные рядом, эффективно.
- **Обновление остатков** — targeted при указании `category`.
- `_id` решает проблему низкой кардинальности `category`.
- Риск: горячая категория (см. раздел 2).

**Команды:**

```javascript
sh.shardCollection("mobilnyimir.products", { category: 1, _id: 1 })

db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ name: "text" })
```

### 1.3. Коллекция `carts`

**Схема документа:**

```json
{
  "_id": ObjectId("..."),
  "user_id": "cust_100500",
  "session_id": "sess_abc123",
  "items": [
    { "product_id": "prod_1", "quantity": 1 },
    { "product_id": "prod_2", "quantity": 3 }
  ],
  "status": "active",
  "created_at": ISODate("2026-04-30T10:00:00Z"),
  "updated_at": ISODate("2026-04-30T11:30:00Z"),
  "expires_at": ISODate("2026-05-07T10:00:00Z")
}
```

**Шард-ключ: `{ _id: "hashed" }`** — хэшированное шардирование

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `_id` hashed | Равномерное распределение; CRUD по `_id` — targeted | Поиск по `user_id` / `session_id` — scatter-gather |
| `user_id` hashed | Targeted по `user_id` | Гостевые корзины (`user_id = null`) — все на одном шарде, hot spot |
| `session_id` hashed | Targeted для гостей | Запросы по `user_id` — scatter-gather |
| `status` | — | Кардинальность 3 — непригоден |

**Обоснование:**
- Корзины — короткоживущие данные с TTL, scatter-gather по `user_id` / `session_id` приемлем.
- Нет hot spot на гостевых корзинах (в отличие от `user_id`).
- CRUD по `_id` — targeted. Слияние корзин — обе операции по `_id`, targeted.
- TTL-индекс работает локально на каждом шарде.

**Команды:**

```javascript
sh.shardCollection("mobilnyimir.carts", { _id: "hashed" })

db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

### 1.4. Сводная таблица шард-ключей

| Коллекция | Шард-ключ | Стратегия | Обоснование |
|-----------|-----------|-----------|-------------|
| `orders` | `{ customer_id: "hashed" }` | Hashed | Равномерная запись; история клиента — targeted |
| `products` | `{ category: 1, _id: 1 }` | Ranged (compound) | Поиск по категории targeted; `_id` даёт кардинальность |
| `carts` | `{ _id: "hashed" }` | Hashed | Нет hot spot на гостях; CRUD по `_id` — targeted |

---

## 2. Выявление и устранение горячих шардов

### 2.1. Проблема

При ranged-шардировании `products` по `{ category: 1, _id: 1 }` все товары категории «Электроника» попадают в смежные чанки на одном шарде. 70% запросов приходится на эту категорию — hot shard.

### 2.2. Метрики мониторинга

#### Распределение данных

```javascript
db.products.getShardDistribution()
sh.status()

db.getSiblingDB("config").chunks.aggregate([
  { $match: { ns: "mobilnyimir.products" } },
  { $group: { _id: "$shard", count: { $sum: 1 } } }
])
```

#### Нагрузка на шарды

```javascript
db.serverStatus().opcounters
db.currentOp({ active: true, secs_running: { $gt: 1 } })
```

#### Латентность и очереди

```javascript
db.serverStatus().globalLock
db.serverStatus().wiredTiger.cache
```

#### Активность балансировщика

```javascript
db.getSiblingDB("config").changelog.find({ what: "moveChunk.commit" }).sort({ time: -1 }).limit(10)
sh.getBalancerState()
sh.isBalancerRunning()
```

#### Сводная таблица метрик

| Метрика | Команда / источник | Порог тревоги |
|---------|-------------------|---------------|
| Перекос чанков | `getShardDistribution()` | > 20% разницы |
| Перекос объёма данных | `getShardDistribution()` | > 30% разницы |
| Запросов/сек на шард | `serverStatus().opcounters` | Один шард > 2x среднего |
| Очередь блокировок | `serverStatus().globalLock` | `currentQueue.total` > 0 постоянно |
| Латентность p95 | Prometheus / Grafana | > 100ms при норме < 20ms |
| Cache miss WiredTiger | `serverStatus().wiredTiger.cache` | `pages read into cache` растёт |
| Replication lag | `rs.status().members[].optimeDate` | Lag > 10 сек |

### 2.3. Механизмы устранения

#### Ручное разбиение и миграция чанков (быстрое решение)

```javascript
db.getSiblingDB("config").chunks.find({
  ns: "mobilnyimir.products",
  "min.category": { $lte: "electronics" },
  "max.category": { $gte: "electronics" }
})

sh.splitAt("mobilnyimir.products", { category: "electronics", _id: ObjectId("mid_point_id") })
sh.moveChunk("mobilnyimir.products", { category: "electronics", _id: ObjectId("...") }, "shard2ReplSet")
```

#### Зонное шардирование (tag-aware)

Распределить «Электронику» по нескольким шардам:

```javascript
sh.addShardTag("shard1ReplSet", "electronics_A")
sh.addShardTag("shard2ReplSet", "electronics_B")

sh.addTagRange("mobilnyimir.products",
  { category: "electronics", _id: MinKey },
  { category: "electronics", _id: ObjectId("mid_point_id") },
  "electronics_A"
)
sh.addTagRange("mobilnyimir.products",
  { category: "electronics", _id: ObjectId("mid_point_id") },
  { category: "electronics", _id: MaxKey },
  "electronics_B"
)
```

#### Изменение шард-ключа (кардинальное решение)

```javascript
// MongoDB 7.0+
db.adminCommand({ unshardCollection: "mobilnyimir.products" })
sh.shardCollection("mobilnyimir.products", { _id: "hashed" })
```

Компромисс: запросы по категории станут scatter-gather, но нагрузка равномерна. Компенсация — Redis-кеш.

#### Настройка балансировщика

```javascript
db.getSiblingDB("config").settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 64 } },
  { upsert: true }
)

db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)
```

#### Добавление шардов

```javascript
sh.addShard("shard3ReplSet/shard3-1:27017,shard3-2:27017,shard3-3:27017")
```

### 2.4. План действий при обнаружении hot shard

| Шаг | Действие | Когда применять |
|-----|----------|-----------------|
| 1 | Мониторинг метрик (opcounters, latency, chunk distribution) | Превентивно |
| 2 | Уменьшить размер чанка до 64 МБ | Первые признаки перекоса |
| 3 | Разбить крупные чанки и мигрировать вручную | Быстрое снятие нагрузки |
| 4 | Зонное шардирование для горячих категорий | Устойчивое решение |
| 5 | Добавить шард | Общий рост нагрузки |
| 6 | Перешардировать на hashed-ключ | Hot spots в разных категориях |

---

## 3. Настройка чтения с реплик и консистентность

### 3.1. Коллекция `products`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Карточка товара | `secondaryPreferred` | Данные меняются редко, устаревание на 1–2 сек незаметно |
| Поиск по категории и цене | `secondaryPreferred` | Каталожные запросы тяжёлые и частые, secondary разгружает primary |
| Проверка остатка при добавлении в корзину | `primary` | **Критично.** Устаревший остаток → продажа недоступного товара |
| Списание остатка | `primary` | Запись — всегда primary. `findOneAndUpdate` с `stock >= quantity` |

**Допустимый лаг:** до 2 сек для каталога. Для остатков — недопустим.

### 3.2. Коллекция `orders`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Статус заказа (для покупателя) | `primary` | **Критично.** Пользователь ожидает мгновенное обновление после оплаты |
| История заказов | `secondaryPreferred` | Исторические заказы не меняются, задержка 1–2 сек допустима |
| Аналитика и отчёты | `secondary` | Тяжёлые запросы изолируются от primary |
| Создание заказа | `primary` | Запись, транзакция (заказ + списание) |

**Допустимый лаг:** до 2 сек для истории, до 10 сек для аналитики. Для статуса — недопустим.

### 3.3. Коллекция `carts`

| Операция | Read Preference | Обоснование |
|----------|----------------|-------------|
| Активная корзина | `primary` | **Критично.** Устаревшее чтение → потеря товара, дублирование |
| Добавление/удаление товара | `primary` | Запись — `$push` / `$pull` по `items` |
| Слияние гостевой → пользовательской | `primary` | **Критично.** Затрагивает две корзины, устаревшие данные → потеря товаров |
| Очистка брошенных корзин | `secondary` | Фоновый процесс, задержка некритична |

**Допустимый лаг:** до 30 сек для фоновой очистки. Для пользовательских операций — недопустим.

### 3.4. Сводная таблица

| Коллекция | Операция | Read Preference | Макс. лаг |
|-----------|----------|----------------|-----------|
| `products` | Карточка товара | `secondaryPreferred` | 2 сек |
| `products` | Каталог | `secondaryPreferred` | 2 сек |
| `products` | Проверка остатка | `primary` | — |
| `orders` | Статус заказа | `primary` | — |
| `orders` | История заказов | `secondaryPreferred` | 2 сек |
| `orders` | Аналитика | `secondary` | 10 сек |
| `carts` | Активная корзина | `primary` | — |
| `carts` | Слияние корзин | `primary` | — |
| `carts` | Очистка брошенных | `secondary` | 30 сек |

### 3.5. Настройка maxStalenessSeconds

```javascript
// Каталог — лаг не более 5 сек
db.products.find({ category: "electronics" }).readPref("secondaryPreferred", [], { maxStalenessSeconds: 5 })

// История заказов — лаг не более 5 сек
db.orders.find({ customer_id: "cust_123" }).readPref("secondaryPreferred", [], { maxStalenessSeconds: 5 })

// Аналитика — лаг до 30 сек
db.orders.aggregate([...]).readPref("secondary", [], { maxStalenessSeconds: 30 })
```

### 3.6. Принципы выбора

1. **`primary`** — данные меняются часто, устаревшее чтение = бизнес-риск (продажа отсутствующего товара, потеря товара из корзины, неверный статус)
2. **`secondaryPreferred`** — данные меняются редко или задержка 1–2 сек незаметна (каталог, история)
3. **`secondary`** — тяжёлые фоновые/аналитические операции, изоляция от primary

---

## 4. Cassandra: анализ данных, модель и стратегии целостности

### 4.1. Классификация данных и обоснование

| Сущность | Целостность | Скорость записи | Скорость чтения | Геораспределённость |
|----------|-------------|-----------------|-----------------|---------------------|
| Товары (остатки) | **Критическая** | Высокая | Высокая | Средняя |
| Заказы (активные) | **Критическая** | Высокая (Black Friday) | Средняя | Средняя |
| Корзины | Средняя | Очень высокая | Очень высокая | Высокая |
| История заказов | Низкая (append-only) | Низкая | Средняя | Высокая |
| Сессии | Низкая (пересоздаваемые) | Очень высокая | Очень высокая | **Критическая** |

#### Где Cassandra имеет смысл

| Сущность | Cassandra? | Обоснование |
|----------|:----------:|-------------|
| **Сессии** | **Да** | Огромный объём записи, TTL, eventual consistency допустима, геораспределённость критична |
| **История заказов** | **Да** | Append-only, партиционирование по `customer_id`, time-series с кластерной сортировкой |
| **Корзины** | **Да** | Высокая частота I/O, TTL, eventual consistency допустима |
| **Товары (остатки)** | **Нет** | Атомарное списание требует строгой консистентности; LWT в Cassandra медленные |
| **Заказы (активные)** | **Нет** | Multi-partition транзакции невозможны; потеря заказа — критический риск |

### 4.2. Концептуальная модель данных (CQL)

#### Пользовательские сессии

```sql
CREATE TABLE sessions (
    session_id  text,
    user_id     text,
    geo_zone    text,
    data        map<text, text>,
    created_at  timestamp,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 3600
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'HOURS',
                    'compaction_window_size': 1};
```

**Partition key: `session_id`**
- Высокая кардинальность — равномерное распределение по кластеру.
- Точечный доступ (get/set/delete) — одна партиция.
- TTL 1 час — автоматическая очистка, нет роста данных.
- Горячие партиции невозможны: 1 сессия = 1 пользователь.

#### История заказов

```sql
CREATE TYPE order_item (
    product_id  text,
    name        text,
    quantity    int,
    price       decimal
);

CREATE TABLE orders_by_customer (
    customer_id text,
    year_month  text,
    created_at  timestamp,
    order_id    uuid,
    items       list<frozen<order_item>>,
    status      text,
    total       decimal,
    geo_zone    text,
    PRIMARY KEY ((customer_id, year_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

**Partition key: `(customer_id, year_month)` (составной)**
- `year_month` ограничивает рост партиции: макс. сотни заказов клиента за месяц.
- Запрос «история за апрель» → одна партиция, без scatter.
- Горячие партиции маловероятны даже для VIP-клиентов.

**Clustering key: `(created_at DESC, order_id)`**
- Последние заказы возвращаются первыми.
- `order_id` — уникальность при совпадении `created_at`.

#### Корзины

```sql
CREATE TYPE cart_item (
    product_id  text,
    quantity    int
);

CREATE TABLE carts (
    cart_id     uuid,
    user_id     text,
    session_id  text,
    status      text,
    items       list<frozen<cart_item>>,
    created_at  timestamp,
    updated_at  timestamp,
    PRIMARY KEY (cart_id)
) WITH default_time_to_live = 604800;

-- Lookup-таблицы (денормализация)
CREATE TABLE active_cart_by_user (
    user_id   text,
    cart_id   uuid,
    PRIMARY KEY (user_id)
);

CREATE TABLE active_cart_by_session (
    session_id  text,
    cart_id     uuid,
    PRIMARY KEY (session_id)
);
```

**Partition key: `cart_id` (UUID)**
- Максимальная равномерность (UUID — случайный).
- CRUD по `cart_id` — одна партиция.
- Lookup-таблицы — денормализация, высокая кардинальность ключа.
- TTL 7 дней — объём стабилен.
- Решардинг: UUID через consistent hashing, при добавлении узла перемещается ~1/N данных.

### 4.3. Сводная таблица ключей Cassandra

| Таблица | Partition Key | Clustering Key | Риски горячих партиций |
|---------|--------------|----------------|------------------------|
| `sessions` | `session_id` | — | Нет (1 сессия = 1 запись) |
| `orders_by_customer` | `(customer_id, year_month)` | `created_at DESC, order_id` | Минимальный (бакетирование по месяцу) |
| `carts` | `cart_id` (UUID) | — | Нет (UUID — случайный) |
| `active_cart_by_user` | `user_id` | — | Нет (1 корзина на пользователя) |
| `active_cart_by_session` | `session_id` | — | Нет (1 корзина на сессию) |

### 4.4. Стратегии обеспечения целостности

#### Обзор стратегий

| Стратегия | Как работает | Влияние на latency | Когда данные консистентны |
|-----------|-------------|--------------------|------------------------------------|
| **Hinted Handoff** | Координатор хранит запись для недоступного узла, доставляет при восстановлении | Не влияет | После восстановления (минуты) |
| **Read Repair** | При чтении координатор сравнивает реплики, обновляет устаревшие | Добавляет latency | При следующем чтении |
| **Anti-Entropy Repair** | `nodetool repair` сравнивает Merkle-деревья реплик | Не влияет на клиентов | По расписанию (часы/дни) |

#### Выбор по сущностям

**Сессии:**

| Стратегия | Применять? | Обоснование |
|-----------|:---------:|-------------|
| Hinted Handoff | **Да** | Основной механизм. TTL 1 час — если hint не успел, сессия уже протухла |
| Read Repair | Нет | Добавляет latency при каждом чтении; сессии читаются очень часто |
| Anti-Entropy Repair | Нет | Данные с TTL 1 час удалятся раньше, чем запустится repair |

Consistency Level: **Write ONE / Read ONE** — минимальная latency, потеря сессии некритична.

**История заказов:**

| Стратегия | Применять? | Обоснование |
|-----------|:---------:|-------------|
| Hinted Handoff | **Да** | Базовая защита при недоступности узла |
| Read Repair | **Да** | Расхождения исправляются при просмотре истории; latency допустима |
| Anti-Entropy Repair | **Да** | Старые заказы не читаются месяцами — `nodetool repair` раз в неделю |

Consistency Level: **Write QUORUM / Read ONE** — заказ не должен потеряться, eventual consistency при чтении допустима.

**Корзины:**

| Стратегия | Применять? | Обоснование |
|-----------|:---------:|-------------|
| Hinted Handoff | **Да** | Частые обновления, hints доставят при сбоях |
| Read Repair | **Да** | Корзина читается при каждом открытии страницы — расхождения исправятся |
| Anti-Entropy Repair | Нет | TTL 7 дней + постоянные чтения — Read Repair достаточен |

Consistency Level: **Write LOCAL_QUORUM / Read LOCAL_ONE** — баланс надёжности и скорости.

### 4.5. Сводная таблица стратегий целостности

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy Repair | Write CL | Read CL |
|----------|:-:|:-:|:-:|----------|---------|
| Сессии | + | — | — | ONE | ONE |
| История заказов | + | + | + (еженедельно) | QUORUM | ONE |
| Корзины | + | + | — | LOCAL_QUORUM | LOCAL_ONE |
