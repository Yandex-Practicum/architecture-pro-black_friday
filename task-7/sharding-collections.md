# Задание 7. Схемы коллекций и шардирование (MongoDB)

## 1. Коллекция `orders`

### 1.1. Схема документа

```js
{
  _id: ObjectId, // id заказа
  order_no: String, // публичный номер, unique, UI/поддержка
  customer_id: ObjectId, // покупатель
  created_at: Date,
  items: [
    {
      product_id: ObjectId,
      title_snapshot: String, // витрина
      category_snapshot: String, // в одной сделке разные категории, без джойна
      price: Decimal128, // или Double, цена в строке
      quantity: Int32,
    },
  ],
  status: String, // new, paid, …
  total: Decimal128, // или Double, сумма
  currency: String, // ISO
  geo_zone: String, // зона, одна на заказ
  version: Int32, // опц., optimistic
}
```

Одна `geo_zone`, в строке заказа — разные категории за счёт снимка в `items`.

Операции

- Изменение остатка `products.stock[зона]`
- История — по `customer_id` + индекс.
- Просмотр/статус — по `_id` или `order_no` (индекс на `order_no`).

```js
db.orders.createIndex({ customer_id: 1, status: 1, created_at: -1 });
db.orders.createIndex({ order_no: 1 }, { unique: true });
```

### 1.2. Кандидаты в шард-ключ

- `hashed` по `_id` — вставка ровная, по клиенту история с scatter
- `hashed` по `order_no` — неравномер, плохо для истории по `customer_id`
- `hashed` по `customer_id` — заказы одного пользователя сужают поиск
- `compound` hashed — только при явной второй оси, сложнее

### 1.3. Выбор

- `hashed` по `customer_id` — вставка по разным id и «история моих заказов» совпадают с ключом, выброс «тяжёлый клиент» терпим

```js
sh.enableSharding("shop");
sh.shardCollection("shop.orders", { customer_id: "hashed" });
```

## 2. Коллекция `products`

### 2.1. Схема

```js
{
  _id: ObjectId, // или `product_id` в проекте
  name: String,
  category: String, // витрина
  price: Number, // цена
  stock: { /* код_зоны: Int32, … */ },
  description: String, // карточка
  attrs: { /* color, size, … */ },
  updated_at: Date, // остаток, витрина, …
}
```

Остаток по зонам — `stock.ключ` (код → Int32). Операции: часто менять `stock[зона]`; список с фильтром; карточка — `find` по `_id` + индексы витрины (не в шард-ключе).

```js
db.products.createIndex({ category: 1, price: 1 });
// опц.:
db.products.createIndex({ name: "text" });
```

### 2.2. Кандидаты

- `hashed` по `_id` / `product_id` — витрина с фильтрами = multi-shard, для каталога норм; hot category вне ключа, зад. 8
- `category` в шард-ключе — риск горячего чанка
- `hashed` по `sku` — если поле стабильно

### 2.3. Выбор

- `hashed` по id товара: остатки и карточка — обновления по одному id

```js
sh.shardCollection("shop.products", { _id: "hashed" });
```

## 3. Коллекция `carts`

`user_id` и `session_id` — sparse: гость по `session_id`, пользователь по `user_id`; merge — гостевую `abandoned`, опц. `merged_from_session`, при оформлении опц. `order_id`.

### 3.1. Схема

```js
{
  _id: ObjectId,
  user_id: ObjectId, // залогинен
  session_id: String, // гость
  items: [
    {
      product_id: ObjectId, // опц.: price, снимок с витрины
      quantity: Int32,
    },
  ],
  status: String, // active, ordered, abandoned, …
  created_at: Date, updated_at: Date, expires_at: Date, // для TTL-индекса
  merged_from_session: String, // опц.
  order_id: ObjectId, // опц., ссылка на заказ
}
```

- Создать: insert с `session_id` или `user_id`
- Активная: `{ session_id, status: "active" }` или `{ user_id, status: "active" }` + составные индексы; одна active на владельца — правила в приложении или partial unique
- Позиции: update `items`, `updated_at`
- Слияние гостя в пользователя: find гостя → merge `items` в свою → гостя `abandoned`; на разных шардах — транзакция/стратегия переноса
- Оформлен: `status` + опц. `order_id`
- Индексы: TTL по `expires_at` (см. доку MongoDB)

### 3.2. Кандидаты

- `hashed` по `_id` — просто, поиск «моя корзина» по `user_id`/`session_id` без ключа-владельца — scatter
- `hashed` по `user_id` — у гостя нет id: псевдо-`ObjectId`, отдельная коллекция или поле-владелец
- `hashed` только по `session_id` — для гостя, с пользователем две модели, merge тяжелее

### 3.3. Выбор

- Один смысл владельца в ключе: например `owner_key` (строка от `user_id` или `session_id`) + `hashed` по нему
- Проще на курсе: `hashed` по `user_id`, гостю выдать псевдо-`user_id` в cookie

```js
db.carts.createIndex(
  { expires_at: 1 },
  { expireAfterSeconds: 0 },
);
sh.shardCollection("shop.carts", { owner_key: "hashed" });
// вариант без owner_key: sh.shardCollection("shop.carts", { user_id: "hashed" });
```
