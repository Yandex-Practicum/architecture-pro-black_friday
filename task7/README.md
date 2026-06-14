# Задание 7. Проектирование схем коллекций для шардирования данных

Архитектурный документ для онлайн-магазина «Мобильный мир».

Бэкенд — микросервисы; данные о **заказах**, **товарах** и **корзинах** хранятся в MongoDB (БД `mobile_world`) в трёх коллекциях. Связи между коллекциями логические, через `product_id` в `items`. FK в MongoDB нет.

**Схемы:**
- ERD коллекций — [diagrams/erd-mobile-world.drawio](diagrams/erd-mobile-world.drawio)
- Распределение данных по шардам — [diagrams/shard-data-distribution.drawio](diagrams/shard-data-distribution.drawio)


---

## 1. `products` — товары

### Документ

```json
{
  "_id": "prod_8f3a2c1b",
  "name": "Смартфон X",
  "category": "electronics",
  "subcategory": "smartphones",
  "price": 49990,
  "currency": "RUB",
  "stock_by_zone": {
    "moscow": 50,
    "ekaterinburg": 30,
    "kaliningrad": 12
  },
  "attributes": { "color": "black", "storage_gb": 256 },
  "is_active": true,
  "updated_at": ISODate("2026-06-14T10:15:00Z")
}
```

### Что делаем чаще всего

- Частые обновления остатков при покупках.
- Поиск товаров по категориям и фильтрация по диапазону цен.
- Описание товара на странице продукта.

### Кандидаты на шард-ключ

| Ключ | За | Против |
|------|-----|--------|
| `_id` (hashed) | Точечные read/write, ровное распределение | Каталог — scatter-gather |
| `category` | Каталог на одном шарде | Hot shard: «Электроника» съест всё |
| `geo_zone` | Склад по региону | Один товар = все зоны в одном доке; Москва перегрузит шард |


### Решение

**`{ _id: "hashed" }`** — hashed sharding.

### Индексы

```javascript
db.products.createIndex({ category: 1, price: 1 })
```

---

## 2. `orders` — заказы

### Документ

```json
{
  "_id": "ord_a91f0042",
  "customer_id": "user_10482",
  "created_at": ISODate("2026-06-14T11:02:33Z"),
  "status": "paid",
  "geo_zone": "moscow",
  "items": [
    {
      "product_id": "prod_8f3a2c1b",
      "name": "Смартфон X",
      "category": "electronics",
      "quantity": 1,
      "unit_price": 49990,
      "line_total": 49990
    },
    {
      "product_id": "prod_book_221",
      "name": "MongoDB: The Definitive Guide",
      "category": "books",
      "quantity": 2,
      "unit_price": 1890,
      "line_total": 3780
    }
  ],
  "total_amount": 53770,
  "currency": "RUB",
  "updated_at": ISODate("2026-06-14T11:02:35Z")
}
```

В `items` дублируем `name` и `category` — чтобы история заказа не ломалась, если товар в каталоге переименуют.

Заказ из Москвы может содержать «Электронику» и «Книги» — категории разные, `geo_zone` одна.

### Что делаем чаще всего

- Создаём заказ + списываем остатки в `products`
- Смотрим историю заказов пользователя
- Показываем статус заказа

### Кандидаты на шард-ключ

| Ключ | За | Против |
|------|-----|--------|
| `{ customer_id, created_at }` | История и создание — targeted, сортировка по дате | B2B-клиент с кучей заказов может раздуть один шард |
| `_id` (hashed) | Статус по order_id — targeted | История пользователя — scatter-gather |
| `geo_zone` | По региону | Москва = hot shard; основной read — по клиенту, не по зоне |
| `created_at` | — | Все новые заказы в один chunk |

### Решение

**`{ customer_id: 1, created_at: 1 }`** — compound range.

История, создание и статус (когда в запросе есть `customer_id` — из сессии или UI) — targeted на одном шарде. Поиск только по `_id` заказа без `customer_id` — scatter-gather; в UI передаём оба поля или храним `customer_id` в ссылке на заказ.

`geo_zone` в ключ не кладём: это где исполняют заказ, а не как его ищут.

### Индексы

```javascript
db.orders.createIndex({ customer_id: 1, _id: 1 })
db.orders.createIndex({ _id: 1 })
```

---

## 3. `carts` — корзины

### Документ

Гости и пользователи — разные поля (`session_id` / `user_id`). Чтобы один шард-ключ покрывал обоих, вводим **`owner_key`**:

- пользователь: `user:user_10482`
- гость: `session:sess_9f2caa01`

```json
{
  "_id": "cart_7c2e9f11",
  "owner_key": "user:user_10482",
  "user_id": "user_10482",
  "session_id": null,
  "status": "active",
  "items": [
    { "product_id": "prod_8f3a2c1b", "quantity": 1 }
  ],
  "created_at": ISODate("2026-06-14T09:00:00Z"),
  "updated_at": ISODate("2026-06-14T10:55:00Z"),
  "expires_at": ISODate("2026-06-28T09:00:00Z")
}
```

Гостевая корзина — то же самое, но `owner_key: "session:sess_9f2caa01"`, `user_id: null`, `session_id: "sess_9f2caa01"`.

### Операции (как в ТЗ)

| Операция | Запрос | Шард |
|----------|--------|------|
| Активная корзина гостя | `{ session_id, status: "active" }` + `owner_key: "session:…"` | targeted |
| Активная корзина юзера | `{ user_id, status: "active" }` + `owner_key: "user:…"` | targeted |
| Добавить товар | `updateOne` по `owner_key` + `$push` / `$set` в `items` | targeted |
| Слияние при логине | read guest → merge items → `abandoned` guest, update user cart | 1–2 шарда |
| После заказа | `status: "ordered"` | targeted |

### Что делаем чаще всего

- Создаём / читаем активную корзину
- Добавляем и убираем товары
- При логине сливаем гостевую в пользовательскую
- Помечаем корзину как `ordered`
- Старые корзины чистит TTL по `expires_at`

### Кандидаты на шард-ключ

| Ключ | За | Против |
|------|-----|--------|
| `owner_key` | Один ключ для гостей и юзеров, все CRUD targeted | Слияние гостевой и user-корзины — два шарда, если `owner_key` разные |
| `_id` (hashed) | Ровное распределение | Поиск корзины — scatter-gather |
| `status` | — | Все `active` на одном шарде |

### Решение

**`{ owner_key: 1 }`** — range sharding.

### Индексы

```javascript
db.carts.createIndex(
  { owner_key: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: "active" } }
)
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

Одна активная корзина на владельца — за счёт partial unique index.

---

## 4. Итого по шардированию

| Коллекция | Шард-ключ | Зачем |
|-----------|-----------|-------|
| `products` | `{ _id: "hashed" }` | Покупка и карточка — по product_id |
| `orders` | `{ customer_id: 1, created_at: 1 }` | История и создание — по клиенту |
| `carts` | `{ owner_key: 1 }` | Вся работа с корзиной — по владельцу |

Заказ + остатки — разные шард-ключи; для атомарности нужна **multi-document transaction** через mongos (или saga). B2B с миллионом заказов — можно сменить ключ `orders` на `{ customer_id: "hashed" }`.

---

## 5. Команды MongoDB

### Включение шардирования

```javascript
sh.enableSharding("mobile_world")

sh.shardCollection("mobile_world.products", { _id: "hashed" })
sh.shardCollection("mobile_world.orders", { customer_id: 1, created_at: 1 })
sh.shardCollection("mobile_world.carts", { owner_key: 1 })
```

### Индексы (перед или после `shardCollection`)

```javascript
use mobile_world

db.products.createIndex({ category: 1, price: 1 })

db.orders.createIndex({ customer_id: 1, _id: 1 })
db.orders.createIndex({ _id: 1 })

db.carts.createIndex(
  { owner_key: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: "active" } }
)
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ user_id: 1, status: 1 })
```



### Примеры операций

**Каталог (scatter-gather — нет шард-ключа в фильтре):**

```javascript
db.products.find({
  category: "electronics",
  price: { $gte: 10000, $lte: 80000 },
  is_active: true,
}).sort({ price: 1 })
```

**Карточка товара и списание остатка (targeted по `_id`):**

```javascript
db.products.findOne({ _id: "prod_8f3a2c1b" })

db.products.updateOne(
  { _id: "prod_8f3a2c1b" },
  { $inc: { "stock_by_zone.moscow": -1 }, $set: { updated_at: new Date() } }
)
```

**История заказов пользователя (targeted):**

```javascript
db.orders.find({ customer_id: "user_10482" })
  .sort({ created_at: -1 })
  .limit(20)
```

**Статус заказа (targeted, если есть `customer_id`):**

```javascript
db.orders.findOne({ _id: "ord_a91f0042", customer_id: "user_10482" })
```

**Корзина и оформление:**

```javascript
db.carts.findOne({ owner_key: "user:user_10482", status: "active" })

db.carts.updateOne(
  { owner_key: "user:user_10482", status: "active" },
  { $push: { items: { product_id: "prod_8f3a2c1b", quantity: 1 } }, $set: { updated_at: new Date() } }
)

// слияние гостевой корзины при логине (два owner_key → возможно два шарда)
const guest = db.carts.findOne({ owner_key: "session:sess_9f2caa01", status: "active" })
// ... merge items в user-корзину ...
db.carts.updateOne({ owner_key: "session:sess_9f2caa01" }, { $set: { status: "abandoned" } })
```

**Оформление заказа (cross-shard — нужна транзакция):**

```javascript
const session = db.getMongo().startSession()
session.startTransaction()
try {
  const db = session.getDatabase("mobile_world")
  // read cart → dec stock per product_id → insert order → cart.status = ordered
  session.commitTransaction()
} catch (e) {
  session.abortTransaction()
} finally {
  session.endSession()
}
```

Распределение документов по шардам — [diagrams/shard-data-distribution.drawio](diagrams/shard-data-distribution.drawio).

---