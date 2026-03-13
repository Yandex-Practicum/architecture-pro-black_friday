# Архитектурный документ: Шардирование, репликация и масштабирование

## Содержание

1. [Задание 7: Схемы коллекций для шардирования](#задание-7-схемы-коллекций-для-шардирования)
2. [Задание 8: Выявление и устранение горячих шардов](#задание-8-выявление-и-устранение-горячих-шардов)
3. [Задание 9: Настройка чтения с реплик](#задание-9-настройка-чтения-с-реплик)
4. [Задание 10: Миграция на Cassandra](#задание-10-миграция-на-cassandra)

---

# Задание 7: Схемы коллекций для шардирования

## Обзор

Онлайн-магазин «Мобильный мир» хранит данные в трёх коллекциях MongoDB: `orders`, `products`, `carts`. Каждая требует особого подхода к шардированию.

---

## Коллекция `orders` (Заказы)

### Схема документа

```javascript
{
  "_id": ObjectId("507f1f77bcf86cd799439011"),
  "user_id": ObjectId("507f191e810c19729de860ea"),
  "created_at": ISODate("2024-01-15T10:30:00Z"),
  "items": [
    { "product_id": ObjectId("..."), "quantity": 2, "price": Decimal128("1999.00") }
  ],
  "status": "paid",
  "total_amount": Decimal128("3998.00"),
  "geo_zone": "moscow"
}
```

### Шард-ключ: `{ "user_id": "hashed" }`

**Стратегия:** Hashed Sharding

**Обоснование:**
- Основная операция — поиск истории заказов по `user_id`
- Hashed ключ обеспечивает равномерное распределение
- Targeted queries по `user_id`

**Команда:**
```javascript
sh.shardCollection("shop.orders", { "user_id": "hashed" })
```

---

## Коллекция `products` (Товары)

### Схема документа

```javascript
{
  "_id": ObjectId("507f1f77bcf86cd799439012"),
  "name": "Смартфон X",
  "category": "electronics",
  "price": Decimal128("49999.00"),
  "stock": { "moscow": 50, "spb": 30 },
  "attributes": { "color": "black", "brand": "BrandX" }
}
```

### Шард-ключ: `{ "category": "hashed" }`

**Стратегия:** Hashed Sharding

**Обоснование:**
- Основная операция — поиск по категории
- Hashed ключ избегает «горячего» шарда для популярной категории

**Команда:**
```javascript
sh.shardCollection("shop.products", { "category": "hashed" })
```

---

## Коллекция `carts` (Корзины)

### Схема документа

```javascript
{
  "_id": ObjectId("507f1f77bcf86cd799439013"),
  "user_id": ObjectId("..."),  // null для гостей
  "session_id": "sess_abc123xyz",
  "shard_key": ObjectId("...") || "sess_abc123xyz",  // user_id или session_id
  "items": [{ "product_id": ObjectId("..."), "quantity": 1 }],
  "status": "active",
  "expires_at": ISODate("2024-01-22T10:00:00Z")
}
```

### Шард-ключ: `{ "shard_key": "hashed" }`

**Стратегия:** Hashed Sharding с вычисляемым полем

**Обоснование:**
- `user_id` для авторизованных, `session_id` для гостей
- Равномерное распределение корзин

**Команда:**
```javascript
sh.shardCollection("shop.carts", { "shard_key": "hashed" })
```

---

## Итоговая таблица шард-ключей

| Коллекция | Шард-ключ | Стратегия | Основной паттерн доступа |
|-----------|-----------|-----------|-------------------------|
| `orders` | `{ "user_id": "hashed" }` | Hashed | История заказов пользователя |
| `products` | `{ "category": "hashed" }` | Hashed | Поиск по категории |
| `carts` | `{ "shard_key": "hashed" }` | Hashed | Доступ к корзине |

---

# Задание 8: Выявление и устранение горячих шардов

## Метрики мониторинга

### Таблица метрик

| Метрика | Описание | Порог тревоги | Действие |
|---------|----------|---------------|----------|
| `dataSize` дисбаланс | Разница размера данных между шардами | > 20% | Включить Balancer |
| `operationCount` дисбаланс | Разница ops/sec между шардами | > 30% | Анализ запросов |
| `queryLatency` | Время выполнения запросов | > 100ms | Оптимизация индексов |
| `chunkCount` дисбаланс | Разница количества чанков | > 30% | Ручное перемещение |
| `replicationLag` | Задержка репликации | > 10 сек | Проверка сети |

---

## Команды мониторинга

```javascript
// Распределение данных по шардам
db.collection.getShardDistribution()

// Статистика шардов
db.collection.stats().shards

// Статус балансировщика
sh.getBalancerState()
sh.isBalancerRunning()

// Найти большие чанки
db.chunks.find({ "ns": "shop.products", "jumbo": true })
```

---

## Механизмы перераспределения

### 1. Автоматический Balancer

```javascript
// Проверка статуса
sh.getBalancerState()

// Настройка размера чанка
db.settings.update(
  { "_id": "chunksize" },
  { $set: { "value": 32 } },  // 32 MB
  { upsert: true }
)
```

### 2. Ручное перемещение чанков

```javascript
// Переместить чанк
sh.moveChunk("shop.products", { "category": "electronics" }, "shard2")

// Разделить большой чанк
sh.splitAt("shop.products", { "category": "electronics", "_id": ObjectId("...") })
```

### 3. Теги шардов

```javascript
// Создать теги
sh.addShardTag("shard1", "electronics_part1")
sh.addShardTag("shard2", "electronics_part2")

// Привязать диапазоны
sh.addTagRange("shop.products", 
  { "category": "electronics", "_id": MinKey },
  { "category": "electronics", "_id": ObjectId("...") },
  "electronics_part1"
)
```

---

## Алгоритм устранения горячего шарда

1. **Идентификация:** Проверить метрики дисбаланса
2. **Анализ:** Определить причину (популярная категория, активные пользователи)
3. **Действие:**
   - Включить/ускорить Balancer
   - Ручное перемещение чанков
   - Изменить шард-ключ
   - Использовать теги шардов
4. **Мониторинг:** Проверить снижение дисбаланса

---

# Задание 9: Настройка чтения с реплик

## Read Preference

| Режим | Описание | Использование |
|-------|----------|---------------|
| `primary` | Только PRIMARY | Строгая консистентность |
| `secondary` | Только SECONDARY | Аналитика |
| `secondaryPreferred` | SECONDARY приоритет | Снижение нагрузки на PRIMARY |

---

## Операции чтения по коллекциям

### `products` (Товары)

| Операция | Read Preference | Обоснование |
|----------|-----------------|-------------|
| Поиск по категории | `secondaryPreferred` | Задержка допустима |
| Страница товара | `primary` | Актуальная цена |
| Проверка остатков | `primary` | Критично для продажи |

### `orders` (Заказы)

| Операция | Read Preference | Обоснование |
|----------|-----------------|-------------|
| История заказов | `primary` | Консистентность |
| Статус заказа | `primary` | Критично для UX |
| Аналитика | `secondary` | Задержка допустима |

### `carts` (Корзины)

| Операция | Read Preference | Обоснование |
|----------|-----------------|-------------|
| Текущая корзина | `primary` | Консистентность |
| Аналитика корзин | `secondary` | Задержка допустима |

---

## Допустимая задержка репликации

| Операция | Макс. задержка |
|----------|----------------|
| Критичные (остатки, корзина, статус заказа) | 0 сек (PRIMARY) |
| Поиск товаров | 30 сек |
| Аналитика | 5-10 минут |

---

## Примеры запросов

```python
from pymongo import MongoClient, ReadPreference

client = MongoClient("mongodb://mongos:27017")

# Чтение с PRIMARY
def get_user_orders(user_id):
    return client.shop.orders.with_options(
        read_preference=ReadPreference.PRIMARY
    ).find({"user_id": user_id})

# Чтение с SECONDARY
def get_products_analytics():
    return client.shop.products.with_options(
        read_preference=ReadPreference.SECONDARY
    ).aggregate([...])
```

---

# Задание 10: Миграция на Cassandra

## Обоснование миграции

**Проблема MongoDB:** При добавлении шардов происходит полное перераспределение данных → просадка latency.

**Преимущества Cassandra:**
- Leaderless-репликация
- Добавление узлов без перераспределения
- Равномерное распределение данных

---

## Что переносим в Cassandra

| Сущность | Причина |
|----------|---------|
| `carts` (корзины) | Высокая скорость, TTL данные |
| `order_history` | Большой объём, append-only |
| `user_sessions` | TTL, высокая скорость |
| `product_views` | Аналитика, объём |

## Что оставляем в MongoDB

| Сущность | Причина |
|----------|---------|
| `products` | Сложные запросы, фильтрация |
| `orders` (активные) | Транзакции |
| `users` | Связи, ad-hoc запросы |

---

## Модель данных Cassandra

### Таблица: carts

```sql
CREATE TABLE carts (
    user_id UUID,
    created_at TIMESTAMP,
    item_id UUID,
    product_id UUID,
    quantity INT,
    price DECIMAL,
    PRIMARY KEY (user_id, created_at, item_id)
) WITH CLUSTERING ORDER BY (created_at DESC, item_id ASC)
  AND default_time_to_live = 604800;
```

**Partition Key:** `user_id` — все товары корзины на одной партиции

### Таблица: order_history

```sql
CREATE TABLE order_history (
    user_id UUID,
    order_date TIMESTAMP,
    order_id UUID,
    status TEXT,
    total_amount DECIMAL,
    PRIMARY KEY (user_id, order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC);
```

**Partition Key:** `user_id` — все заказы пользователя на одной партиции

### Таблица: user_sessions

```sql
CREATE TABLE user_sessions (
    session_id UUID,
    user_id UUID,
    created_at TIMESTAMP,
    data TEXT,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400;
```

**Partition Key:** `session_id` — равномерное распределение

---

## Стратегии восстановления целостности

| Стратегия | Описание | Для каких сущностей |
|-----------|----------|---------------------|
| **Hinted Handoff** | Хранение записей для недоступного узла | carts, sessions |
| **Read Repair** | Синхронизация при чтении | order_history, product_views |
| **Anti-Entropy Repair** | Полная синхронизация (nodetool repair) | order_history (еженедельно) |

---

## Уровни консистентности

| Операция | Write | Read | Обоснование |
|----------|-------|------|-------------|
| Корзина | `LOCAL_QUORUM` | `ONE` | Баланс скорости и надёжности |
| Заказ | `QUORUM` | `QUORUM` | Важна консистентность |
| Сессия | `ONE` | `ONE` | Максимальная скорость |
| Аналитика | `ONE` | `ONE` | Скорость важнее |

---

## Архитектура гибридного решения

```
┌─────────────────────────────────────────────────────────────────┐
│                         Приложение                               │
└─────────────────────────────────────────────────────────────────┘
                │                           │
                ↓                           ↓
┌───────────────────────────┐   ┌───────────────────────────┐
│       MongoDB             │   │       Cassandra           │
│                           │   │                           │
│  • products (товары)      │   │  • carts (корзины)        │
│  • orders (активные)      │   │  • order_history          │
│  • users (пользователи)   │   │  • user_sessions          │
│                           │   │  • product_views          │
└───────────────────────────┘   └───────────────────────────┘
```

---

## Сравнение MongoDB vs Cassandra

| Критерий | MongoDB | Cassandra |
|----------|---------|-----------|
| Масштабируемость | Авто-балансировка | Без перераспределения |
| Latency при масштабировании | Высокая | Низкая |
| Консистентность | Strong / Eventual | Tunable Eventual |
| Транзакции | ACID | Нет |
| Запросы | Ad-hoc | Только по partition key |
| Отказоустойчивость | Primary-based | Leaderless |

---

## План миграции

1. **Подготовка** (1-2 недели): Развёртывание Cassandra, создание схемы
2. **Двойная запись** (2-4 недели): Проверка консистентности
3. **Переключение чтения** (2-4 недели): Мониторинг производительности
4. **Полная миграция** (1-2 недели): Отключение MongoDB для мигрированных данных

---

## Вывод

Гибридная архитектура использует сильные стороны обеих СУБД:
- **MongoDB** — для сложных запросов, транзакций, ad-hoc доступа
- **Cassandra** — для высокой скорости, TTL данных, линейного масштабирования
