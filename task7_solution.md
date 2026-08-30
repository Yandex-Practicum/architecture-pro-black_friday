# Задание 7. Проектирование схем коллекций для шардирования данных

## Коллекция orders

### Схема документа

```javascript
{
  _id: ObjectId("..."),
  order_id: "ord_1000001",
  user_id: "user_12345",
  created_at: ISODate("2026-08-28T10:15:00Z"),
  items: [
    {
      product_id: "product_100",
      name: "Смартфон X",
      category_id: "electronics",
      price: NumberDecimal("49990.00"),
      quantity: 1
    },
    {
      product_id: "product_501",
      name: "Книга",
      category_id: "books",
      price: NumberDecimal("990.00"),
      quantity: 2
    }
  ],
  status: "created",
  total_amount: NumberDecimal("51970.00"),
  geo_zone: "msk"
}
```

### Основные запросы

```javascript
db.orders.insertOne(order)

db.orders.find({ user_id: "user_12345" }).sort({ created_at: -1 })

db.orders.findOne({ _id: ObjectId("...") })

db.orders.findOne({ order_id: "ord_1000001" })
```

### Кандидаты для shard key

| Поле | Плюсы | Минусы |
| --- | --- | --- |
| `_id` hashed | Хорошо распределяет записи | История заказов пользователя пойдет по всем шардам |
| `order_id` hashed | Хорошо для поиска конкретного заказа | Не помогает с историей заказов пользователя |
| `user_id` hashed | Хорошо распределяет пользователей и их заказы | Запросы по диапазону дат внутри всех пользователей не будут локальными |
| `{ user_id, created_at }` | Хорошо для истории заказов пользователя | При обычном range shard key возможен перекос по крупным клиентам |
| `geo_zone` | Можно хранить заказы ближе к региону | Мало разных значений, будет плохое распределение |

### Выбранная стратегия

Для `orders` выбираем shard key:

```javascript
{ user_id: "hashed" }
```

Почему подходит:

- создание заказов распределяется по пользователям, а значит нагрузка не падает на один шард;
- история заказов конкретного пользователя ищется по shard key и не требует обхода всего кластера;
- статус заказа обычно можно искать по `_id` или `order_id`, для этого нужен отдельный индекс;
- геозона остается обычным полем для аналитики и фильтрации, но не становится shard key, потому что регионов мало.

### Индексы и команды

```javascript
use somedb

db.orders.createIndex({ user_id: "hashed" })
sh.shardCollection("somedb.orders", { user_id: "hashed" })

db.orders.createIndex({ user_id: 1, created_at: -1 })
db.orders.createIndex({ order_id: 1 })
db.orders.createIndex({ status: 1, created_at: -1 })
```

## Коллекция products

### Схема документа

```javascript
{
  _id: ObjectId("..."),
  product_id: "product_100",
  name: "Смартфон X",
  category_id: "electronics",
  price: NumberDecimal("49990.00"),
  stock_by_geo_zone: [
    { geo_zone: "ekb", quantity: 50 },
    { geo_zone: "kgd", quantity: 30 },
    { geo_zone: "msk", quantity: 120 }
  ],
  attributes: {
    color: "black",
    storage: "256gb",
    warranty_months: 12
  },
  updated_at: ISODate("2026-08-28T10:15:00Z")
}
```

### Основные запросы

```javascript
db.products.find({ category_id: "electronics", price: { $gte: 10000, $lte: 60000 } })

db.products.findOne({ product_id: "product_100" })

db.products.updateOne(
  { product_id: "product_100", "stock_by_geo_zone.geo_zone": "ekb" },
  { $inc: { "stock_by_geo_zone.$.quantity": -1 } }
)
```

### Кандидаты для shard key

| Поле | Плюсы | Минусы |
| --- | --- | --- |
| `product_id` hashed | Хорошее распределение, удобно для карточки товара | Поиск по категории и цене будет scatter-gather |
| `category_id` | Категорий много, запросы каталога частые | Популярная категория может перегрузить один шард |
| `{ category_id, price }` | Удобно для каталога и фильтра цены | Диапазоны цены могут создавать горячие участки |
| `{ category_id, product_id }` | Категория участвует в запросах каталога | Без хеширования возможен перекос внутри популярных категорий |
| `geo_zone` | Остатки завязаны на регион | Регионов мало, распределение слабое |

### Выбранная стратегия

Для `products` выбираем compound hashed shard key:

```javascript
{ category_id: 1, product_id: "hashed" }
```

Почему подходит:

- каталог часто открывают по категории, поэтому `category_id` должен быть в shard key;
- `product_id` в хешированном виде помогает распределять товары внутри категории;
- популярная категория не должна целиком лежать на одном шарде;
- обновление остатков конкретного товара можно выполнять с `category_id` и `product_id`, тогда запрос будет направлен точнее.

### Индексы и команды

```javascript
use somedb

db.products.createIndex({ category_id: 1, product_id: "hashed" })
sh.shardCollection("somedb.products", { category_id: 1, product_id: "hashed" })

db.products.createIndex({ product_id: 1 })
db.products.createIndex({ category_id: 1, price: 1 })
db.products.createIndex({ name: "text" })
```

Пример обновления остатков:

```javascript
db.products.updateOne(
  {
    category_id: "electronics",
    product_id: "product_100",
    "stock_by_geo_zone.geo_zone": "ekb"
  },
  {
    $inc: { "stock_by_geo_zone.$.quantity": -1 },
    $set: { updated_at: new Date() }
  }
)
```

## Коллекция carts

### Схема документа

```javascript
{
  _id: ObjectId("..."),
  owner_key: "user:user_12345",
  user_id: "user_12345",
  session_id: null,
  items: [
    { product_id: "product_100", quantity: 1 },
    { product_id: "product_777", quantity: 2 }
  ],
  status: "active",
  created_at: ISODate("2026-08-28T10:00:00Z"),
  updated_at: ISODate("2026-08-28T10:20:00Z"),
  expires_at: ISODate("2026-09-04T10:20:00Z")
}
```

Для гостевой корзины:

```javascript
{
  _id: ObjectId("..."),
  owner_key: "session:8f53b2e1",
  user_id: null,
  session_id: "8f53b2e1",
  items: [],
  status: "active",
  created_at: ISODate("2026-08-28T10:00:00Z"),
  updated_at: ISODate("2026-08-28T10:00:00Z"),
  expires_at: ISODate("2026-08-30T10:00:00Z")
}
```

### Основные запросы

```javascript
db.carts.findOne({ owner_key: "session:8f53b2e1", status: "active" })

db.carts.findOne({ owner_key: "user:user_12345", status: "active" })

db.carts.updateOne(
  { owner_key: "user:user_12345", status: "active" },
  { $set: { items: newItems, updated_at: new Date() } }
)
```

### Кандидаты для shard key

| Поле | Плюсы | Минусы |
| --- | --- | --- |
| `user_id` hashed | Хорошо для авторизованных пользователей | Не подходит для гостей без `user_id` |
| `session_id` hashed | Хорошо для гостей | Не подходит для авторизованных пользователей |
| `_id` hashed | Хорошее распределение | Получение активной корзины по user/session будет scatter-gather |
| `{ user_id, status }` | Удобно для активной корзины пользователя | Гостевые корзины снова выпадают |
| `owner_key` hashed | Один ключ для пользователей и гостей | Нужно формировать дополнительное поле в приложении |

### Выбранная стратегия

Для `carts` выбираем shard key:

```javascript
{ owner_key: "hashed" }
```

Почему подходит:

- один и тот же подход работает для гостя и авторизованного пользователя;
- получение активной корзины идет по `owner_key`, то есть запрос попадает на конкретный шард;
- добавление, удаление и замена товара в корзине тоже идут по `owner_key`;
- слияние гостевой корзины с пользовательской затрагивает две конкретные корзины, а не всю коллекцию;
- TTL-очистка старых корзин остается отдельным индексом и не мешает шардированию.

### Индексы и команды

```javascript
use somedb

db.carts.createIndex({ owner_key: "hashed" })
sh.shardCollection("somedb.carts", { owner_key: "hashed" })

db.carts.createIndex({ owner_key: 1, status: 1 })
db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

Пример слияния гостевой корзины в пользовательскую:

```javascript
const guestCart = db.carts.findOne({
  owner_key: "session:8f53b2e1",
  status: "active"
})

db.carts.updateOne(
  { owner_key: "user:user_12345", status: "active" },
  {
    $push: { items: { $each: guestCart.items } },
    $set: { updated_at: new Date() }
  },
  { upsert: true }
)

db.carts.updateOne(
  { owner_key: "session:8f53b2e1", status: "active" },
  {
    $set: {
      status: "abandoned",
      updated_at: new Date()
    }
  }
)
```
