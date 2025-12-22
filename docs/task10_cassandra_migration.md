# Задание 10. Миграция на Cassandra

## Контекст

При нагрузке 50 000 req/sec во время "чёрной пятницы" MongoDB с Range-Based Sharding показала высокую задержку при масштабировании из-за полного перераспределения данных между шардами.

**Преимущества Cassandra:**
- Leaderless репликация (нет single point of failure)
- Consistent hashing — добавление ноды перемещает только ~1/N данных
- Линейное горизонтальное масштабирование
- Оптимизирована для write-heavy нагрузок

---

# Задание 10.1. Анализ данных для миграции

## 1.1 Критерии выбора данных для Cassandra

| Критерий | Cassandra подходит | MongoDB лучше |
|----------|-------------------|---------------|
| Паттерн записи | Write-heavy, append-only | Update-heavy |
| Консистентность | Eventual OK | Strong required |
| Запросы | По известному ключу | Ad-hoc, aggregations |
| Масштабирование | Линейное, быстрое | Сложнее, chunk migration |
| Транзакции | Не нужны | ACID нужен |

## 1.2 Анализ сущностей интернет-магазина

| Сущность | Паттерн | Критичность целостности | Рекомендация |
|----------|---------|------------------------|--------------|
| **products** (товары) | Update-heavy (остатки) | Высокая (overselling) | **MongoDB** |
| **orders** (активные заказы) | Write-then-read | Высокая (оплата) | **MongoDB** |
| **order_history** (история) | Append-only, read-heavy | Средняя | **Cassandra** ✓ |
| **carts** (корзины) | Update-heavy | Высокая (UX) | **MongoDB** |
| **user_sessions** | Write-heavy, TTL | Низкая | **Cassandra** ✓ |
| **product_views** (просмотры) | Append-only, analytics | Низкая | **Cassandra** ✓ |
| **click_events** (события) | Append-only, high volume | Низкая | **Cassandra** ✓ |

## 1.3 Обоснование выбора

### Данные для Cassandra:

**1. order_history (История заказов)**
- ✅ Append-only: заказ создаётся один раз, не изменяется
- ✅ Read по user_id: известный partition key
- ✅ Eventual consistency OK: история не влияет на бизнес-операции
- ✅ Высокий объём: миллионы заказов, нужно масштабирование

**2. user_sessions (Сессии пользователей)**
- ✅ Write-heavy: создание/обновление при каждом запросе
- ✅ TTL: автоматическое удаление старых сессий
- ✅ Простые запросы: get by session_id
- ✅ Eventual consistency OK: потеря сессии = повторный логин

**3. product_views (Просмотры товаров)**
- ✅ Append-only: аналитика, никогда не обновляется
- ✅ Огромный объём: тысячи событий в секунду
- ✅ Eventual consistency OK: аналитика не real-time критична

**4. click_events (Клик-стрим)**
- ✅ Time-series данные
- ✅ Только вставка, без обновлений
- ✅ Огромный объём записи

### Данные остаются в MongoDB:

**1. products (Товары)**
- ❌ Update-heavy: остатки меняются при каждой покупке
- ❌ Сложные запросы: фильтрация по категории, цене, атрибутам
- ❌ Strong consistency: риск overselling

**2. orders (Активные заказы)**
- ❌ Нужны транзакции: списание остатков + создание заказа
- ❌ Частые обновления статуса
- ❌ Strong consistency: риск двойной оплаты

**3. carts (Корзины)**
- ❌ Update-heavy: добавление/удаление товаров
- ❌ Strong consistency: пользователь ожидает мгновенную реакцию

---

# Задание 10.2. Модель данных Cassandra

## 2.1 Таблица order_history

### Концептуальная модель

```
┌─────────────────────────────────────────────────────────────────┐
│                        order_history                            │
├─────────────────────────────────────────────────────────────────┤
│ Partition Key: (user_id, year_month)                            │
│ Clustering Key: (order_date DESC, order_id)                     │
├─────────────────────────────────────────────────────────────────┤
│ Запросы:                                                        │
│ - История заказов пользователя за месяц                         │
│ - Последние N заказов пользователя                              │
└─────────────────────────────────────────────────────────────────┘
```

### CQL Schema

```sql
CREATE KEYSPACE mobile_world WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
};

CREATE TABLE mobile_world.order_history (
    user_id UUID,
    year_month TEXT,           -- '2024-11' для bucket по месяцам
    order_date TIMESTAMP,
    order_id UUID,
    items LIST<FROZEN<order_item>>,
    total_amount DECIMAL,
    status TEXT,
    geo_zone TEXT,
    PRIMARY KEY ((user_id, year_month), order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC)
  AND default_time_to_live = 94608000;  -- 3 года

CREATE TYPE mobile_world.order_item (
    product_id UUID,
    name TEXT,
    quantity INT,
    price DECIMAL
);
```

### Обоснование ключей

| Компонент | Значение | Почему |
|-----------|----------|--------|
| **Partition Key** | `(user_id, year_month)` | Распределение по пользователям + ограничение размера партиции |
| **Clustering Key** | `order_date DESC` | Сортировка: новые заказы первыми |
| **Clustering Key** | `order_id` | Уникальность внутри партиции |

**Избежание горячих партиций:**
- Добавление `year_month` предотвращает неограниченный рост партиции
- Активные пользователи распределены по разным партициям (месяцам)
- При добавлении ноды перемещается ~1/N партиций

### Примеры запросов

```sql
-- История заказов за ноябрь 2024
SELECT * FROM order_history 
WHERE user_id = ? AND year_month = '2024-11';

-- Последние 10 заказов (текущий месяц)
SELECT * FROM order_history 
WHERE user_id = ? AND year_month = '2024-12'
LIMIT 10;
```

---

## 2.2 Таблица user_sessions

### CQL Schema

```sql
CREATE TABLE mobile_world.user_sessions (
    session_id UUID,
    user_id UUID,
    created_at TIMESTAMP,
    last_activity TIMESTAMP,
    ip_address TEXT,
    user_agent TEXT,
    geo_zone TEXT,
    data MAP<TEXT, TEXT>,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400;  -- 24 часа TTL
```

### Обоснование

| Компонент | Значение | Почему |
|-----------|----------|--------|
| **Partition Key** | `session_id` | Уникальный UUID — идеальное распределение |
| **TTL** | 24 часа | Автоматическая очистка старых сессий |

**Преимущества:**
- UUID обеспечивает равномерное распределение (никаких hotspot)
- Один запрос = одна партиция (O(1) lookup)
- TTL избавляет от необходимости cleanup jobs

### Дополнительная таблица для поиска по user_id

```sql
CREATE TABLE mobile_world.sessions_by_user (
    user_id UUID,
    session_id UUID,
    created_at TIMESTAMP,
    PRIMARY KEY (user_id, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC)
  AND default_time_to_live = 86400;
```

---

## 2.3 Таблица product_views

### CQL Schema

```sql
CREATE TABLE mobile_world.product_views (
    product_id UUID,
    view_date DATE,
    view_time TIMESTAMP,
    view_id TIMEUUID,
    user_id UUID,
    session_id UUID,
    geo_zone TEXT,
    PRIMARY KEY ((product_id, view_date), view_time, view_id)
) WITH CLUSTERING ORDER BY (view_time DESC, view_id DESC)
  AND default_time_to_live = 7776000;  -- 90 дней
```

### Обоснование

| Компонент | Значение | Почему |
|-----------|----------|--------|
| **Partition Key** | `(product_id, view_date)` | Bucket по дням, ограничение размера партиции |
| **Clustering Key** | `view_time DESC` | Хронологический порядок |
| **TIMEUUID** | `view_id` | Уникальность + встроенный timestamp |

**Избежание горячих партиций:**
- Популярный товар генерирует много просмотров
- `view_date` в partition key разбивает нагрузку по дням
- Каждый день — новая партиция

---

## 2.4 Таблица click_events

### CQL Schema

```sql
CREATE TABLE mobile_world.click_events (
    event_date DATE,
    bucket INT,              -- 0-99 для дополнительного распределения
    event_time TIMESTAMP,
    event_id TIMEUUID,
    event_type TEXT,         -- 'click', 'add_to_cart', 'purchase'
    user_id UUID,
    session_id UUID,
    product_id UUID,
    page_url TEXT,
    metadata MAP<TEXT, TEXT>,
    PRIMARY KEY ((event_date, bucket), event_time, event_id)
) WITH CLUSTERING ORDER BY (event_time DESC, event_id DESC)
  AND default_time_to_live = 604800  -- 7 дней
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 1};
```

### Обоснование

| Компонент | Значение | Почему |
|-----------|----------|--------|
| **Partition Key** | `(event_date, bucket)` | 100 партиций в день для распределения |
| **Bucket** | `0-99` | hash(event_id) % 100 для равномерности |
| **TWCS** | TimeWindow | Оптимизация для time-series данных |

---

## 2.5 Сводная таблица ключей

| Таблица | Partition Key | Clustering Key | Размер партиции |
|---------|---------------|----------------|-----------------|
| order_history | `(user_id, year_month)` | `order_date DESC, order_id` | ~100-1000 записей |
| user_sessions | `session_id` | — | 1 запись |
| sessions_by_user | `user_id` | `created_at DESC` | ~10-50 записей |
| product_views | `(product_id, view_date)` | `view_time DESC, view_id` | ~1K-100K записей |
| click_events | `(event_date, bucket)` | `event_time DESC, event_id` | ~10K-1M записей |

---

# Задание 10.3. Стратегии обеспечения целостности

## 3.1 Обзор механизмов

| Механизм | Когда работает | Latency impact | Гарантии |
|----------|----------------|----------------|----------|
| **Hinted Handoff** | Нода недоступна при записи | Нет | Запись доставится позже |
| **Read Repair** | При чтении обнаружено расхождение | Увеличивает latency чтения | Синхронизация при чтении |
| **Anti-Entropy Repair** | Фоновый процесс (nodetool repair) | Нет (фоновый) | Полная консистентность |

## 3.2 Выбор стратегий по таблицам

### order_history

| Механизм | Использование | Обоснование |
|----------|---------------|-------------|
| **Hinted Handoff** | ✅ Включён | Гарантия доставки записи при временной недоступности ноды |
| **Read Repair** | ✅ `read_repair_chance = 0.1` | 10% чтений проверяют консистентность |
| **Anti-Entropy Repair** | ✅ Раз в неделю | Полная синхронизация для исторических данных |

```sql
ALTER TABLE order_history WITH 
  read_repair_chance = 0.1 AND
  dclocal_read_repair_chance = 0.2;
```

**Обоснование:**
- История заказов — read-heavy, eventual consistency OK
- Read Repair 10% достаточно для обнаружения расхождений
- Еженедельный repair для гарантии целостности

---

### user_sessions

| Механизм | Использование | Обоснование |
|----------|---------------|-------------|
| **Hinted Handoff** | ✅ Включён | Критично для UX — сессия должна сохраниться |
| **Read Repair** | ❌ `read_repair_chance = 0` | Latency критична, TTL и так очистит старые данные |
| **Anti-Entropy Repair** | ❌ Не нужен | Данные с TTL, нет смысла repair'ить |

```sql
ALTER TABLE user_sessions WITH 
  read_repair_chance = 0 AND
  dclocal_read_repair_chance = 0;
```

**Обоснование:**
- Сессии — latency critical (каждый запрос)
- TTL 24 часа — старые данные автоматически удаляются
- Потеря сессии = повторный логин (приемлемо)

---

### product_views

| Механизм | Использование | Обоснование |
|----------|---------------|-------------|
| **Hinted Handoff** | ✅ Включён | Аналитика не должна терять данные |
| **Read Repair** | ✅ `read_repair_chance = 0.05` | 5% — аналитика не real-time критична |
| **Anti-Entropy Repair** | ✅ Раз в месяц | Для точности отчётов |

```sql
ALTER TABLE product_views WITH 
  read_repair_chance = 0.05 AND
  dclocal_read_repair_chance = 0.1;
```

---

### click_events

| Механизм | Использование | Обоснование |
|----------|---------------|-------------|
| **Hinted Handoff** | ✅ Включён | Не терять события |
| **Read Repair** | ❌ `read_repair_chance = 0` | Write-only workload, чтений мало |
| **Anti-Entropy Repair** | ❌ Не нужен | TTL 7 дней, данные быстро устаревают |

```sql
ALTER TABLE click_events WITH 
  read_repair_chance = 0 AND
  dclocal_read_repair_chance = 0;
```

**Обоснование:**
- 99% операций — записи
- Чтение только для batch-аналитики (Spark/Flink)
- TTL 7 дней — нет смысла repair'ить

---

## 3.3 Сводная таблица стратегий

| Таблица | Hinted Handoff | Read Repair | Anti-Entropy | Consistency Level |
|---------|----------------|-------------|--------------|-------------------|
| order_history | ✅ | 10% | Weekly | `LOCAL_QUORUM` |
| user_sessions | ✅ | 0% | — | `LOCAL_ONE` |
| sessions_by_user | ✅ | 0% | — | `LOCAL_ONE` |
| product_views | ✅ | 5% | Monthly | `LOCAL_ONE` |
| click_events | ✅ | 0% | — | `ANY` |

## 3.4 Настройка Consistency Level

```java
// Java Driver примеры

// order_history — нужна консистентность
session.execute(
    SimpleStatement.builder(query)
        .setConsistencyLevel(ConsistencyLevel.LOCAL_QUORUM)
        .build()
);

// user_sessions — нужна скорость
session.execute(
    SimpleStatement.builder(query)
        .setConsistencyLevel(ConsistencyLevel.LOCAL_ONE)
        .build()
);

// click_events — максимальная скорость записи
session.execute(
    SimpleStatement.builder(insertQuery)
        .setConsistencyLevel(ConsistencyLevel.ANY)
        .build()
);
```

---

## 3.5 Расписание Anti-Entropy Repair

```bash
# Cron job для repair

# order_history — еженедельно (воскресенье 3:00)
0 3 * * 0 nodetool repair mobile_world order_history

# product_views — ежемесячно (1 число 4:00)
0 4 1 * * nodetool repair mobile_world product_views
```

---

## 4. Диаграмма гибридной архитектуры

```
┌─────────────────────────────────────────────────────────────────┐
│                        Application Layer                        │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│         MongoDB             │   │         Cassandra           │
│    (Strong Consistency)     │   │    (High Availability)      │
├─────────────────────────────┤   ├─────────────────────────────┤
│ • products (остатки)        │   │ • order_history             │
│ • orders (активные)         │   │ • user_sessions             │
│ • carts                     │   │ • product_views             │
│                             │   │ • click_events              │
├─────────────────────────────┤   ├─────────────────────────────┤
│ Операции:                   │   │ Операции:                   │
│ • ACID транзакции           │   │ • Append-only записи        │
│ • Complex queries           │   │ • Key-based lookups         │
│ • Updates                   │   │ • Time-series               │
└─────────────────────────────┘   └─────────────────────────────┘
```

---

## 5. Риски и митигация

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Горячая партиция в order_history | Низкая | Bucket по year_month |
| Горячая партиция в product_views | Средняя | Bucket по view_date |
| Потеря сессии при сбое | Низкая | Hinted Handoff + LOCAL_ONE |
| Несогласованность order_history | Низкая | Read Repair 10% + Weekly repair |
| Потеря click_events | Очень низкая | Hinted Handoff + ANY |

