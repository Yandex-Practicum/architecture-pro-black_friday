# Задание 7. Шардирование коллекций интернет-магазина

## 1. Коллекция `orders` (заказы)

### Схема

```javascript
{
  _id: ObjectId("..."),
  user_id: "user123",
  order_date: ISODate("2024-01-15T10:30:00Z"),
  items: [
    { product_id: "prod456", name: "Смартфон X", quantity: 1, price: 50000 },
    { product_id: "prod789", name: "Наушники", quantity: 2, price: 3000 }
  ],
  status: "completed",
  total_amount: 56000,
  geo_zone: "moscow"
}
```

### Варианты шард-ключа

- `_id` - плохо, монотонно растущий, все новые заказы попадут на один шард
- `user_id` - может быть перегрузка, если один пользователь делает много заказов
- `geo_zone` - плохо, мало значений (Москва, СПб, Екб...)
- `{geo_zone: 1, user_id: 1}` - ✅ лучший вариант

### Выбор: `{geo_zone: 1, user_id: 1}`

**Почему:**
- Заказы из одного региона хранятся вместе (быстрые запросы по региону)
- user_id добавляет равномерность
- Новые заказы распределяются по разным шардам

**Минусы:**
- Запрос всех заказов пользователя пойдет на все шарды

**Команды:**

```javascript
sh.enableSharding("shop")
sh.shardCollection("shop.orders", { geo_zone: 1, user_id: 1 })
```


## 2. Коллекция `products` (товары)

### Схема

```javascript
{
  _id: ObjectId("..."),
  product_id: "prod456",
  name: "Смартфон X",
  category: "electronics",
  price: 50000,
  stock: {
    moscow: 50,
    ekaterinburg: 30,
    kaliningrad: 20
  },
  attributes: {
    color: "black",
    size: "6.5inch"
  }
}
```

### Варианты шард-ключа

- `_id` - плохо, монотонно растущий
- `product_id` - много уникальных значений, хорошо
- `category` - плохо, мало категорий (электроника, книги...)
- `{category: 1, product_id: 1}` - можно, но сложно

### Выбор: `{product_id: "hashed"}`

**Почему:**
- Товары равномерно распределены по всем шардам
- Обновления остатков (главная операция) идут на разные шарды
- Нет перегрузки на популярных товарах

**Минусы:**
- Запросы по категориям идут на все шарды (но это редко)

**Команды:**

```javascript
sh.shardCollection("shop.products", { product_id: "hashed" })
```


## 3. Коллекция `carts` (корзины)

### Схема

```javascript
{
  _id: ObjectId("..."),
  user_id: "user123",
  session_id: "sess_abc123",
  items: [
    { product_id: "prod456", quantity: 1 },
    { product_id: "prod789", quantity: 2 }
  ],
  status: "active",
  created_at: ISODate("2024-01-15T10:00:00Z"),
  updated_at: ISODate("2024-01-15T10:30:00Z"),
  expires_at: ISODate("2024-01-22T10:00:00Z")
}
```

### Варианты шард-ключа

- `_id` - плохо, монотонно растущий
- `user_id` - проблема: у гостей user_id пустой, все корзины гостей на одном шарде
- `session_id` - ✅ каждая сессия уникальна
- `{user_id: 1, session_id: 1}` - можно, но сложнее

### Выбор: `{session_id: "hashed"}`

**Почему:**
- Все корзины (гостей и пользователей) равномерно распределены
- Работа с корзиной (добавить/удалить товар) идет на один шард
- TTL удаление старых корзин работает на всех шардах

**Минусы:**
- Слияние гостевой и пользовательской корзин требует запроса на все шарды (но это редко)

**Команды:**

```javascript
sh.shardCollection("shop.carts", { session_id: "hashed" })
```


## Примеры запросов

```javascript
// Создать заказ
db.orders.insertOne({
  user_id: "user123",
  geo_zone: "moscow",
  items: [{ product_id: "prod456", quantity: 1, price: 50000 }],
  total_amount: 50000
})

// История заказов пользователя
db.orders.find({ user_id: "user123" }).sort({ order_date: -1 })

// Обновить остаток товара
db.products.updateOne(
  { product_id: "prod456" },
  { $inc: { "stock.moscow": -1 } }
)

// Найти товары по категории и цене
db.products.find({ category: "electronics", price: { $lt: 60000 } })

// Получить активную корзину
db.carts.findOne({ session_id: "sess_abc123", status: "active" })

// Добавить товар в корзину
db.carts.updateOne(
  { session_id: "sess_abc123", status: "active" },
  { $push: { items: { product_id: "prod456", quantity: 1 } } }
)
```


## Проверка распределения

```javascript
db.orders.getShardDistribution()
db.products.getShardDistribution()
db.carts.getShardDistribution()
sh.status()
```
