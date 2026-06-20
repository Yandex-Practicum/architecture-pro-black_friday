# Архитектурный документ для заданий 7-10

## Задание 7. Проектирование схем коллекций для шардирования данных

Онлайн-магазин «Мобильный мир» хранит информацию о заказах, товарах и корзинах в трёх коллекциях MongoDB (`products`, `orders`, `carts`). Бэкенд состоит из нескольких микросервисов; связи между коллекциями логические, через `product_id` в `items`.

**Диаграмма — ERD коллекций MongoDB:** [`diagrams/task7-erd-mobile-world.drawio`](diagrams/task7-erd-mobile-world.drawio)

### 7.1. Коллекция `products`

Назначение: каталог товаров, характеристики, цена, доступность, остатки по геозонам.

Пример документа:

```javascript
{
  _id: "prod_8f3a2c1b",              // string, уникальный идентификатор товара
  name: "Смартфон X",                // string
  category: "electronics",           // string
  subcategory: "smartphones",        // string
  price: 49990,                      // decimal/int
  currency: "RUB",                   // string
  stock_by_zone: {                   // object: geo_zone -> int
    moscow: 50,
    ekaterinburg: 30,
    kaliningrad: 12
  },
  attributes: {                      // object, произвольные атрибуты
    color: "black",
    storage_gb: 256
  },
  is_active: true,                   // boolean
  updated_at: ISODate("2026-06-14T10:15:00Z")
}
```

Основные операции:

- карточка товара по `_id`;
- поиск по категории и диапазону цены;
- частые обновления остатков при покупке.

Кандидаты на shard key:

| Ключ | Преимущества | Риски |
|---|---|---|
| `{ _id: "hashed" }` | Равномерное распределение товаров, targeted-запросы по карточке и списанию остатка | Каталог по `{ category, price }` будет scatter-gather |
| `{ category: 1 }` | Каталог одной категории может быть targeted | `electronics` создаёт hot shard |
| `{ geo_zone: 1 }` | Региональная локальность остатков | Москва/крупные регионы могут перегрузить один шард |

**Выбор:** `{ _id: "hashed" }` — hashed sharding.

**Обоснование:** `_id` имеет высокую кардинальность и хорошо распределяет товары. Популярная категория не попадает целиком на один шард, поэтому снижается риск hot shard из-за `electronics`. Для каталожных запросов нужен индекс и кеширование, но это безопаснее, чем класть `category` в shard key.

Индексы:

```javascript
db.products.createIndex({ category: 1, price: 1 })
```

### 7.2. Коллекция `orders`

Назначение: история заказов, статус заказа, snapshot товаров на момент покупки.

Пример документа:

```javascript
{
  _id: "ord_a91f0042",               // string, уникальный идентификатор заказа
  customer_id: "user_10482",         // string
  created_at: ISODate("2026-06-14T11:02:33Z"),
  status: "paid",                    // pending | paid | cancelled | shipped | delivered
  geo_zone: "moscow",                // string
  items: [                           // array<object>
    {
      product_id: "prod_8f3a2c1b",
      name: "Смартфон X",
      category: "electronics",
      quantity: 1,
      unit_price: 49990,
      line_total: 49990
    }
  ],
  total_amount: 49990,               // decimal/int
  currency: "RUB",
  updated_at: ISODate("2026-06-14T11:02:35Z")
}
```

Основные операции:

- быстрое создание заказов с одновременным списанием остатков;
- поиск истории заказов конкретного пользователя;
- отображение статуса заказа.

Кандидаты на shard key:

| Ключ | Преимущества | Риски |
|---|---|---|
| `{ customer_id: 1, created_at: 1 }` | Targeted-история пользователя, сортировка по времени | Крупный B2B-клиент может раздуть одну область данных |
| `{ _id: "hashed" }` | Равномерно и быстро для lookup по order_id | История пользователя станет scatter-gather |
| `{ geo_zone: 1 }` | Региональная аналитика targeted | Москва может стать hot shard, основной запрос не по региону |
| `{ created_at: 1 }` | Простые range-запросы по времени | Все новые заказы идут в один chunk |

**Выбор:** `{ customer_id: 1, created_at: 1 }` — compound range sharding.

**Обоснование:** основной read pattern — история конкретного пользователя, а не глобальный поиск по заказам. `created_at` как range-компонент упорядочивает историю. `geo_zone` в ключ не кладём: это где исполняют заказ, а не как его ищут. Для больших B2B-клиентов можно добавить bucket по месяцу или hash-prefix.

Индексы:

```javascript
db.orders.createIndex({ customer_id: 1, _id: 1 })
db.orders.createIndex({ _id: 1 })
```

### 7.3. Коллекция `carts`

Назначение: текущие корзины пользователей и гостей, TTL для очистки старых корзин.

Чтобы одинаково искать гостевые и пользовательские корзины, вводится поле `owner_key`:

- пользователь: `user:user_10482`;
- гость: `session:sess_9f2caa01`.

Пример документа:

```javascript
{
  _id: "cart_7c2e9f11",              // string
  owner_key: "user:user_10482",      // string, shard key
  user_id: "user_10482",             // string | null
  session_id: null,                  // string | null
  items: [
    { product_id: "prod_8f3a2c1b", quantity: 1 }
  ],
  status: "active",                 // active | ordered | abandoned
  created_at: ISODate("2026-06-14T09:00:00Z"),
  updated_at: ISODate("2026-06-14T10:55:00Z"),
  expires_at: ISODate("2026-06-28T09:00:00Z")
}
```

Основные операции:

- создание корзины гостя или пользователя;
- получение активной корзины по `{ session_id, status: "active" }` или `{ user_id, status: "active" }`;
- add/remove/replace товара;
- merge гостевой корзины в пользовательскую после логина;
- перевод корзины в `ordered`;
- TTL-очистка старых корзин по `expires_at`.

Кандидаты на shard key:

| Ключ | Преимущества | Риски |
|---|---|---|
| `{ owner_key: 1 }` | Все CRUD-операции корзины targeted | Merge guest -> user может затронуть два шарда |
| `{ _id: "hashed" }` | Ровное распределение | Поиск активной корзины по session/user будет scatter-gather |
| `{ status: 1 }` | Нет практических преимуществ | Все `active` попадут в узкую область |

**Выбор:** `{ owner_key: 1 }` — range sharding.

**Обоснование:** корзина почти всегда читается и изменяется по владельцу. `owner_key` объединяет user/session-сценарии и сохраняет targeted-запросы.

Индексы:

```javascript
db.carts.createIndex(
  { owner_key: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: "active" } }
)
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ user_id: 1, status: 1 })
```

### 7.4. Итого по шардированию

| Коллекция | Shard key | Стратегия | Зачем |
|---|---|---|---|
| `products` | `{ _id: "hashed" }` | Hashed | Покупка и карточка — по `product_id`, без hot shard по категории |
| `orders` | `{ customer_id: 1, created_at: 1 }` | Compound range | История и создание — по клиенту |
| `carts` | `{ owner_key: 1 }` | Range | Вся работа с корзиной — по владельцу |

Заказ + остатки — разные shard keys; для атомарности нужна multi-document transaction через mongos или saga.

**Диаграмма — распределение данных по шардам:** [`diagrams/task7-shard-data-distribution.drawio`](diagrams/task7-shard-data-distribution.drawio)

### 7.5. Команды MongoDB

```javascript
sh.enableSharding("mobile_world")

sh.shardCollection("mobile_world.products", { _id: "hashed" })
sh.shardCollection("mobile_world.orders", { customer_id: 1, created_at: 1 })
sh.shardCollection("mobile_world.carts", { owner_key: 1 })
```

Примеры targeted-запросов:

```javascript
// Карточка товара
db.products.findOne({ _id: "prod_8f3a2c1b" })

// Каталог (scatter-gather — нет шард-ключа в фильтре)
db.products.find({
  category: "electronics",
  price: { $gte: 10000, $lte: 80000 },
  is_active: true,
}).sort({ price: 1 })

// История заказов пользователя
db.orders.find({ customer_id: "user_10482" })
  .sort({ created_at: -1 })
  .limit(20)

// Статус заказа (targeted, если есть customer_id)
db.orders.findOne({ _id: "ord_a91f0042", customer_id: "user_10482" })

// Активная корзина
db.carts.findOne({ owner_key: "user:user_10482", status: "active" })

// Слияние гостевой корзины при логине (возможно два шарда)
const guest = db.carts.findOne({ owner_key: "session:sess_9f2caa01", status: "active" })
// ... merge items в user-корзину ...
db.carts.updateOne({ owner_key: "session:sess_9f2caa01" }, { $set: { status: "abandoned" } })
```

## Задание 8. Выявление и устранение «горячих» шардов

**Инцидент:** из-за категории «Электроника» (~70% запросов) перегрузился один из шардов MongoDB. Популярные категории и hot SKU могут создавать непропорциональную нагрузку на отдельные узлы.

**Диаграмма — runbook выявления и устранения hot shard:** [`diagrams/task8-hot-shard-runbook.drawio`](diagrams/task8-hot-shard-runbook.drawio)

### 8.1. Метрики мониторинга шардов

| Метрика | Как смотреть | Целевое состояние |
|---|---|---|
| Chunks distribution | `getShardDistribution()`, `config.chunks` | Разница chunks между шардами не более 10% |
| Query/load per shard | `mongostat`, `serverStatus().opcounters` | Отклонение ops/s не более 20% от среднего |
| Read/write latency p99 | `$collStats`, profiler, `currentOp` | p99 до 100 ms и не более 2x других шардов |
| CPU/IOPS | `docker stats`, node exporter | CPU и диск ниже 70% в пик |
| Balancer state | `sh.getBalancerState()`, `sh.getBalancerStatus()` | Balancer включён, нет зависших миграций |
| Replication lag | `rs.printSecondaryReplicationInfo()` | Secondary не отстаёт сверх допустимого lag |

### 8.2. Команды диагностики

```javascript
sh.status(true)

use mobile_world
db.products.getShardDistribution()
db.orders.getShardDistribution()
db.carts.getShardDistribution()

use config
db.chunks.aggregate([
  { $match: { ns: /^mobile_world\./ } },
  {
    $group: {
      _id: "$shard",
      chunks: { $sum: 1 },
      jumbo: { $sum: { $cond: ["$jumbo", 1, 0] } }
    }
  }
])

sh.getBalancerState()
sh.getBalancerStatus()
```

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet --eval 'db.serverStatus().opcounters'
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'db.serverStatus().opcounters'

docker compose exec -T shard1-1 mongostat --port 27019 'insert query update command' 5
docker compose exec -T shard2-1 mongostat --port 27019 'insert query update command' 5
```

### 8.3. Меры устранения дисбаланса

| Причина | Действие |
|---|---|
| Дисбаланс chunks | Проверить balancer, выполнить split/moveRange для крупных диапазонов |
| Hot key `category` | Не использовать `category` как shard key; перейти на `{ _id: "hashed" }` или compound key с bucket |
| Scatter-gather каталога | Добавить индекс `{ category: 1, price: 1 }`, кешировать выдачу, вынести поиск в search/read model |
| Hot SKU при списании остатков | Вынести остатки в `inventory_by_product_zone` (Cassandra) или добавить bucket |
| Secondary lag | Уменьшить чтения с отстающих secondary через `maxStalenessSeconds`, проверить I/O и oplog |
| Jumbo chunks | Уменьшить размер chunk, пересмотреть shard key, выполнить resharding |

### 8.4. Автоматическое перераспределение данных

MongoDB balancer автоматически переносит chunks между шардами при дисбалансе. Для ручного управления:

```javascript
sh.startBalancer()
sh.setBalancerState(true)

// Для диапазонного ключа при необходимости:
sh.splitAt("mobile_world.orders", { customer_id: "user_50000", created_at: MinKey })
sh.moveRange(
  "mobile_world.orders",
  { customer_id: "user_50000", created_at: MinKey },
  { customer_id: "user_70000", created_at: MaxKey },
  "rs-shard2"
)
```

---

## Задание 9. Настройка чтения с реплик и консистентность

### 9.1. Таблица операций чтения

| Коллекция | Операция чтения | Реплика | Допустимый lag | Обоснование |
|---|---|---|---|---|
| `products` | Каталог по категории/цене | `secondaryPreferred` | до 30 сек | Stale описание в списке не ломает покупку |
| `products` | Карточка товара (название, описание, фото) | `secondaryPreferred` | до 30 сек | Характеристики меняются редко |
| `products` | Цена перед оплатой | `primary` | 0 сек | Устаревшая цена = неверная сумма заказа |
| `products` | Остаток перед резервом | `primary` | 0 сек | Риск продажи недоступного товара |
| `products` | `is_active` перед покупкой | `primary` | 0 сек | Secondary может показать снятый с продажи товар |
| `products` | Рекомендации, витрина | `secondaryPreferred` | до 60 сек | Не участвуют в checkout |
| `orders` | История прошлых заказов | `secondaryPreferred` | до 10 сек | Старые заказы почти не меняются |
| `orders` | Детали завершённого заказа | `secondaryPreferred` | до 30 сек | Snapshot в `items` стабилен |
| `orders` | Статус текущего заказа | `primary` | 0 сек | Пользователь увидит устаревший `pending` вместо `paid` |
| `orders` | Подтверждение сразу после создания | `primary` | 0 сек | Read-your-writes после оформления |
| `orders` | Админский отчёт | `secondary` | до 60 сек | Отчёт не в user flow |
| `carts` | Активная корзина | `primary` | 0 сек | Корзина меняется при каждом клике |
| `carts` | Пересчёт перед checkout | `primary` | 0 сек | Нужны актуальные позиции и скидки |
| `carts` | После add/remove | `primary` | 0 сек | Read-your-writes |
| `carts` | Брошенные корзины для маркетинга | `secondaryPreferred` | до 60 сек | Фоновый сценарий |
| `carts` | Аналитика брошенных корзин | `secondary` | до 5 мин | Batch-отчёт |

### 9.2. Допустимая задержка репликации

| Класс операции | Lag | Примеры |
|---|---|---|
| Критичные, влияют на оплату и UX после действия | **0 сек**, только `primary` | checkout, остатки, статус заказа, активная корзина |
| Обычные пользовательские чтения | **10–30 сек** | каталог, карточка, история заказов |
| Витринные / некритичные | **30–60 сек** | рекомендации, брошенные корзины |
| Отчёты и аналитика | **60 сек – 5 мин** | админские отчёты, аналитика корзин |

### 9.3. Обоснование выбора

**`products`:** стабильные данные (название, описание) и критичные (цена, остаток, `is_active`). Каталог и карточки можно читать с secondary — небольшое отставание не ломает покупку. Перед checkout цену, остаток и `is_active` читаем только с primary: в Black Friday lag даже в несколько секунд может показать товар в наличии, когда он уже закончился.

**`orders`:** завершённые заказы меняются редко — для истории достаточно eventual consistency. Текущий заказ после оплаты, отмены или смены доставки — только primary: иначе покажем устаревший статус.

**`carts`:** активная корзина постоянно меняется — stale read напрямую ломает checkout. Secondary только для фоновых сценариев: брошенные корзины, маркетинг, аналитика.

### 9.4. Пример конфигурации

```javascript
// Некритичные чтения
readPreference: "secondaryPreferred"
maxStalenessSeconds: 30

// Checkout/read-your-writes
readPreference: "primary"
```

---

## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

**Контекст:** во время «чёрной пятницы» MongoDB с range-based sharding при нагрузке **50 000 запросов/сек.** при добавлении шардов полностью перераспределяла данные между всеми узлами → просадка latency в пик.

### Задание 10.1. Какие данные переносим в Cassandra

| Сущность | Критичность (целостность / скорость) | Нагрузка в Black Friday | Cassandra? | Решение |
|---|---|---|---|---|
| **Заказы** | Высокая / высокая | Массовая запись при checkout | **Да** | `orders_by_customer`, `orders_by_id` |
| **Корзины** | Высокая / очень высокая | Постоянные add/remove, read-your-writes | **Да** | `carts_by_owner` |
| **Остатки по зонам** | Критическая / очень высокая | `$inc` на hot SKU — источник hot shard | **Да** | `inventory_by_product_zone` |
| **История заказов** (snapshot в `orders.items`) | Средняя / средняя | Append-only после оплаты | **Да** | Вместе с заказами |
| **Каталог товаров** | Средняя / средняя | Фильтры `{ category, price }`, scatter-gather | **Нет** | MongoDB + Redis/CDN |
| **Пользовательские сессии** | Средняя / высокая | TTL, point read/write | **Нет** | Redis |
| **Платежи** | Критическая / низкая | ACID, мало записей | **Нет** | Внешний payment provider |

**Обоснование переноса в Cassandra:** сущности с высокой скоростью записи, предсказуемым ключом доступа (`customer_id`, `owner_key`, `product_id`) и допустимостью eventual consistency с точечным усилением через `LOCAL_QUORUM` / LWT. Новые узлы получают только свои token ranges без полной миграции всех chunks, в отличие от MongoDB balancer.

**Оставляем вне Cassandra:**

- **Каталог** — запросы по вторичным полям в Cassandra = full scan или дублирование таблиц под каждый access pattern.
- **Сессии** — короткий жизненный цикл, TTL; Redis проще и быстрее.
- **Платежи** — PCI-DSS на стороне провайдера; в системе только `payment_id` и статус в заказе.
- **Checkout** — Cassandra не даёт multi-partition ACID; оркестрируем через **saga** с компенсирующими шагами.

### Задание 10.2. Модель данных, partition key и clustering key

**Принципы проектирования:**

| Принцип | Как применяем |
|---|---|
| Запрос определяет модель | Одна таблица = один основной access pattern |
| Partition key = равномерность | UUID / hashed id / составной ключ с высокой кардинальностью |
| Избегаем hot partition | Не кладём `category` или `created_at` без bucket в partition key |
| Денормализация | `orders_by_id` дублирует заказ для lookup без `customer_id` |
| Решардинг | Новый узел → перераспределение только ~1/N token ranges |

#### Таблица `orders_by_customer`

| Ключ | Поле | Зачем |
|---|---|---|
| **Partition key** | `customer_id` | Все заказы клиента на одной партиции — targeted read/write |
| **Clustering key** | `created_at DESC`, `order_id` | Сортировка по дате; `order_id` уникализирует строку |

**Hot partition:** B2B-клиент с миллионом заказов → bucket `customer_id|YYYY-MM` или hash-prefix.

```sql
CREATE TYPE mobile_world.order_item (
  product_id  text,
  name        text,
  category    text,
  quantity    int,
  unit_price  decimal,
  line_total  decimal
);

CREATE TABLE mobile_world.orders_by_customer (
  customer_id   text,
  created_at    timestamp,
  order_id      text,
  status        text,
  geo_zone      text,
  total_amount  decimal,
  currency      text,
  items         list<frozen<order_item>>,
  updated_at    timestamp,
  PRIMARY KEY ((customer_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC)
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 7
  };
```

```sql
SELECT * FROM mobile_world.orders_by_customer
WHERE customer_id = 'user_10482'
LIMIT 20;
```

#### Таблица `orders_by_id`

| Ключ | Поле | Зачем |
|---|---|---|
| **Partition key** | `order_id` | Равномерное распределение UUID-подобных id |
| **Clustering key** | — | Одна строка на заказ |

```sql
CREATE TABLE mobile_world.orders_by_id (
  order_id      text PRIMARY KEY,
  customer_id   text,
  created_at    timestamp,
  status        text,
  geo_zone      text,
  total_amount  decimal,
  currency      text,
  items         list<frozen<order_item>>,
  updated_at    timestamp
);
```

#### Таблица `carts_by_owner`

| Ключ | Поле | Зачем |
|---|---|---|
| **Partition key** | `owner_key` | `user:user_10482` / `session:sess_9f2caa01` |
| **Clustering key** | `cart_id` | Одна активная корзина на владельца |

```sql
CREATE TYPE mobile_world.cart_item (
  product_id  text,
  quantity    int
);

CREATE TABLE mobile_world.carts_by_owner (
  owner_key    text,
  cart_id      text,
  user_id      text,
  session_id   text,
  status       text,
  items        list<frozen<cart_item>>,
  created_at   timestamp,
  updated_at   timestamp,
  expires_at   timestamp,
  PRIMARY KEY ((owner_key), cart_id)
) WITH default_time_to_live = 1209600;
```

#### Таблица `inventory_by_product_zone`

| Ключ | Поле | Зачем |
|---|---|---|
| **Partition key** | `(product_id, geo_zone)` | Hot SKU распределяется по зонам |
| **Clustering key** | — | Одна строка на товар+зону |

**Hot partition:** один SKU в одной зоне в пик — митигация: bucket `product_id#0..7`, очередь резервирования.

```sql
CREATE TABLE mobile_world.inventory_by_product_zone (
  product_id   text,
  geo_zone     text,
  stock        int,
  reserved     int,
  updated_at   timestamp,
  PRIMARY KEY ((product_id, geo_zone))
);

UPDATE mobile_world.inventory_by_product_zone
SET stock = 49, reserved = 1, updated_at = toTimestamp(now())
WHERE product_id = 'prod_8f3a2c1b' AND geo_zone = 'moscow'
IF stock = 50 AND reserved = 0;
```

#### Сводка ключей Cassandra

| Таблица | Partition key | Clustering key | Риск hot partition | Решардинг |
|---|---|---|---|---|
| `orders_by_customer` | `customer_id` | `created_at`, `order_id` | B2B-аккаунты | Новый узел → только его tokens |
| `orders_by_id` | `order_id` | — | Низкий | То же |
| `carts_by_owner` | `owner_key` | `cart_id` | Низкий | То же |
| `inventory_by_product_zone` | `(product_id, geo_zone)` | — | Hot SKU в одной зоне | То же; bucket при необходимости |

**Схема потоков данных после миграции (checkout):**

```text
Каталог (остаётся в MongoDB):
  user -> CDN/Redis/API -> MongoDB products (secondaryPreferred)
                         -> цена, is_active только с primary перед оплатой

Checkout (write-heavy — Cassandra):
  user -> API
       -> read active cart          (Cassandra carts_by_owner, LOCAL_QUORUM)
       -> reserve stock            (Cassandra inventory_by_product_zone, LWT)
       -> create order             (Cassandra orders_by_customer + orders_by_id)
       -> mark cart ordered        (Cassandra carts_by_owner)
       -> при ошибке: saga/compensate

Аналитика:
  admin/report -> MongoDB secondary / Cassandra LOCAL_ONE
```

#### Уровни консистентности

| Операция | Write CL | Read CL | Обоснование |
|---|---|---|---|
| Создание заказа | `LOCAL_QUORUM` | — | Данные на большинстве локальных реплик |
| Статус заказа после оплаты | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Read-your-writes |
| История заказов | — | `LOCAL_ONE` | Допустима eventual consistency |
| Активная корзина | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Нельзя показать устаревший состав |
| Остаток перед резервом | LWT + `LOCAL_QUORUM` | `LOCAL_QUORUM` | Защита от oversell |

Checkout — saga:

```text
read active cart
  -> reserve inventory with LWT
  -> create order in orders_by_customer and orders_by_id
  -> mark cart ordered
  -> if failure, compensate reservation/order/cart status
```

### Задание 10.3. Стратегии восстановления целостности данных

| Стратегия | Когда срабатывает | Latency | Гарантия |
|---|---|---|---|
| **Hinted Handoff (HH)** | Запись при временно недоступной реплике | Нулевая для клиента | Восстанавливает пропущенные записи после возврата узла |
| **Read Repair** | Чтение обнаружило расхождение версий | +latency на этот read | Синхронно чинит реплики |
| **Anti-Entropy Repair** | Плановый `nodetool repair` | Фоново | Полное сравнение Merkle trees между репликами |

**Матрица применения по сущностям:**

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy Repair | Обоснование |
|---|---|---|---|---|
| **Заказы** (текущий статус) | Вкл. | **Вкл.** (`LOCAL_QUORUM`) | Вкл., еженедельно | Статус `paid`/`cancelled` критичен |
| **Заказы** (история) | Вкл. | Выкл. / редко | **Вкл.** | История с `LOCAL_ONE`; AE восстановит «тихие» расхождения |
| **Корзины** | Вкл. | **Вкл.** | Вкл., 3–7 дней | Read-your-writes перед checkout |
| **Остатки** | Вкл. | **Вкл.** + LWT | **Вкл.**, ежедневно | Ошибка stock = oversell |

**Настройки:**

```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа
```

```shell
nodetool repair -full mobile_world inventory_by_product_zone   # остатки, nightly
nodetool repair mobile_world orders_by_customer orders_by_id   # заказы, weekly
nodetool repair mobile_world carts_by_owner                  # корзины, каждые 3 дня
```

**Компромиссы latency ↔ консистентность:**

| Уровень | Сущности / операции | Стратегии | Latency |
|---|---|---|---|
| Высокая консистентность | inventory, carts checkout, order status | LWT + LOCAL_QUORUM + read repair + AE | Выше |
| Eventual допустима | order history list | LOCAL_ONE + weekly AE | Ниже |
| Вне Cassandra | sessions | Redis TTL, без repair | Минимальная |

---

## Приложение. Итоговая матрица решений

| Область | Решение | Преимущество | Риск и митигация |
|---|---|---|---|
| `products` в MongoDB | Shard key `{ _id: "hashed" }` | Равномерность, нет hot shard по category | Каталог scatter-gather → индекс, Redis/CDN |
| `orders` в MongoDB | Shard key `{ customer_id, created_at }` | История пользователя targeted | B2B hot partition → bucket/hash-prefix |
| `carts` в MongoDB | Shard key `{ owner_key }` | CRUD корзины targeted | Merge guest/user → saga |
| Hot shards | Метрики chunks, ops/s, p99, CPU/IOPS, balancer, lag | Быстрое выявление дисбаланса | Balancer + split/moveRange/resharding |
| Чтение с реплик | Primary для checkout, secondary для каталога | Разгрузка primary | `maxStalenessSeconds` |
| Cassandra | Заказы, корзины, остатки | Leaderless, consistent hashing | LOCAL_QUORUM, LWT, saga, repair |
| Redis | Сессии и кеш | Быстрый TTL/cache layer | Потеря сессии некритична |

**Сводка по хранилищам:** MongoDB — read-heavy каталог; Redis — сессии и кеш; Cassandra — write-heavy заказы, корзины и остатки. Диаграммы по заданиям 7–8 — в §7 и §8; поток checkout после миграции — в §10.2.
