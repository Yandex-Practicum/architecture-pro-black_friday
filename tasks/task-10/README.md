# Архитектурный документ: Миграция на Cassandra

## Задание 10.1: Анализ критических данных

### 1. Классификация данных интернет-магазина

| Сущность | Объём | Частота записи | Частота чтения | Требования к целостности | Критичность |
|----------|-------|-----------------|-----------------|--------------------------|-------------|
| **Заказы (orders)** | Высокий | Высокая (50k/сек) | Высокая (статус) | Абсолютная | **Критическая** |
| **Корзины (carts)** | Средний | Очень высокая | Очень высокая | Высокая | **Критическая** |
| **Товары (products)** | Средний | Низкая | Очень высокая | Средняя | **Некритическая** |
| **Пользовательские сессии** | Очень высокий | Очень высокая | Высокая | Низкая | **Критическая** |
| **История заказов** | Очень высокий | Средняя | Средняя | Средняя | **Некритическая** |

### 2. Обоснование выбора сущностей для Cassandra

#### Критические сущности для миграции:

| Сущность | Почему в Cassandra | Почему не в MongoDB |
|----------|-------------------|---------------------|
| **Заказы (orders)** | 50k запросов/сек, требуется линейная масштабируемость, геораспределённость | Range-based шардинг вызывает просадки при масштабировании |
| **Корзины (carts)** | Очень высокая частота обновлений, требуется низкая latency | Полное перераспределение данных при добавлении узлов |
| **Пользовательские сессии** | Высокая скорость записи, TTL, геораспределённость | Нет встроенного TTL, сложное масштабирование |

#### Некритические сущности (остаются в MongoDB):

| Сущность | Причина |
|----------|---------|
| **Товары (products)** | Низкая частота обновлений, сложные агрегации, текстовый поиск |
| **История заказов** | Сложные аналитические запросы, агрегации по пользователям |

---

## Задание 10.2: Модель данных для Cassandra

### 1. Концептуальная модель

#### Таблица `orders_by_user`

```sql
CREATE TABLE orders_by_user (
    user_id UUID,
    order_id UUID,
    order_date TIMESTAMP,
    status TEXT,
    geo_zone TEXT,
    total_amount DECIMAL,
    items LIST<FROZEN<order_item>>,
    PRIMARY KEY ((user_id), order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC);
```

**Обоснование:**
- **Partition Key:** `user_id` — все заказы пользователя в одной партиции
- **Clustering Key:** `order_date` + `order_id` — сортировка по дате, уникальность
- **Кластеризация:** `DESC` — сначала новые заказы

#### Таблица `orders_by_status`

```sql
CREATE TABLE orders_by_status (
    status TEXT,
    order_date TIMESTAMP,
    order_id UUID,
    user_id UUID,
    geo_zone TEXT,
    total_amount DECIMAL,
    PRIMARY KEY ((status), order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC);
```

**Обоснование:**
- **Partition Key:** `status` — для мониторинга и фоновых процессов
- **Clustering Key:** `order_date` + `order_id` — сортировка по времени

#### Таблица `carts_by_user`

```sql
CREATE TABLE carts_by_user (
    user_id UUID,
    cart_id UUID,
    status TEXT, -- active, ordered, abandoned
    items MAP<UUID, INT>, -- product_id -> quantity
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    expires_at TIMESTAMP,
    PRIMARY KEY ((user_id), status, updated_at)
) WITH CLUSTERING ORDER BY (status ASC, updated_at DESC);
```

**Обоснование:**
- **Partition Key:** `user_id` — все корзины пользователя в одной партиции
- **Clustering Key:** `status` + `updated_at` — быстрый поиск активной корзины
- **TTL:** автоматическое удаление через `expires_at`

#### Таблица `carts_by_session`

```sql
CREATE TABLE carts_by_session (
    session_id TEXT,
    cart_id UUID,
    items MAP<UUID, INT>,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    expires_at TIMESTAMP,
    PRIMARY KEY ((session_id), updated_at)
) WITH CLUSTERING ORDER BY (updated_at DESC);
```

**Обоснование:**
- **Partition Key:** `session_id` — для гостевых корзин
- **TTL:** автоматическое удаление через 7 дней

#### Таблица `sessions`

```sql
CREATE TABLE sessions (
    session_id TEXT,
    user_id UUID,
    created_at TIMESTAMP,
    expires_at TIMESTAMP,
    data TEXT,
    PRIMARY KEY ((session_id))
) WITH default_time_to_live = 86400; -- 24 часа
```

**Обоснование:**
- **Partition Key:** `session_id` — прямой доступ по ID сессии
- **TTL:** автоматическое удаление через 24 часа

### 2. Примеры данных

```sql
-- Заказ
INSERT INTO orders_by_user (user_id, order_id, order_date, status, geo_zone, total_amount, items)
VALUES (
    123e4567-e89b-12d3-a456-426614174000,
    987fcdeb-51a2-43d7-9b56-241674124000,
    '2026-03-11 10:30:00',
    'new',
    'msk',
    29990.00,
    [{product_id: 111, quantity: 1, price: 29990}]
);

-- Активная корзина пользователя
INSERT INTO carts_by_user (user_id, cart_id, status, items, created_at, updated_at, expires_at)
VALUES (
    123e4567-e89b-12d3-a456-426614174000,
    uuid(),
    'active',
    {111: 2, 222: 1},
    toTimestamp(now()),
    toTimestamp(now()),
    toTimestamp(now()) + 604800000
);
```

### 3. Стратегии распределения и "горячие" партиции

| Таблица | Partition Key | Риск горячей партиции | Решение |
|---------|---------------|----------------------|---------|
| `orders_by_user` | `user_id` | Низкий (равномерное распределение) | Хэширование |
| `orders_by_status` | `status` | **Высокий** (статус "new") | Композитный ключ + Bucketing |
| `carts_by_user` | `user_id` | Низкий | Хэширование |
| `carts_by_session` | `session_id` | Низкий | Хэширование |
| `sessions` | `session_id` | Низкий | Хэширование |

#### Решение для горячей партиции `orders_by_status`:

```sql
-- Добавляем bucket для равномерного распределения
CREATE TABLE orders_by_status (
    status_bucket TEXT, -- status + date_bucket
    order_date TIMESTAMP,
    order_id UUID,
    user_id UUID,
    status TEXT,
    geo_zone TEXT,
    total_amount DECIMAL,
    PRIMARY KEY ((status_bucket), order_date, order_id)
);

-- Вставка с bucket
INSERT INTO orders_by_status (
    status_bucket, order_date, order_id, user_id, status, geo_zone, total_amount
) VALUES (
    'new_2026-03-11',
    '2026-03-11 10:30:00',
    uuid(),
    123e4567-e89b-12d3-a456-426614174000,
    'new',
    'msk',
    29990.00
);
```

---

## Задание 10.3: Стратегии обеспечения целостности данных

### 1. Сравнение стратегий

| Стратегия | Механизм | Влияние на latency | Гарантия целостности |
|-----------|----------|-------------------|---------------------|
| **Hinted Handoff** | Запись на другой узел при недоступности | Низкое | Средняя |
| **Read Repair** | Исправление при чтении | Среднее | Высокая |
| **Anti-Entropy Repair** | Периодическая сверка | Нет (фоновый) | Полная |

### 2. Выбор стратегий по сущностям

#### Таблица `orders_by_user` (критичные заказы)

| Стратегия | Применение | Обоснование |
|-----------|------------|-------------|
| **Hinted Handoff** | ✅ Всегда включено | Минимальная задержка записи |
| **Read Repair** | ✅ `ALL` или `QUORUM` | Гарантия актуальности статуса |
| **Anti-Entropy Repair** | ✅ Еженедельно | Полная синхронизация в фоне |

**Настройки согласованности:**
```sql
-- Запись заказа
INSERT INTO orders_by_user (...) VALUES (...)
USING CONSISTENCY QUORUM;

-- Чтение статуса заказа
SELECT * FROM orders_by_user WHERE user_id = ? AND order_date = ?
USING CONSISTENCY LOCAL_QUORUM;
```

#### Таблица `carts_by_user` (корзины)

| Стратегия | Применение | Обоснование |
|-----------|------------|-------------|
| **Hinted Handoff** | ✅ Всегда | Высокая скорость записи |
| **Read Repair** | ✅ `ONE` | Достаточно слабой согласованности |
| **Anti-Entropy Repair** | ✅ Ежедневно | Корзины с TTL требуют синхронизации |

**Настройки согласованности:**
```sql
-- Обновление корзины (допустима слабая согласованность)
UPDATE carts_by_user SET items = ?, updated_at = ? WHERE user_id = ? AND status = 'active'
USING CONSISTENCY ONE;

-- Чтение корзины (требуется актуальность)
SELECT * FROM carts_by_user WHERE user_id = ? AND status = 'active'
USING CONSISTENCY LOCAL_QUORUM;
```

#### Таблица `sessions` (сессии)

| Стратегия | Применение | Обоснование |
|-----------|------------|-------------|
| **Hinted Handoff** | ✅ Всегда | Критична скорость записи |
| **Read Repair** | ❌ Отключена | Сессии не требуют строгой целостности |
| **Anti-Entropy Repair** | ❌ Не требуется | TTL автоматически удаляет |

**Настройки согласованности:**
```sql
-- Запись сессии (только скорость)
INSERT INTO sessions (session_id, user_id, created_at, expires_at, data)
VALUES (?, ?, ?, ?, ?)
USING CONSISTENCY ONE;

-- Чтение сессии
SELECT * FROM sessions WHERE session_id = ?
USING CONSISTENCY ONE;
```

### 3. Итоговые настройки

| Сущность | Write Consistency | Read Consistency | Repair Strategy |
|----------|------------------|------------------|-----------------|
| **orders_by_user** | `QUORUM` | `LOCAL_QUORUM` | Hinted + Read + Weekly AE |
| **orders_by_status** | `QUORUM` | `ONE` | Hinted + Read + Weekly AE |
| **carts_by_user** | `ONE` | `LOCAL_QUORUM` | Hinted + Read + Daily AE |
| **carts_by_session** | `ONE` | `LOCAL_QUORUM` | Hinted + Read + Daily AE |
| **sessions** | `ONE` | `ONE` | Hinted только |

---

## 4. Преимущества перед MongoDB

| Критерий | MongoDB | Cassandra | Преимущество |
|----------|---------|-----------|---------------|
| **Масштабирование** | Range-based + полное перераспределение | Consistent hashing + виртуальные узлы | ✅ Без просадок |
| **Репликация** | Master-slave | Leaderless | ✅ Нет единой точки отказа |
| **Запись** | Журнал операций | Commit log + memtable | ✅ Выше скорость |
| **Геораспределение** | Сложно | Нативно | ✅ Multi-DC поддержка |
| **TTL** | Нет | Встроенный | ✅ Автоочистка сессий |

---

## 5. Заключение

Предложенная модель данных для Cassandra обеспечивает:
1. **Линейную масштабируемость** без просадок при добавлении узлов
2. **Равномерное распределение** через хорошо подобранные partition key
3. **Геораспределённость** для разных регионов
4. **Автоматическую очистку** через TTL для сессий и корзин
5. **Баланс между согласованностью и производительностью** через настройки consistency

**Критически важные сущности успешно перенесены в Cassandra, обеспечивая целостность и производительность при 50k запросов/сек.**