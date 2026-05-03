# Проектирование схем коллекций для шардирования

## 1. Коллекция `orders`

### Схема документа

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

### Выбор шард-ключа

**Шард-ключ: `{ customer_id: "hashed" }`**

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `customer_id` hashed | Равномерное распределение; поиск истории заказов клиента — targeted query на один шард | Запросы по `geo_zone` или `status` — scatter-gather |
| `geo_zone` | Локальность по региону | Низкая кардинальность (мало регионов) — перекос данных |
| `_id` hashed | Идеальная равномерность записи | Все бизнес-запросы — scatter-gather |
| `{ geo_zone, customer_id }` | Targeted по региону и клиенту | Неравномерное распределение между геозонами |

### Стратегия: хэшированное шардирование

- **Запись** — равномерно распределяется по шардам, нет hot spot при массовом создании заказов.
- **Поиск истории клиента** (`customer_id`) — targeted query, mongos направляет запрос на один шард.
- **Статус заказа** — если запрос по `_id`, то targeted (mongos знает шард по `_id`). Если по `order_id` через `customer_id`, тоже targeted.
- Компромисс: аналитические запросы по `geo_zone` или `status` будут scatter-gather, но это допустимо для аналитики.

### Команды

```javascript
sh.enableSharding("mobilnyimir")

sh.shardCollection("mobilnyimir.orders", { customer_id: "hashed" })

// Дополнительные индексы
db.orders.createIndex({ customer_id: 1, created_at: -1 })
db.orders.createIndex({ status: 1 })
```

---

## 2. Коллекция `products`

### Схема документа

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

### Выбор шард-ключа

**Шард-ключ: `{ category: 1, _id: 1 }`**

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `{ category, _id }` compound | Поиск по категории — targeted; `_id` обеспечивает кардинальность внутри категории | Если категорий мало — неидеальное распределение |
| `_id` hashed | Равномерная запись | Все поисковые запросы по категории — scatter-gather |
| `category` hashed | Равномерность по категориям | Поиск по категории — scatter-gather (хэш ломает диапазонные запросы) |
| `price` | Range-запросы по цене targeted | Очень неравномерное распределение |

### Стратегия: ranged шардирование по составному ключу

- **Поиск по категории** (`category: "electronics"`) — targeted query, все товары категории на одном шарде (или нескольких соседних чанках).
- **Фильтрация по цене** внутри категории — работает эффективно, данные рядом.
- **Страница товара** (по `_id`) — если в запросе есть `category`, то targeted. Иначе scatter-gather, но это один документ — быстро.
- **Обновление остатков** — targeted, если указана `category` (обычно известна при покупке).
- `_id` в составном ключе решает проблему низкой кардинальности `category` — чанки делятся по `_id` внутри категории.

### Команды

```javascript
sh.shardCollection("mobilnyimir.products", { category: 1, _id: 1 })

// Индексы для частых операций
db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ name: "text" })
```

---

## 3. Коллекция `carts`

### Схема документа

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

### Выбор шард-ключа

**Шард-ключ: `{ _id: "hashed" }`**

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `_id` hashed | Равномерное распределение; все операции с конкретной корзиной — targeted | Поиск активной корзины по `user_id`/`session_id` — scatter-gather |
| `user_id` hashed | Targeted по `user_id` | У гостевых корзин `user_id = null` — все гости на одном шарде, критический hot spot |
| `session_id` hashed | Targeted для гостей | Запросы по `user_id` — scatter-gather; при слиянии корзин обе операции на разных шардах |
| `status` | — | Кардинальность 3 значения — непригоден |

### Стратегия: хэшированное шардирование по `_id`

- **Корзины — короткоживущие данные** с TTL. Объём коллекции ограничен, scatter-gather на поиск активной корзины по `user_id`/`session_id` приемлем.
- **Равномерная запись** — гостевые и пользовательские корзины распределяются одинаково, нет hot spot.
- **Все CRUD-операции с конкретной корзиной** (добавление/удаление товара, обновление) — по `_id`, targeted.
- **Слияние корзин**: чтение гостевой и обновление пользовательской — обе операции по `_id`, targeted на свой шард.
- **TTL-индекс** для автоматической очистки: `{ expires_at: 1 }` — работает локально на каждом шарде.

### Команды

```javascript
sh.shardCollection("mobilnyimir.carts", { _id: "hashed" })

// Индексы для поиска активных корзин
db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ session_id: 1, status: 1 })

// TTL-индекс для автоматического удаления
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

---

## Сводная таблица

| Коллекция | Шард-ключ | Стратегия | Обоснование |
|-----------|-----------|-----------|-------------|
| `orders` | `{ customer_id: "hashed" }` | Hashed | Равномерная запись; история заказов клиента — targeted query |
| `products` | `{ category: 1, _id: 1 }` | Ranged (compound) | Поиск по категории targeted; `_id` даёт кардинальность для равномерного деления чанков |
| `carts` | `{ _id: "hashed" }` | Hashed | Равномерное распределение без hot spot на гостевых корзинах; CRUD по `_id` — targeted |
