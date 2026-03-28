# Задание 7. Проектирование схем коллекций для шардирования данных

## 1. Цель
Спроектировать коллекции `orders`, `products`, `carts` и выбрать шард-ключи, обеспечивающие:
- равномерное распределение нагрузки
- быстрые основные операции
- масштабируемость

## 2. Коллекция `orders`
### Схема
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": ISODate,
  "status": "created|paid|shipped|delivered|cancelled",
  "geo_zone": "MSK",
  "items": [
    {
      "product_id": ObjectId,
      "price": NumberDecimal,
      "quantity": Number,
      "line_total": NumberDecimal
    }
  ],
  "total_amount": NumberDecimal
}
```

Шард ключ { user_id: "hashed" }

#### Обоснование
- частые запросы по user_id (история заказов)
- равномерное распределение записей
- отсутствие горячих шардов при росте заказов

## 3. Коллекция `products`
### Схема
```json
{
  "_id": ObjectId,
  "sku": "string",
  "name": "string",
  "category": "string",
  "price": NumberDecimal,
  "attributes": {
    "color": "string",
    "size": "string"
  },
  "stock_by_geo": [
    { "geo_zone": "MSK", "quantity": Number }
  ],
  "updated_at": ISODate
}
```
Шард-ключ { _id: "hashed" }

#### Обоснование
- частые обновления остатков -> нужна равномерная запись
- быстрый доступ к товару по ID
- избегаем перекоса по категориям

## 4. Коллекция carts
### Схема
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "session_id": "string",
  "owner_key": "user:<id> | session:<id>",
  "status": "active|ordered|abandoned",
  "items": [
    { "product_id": ObjectId, "quantity": Number }
  ],
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate
}
```
Шард ключ { owner_key: "hashed" }

#### Обоснование
- единый доступ для гостей и пользователей
- точечные запросы к активной корзине
- равномерное распределение write-нагрузки

Индексы:

```
db.orders.createIndex({ user_id: 1, created_at: -1 })
db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ sku: 1 }, { unique: true })
db.carts.createIndex({ owner_key: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

Команды для шардинга

```
sh.enableSharding("mobile_world")

sh.shardCollection("mobile_world.orders", { user_id: "hashed" })
sh.shardCollection("mobile_world.products", { _id: "hashed" })
sh.shardCollection("mobile_world.carts", { owner_key: "hashed" })
```