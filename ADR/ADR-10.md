### **Название задачи: Миграция интернет-магазина на Cassandra: модель данных, репликация и распределение нагрузки**  
### **Автор: Торопов Андрей**
### **Дата: 04.04.2026**


## Контекст

Во время распродажи типа «чёрная пятница» интернет-магазин столкнулся с резким ростом нагрузки до 50 000 запросов в секунду. Текущая реализация на MongoDB с range-based sharding показала ограничение: при добавлении новых шардов происходило значительное перераспределение данных между узлами, что увеличивало latency.

Принято решение использовать Cassandra для высоконагруженных сценариев.

Cassandra использует consistent hashing:
- перераспределяется только часть данных;
- нет полного reshuffle;
- масштабирование происходит плавно;
- лучше подходит для пиковых нагрузок.

---

## Цель

Определить:
- какие данные переносить;
- как моделировать данные;
- как обеспечить консистентность.

---

# 1. Выбор сущностей

## Переносим
- orders
- orders history
- carts
- sessions
- catalog views

## Не переносим
- сложные транзакционные данные
- master-данные товаров

---

# 2. Модель данных

## Orders by id
```sql
CREATE TABLE orders_by_id (
    order_id text PRIMARY KEY,
    user_id text,
    created_at timestamp,
    status text
);
```

Обоснование:
- высокий cardinality → равномерное распределение
- нет hot partition

---

## Orders by user
```sql
CREATE TABLE orders_by_user (
    user_id text,
    order_month text,
    created_at timestamp,
    order_id text,
    PRIMARY KEY ((user_id, order_month), created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

Обоснование:
- user_id — доступ по пользователю
- order_month — ограничение размера партиции
- предотвращает hot partition

---

## Carts
```sql
CREATE TABLE carts_by_owner (
    owner_type text,
    owner_id text,
    items_json text,
    PRIMARY KEY ((owner_type, owner_id))
);
```

Обоснование:
- высокая кардинальность
- быстрый key-based доступ

---

## Sessions
```sql
CREATE TABLE sessions_by_id (
    session_id text PRIMARY KEY,
    user_id text
);
```

Обоснование:
- равномерное распределение
- TTL-friendly

---

## Product views
```sql
CREATE TABLE product_views_by_category (
    category text,
    bucket int,
    product_id text,
    price decimal,
    PRIMARY KEY ((category, bucket), price)
);
```

Обоснование:
- bucket устраняет hot partition
- равномерное распределение внутри категории

---

# 3. Защита от hot partitions

- высокий cardinality ключей
- time bucketing
- hash bucketing
- денормализация под запросы

---

# 4. Стратегии консистентности

## Orders
- Hinted Handoff
- Read Repair
- Anti-Entropy Repair

Почему:
- критичные данные
- нужна максимальная целостность

---

## Orders History
- Hinted Handoff
- Read Repair
- Anti-Entropy Repair

Почему:
- часто читаются
- допустима небольшая задержка

---

## Carts
- Hinted Handoff
- Anti-Entropy Repair

Почему:
- важна скорость
- Read Repair увеличивает latency

---

## Sessions
- Hinted Handoff

Почему:
- TTL данные
- строгая консистентность не критична

---

## Catalog
- Hinted Handoff
- Anti-Entropy Repair

Почему:
- read-heavy
- допустима eventual consistency

---

# 5. Итог

Cassandra используется для:
- высоконагруженных данных
- предсказуемых запросов
- горизонтального масштабирования

---

# Вывод

Переход на Cassandra:
- устраняет проблему полного решардинга
- снижает latency
- обеспечивает устойчивость к пиковым нагрузкам
