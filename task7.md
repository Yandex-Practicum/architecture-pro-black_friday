# Задание 7. Проектирование схем коллекций для шардирования данных

## Collection

### Orders
```json lines
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": Date,
  "items": [
    {
      "product_id": ObjectId,
      "price": Number
    }
  ],
  "status": String,
  "total_price": Number,
  "geo": String
}
```
#### Sharding 
Рекомендуемый шард-ключ:
- user_id: hashed

Он даёт оптимум по всем трём основным операциям:
- Быстрое создание заказа -  распределение по шардам
- История заказов пользователя - targeted queries по одному шард-диапазону
- Отображение статуса - _id работает независимо от шардинга

### Products
```json lines
{
  "_id": ObjectId,
  "sku": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "stock": [
    {
        "count": Number,
        "geo": String
    }
  ],
  "params": {
    "color": String,
    "size": String,
  }
}
```
#### Sharding
Выносим stock в отдельную коллекцию, т.к. эта часть документа чаще всего обновляется:
#### products
```json lines
{
  "_id": ObjectId,
  "sku": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "params": {
    "color": String,
    "size": String,
  }
}
```
#### stocks
```json lines

{
  "_id": ObjectId,
  "sku": ObjectId,
  "count": Number,
  "geo": String
}
```
Итоговое решение
- Коллекция products

1. НЕ шардируем
2. Индекс: {category, price}
3. Ориентирована на поиск

- Коллекция stock

1. Шардируем по sku: hashed
2. Частые обновления остатков
3. Нагрузка распределяется по всем шардам

### Carts
```json lines
{
  "_id": ObjectId,
  "user_id": String,
  "session_id": String,
  "items": [
    {
      "product_id": ObjectId,
      "quantity": Number
    }
  ],
  "status": String,
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date
}
```
#### Sharding
Объединяем user_id и session_id в одно поле: ownerId
```json lines
{
  "_id": ObjectId,
  "owner_Id": String
  "user_id": String | null,
  "session_id": String | null,
  "items": [
    {
      "product_id": ObjectId,
      "quantity": Number
    }
  ],
  "status": String,
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date
}

Шард-ключ:
shard key: { owner: "hashed" }