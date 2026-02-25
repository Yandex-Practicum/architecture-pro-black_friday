## Описание схемы коллекций.

### Коллекция заказы:

#### Описание:

```
orders: {
  _id: ObjectId,
  user_id: "u123",
  created_at: ISODate("2026-02-25T12:34:56Z"),
  geo_zone: "MSK",
  status: "created" | "paid" | "shipped" | "delivered" | "cancelled",
  items: [
    {
      product_id: ObjectId,
      title: "Смартфон X",
      category: "electronics",
      unit_price: 49990,
      quantity: 1,
      amount: 49990
    }
  ],
  total_amount: 49990,
}
```

Кандидат на шард-ключ: `user_id`.
Стратегия кеширования: хеширование.
Ключ и стратегия выбраны из-за большого количества пользователей, что позволит равномерно распределить заказы по всем
шардам.

#### Индексы:

1. Оптимизация поиска заказов пользователя:
   ```javascript
    db.orders.createIndex({ user_id: 1, created_at: -1 })
    ```

### Товары:

#### Описание:

```
products: {
_id: ObjectId,
title: "Смартфон X",
category: "electronics",
price: 49990,
attrs: { color: "black", size: "128gb" },

stock_by_zone:{
    "EKB": 50,
    "KGD": 30,
    "MSK": 120
  },
}
```

Кандидат на шард-ключ: `category+price`.
Стратегия кеширования: диапазонная.
Ключ и стратегия выбраны из-за того, что ожидается часты поиск товаров по категориям и фильтрация по диапазону цен.
Явным недостатком будет стратегии будет возможное появление "горячих" шардов.

#### Индексы:

1. Оптимизация поиска товаров:
   ```javascript
    db.products.createIndex({ category: 1, price: 1 })
    ```

### Коллекция корзины:

#### Описание:

```
carts: {
_id: ObjectId,
user_id: "u123" | null,
session_id: "s-abc" | null,
owner_key: "u:u123" | "s:s-abc",
status: "active" | "ordered" | "abandoned",
items: [
    {
      product_id: ObjectId,
      quantity: 2, 
      added_at: ISODate(...) 
    }
],
created_at: ISODate(...),
updated_at: ISODate(...),
expires_at: ISODate(...)
}
```

Кандидат на шард-ключ: `owner_key`.
Стратегия кеширования: хеширование.
Отдельный атрибут создан для простоты расчёта ключа. Данная стратегия позволит быстро искать корзину конкретного
пользователя, а судя по описанию основная масса операций будет начинаться с поиска корзины пользователя. Также данный
шард-ключ обеспечит высокую кардинальность данных.

#### Индексы:

1. Оптимизация поиска корзины для конкретного владельца:
   ```javascript
    db.carts.createIndex({ owner_key: 1, status: 1 })
    ```
2. Оптимизация поиска устаревших корзины:
   ```javascript
    db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
    ```
