# Задание 7. Проектирование схем коллекций

---

## 1. Коллекция `orders`

### Атрибуты и операции
| Атрибут | Тип | Назначение |
|---|---|---|
| `_id` | ObjectId/UUID | Уникальный id заказа |
| `customer_id` | string | Идентификатор клиента |
| `order_date` | ISODate | Дата/время оформления |
| `items` | array | `[{product_id, name, price, quantity}]` — снапшот товара и цены |
| `status` | string | `new`/`paid`/`shipped`/`delivered`/`cancelled` |
| `total_amount` | Decimal128 | Общая сумма |
| `geo_zone` | string | Геозона заказа (Москва, Екатеринбург…) |

Операции:
1. Быстрое создание заказа + списание остатков (write).
2. **Поиск истории заказов конкретного пользователя** (read, по `customer_id`).
3. Отображение статуса заказа (read, по `order_id`).


### Выбор для шард-ключа: `customer_id` **hashed**

**Почему подходит:**
- История заказов пользователя — главная read-операция. Все заказы одного `customer_id` имеют одинаковый хеш, значит лежат на одном шарде при запросе мы делаем один поход в конкретный шард по айди покупателя, а не прохощдимся по всем шардам для поиска.
- Создание заказа пишется с известным `customer_id`, балансируется между шардами и тоже ходим в конкретный шард.
- Даже если `customer_id` — монотонно растущий, хеш размазывает новые заказы по всем шардам.
- Статус заказа по `order_id`: в приложении пользователь залогинен, поэтому запрос всегда несёт `customer_id` (`{_id: order_id, customer_id}`). 

### BSON-схема
```json
{
  "_id": ObjectId("..."),              // order_id
  "customer_id": "cust_8f3a2",         // ШАРД-КЛЮЧ (hashed)
  "order_date": ISODate("2026-09-23T12:00:00Z"),
  "items": [
    { "product_id": "prod_001", "name": "Смартфон X", "price": NumberDecimal("49990"), "quantity": 1 },
    { "product_id": "prod_120", "name": "Чехол",     "price": NumberDecimal("590"),   "quantity": 2 }
  ],
  "status": "paid",
  "total_amount": NumberDecimal("51170"),
  "geo_zone": "msk"
}
```
---

## 2. Коллекция `products`

### Атрибуты и операции
| Атрибут | Тип | Назначение |
|---|---|---|
| `_id` | string | Уникальный id товара |
| `name` | string | Наименование |
| `category` | string | Категория (Электроника, Аудио, Бытовая техника…) |
| `price` | Decimal128 | Цена |
| `stock` | object | Остаток по геозонам: `{ "ekb": 50, "kgd": 30 }` |
| `attrs` | object | Доп. атрибуты: `color`, `size`, … |



Операции:
1. **Частые обновления остатков при покупках** (write, пиковая нагрузка на Black Friday).
2. Поиск товаров по категориям + фильтр по диапазону цен (read).
3. Описание товара на странице продукта (read, по `product_id`).


### Выбор: `_id` (product_id) **hashed**


**Почему подходит:**
- Главная пиковая нагрузка - обновления остатков при каждой покупке. Если шардировать по `category`, популярная категория сосредоточит весь write-трафик Black Friday на одном шарде . **Hashed `_id`** размазывает обновления по всем шардам равномерно.
- Страница товара - запрос идёт в один шард.
- Поиск по категории + цене - scatter-gather, но `products` — маленький каталог, а запрос покрыт составным индексом `{category, price}`. Scatter-gather по 2–N шардам с индексом приемлем для read операции.
- `category` как ключ не подходит из-за hotspot (есть попуцлярные и менее популярные категории)

### BSON-схема
```json
{
  "_id": "prod_001",                    // product_id, ШАРД-КЛЮЧ (hashed)
  "name": "Смартфон X",
  "category": "Электроника",
  "price": NumberDecimal("49990"),
  "stock": {
    "ekb": 50,
    "kgd": 30,
    "msk": 120
  },
  "attrs": { "color": "чёрный", "size": null, "brand": "BrandX" }
}
```
---

## 3. Коллекция `carts`

### Атрибуты и операции
| Атрибут | Тип | Назначение |
|---|---|---|
| `_id` | string | Уникальный id корзины |
| `user_id` | string \| null | Для залогиненных; `null` для гостей |
| `session_id` | string | Есть всегда (и для гостя, и для залогиненного) |
| `items` | array | `[{product_id, quantity}]` |
| `status` | string | `active` \| `ordered` \| `abandoned` |
| `created_at` | ISODate | |
| `updated_at` | ISODate | |
| `expires_at` | ISODate | TTL для авто-очистки старых корзин |

Операции:
1. Создание корзины (гость/новый пользователь).
2. Получение текущей корзины по `{session_id, status:"active"}` **или** `{user_id, status:"active"}`.
3. Добавление/замена товара.
4. Удаление товара.
5. Слияние гостевой корзины в пользовательскую.
6. Отметка корзины как заказанной.


### Выбор: `user_id` (если незалогинен берем `session_id`)

**Почему подходит:**
- Получение текущей корзины - запрос в конкретный шард: `mongos` считает хеш и идёт в один шард. Это основная операция.
- Добавление/замена/удаление товара - запрос в конкретный шард.
- Hashed защищает от hotspot
- TTL-очистка старых корзин работает на основе индекса по `expires_at`, не зависит от шард-ключа.

### BSON-схема
```json
{
  "_id": "cart_7c1b",                   // cart id
  "user_id": "cust_8f3a2",              // Шард-ключ
  "items": [
    { "product_id": "prod_001", "quantity": 2 },
    { "product_id": "prod_120", "quantity": 1 }
  ],
  "status": "active",
  "created_at": ISODate("2026-09-23T11:00:00Z"),
  "updated_at": ISODate("2026-09-23T11:30:00Z"),
  "expires_at":  ISODate("2026-09-24T11:00:00Z")
}
```
---

# Задание 8 

## 1. Метрики мониторинга шардов: 
 - на уровне MongoDB (чанки, операции, latency) 
 - на уровне ОС (CPU, диск, сеть)

1.1. Распределение данных по шардам:

- Кол-во документов на шарде 
- Сколько чанков на шарде - сколько единиц балансировки 
- Общий статус кластера 
- Jumbo-чанки (нельзя мигрировать → корень застрявшего hotspot)

**Команды (на роутере `router1`):**
```bash
# Общий статус кластера: шарды, чанки, зоны, диапазоны
docker exec -it router1 mongosh --eval 'sh.status()'

# Сколько данных/документов на каждом шарде (по коллекции)
docker exec -it router1 mongosh somedb --eval 'db.products.getShardDistribution()'

# Кол-во чанков на каждый шард
docker exec -it router1 mongosh --eval 'db.getSiblingDB("config").chunks.aggregate([{$group:{_id:"$shard", n:{$sum:1}}}, {$sort:{n:-1}}])'

# Найти jumbo-чанки
docker exec -it router1 mongosh --eval 'db.getSiblingDB("config").chunks.find({jumbo:true},{ns:1,min:1,max:1,shard:1}).toArray()'

# Список шардов
docker exec -it router1 mongosh --eval 'db.getSiblingDB("config").shards.find({},{_id:1,tags:1}).toArray()'
```

1.2. Нагрузка на шарды 

- latency операций на шарде
- Активные соединения 
- Длительность самых дорогих операций на шарде
- Распределение нагрузки (запросов) по шардам
- Ops/sec на шарде

**Команды (`serverStatus` берём на primary каждого шарда — `shard1a`, `shard2a`):**
```bash
# Ops/sec (накопительные счётчики с момента старта)
docker exec -it shard1a mongosh --eval 'db.adminCommand({serverStatus:1}).opcounters'

# Latency чтений/записей/команд
docker exec -it shard1a mongosh --eval 'db.adminCommand({serverStatus:1}).opLatencies'

# Длина очереди блокировок 
docker exec -it shard1a mongosh --eval 'db.adminCommand({serverStatus:1}).globalLock.currentQueue'

# Подключения к шарду (current/available)
docker exec -it shard1a mongosh --eval 'db.adminCommand({serverStatus:1}).connections'

# Снимок ops/sec по всем шардам сразу
docker exec -it router1 mongostat --discover -n 30
```
> И так же для `shard2a` (и `shard3a`) 

1.3. Поиск тяжелых запросов на горячем шарде (с помощью запроса в базу)

**Команды:**
```bash
# Активные долгие операции (>5 сек)
docker exec -it router1 mongosh --eval 'db.currentOp({secs_running:{$gt:5}, active:true}).inprog.map(o => ({ns:o.ns, op:o.op, secs:o.secs_running, cmd:o.command}))'

# Включить профайлер медленных запросов (>50 мс)
docker exec -it router1 mongosh somedb --eval 'db.setProfilingLevel(1, {slowms:50, sampleRate:1})'

# Топ-20 самых медленных запросов
docker exec -it router1 mongosh somedb --eval 'db.system.profile.find().sort({millis:-1}).limit(20).map(p => ({ns:p.ns, op:p.op, millis:p.millis, command:p.command})).forEach(printjson)'

# Выключить профайлер после разбора
docker exec -it router1 mongosh somedb --eval 'db.setProfilingLevel(0)'
```

CPU/диск/сеть — на уровне ОС, не из Mongo

1.5. Алерты при привышении пороговых значений 

## 2. Механизмы для автоматическго перераспределения

Предположим, что products зашардирован по category (range) => вся Электроника в одном чанке. Можем поменять шард-ключ, чтобы распределить данные по шардам.

Можем включить балансер и авто-разрезание чанков, который мигрирует чанки между шардами (но в нашем случае может не помочь, так как проблема может быть в неправильно выбранном шард-ключе). 

**2.1. Balancer + autosplit:**
```bash
# Включить/выключить балансер
docker exec -it router1 mongosh --eval 'sh.startBalancer()'
docker exec -it router1 mongosh --eval 'sh.stopBalancer()'

# Окно балансировки (миграции только ночью, не мешают пику)
docker exec -it router1 mongosh --eval 'db.getSiblingDB("config").settings.update({_id:"balancer"},{$set:{activeWindow:{start:"23:00", stop:"06:00"}}},{upsert:true})'

# Авто-разрезание чанков (обычно включено)
docker exec -it router1 mongosh --eval 'sh.enableAutoSplit()'
docker exec -it router1 mongosh --eval 'sh.isAutoSplitEnabled()'

# Балансировка по размеру данных, а не по числу чанков (MongoDB 6.0+)
docker exec -it router1 mongosh somedb --eval 'sh.defragmentCollection("somedb.products")'
```


**2.3. Решардирование:**
```bash

# Решардировать на ключ, размазывающий товары по шардам:
docker exec -it router1 mongosh somedb --eval 'sh.reshardCollection("somedb.products", { _id: "hashed" })'

# Комплексный шард-ключ 
docker exec -it router1 mongosh somedb --eval 'sh.reshardCollection("somedb.products", { category: 1, _id: "hashed" })'

# Контроль прогресса решардирования
docker exec -it router1 mongosh --eval 'db.getSiblingDB("config").reshardingOperations.find({ns:"somedb.products"}).toArray()'
```

**2.4. Доп. меры (снятие read-нагрузки):**
```bash
#
# Кэш горячих запросов в Redis (вынос read-трафика «Электроники» из Mongo )

# Индексы под горячие запросы
docker exec -it router1 mongosh somedb --eval 'db.products.createIndex({category:1, price:1})'
docker exec -it router1 mongosh somedb --eval 'db.products.createIndex({_id:1, category:1})'
```

---

## Задание 9. 


## 1. Сводная таблица: primary vs secondary

| Коллекция | Операция чтения                                      | Куда | Допустимая задержка |
|---|------------------------------------------------------|---|---|
| products | Поиск по категории + диапазону цен (каталог)         | secondary | до 60 сек |
| products | Страница товара                        | secondary | до 30 сек |
| products | Проверка остатка при добавлении в корзину / оформлении | **primary** | 0 |
| orders | История заказов пользователя                         | **primary** | 0 |
| orders | Статус заказа (для пользователя)                     | **primary** | 0 |
| orders | История/статус для аналитики        | secondary | до 5 мин |
| carts | Получение текущей корзины                            | **primary** | 0 |


## 2. Обоснование по коллекциям

### products
- Требования к консистентности: каталог терпит слабую задержку, но списание остатка и показ «в наличии» при покупке критично.
- Частота обновлений: очень высокая (остатки обновляются при каждой покупке)
- Бизнес-логика: риск продать недоступный товар недопустим 

### orders
- Требования к консистентности: read-your-writes - пользователь только что создал заказ или сменил статус и перечитывает; secondary может не иметь данных.
- Частота обновлений: невысокая, заказ создаётся один раз, статус заказа меняется несколько раз, но не критично, если актуальный статус появится с задержкой.
- Бизнес-логика: устаревший статус не критичен; сразу после действия read-your-writes важнее. Для аналитики допустимо читать из secondary с задержкой до минут.

### carts
- Требования к консистентности: строго read-your-writes, после добавления/удаленич товаров сразу перечитываем корзину, у secondary задержка
- Частота обновлений: высокая, корзину надо обновлять после каждого действия.
- Бизнес-логика: корзина = текущее состояние сессии.


# Задание 10

## Задание 10.1. 

Заказы и корзины можно перенести в Cassandra, так как она оптимизирована под записи, но не под согласованность данных. Для транзакций типа создания заказа и уменьшение кол-ва товара и для остатка товара она не подойдет. Товары и заказы оставляем в Mongo, но дублируем в Cassandra, например, для истории заказов. 


## Задание 10.2. 


### 1. Корзины (carts) 

```cql
CREATE TYPE cart_item ( product_id text, quantity int );

CREATE TABLE cart_items (
  user_id   text,          -- user_id или session_id
  product_id text,
  quantity   int,
  added_at   timestamp,
  PRIMARY KEY (owner_id, product_id)
) WITH default_time_to_live = 2592000;   -- 30 дней
```
- **Partition key** `user_id`
- **Clustering key** `product_id` точечный доступ/удаление по товару в пределах партиции.
- Размер партиции ограничен (в корзине мало товаров).

### 3. История заказов по пользователю (orders_by_user)

```cql
CREATE TYPE order_item ( product_id text, name text, price decimal, quantity int );

CREATE TABLE orders_by_user (
  customer_id  text,
  yyyymm       text,             
  order_date   timestamp,
  order_id     uuid,
  status       text,
  total_amount decimal,
  geo_zone     text,
  items        list<frozen<order_item>>,
  PRIMARY KEY ((customer_id, yyyymm), order_date)
) WITH CLUSTERING ORDER BY (order_date DESC);
```
- **Partition key** `(customer_id, yyyymm)` заказы пользователя разбиты по месяцам, партиция ограничена размером, нет большой партици у активного покупателя
- **Clustering key** `order_date DESC` история отдаётся свежими сверху за один скан.

### 4. Заказ по id (orders_by_id) — 

```cql
CREATE TABLE orders_by_id (
  order_id     uuid,
  customer_id  text,
  order_date   timestamp,
  status       text,
  total_amount decimal,
  items        list<frozen<order_item>>,
  PRIMARY KEY (order_id)
);
```
- **Partition key** `order_id` Дублируем данные, пишем в Mongo при создании заказа.

### 5. Каталог товаров 
```cql
CREATE TABLE products (
  product_id text,
  name       text,
  category   text,
  price      decimal,
  attrs      map<text,text>,
  PRIMARY KEY (product_id)
);
-- browse по категории 
CREATE TABLE products_by_category (
  category   text,
  product_id text,
  price      decimal,
  name       text,
  PRIMARY KEY (category, product_id)
);
```
- `products` PK `product_id` обновления каталога происходжитт редко.
- `products_by_category` большая партиция для популярной категории допустима для чтения. (тоже самое храним в Mongo)


### Hot partitions и решардинг
Модель построена на высококардинальных ключах и бакетинг по месяцу, поэтому горячих партиций нет, а при росте кластера Cassandra двигает только примерно 1/N данных, не трогая остальное,
поэтому добавление узлов в пик не роняет latency в отличие от Mongo с полным перераспределением.

## Задание 10.3. Стратегии восстановления целостности

Anti-Entropy Repair используем по расписанию для долгоживущих ценных данных, например, заказы, история заказов, каталог товаров (чаще чем заказы и история, так как каталог важен для витрины, но в каталог товары добавляют реже, чем создаются другие данные); для сессий и корзины не используем, так как это непомтоянные данные и часто меняются. 
Hinted Handoff можем использовать почти бесплатно. Если реплика упала, будем догонять ее в фоне. Для сессий с оговоркой, так как данные непостоянные, можем сделать короткоживущее окно, если реплика не восстановится в течение окна, можем не догонять и не тратить ресурс.
Read Repair для тех данных, где согласованность важна: заказы, корзины, каталог, сессии не включаем (лишняя нагрузка для непостоянных данных). Для этих данных важна постоянная согласованность, поэтому при отставании важно своевременно обогатить отстающие реплики свежими данными. 


