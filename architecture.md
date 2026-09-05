# Архитектурна

## Задание 7. Проектирование схем коллекций для шардирования данных

### `products`

```js
{
  _id: ObjectId,
  name: String,
  category: String,
  price: Decimal128,
  stock: [{ geozone: String, quantity: Number }],
  attributes: { color: String, size: String }
}
```

Shard key: `{ _id: "hashed" }`.

товары распределятся равномерно, без перекосов, остальные поля могут создать горячие точки


### `orders`

```js
{
  _id: ObjectId,
  customer_id: ObjectId,
  created_at: Date,
  items: [{ product_id: ObjectId, price: Decimal128, quantity: Number }],
  status: String,
  total: Decimal128,
  geozone: String
}
```

Shard key: `{ customer_id: "hashed" }`.

тоже равномерно распределит пользователей + позволит получить историю заказов одного пользователя с одного шарда


### `carts`

```js
{
  _id: ObjectId,
  unified_key: String, // user:<id> или session:<id>
  user_id: ObjectId,
  session_id: String,
  items: [{ product_id: ObjectId, quantity: Number }],
  status: String,
  created_at: Date,
  updated_at: Date,
  expires_at: Date
}
```

Shard key: `{ owner_key: "hashed" }`.

`owner_key` потому что у гостя нет `user_id`, а у пользователя может не быть `session_id`.

| Коллекция | Shard key |
|---|---|
| `products` | `{ _id: "hashed" }` |
| `orders` | `{ customer_id: "hashed" }` |
| `carts` | `{ owner_key: "hashed" }` |

## Задание 8. Выявление и устранение «горячих» шардов

следим за метриками каждого шарда:

- CPU;
- память;
- rps read/write;
- p50/p75/p90/p95/p99 времени запросов;
- размер данных и количество chunks;
- число соединений;
- replication lag;

команды чтоб следить за состоянием кластера:

```js
sh.status()
db.products.getShardDistribution()
```

если один из шардов перегружен - надо проверить состояние кластера, включить балансёр, и в крайнем случае решардировать кластер поменяв ключ, например так:

```js
sh.startBalancer()

db.adminCommand({
  reshardCollection: "shop.products",
  key: { _id: "hashed" }
})
```

## Задание 9. Настройка чтения с реплик и консистентность

| операция | откуда читать | допустимая задержка репликации |
|---|---|---:|
| карточка товара | secondary | до 5 секунд |
| поиск по категории и цене | secondary | до 10 секунд |
| проверка остатка перед покупкой | primary | 0 секунд |
| история заказов | secondary | до 5 секунд |
| статус нового заказа | primary | 0 секунд |
| активная корзина | primary | 0 секунд |
| старые брошенные корзины для аналитики | secondary | до 60 секунд |

secondary используется только для данных, задержка которых не влияет на покупку, остальное читается с primary


## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

### 10.1. в кассандру имеет смысл перенести:

- историю заказов;
- каталог для чтения;
- корзины и пользовательские сессии с TTL;

остатки товара лучше оставить в MongoDB, так как при покупке важно получить актуальное значение

### 10.2 зконцептуальная модель 
заказы пользователя

```sql
CREATE TABLE shop.orders_by_customer (
  customer_id uuid,
  order_month date,
  created_at timestamp,
  order_id uuid,
  status text,
  total decimal,
  PRIMARY KEY ((customer_id, order_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

Partition key: `(customer_id, order_month)` где месяц ограничивает размер партиций.

товары по категории

```sql
CREATE TABLE shop.products_by_category (
  category text,
  bucket int,
  price decimal,
  product_id uuid,
  name text,
  PRIMARY KEY ((category, bucket), price, product_id)
);
```

`bucket = hash(product_id) % 16` распределит популярную категорию по нескольким партициям.

корзина

```sql
CREATE TABLE shop.cart_by_owner (
  owner_key text PRIMARY KEY,
  items map<uuid, int>,
  status text,
  updated_at timestamp
) WITH default_time_to_live = 2592000;
```

### 10.3 целостность

```sql
CREATE KEYSPACE shop
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3
};
```

| механизм | где использовать |
|---|---|
| Hinted Handoff | для временно недоступных реплик |
| Read Repair | для заказов и корзин при чтении |
| Anti-Entropy Repair | периодическая полная сверка реплик |

заказы и корзина используют `LOCAL_QUORUM` на запись и чтение

для каталога допустимо чтение `LOCAL_ONE`, так как небольшая задержка обновления не критична.
