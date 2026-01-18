# Задача 10

### Требования 

- Высокую отказоустойчивость (leaderless‑репликация).
- Быстрое горизонтальное масштабирование без полного перераспределения данных.
- Равномерное распределение данных.

### Решение
- Миграция данных на БД  Cassandra

#### Плюсы решения
- Благодаря leaderless подходы к репликаям достигарется высокая отказоустойчивость
- Cassadra поддерживает горизонтальное масштабирование 
- Достигается равномерное распределение данных



## Задача 10.1 Анализ критически важных данных и целесообразность Cassandra

### Классификация данных по критичности:

#### 1. Критически важные (требуют высокой целостности и скорости):
- Корзины покупок (carts) — высокая волатильность, требуется мгновенная консистентность
- Остатки товаров (stock) — требование строгой консистентности
- Создание заказов (orders) — финансовые транзакции, атомарность обязательна
- Платежные операции — максимальная надежность и консистентность

#### 2. Важные, но допускающие eventual consistency:
- История заказов — чтение преобладает, небольшая задержка допустима
- Каталог товаров — частое чтение, редкое обновление
- Логи действий пользователей — аналитические данные

## Целесообразность Cassandra для разных типов данных:
### Идеально подходит для Cassandra:
- Корзины покупок (carts)
  - Требования: Высокая скорость записи/чтения, горизонтальное масштабирование
  - Почему Cassandra: Leaderless архитектура, линейная масштабируемость, отказоустойчивость
  
- История заказов (read-heavy)
  - Требования: Высокая доступность, геораспределение, архивное хранение
  - Почему Cassandra: Отличная производительность на чтение

- Логи действий пользователей
  - Требования: Высокая скорость записи, временные ряды, аналитика
  - Почему Cassandra: Time-series оптимизация, эффективное хранение временных данных


# Задача 10.2
Описание детальной схемы для ключевых сущностей интернет‑магазина с обоснованием выбора ключей и стратегий распределения.

## carts

```sql
CREATE TABLE carts (
    -- Partition key: комбинация user_id и bucket для распределения
    user_id uuid,
    bucket int,  -- 0-15 для распределения горячих пользователей
    cart_id uuid,
    
    -- Clustering columns
    item_added_at timestamp,
    
    -- Данные
    product_id uuid,
    quantity int,
    price decimal,
    product_name text,
    attributes map<text, text>,
    
    -- Метаданные корзины
    cart_status text,  -- 'active', 'abandoned', 'ordered'
    session_id text,
    geo_zone text,
    expires_at timestamp,
    last_updated_at timestamp,
    
    PRIMARY KEY ((user_id, bucket), cart_id, item_added_at, product_id)
) WITH CLUSTERING ORDER BY (cart_id ASC, item_added_at DESC, product_id ASC);
```

### Обоснование ключей:

- ``Partition Key: (user_id, bucket)`` — равномерное распределение даже для популярных пользователей
  - bucket = user_id.hash_code() % 16 — предотвращает hot partitions

- ``Clustering Key: cart_id, item_added_at, product_id`` — эффективные запросы:
  - Получить все товары в корзине: WHERE user_id=? AND bucket=? AND cart_id=?
  - Последние добавленные товары: ORDER BY item_added_at DESC

## stock
```sql
CREATE TABLE stock_by_product_geo (
    -- Partition key: продукт + геозона
    product_id uuid,
    geo_zone text,
    
    -- Clustering columns
    warehouse_id uuid,
    
    -- Данные
    available_quantity int,
    reserved_quantity int,
    in_transit int,
    safety_stock int,
    last_restocked timestamp,
    
    -- Версионирование для optimistic locking
    version int,
    
    PRIMARY KEY ((product_id, geo_zone), warehouse_id)
);

-- Денормализованная таблица для быстрого поиска по товарам
CREATE TABLE products_by_category (
    category text,
    product_id uuid,
    name text,
    price decimal,
    total_stock int,
    geo_zones set<text>,
    
    PRIMARY KEY ((category), product_id)
) WITH compaction = {'class': 'TimeWindowCompactionStrategy'};
```

### Обоснование ключей:

- Partition Key: (product_id, geo_zone) — все остатки товара в регионе в одной партиции
   - Оптимально для атомарных операций списания
- Clustering Key: warehouse_id — для управления остатками по складам

## orders

```sql
CREATE TABLE orders_by_customer_date (
    -- Partition key: клиент + временной bucket
    customer_id uuid,
    date_bucket text,  -- '2024-01', '2024-02' или '2024-W01'
    
    -- Clustering columns
    order_created_at timestamp,
    order_id uuid,
    
    -- Данные заказа
    status text,
    total_amount decimal,
    shipping_address frozen<address>,
    payment_method text,
    items list<frozen<order_item>>,
    
    PRIMARY KEY ((customer_id, date_bucket), order_created_at, order_id)
) WITH CLUSTERING ORDER BY (order_created_at DESC);

-- Для поиска по ID заказа (материализованное представление)
CREATE TABLE orders_by_id (
    order_id uuid,
    customer_id uuid,
    date_bucket text,
    order_created_at timestamp,
    status text,
    
    PRIMARY KEY (order_id)
);
```


### Обоснование ключей:

- ``Partition Key: (customer_id, date_bucket)`` — история заказов клиента распределена по времени
  - Предотвращает неограниченный рост партиций
  - Упрощает удаление старых данных (TTL или периодическая чистка)
- Clustering Key: order_created_at DESC — новые заказы в начале, оптимально для истории

# Задача 10.3

## carts

Стратегии:

- Hinted Handoff: Включен всегда — доступность важнее консистентности

- Read Repair: 10% — корзины часто читаются, ремонт при чтении эффективен

- Anti-Entropy: Еженедельно — для гарантии долгосрочной консистентности

Обоснование: Корзины — высокодоступные данные, потеря части обновлений менее критична, чем недоступность.

## stock

Стратегии:

- Hinted Handoff: Отключен — риск overselling из-за рассинхронизации

- Read Repair: 30% — высокий приоритет исправления расхождений

- Anti-Entropy: Ежедневно — обязательная проверка остатков

Обоснование: Остатки требуют строгой консистентности. Лучше отказать в операции, чем продать отсутствующий товар.


## orders

Стратегии:

- Hinted Handoff: Включен, но с ограничением по времени (3 часа)
- Read Repair: 15% — умеренный уровень, баланс latency/консистентность
- Anti-Entropy: Раз в 2 дня — заказы важны, но не требуют ежесекундной синхронности

Обоснование: Заказы требуют надежности, но небольшая задержка в репликации допустима.