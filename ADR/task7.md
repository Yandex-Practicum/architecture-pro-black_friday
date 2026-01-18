# ADR Проектирование схем коллекций для шардирования данных

## Коллекция products
### Схема документа
```javascript
{
  _id: ObjectId,              // Уникальный идентификатор товара
  name: String,               // Наименование товара
  category: String,           // Категория (электроника, книги и т.д.)
  price: Decimal128,          // Цена
  attributes: {               // Доп. атрибуты (цвет, размер)
    color: String,
    size: String
  },
  stock: {                    // Остатки по геозонам
    "москва": Number,
    "екатеринбург": Number,
    // ... другие регионы
  }
}
```
Шард-ключ: category
Стратегия: Range-based sharding
Обоснование:
- Запросы часто фильтруют товары по категориям (например, «Электроника»).
- Распределение по категориям обеспечивает локальность данных для поисковых запросов.
- Обновления остатков (stock) происходят равномерно по разным категориям, что исключает риск перекоса нагрузки.
### Команды
#### Создание индексов
```javascript
// Индекс для поиска по категории и цене
db.products.createIndex({ category: 1, price: 1 });
// Индекс для остатков в геозоне (москва)
db.products.createIndex({ "stock.moscow": 1 });
// Текстовый индекс для поиска по названию товара
db.products.createIndex({ name: "text" });
```
#### Добавление товара
```javascript
db.products.insertOne({
  name: "Смартфон X",
  category: "Электроника",
  price: NumberDecimal("599.99"),
  attributes: { color: "черный", size: "6.5" },
  stock: { москва: 50, екатеринбург: 30 }
});
```
#### Поиск товаров
```javascript
// Поиск по категории "Электроника" с сортировкой по цене (возрастание)
db.products.find({ category: "Электроника" }).sort({ price: 1 });
// Поиск товаров в наличии в Москве (остаток > 0)
db.products.find({ "stock.moscow": { $gt: 0 } });
// Поиск по названию (текстовый индекс)
db.products.find({ $text: { $search: "Смартфон" } });
```
#### Обновление остатков
```javascript
// Уменьшение остатка при покупке (атомарно)
db.products.updateOne(
  { _id: ObjectId("..."), "stock.moscow": { $gte: 2 } },
  { $inc: { "stock.moscow": -2 } }
);
```

## Коллекция orders
### Схема документа
```javascript
{
  _id: ObjectId,              // Уникальный ID заказа
  user_id: ObjectId,          // ID клиента
  created_at: ISODate,        // Дата/время создания
  items: [                    // Список товаров
    {
      product_id: ObjectId,
      price: Decimal128,
      quantity: Number
    }
  ],
  total: Decimal128,          // Общая сумма
  status: String,             // Статус (новый, оплачен, доставлен)
  geo_zone: String,           // Геозона (москва, екатеринбург)
  updated_at: ISODate         // Время последнего обновления
}
```
Шард-ключ: user_id
Стратегия: Hashed sharding
Обоснование:
- Основные запросы — поиск заказов по user_id (история заказов).
- Хеширование обеспечит равномерное распределение заказов по шардам.
- user_id имеет высокую кардинальность, что минимизирует "горячие" шарды.
- Записи одного пользователя могут попасть на один шард, что ускорит выборку истории заказов.
### Команды
#### Создание индексов
```javascript
// Индекс для поиска заказов по user_id
db.orders.createIndex({ user_id: 1 });
// Индекс для поиска по геозоне и дате
db.orders.createIndex({ geo_zone: 1, created_at: -1 });
```
#### Создание заказа
```javascript
db.orders.insertOne({
  user_id: ObjectId("..."),
  created_at: new Date(),
  items: [
    { product_id: ObjectId("..."), price: NumberDecimal("599.99"), quantity: 1 }
  ],
  total: NumberDecimal("599.99"),
  status: "новый",
  geo_zone: "москва"
});
```
#### Поиск заказов
```javascript
// Все заказы пользователя
db.orders.find({ user_id: ObjectId("...") });
// Заказы в статусе "новый" по геозоне "москва"
db.orders.find({ status: "новый", geo_zone: "москва" });
// Заказы за последние 7 дней
db.orders.find({ created_at: { $gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) }});
```
#### Обновление статуса заказа
```javascript
db.orders.updateOne(
  { _id: ObjectId("...") },
  { $set: { status: "оплачен", updated_at: new Date() } }
);
```
#### Создание заказа с атомарным списанием остатков
```javascript
session.startTransaction();
try {
  const order = db.orders.insertOne({ ... });
  db.products.updateOne(
    { _id: productId, "stock.moscow": { $gte: quantity } },
    { $inc: { "stock.moscow": -quantity } }
  );
  session.commitTransaction();
} catch (error) {
  session.abortTransaction();
}
```

## Коллекция carts
### Схема документа
```javascript
{
  _id: ObjectId,              // Уникальный ID корзины
  user_id: ObjectId,          // ID пользователя (null для гостей)
  session_id: String,         // ID сессии (для гостей)
  items: [                    // Товары в корзине
    {
      product_id: ObjectId,
      quantity: Number
    }
  ],
  status: String,             // active | ordered | abandoned
  created_at: ISODate,        // Дата создания
  updated_at: ISODate,        // Дата обновления
  expires_at: ISODate         // TTL для автоматической очистки
}
```
Шард-ключ: session_id (для гостей) / user_id (для пользователей)
Стратегия: Hashed sharding
Обоснование:
- Основные операции: поиск корзины по session_id (гости) или user_id (пользователи).
- Хеширование предотвратит перекос нагрузки, так как корзины создаются часто и удаляются автоматически (TTL).
- Гарантирует, что корзины одного пользователя/сессии будут обрабатываться одним шардом, что важно для операций слияния корзин (логин пользователя).
### Команды
#### Создание индексов
```javascript
// Индекс для поиска корзины по session_id и статусу
db.carts.createIndex({ session_id: 1, status: 1 });
// Индекс для TTL (автоочистка брошенных корзин через 30 дней)
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 2592000 }); // 30 дней
// Индекс для user_id (для залогиненных пользователей)
db.carts.createIndex({ user_id: 1, status: 1 });
```
#### Создание корзины
```javascript
db.carts.insertOne({
  session_id: "abc123",
  items: [],
  status: "active",
  created_at: new Date(),
  updated_at: new Date(),
  expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // TTL = 30 дней
});
```
#### Добавление товара в корзину
```javascript
db.carts.updateOne(
  { session_id: "abc123", status: "active" },
  { $push: { items: { product_id: ObjectId("..."), quantity: 1 } } }
);
```
#### Объединение гостевой и пользовательской корзины
```javascript
// 1. Находим гостевую корзину
const guestCart = db.carts.findOne({ session_id: "abc123", status: "active" });
// 2. Добавляем товары в корзину пользователя
db.carts.updateOne(
  { user_id: ObjectId("..."), status: "active" },
  { $push: { items: { $each: guestCart.items } } }
);
// 3. Помечаем гостевую корзину как "abandoned"
db.carts.updateOne(
  { _id: guestCart._id },
  { $set: { status: "abandoned" } }
);
```

## Дополнительные оптимизации:
### Индексы:
- products: Индексы на category, price, stock.geo_zone (для фильтрации).
- orders: Индексы на user_id, geo_zone, status, created_at.
- carts: Индекс на session_id, user_id, status, expires_at (TTL).

### Репликация:
- Для orders и carts рекомендуется использовать репликацию для отказоустойчивости.
- Для products можно использовать репликацию с чтением из вторичных узлов для разгрузки основного шарда.

### Chunk Size:
- Для products и orders можно увеличить размер чанка (с 64 MB до 128 MB), так как документы могут быть крупными (много товаров в заказе).
- Для carts оставить стандартный размер (64 MB), так как корзины обновляются часто.

### Write Concern:
- Для orders и products использовать { w: "majority" } для гарантии сохранности данных.
- Для carts можно использовать { w: 1 }, так как потеря корзины не критична (пользователь может восстановить её).

## Итог:
- products: Шардирование по category (range) для эффективного поиска по категориям и обновления остатков.
- orders: Шардирование по user_id (hashed) для равномерного распределения и быстрого доступа к истории заказов.
- carts: Шардирование по session_id/user_id (hashed) для балансировки нагрузки при частых операциях CRUD.

Эта схема обеспечит:
- Высокую доступность и отказоустойчивость.
- Равномерное распределение нагрузки по шардам.
- Оптимальную производительность для частых операций.