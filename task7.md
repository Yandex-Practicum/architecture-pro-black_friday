## Коллекция orders

- `_id: uuid` — уникальный идентификатор заказа;
- `user_id: uuid` — идентификатор клиента, **ключ шардирования**;
- `created_at: datetime` — дата и время оформления заказа;
- `products: json_array` — список заказанных товаров и их цену:
  ```json
  [{ "id": "uuid", "name": "string", "price": "decimal", "quantity": "integer" }]
  ```
- `status: string` — статус заказа;
- `total: decimal` — общая сумма заказа;
- `location: string` — геозона заказа.

**Стратегия шардирования**

Используем хешированное шардирование по `user_id`. Это обеспечивает локальность данных: все заказы конкретного пользователя физически хранятся на одном шарде, что гарантирует высокую скорость выполнения частых запросов вида `find({ user_id: ... })`.

## Коллекция products

- `_id: uuid` — уникальный идентификатор товара, **ключ шардирования**;
- `name: string` — наименование;
- `category: string` — категория товара;
- `price: decimal` — цена;
- `quantity: json_array` — остаток товара в каждой геозоне:
  ```json
  [{ "location": "string", "quantity": "integer" }]
  ```
- `additional_attributes: json_object` — дополнительные атрибуты (цвет, размер).

**Стратегия шардирования**

Используем хешированное шардирование по `_id`. Это равномерно распределяет товары и операции обновления остатков между шардами.

Запросы на получение конкретного товара по ID (`findOne({ _id: ... })`) будут выполняться максимально быстро, так как `mongos` сразу определит целевой шард по хэшу.

## Коллекция carts

- `_id: uuid` — уникальный идентификатор корзины;
- `user_id | session_id: uuid` — идентификатор пользователя (`user_id`) и `session_id` для гостей;
- `owner_id: uuid` — либо `session_id`, либо `user_id` для унификации под **ключ шардирования**;
- `items: json_array` — список товаров:
  ```json
  [{ "product_id": "uuid", "quantity": "integer" }]
  ```
- `status: string` — статус корзины (`active`, `ordered`, `abandoned`);
- `created_at: datetime` — дата и время создания;
- `updated_at: datetime` — дата и время последнего обновления;
- `expires_at: datetime` — время удаления (TTL) для автоматической очистки старых корзин.

**Стратегия шардирования**

Используем хешированное шардирование по `owner_id`. Это обеспечивает равномерное распределение корзин разных пользователей между шардами и локальность данных: все корзины конкретного пользователя находятся на одном шарде, что позволяет ускорить запросы `find({ owner_id: ... })`.

## Команды MongoDB

**Настройка шардирования:**

```javascript
sh.shardCollection("somedb.orders", { user_id: "hashed" });
sh.shardCollection("somedb.products", { _id: "hashed" });
sh.shardCollection("somedb.carts", { owner_id: "hashed" });
```

**Создание индексов:**

```javascript
db = db.getSiblingDB("somedb");

db.orders.createIndex({ user_id: 1, created_at: -1 });
db.products.createIndex({ category: 1, price: 1 });
db.carts.createIndex({ owner_id: 1, status: 1 });
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 });
```