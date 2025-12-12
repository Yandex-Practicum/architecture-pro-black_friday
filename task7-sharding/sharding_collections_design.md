# Шардирование коллекций `orders`, `products` и `carts` в MongoDB

## 1. Контекст

Онлайн-магазин «Мобильный мир» активно вырос:

- много категорий товаров,
- больше заказов,
- больше одновременных пользователей,
- несколько микросервисов, использующих общую MongoDB.

Основные коллекции:

- `orders` — оформленные заказы;
- `products` — товары каталога;
- `carts` — текущие корзины (гостевые и пользовательские).

Цель: спроектировать схемы коллекций и подобрать стратегии шардирования, которые:

- равномерно распределяют данные и нагрузку по шардам,
- поддерживают типичные запросы (по пользователю, по геозоне, по категории/цене, по session/user_id),
- не создают «горячих» шардов.

---

## 2. Коллекция `orders`

### 2.1. Схема документа

```
{
  _id: ObjectId,
  user_id: ObjectId,
  created_at: ISODate,
  status: String,
  total_amount: NumberDecimal,
  geo_zone: String,
  items: [
    {
      product_id: ObjectId,
      product_name: String,
      category: String,
      quantity: NumberInt,
      price: NumberDecimal
    }
  ],
  payment_method: String,
  delivery_type: String,
  updated_at: ISODate
}
```

### 2.2. Основные операции

- Создание заказа.
- История заказов пользователя.
- Отображение статуса заказа.

### 2.3. Кандидаты на shard‑key и анализ

- `user_id` — подходит для targeted‑запросов по пользователю.
- `created_at` — вызывает hotspot.
- `geo_zone` — возможны перекосы.
- `_id` hashed — равномерно, но scatter‑gather по user.

### 2.4. Выбранная стратегия

**Shard key:**

```
{ user_id: "hashed", created_at: 1 }
```

Причины:

- hashed(user_id) распределяет равномерно,
- created_at даёт упорядоченность внутри шарда,
- запросы истории пользователя — targeted.

### 2.5. Команды MongoDB

```
sh.enableSharding("mobile_store")

sh.shardCollection(
  "mobile_store.orders",
  { user_id: "hashed", created_at: 1 }
)

db.orders.createIndex({ user_id: 1, created_at: -1 })
db.orders.createIndex({ geo_zone: 1, created_at: -1 })
db.orders.createIndex({ status: 1, updated_at: -1 })
```

---

## 3. Коллекция `products`

### 3.1. Схема

```
{
  _id: ObjectId,
  sku: String,
  name: String,
  category: String,
  price: NumberDecimal,
  stocks: [
    { geo_zone: String, quantity: NumberInt }
  ],
  attributes: {
    color: String,
    size: String
  },
  description: String,
  updated_at: ISODate
}
```

### 3.2. Основные операции

- Частые обновления остатков.
- Поиск по категории и цене.
- Просмотр карточки товара.

### 3.3. Кандидаты на shard‑key

- `category` — риск больших категорий.
- `_id` hashed — простое равномерное распределение.

### 3.4. Выбранная стратегия

**Shard key:**  

```
{ _id: "hashed" }
```

Причины:

- Равномерное распределение,
- Нет hotspot,
- Каталог небольшой, scatter‑gather для поиска по категории допустим.

### 3.5. Команды MongoDB

```
sh.shardCollection(
  "mobile_store.products",
  { _id: "hashed" }
)

db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ sku: 1 }, { unique: true })
db.products.createIndex({ "stocks.geo_zone": 1 })
```

---

## 4. Коллекция `carts`

### 4.1. Схема

```
{
  _id: ObjectId,
  user_id: ObjectId,
  session_id: String,

  owner_key: String,  // "user:<id>" или "session:<id>"

  items: [
    { product_id: ObjectId, quantity: NumberInt }
  ],

  status: String,
  created_at: ISODate,
  updated_at: ISODate,
  expires_at: ISODate  // TTL
}
```

### 4.2. Основные операции

- Создание активной корзины.
- Получение активной корзины по user_id или session_id.
- Добавление / удаление товара.
- Слияние гостевой корзины в пользовательскую.
- Завершение заказа.

### 4.3. Кандидаты на shard key

- `_id` — плохо, все запросы scatter-gather.
- `user_id` — не покрывает гостей.
- `session_id` — не покрывает авторизованных.
- `owner_key` — универсальный идентификатор владельца корзины.

### 4.4. Выбранная стратегия

**Shard key:**  

```
{ owner_key: "hashed" }
```

Причины:

- Все операции по корзине — targeted.
- Поддерживает и пользователей, и гостей.
- Равномерное распределение.

### 4.5. Команды MongoDB

```js
sh.shardCollection(
  "mobile_store.carts",
  { owner_key: "hashed" }
)

db.carts.createIndex(
  { user_id: 1, status: 1 },
  { partialFilterExpression: { status: "active" } }
)

db.carts.createIndex(
  { session_id: 1, status: 1 },
  { partialFilterExpression: { status: "active" } }
)

db.carts.createIndex(
  { expires_at: 1 },
  { expireAfterSeconds: 0 }
)
```

---

## 5. Сводная таблица стратегий

| Коллекция | Shard key | Тип | Причины |
|----------|------------|------|---------|
| `orders` | `{ user_id: "hashed", created_at: 1 }` | hashed + range | История заказов — targeted; нет hotspot; равномерное распределение. |
| `products` | `{ _id: "hashed" }` | hashed | Простое равномерное распределение; минимальный риск hotspot; каталог маленький. |
| `carts` | `{ owner_key: "hashed" }` | hashed | Все операции обращаются по владельцу корзины; targeted; равномерное распределение. |

---

## 6. Итог

Спроектированные shard‑key обеспечивают:

- целевые запросы без scatter‑gather для критичных операций (`orders`, `carts`);
- равномерное распределение нагрузки;
- отсутствие горячих шардов;
- упрощённую логику приложения за счёт нормализованных ключей (`owner_key`).

