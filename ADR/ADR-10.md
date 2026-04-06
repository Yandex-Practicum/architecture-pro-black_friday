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

## Ключевое ограничение

Оформление заказа требует атомарной бизнес-операции:
- проверка актуальных остатков;
- создание заказа;
- обновление остатков.

Если сервис работает с неактуальными данными, возможна продажа товара, которого уже нет (oversell).

Cassandra не обеспечивает удобной и простой реализации таких транзакций между несколькими сущностями.

---

## Не переносим в Cassandra (как источник истины)

- orders
- products
- inventory / остатки

Причины:
- требуется строгая консистентность;
- операции должны быть атомарными;
- высокая бизнес-стоимость ошибки;
- Cassandra ориентирована на eventual consistency.

---

## Переносим в Cassandra

- история заказов (orders history);
- корзины (carts);
- пользовательские сессии (sessions);
- витрины каталога (catalog views);
- денормализованные read-модели.

Причины:
- высокая нагрузка;
- предсказуемые запросы;
- допустима eventual consistency.

---

# 2. Модель данных

## Orders history by user

```sql
CREATE TABLE orders_by_user (
    user_id text,
    order_month text,
    created_at timestamp,
    order_id text,
    status text,
    PRIMARY KEY ((user_id, order_month), created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

Обоснование:
- ограничение размера партиции;
- предотвращение hot partition;
- быстрый доступ к последним заказам.

---

## Carts

```sql
CREATE TABLE carts_by_owner (
    owner_type text,
    owner_id text,
    items_json text,
    updated_at timestamp,
    PRIMARY KEY ((owner_type, owner_id))
);
```

Обоснование:
- высокая кардинальность;
- быстрый доступ;
- частые обновления.

---

## Sessions

```sql
CREATE TABLE sessions_by_id (
    session_id text PRIMARY KEY,
    user_id text,
    created_at timestamp
);
```

Обоснование:
- равномерное распределение;
- TTL-поддержка.

---

## Catalog views

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
- bucket устраняет hot partition;
- равномерное распределение нагрузки.

---

# 3. Защита от hot partitions

- высокий cardinality ключей;
- time bucketing;
- bucket распределение;
- денормализация под запросы.

---

# 4. Стратегии консистентности

## Orders history
- Hinted Handoff
- Read Repair
- Anti-Entropy Repair

## Carts
- Hinted Handoff
- Anti-Entropy Repair

## Sessions
- Hinted Handoff

## Catalog
- Hinted Handoff
- Anti-Entropy Repair

---

# 5. Итог

Cassandra используется как read-оптимизированное хранилище.

---

# Вывод

Гибридная архитектура:
- транзакционные операции вне Cassandra;
- Cassandra для масштабируемых данных.

Это позволяет снизить latency и избежать проблем с масштабированием.
