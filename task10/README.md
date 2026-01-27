# Задание 10. Миграция на Cassandra

## 10.1. Какие данные переносить в Cassandra

| Сущность | Перенос в Cassandra | Почему |
|----------|---------------------|---------|
| orders | Да | Высокая нагрузка записи (50k RPS), append-only данные |
| products | Нет | Частые обновления остатков (риск конфликтов) |
| carts | Нет | Требуется сильная консистентность, частые обновления |
| История заказов | Да | Append-only, аналитика, геораспределение |
| Сессии пользователей | Да | Высокая нагрузка записи/чтения, короткий TTL |


### Обоснование

**orders:** Создание заказа - append-only операция. Высокая нагрузка записи в пики (черная пятница). Cassandra отлично справляется с write-heavy нагрузкой.

**products:** Обновление остатков товара создает конфликты при записи. MongoDB с транзакциями лучше для этого.

**carts:** Частые обновления (добавление/удаление товаров) требуют strong consistency. Корзина должна быть точной, иначе потеряем товары или продадим несуществующие.

**История заказов:** Read-heavy нагрузка для аналитики. Данные не меняются после создания. Cassandra хорошо масштабируется на чтение.

**Сессии:** Write/read heavy, короткий TTL (автоочистка). Cassandra поддерживает TTL на уровне колонок.


## 10.2. Модель данных

### orders

```cql
CREATE TABLE orders_by_user (
    user_id UUID,
    order_date DATE,
    order_id TIMEUUID,
    items LIST<FROZEN<order_item>>,
    total_amount DECIMAL,
    status TEXT,
    geo_zone TEXT,
    PRIMARY KEY ((user_id, order_date), order_id)
) WITH CLUSTERING ORDER BY (order_id DESC);

CREATE TYPE order_item (
    product_id UUID,
    quantity INT,
    price DECIMAL
);
```

**Partition key:** `(user_id, order_date)`
- Равномерное распределение по user_id
- Данные сегментированы по дате (избегаем больших партиций)

**Clustering key:** `order_id` (TIMEUUID)
- Сортировка внутри партиции по времени создания
- Быстрый доступ к последним заказам

**Проблема горячих партиций:** Если один пользователь создает много заказов в день, партиция может быть большой. Решение: добавить hour в partition key: `(user_id, order_date, hour)`.

### orders по статусу (для админки)

```cql
CREATE TABLE orders_by_status (
    status TEXT,
    bucket INT,
    order_id TIMEUUID,
    user_id UUID,
    order_date DATE,
    total_amount DECIMAL,
    geo_zone TEXT,
    PRIMARY KEY ((status, bucket), order_id)
) WITH CLUSTERING ORDER BY (order_id DESC);
```

**Partition key:** `(status, bucket)`
- `status` группирует по статусу (pending, completed, cancelled)
- `bucket` распределяет нагрузку (random 0-99)

**Clustering key:** `order_id`
- Сортировка по времени

**Избегаем горячих партиций:** Без bucket все заказы со статусом "pending" попадут в одну партицию. Bucket равномерно распределяет их.

### История заказов (аналитика)

```cql
CREATE TABLE order_history (
    geo_zone TEXT,
    year_month TEXT,
    order_id TIMEUUID,
    user_id UUID,
    total_amount DECIMAL,
    category TEXT,
    PRIMARY KEY ((geo_zone, year_month), order_id)
) WITH CLUSTERING ORDER BY (order_id DESC);
```

**Partition key:** `(geo_zone, year_month)`
- Данные сегментированы по регионам и месяцам
- Аналитика обычно по периодам

**Clustering key:** `order_id`

### Сессии пользователей

```cql
CREATE TABLE user_sessions (
    session_id UUID,
    user_id UUID,
    last_activity TIMESTAMP,
    cart_items MAP<UUID, INT>,
    expires_at TIMESTAMP,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400;
```

**Partition key:** `session_id`
- Случайный UUID равномерно распределяется

**TTL:** 24 часа (автоочистка старых сессий)


## 10.3. Стратегии восстановления целостности

### Hinted Handoff

Когда узел недоступен, другой узел сохраняет hint (подсказку) и передаст данные позже.

**Применение:**
- **orders:** Да. При пиковой нагрузке узлы могут временно упасть. Hints обеспечат eventual consistency.
- **user_sessions:** Да. Допустима задержка в несколько секунд.

```cql
-- Включено по умолчанию в Cassandra
-- Настройка в cassandra.yaml:
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа
```

### Read Repair

При чтении данные сравниваются между репликами и исправляются различия.

**Применение:**
- **orders:** Да. При чтении заказа исправим расхождения между репликами.
- **order_history:** Нет. Read-heavy нагрузка, лишние проверки замедлят чтение.

```cql
-- Включить read repair для таблицы
ALTER TABLE orders_by_user WITH read_repair_chance = 0.1;
-- 10% запросов будут проверять все реплики
```

### Anti-Entropy Repair

Фоновый процесс сравнения всех реплик и исправления различий.

**Применение:**
- **Все таблицы:** Да. Запускать периодически (раз в неделю).

```bash
# Полный repair всего keyspace
nodetool repair shop

# Repair конкретной таблицы
nodetool repair shop orders_by_user

# Incremental repair (быстрее)
nodetool repair -inc shop
```

### Сводная таблица

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy | Обоснование |
|----------|----------------|-------------|--------------|-------------|
| orders_by_user | Да | 0.1 | Да (еженедельно) | Eventual consistency допустима |
| orders_by_status | Да | 0.05 | Да (еженедельно) | Админка, можно задержку |
| order_history | Да | Нет | Да (ежемесячно) | Аналитика, read-heavy |
| user_sessions | Да | Нет | Нет | TTL 24ч, нет смысла чинить |

## Компромиссы

### Latency vs Consistency

**Consistency Level для записи:**

```cql
-- Высокая консистентность (медленнее)
INSERT INTO orders_by_user (...) VALUES (...) USING CONSISTENCY QUORUM;

-- Быстрая запись (eventual consistency)
INSERT INTO user_sessions (...) VALUES (...) USING CONSISTENCY ONE;
```

**Consistency Level для чтения:**

```cql
-- Гарантия актуальности (медленнее)
SELECT * FROM orders_by_user WHERE user_id = ? CONSISTENCY QUORUM;

-- Быстрое чтение
SELECT * FROM order_history WHERE geo_zone = ? CONSISTENCY ONE;
```

### Рекомендации

**orders:** CL=QUORUM (write + read). Компромисс между скоростью и консистентностью.

**order_history:** CL=ONE (read), CL=QUORUM (write). Читаем быстро, пишем надежно.

**user_sessions:** CL=ONE (write + read). Максимальная скорость, eventual consistency допустима.

## Создание keyspace

```cql
CREATE KEYSPACE shop
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3,
    'datacenter2': 3
}
AND durable_writes = true;
```

**NetworkTopologyStrategy:** Поддержка нескольких ЦОД для геораспределения.

**Replication factor = 3:** Баланс между надежностью и расходом места.

## Масштабирование

```bash
# Добавить новый узел
nodetool status  # Проверить текущее состояние

# В cassandra.yaml нового узла указать:
# - seed_provider (адреса существующих узлов)
# - listen_address (IP нового узла)

# Запустить Cassandra на новом узле
systemctl start cassandra

# Проверить, что узел присоединился
nodetool status

# Перераспределить данные (только новые данные)
nodetool cleanup
```

**Преимущество:** Данные не перемещаются полностью. Только новые записи идут на новый узел. Нет просадки latency в пик нагрузки.
