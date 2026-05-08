# Архитектурный документ: MongoDB и Cassandra

Документ покрывает задания 7-10 для интернет-магазина «Мобильный мир».

## Задание 7. Схемы коллекций и shard key в MongoDB

### products

Назначение: каталог товаров, поиск по категориям и цене, описание товара, обновление остатков по геозонам.

Пример документа:

```javascript
{
  _id: ObjectId("..."),
  name: "Смартфон X",
  category: "electronics",
  price: NumberDecimal("79990.00"),
  stock_by_geo: {
    "moscow": { quantity: 120, reserved: 7, updated_at: ISODate("2026-05-06T09:00:00Z") },
    "ekaterinburg": { quantity: 50, reserved: 2, updated_at: ISODate("2026-05-06T09:00:00Z") },
    "kaliningrad": { quantity: 30, reserved: 1, updated_at: ISODate("2026-05-06T09:00:00Z") }
  },
  attributes: {
    color: "black",
    size: "128Gb"
  },
  created_at: ISODate("2026-05-06T09:00:00Z"),
  updated_at: ISODate("2026-05-06T09:00:00Z")
}
```

Кандидаты для shard key:

| Кандидат | Плюсы | Риски |
| --- | --- | --- |
| `{ _id: "hashed" }` | Равномерно распределяет товары и точечные обновления по товару | Поиск по категории будет scatter-gather |
| `{ category: 1 }` | Хорошо таргетирует запросы категории | Популярная категория создаёт горячий шард |
| `{ category: 1, price: 1 }` | Удобно для фильтрации каталога | Категория «Электроника» всё равно может перегрузить диапазон |
| `{ geo_zone: 1, _id: "hashed" }` | Помогает географическим витринам | Один товар хранит остатки по нескольким геозонам, поле не является естественным ключом документа |

Выбор: `{ _id: "hashed" }`.

Причина: для каталога опаснее всего горячая категория. Хеширование `_id` распределяет товары из любой категории по всем шардам, поэтому запросы категории «Электроника» не концентрируются на одном шарде. Для поиска по категории и цене нужны обычные индексы на каждом шарде, а самые популярные выдачи дополнительно закрываются Redis/CDN-кешем.

Команды:

```javascript
sh.enableSharding("shop")

use shop
db.products.createIndex({ _id: "hashed" })
db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ "stock_by_geo.moscow.quantity": 1 })

sh.shardCollection("shop.products", { _id: "hashed" })
```

### orders

Назначение: создание заказа, история заказов пользователя, отображение статуса заказа.

Пример документа:

```javascript
{
  _id: ObjectId("..."),
  order_id: "ord_01HX...",
  user_id: "usr_123",
  created_at: ISODate("2026-05-06T09:15:00Z"),
  items: [
    { product_id: ObjectId("..."), name: "Смартфон X", quantity: 1, price: NumberDecimal("79990.00") },
    { product_id: ObjectId("..."), name: "Чехол", quantity: 1, price: NumberDecimal("1990.00") }
  ],
  status: "paid",
  total_amount: NumberDecimal("81980.00"),
  geo_zone: "moscow"
}
```

Кандидаты для shard key:

| Кандидат | Плюсы | Риски |
| --- | --- | --- |
| `{ _id: "hashed" }` | Равномерные записи и быстрый поиск по order id | История заказов пользователя будет scatter-gather |
| `{ user_id: "hashed", created_at: -1 }` | Равномерно распределяет пользователей и таргетирует историю заказов | Статус заказа нужно читать с `user_id` или иметь отдельный индекс |
| `{ geo_zone: 1, created_at: -1 }` | Удобно для региональной аналитики | Горячая геозона в распродажу перегружает шард |

Выбор: `{ user_id: "hashed", created_at: -1 }`.

Причина: история заказов конкретного пользователя является основной пользовательской операцией чтения, а хешированный `user_id` равномерно распределяет поток заказов. Для отображения статуса заказа API должен передавать `user_id + order_id`, чтобы запрос был таргетированным.

Команды:

```javascript
use shop
db.orders.createIndex({ user_id: "hashed", created_at: -1 })
db.orders.createIndex({ user_id: 1, order_id: 1 }, { unique: true })
db.orders.createIndex({ status: 1, created_at: -1 })

sh.shardCollection("shop.orders", { user_id: "hashed", created_at: -1 })
```

### carts

Назначение: активные корзины пользователей и гостей, изменение состава корзины, слияние гостевой корзины после логина, TTL-очистка старых корзин.

Для унификации гостевых и пользовательских корзин вводится поле `owner_key`:

- для пользователя: `u:<user_id>`;
- для гостя: `s:<session_id>`.

Пример документа:

```javascript
{
  _id: ObjectId("..."),
  owner_key: "u:usr_123",
  user_id: "usr_123",
  session_id: null,
  items: [
    { product_id: ObjectId("..."), quantity: 1 },
    { product_id: ObjectId("..."), quantity: 2 }
  ],
  status: "active",
  created_at: ISODate("2026-05-06T09:20:00Z"),
  updated_at: ISODate("2026-05-06T09:25:00Z"),
  expires_at: ISODate("2026-05-13T09:25:00Z")
}
```

Кандидаты для shard key:

| Кандидат | Плюсы | Риски |
| --- | --- | --- |
| `{ _id: "hashed" }` | Равномерно распределяет корзины | Получение активной корзины по user/session будет scatter-gather |
| `{ user_id: "hashed" }` | Хорошо для залогиненных пользователей | Не покрывает гостевые корзины |
| `{ session_id: "hashed" }` | Хорошо для гостей | Не покрывает залогиненных пользователей |
| `{ owner_key: "hashed" }` | Единый таргетированный ключ для гостей и пользователей | При слиянии гостевой и пользовательской корзины возможны два разных шарда |

Выбор: `{ owner_key: "hashed" }`.

Причина: все основные операции активной корзины начинаются с владельца корзины. Хешированный `owner_key` равномерно распределяет нагрузку и позволяет таргетировать чтение и обновление активной корзины. Слияние гостевой корзины в пользовательскую может затронуть два шарда, но это редкая операция по сравнению с чтением и обновлением активной корзины.

Команды:

```javascript
use shop
db.carts.createIndex({ owner_key: "hashed" })
db.carts.createIndex(
  { owner_key: 1, status: 1 },
  { unique: true, partialFilterExpression: { status: "active" } }
)
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })

sh.shardCollection("shop.carts", { owner_key: "hashed" })
```

## Задание 8. Горячие шарды: выявление и устранение

### Метрики

| Группа | Метрика | Зачем нужна |
| --- | --- | --- |
| Распределение данных | Количество chunks на shard | Видно перекос распределения чанков |
| Распределение данных | Размер данных на shard | Видно, где скопился объём |
| Нагрузка | `opcounters.query`, `opcounters.insert`, `opcounters.update` по shard | Видно, какой shard получает большую часть операций |
| Latency | p95/p99 latency чтения и записи по shard | Ранний сигнал перегрузки |
| Очереди и блокировки | WiredTiger cache pressure, lock time, tickets | Показывает насыщение MongoDB |
| Балансировщик | Состояние balancer и миграций chunks | Помогает понять, идёт ли перераспределение |
| Репликация | Replication lag secondary | Важно для чтения с реплик |
| Доменные метрики | QPS по категории, SKU, геозоне | Помогает увидеть горячую «Электронику» до перегрева shard |

Команды диагностики:

```javascript
sh.status()
db.adminCommand({ listShards: 1 })
db.adminCommand({ balancerStatus: 1 })

use shop
db.products.getShardDistribution()
db.orders.getShardDistribution()
db.carts.getShardDistribution()

db.serverStatus().opcounters
db.serverStatus().wiredTiger.cache
```

Для прикладного мониторинга нужно дополнительно писать в метрики:

- `catalog_requests_total{category="electronics"}`;
- `product_detail_requests_total{product_id="..."}`;
- `stock_update_total{product_id="...", geo_zone="..."}`;
- `mongodb_query_latency_ms{collection="products", shard="shard1rs"}`.

### Устранение дисбаланса

1. Не использовать `category` как единственный shard key для `products`. Это создаёт горячий диапазон для популярной категории.
2. Использовать хешированный shard key для каталога: `{ _id: "hashed" }`.
3. Для сверхпопулярных категорий добавить синтетические бакеты: `category_bucket = category + ":" + hash(product_id) % 32`. Тогда запрос категории выполняется как 32 таргетированных запроса по бакетам, а не как один горячий диапазон.
4. Включить и контролировать balancer.
5. При неправильном shard key использовать `reshardCollection` в непиковое окно.
6. Для аварийного ручного выравнивания использовать `moveChunk`, если автоматический balancer не успевает.
7. Кешировать популярные страницы каталога в Redis и CDN.

Примеры команд:

```javascript
sh.setBalancerState(true)
sh.startBalancer()
sh.balancerCollectionStatus("shop.products")

sh.reshardCollection("shop.products", { key: { _id: "hashed" } })

sh.moveChunk(
  "shop.products",
  { _id: ObjectId("665000000000000000000001") },
  "shard2rs"
)
```

Пример индексов для бакетированной категории:

```javascript
use shop
db.products.createIndex({ category_bucket: 1, price: 1 })
db.products.createIndex({ category: 1, price: 1 })
```

## Задание 9. Чтение с реплик и консистентность

Общее правило: операции, которые участвуют в покупке, проверке остатков, активной корзине и свежем статусе заказа, читают с `primary`. Операции каталога, истории и аналитики могут читать с `secondary`, если задана допустимая задержка.

| Коллекция | Операция чтения | Источник | Допустимая задержка secondary | Обоснование |
| --- | --- | --- | --- | --- |
| `products` | Проверка остатка перед созданием заказа | `primary` | 0 секунд | Устаревший остаток может привести к продаже недоступного товара |
| `products` | Карточка товара без критичного остатка | `secondaryPreferred` | 2-5 секунд | Цена и описание меняются реже, небольшая задержка допустима |
| `products` | Каталог по категории и цене | `secondaryPreferred` | 5-30 секунд | Высокочастотное чтение, можно разгрузить primary и кешировать результат |
| `products` | Админское подтверждение изменения цены/остатка | `primary` | 0 секунд | Нужна read-your-writes семантика после изменения |
| `orders` | Создание заказа: чтение только что созданного заказа | `primary` | 0 секунд | Пользователь должен увидеть подтверждение без задержки репликации |
| `orders` | Актуальный статус заказа | `primary` | 0 секунд | Устаревший статус ломает бизнес-сценарий поддержки и оплаты |
| `orders` | История завершённых заказов | `secondaryPreferred` | 10-60 секунд | Исторические данные редко меняются |
| `orders` | Аналитика по заказам | `secondary` | 60-300 секунд | Аналитика не должна мешать транзакционному контуру |
| `carts` | Получение активной корзины | `primary` | 0 секунд | Корзина часто меняется, пользователь ожидает свежий состав |
| `carts` | Добавление, замена, удаление товара: чтение перед обновлением | `primary` | 0 секунд | Иначе можно потерять последнее изменение |
| `carts` | Слияние гостевой корзины | `primary` | 0 секунд | Нужна консистентность двух активных корзин |
| `carts` | Поиск abandoned-корзин для фоновой обработки | `secondaryPreferred` | 60 секунд | Фоновый процесс допускает задержку |

Пример подключения для чтения каталога с secondary:

```text
mongodb://mongos:27017/shop?readPreference=secondaryPreferred&maxStalenessSeconds=30
```

Пример подключения для критичных операций:

```text
mongodb://mongos:27017/shop?readPreference=primary
```

## Задание 10. Миграция на Cassandra

### 10.1. Какие данные переносить

| Данные | Критичность | Cassandra подходит | Обоснование |
| --- | --- | --- | --- |
| Активные корзины | Высокая скорость чтения/записи, TTL | Да | Естественная key-value модель по владельцу, много независимых записей, TTL |
| История заказов пользователя | Высокий read QPS, append-only | Да | Запросы хорошо моделируются таблицей `orders_by_user`, записи распределяются по пользователям и месячным бакетам |
| Статусы заказов | Высокая доступность чтения | Да, как read model | Можно хранить актуальный статус по `order_id`, но источник истины лучше держать в заказном сервисе |
| Каталог товаров | Высокий read QPS и геораспределение | Да, как read model | Денормализованные таблицы под запросы категории и карточки товара |
| Остатки товара | Критичная целостность | Частично | Cassandra может работать с `LOCAL_QUORUM` и LWT, но для жёсткой транзакционности списания остатков нужен отдельный контур резервирования |
| Платежи | Максимальная целостность | Нет | Лучше оставить в строго консистентной транзакционной системе |

Вывод: в Cassandra имеет смысл переносить read/write модели, которые масштабируются по ключу доступа: корзины, историю заказов, карточки и витрины каталога, статусы заказов как read model. Критичное списание остатков можно перенести только при явной модели резервирования и quorum/LWT, иначе есть риск oversell.

### 10.2. Концептуальная модель Cassandra

Кластер использует `Murmur3Partitioner` и vnode. При добавлении узлов Cassandra перераспределяет только часть token ranges, а не весь объём данных между всеми узлами.

Keyspace:

```sql
CREATE KEYSPACE IF NOT EXISTS mobile_world
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
};
```

#### carts_by_owner

Запросы: получить активную корзину по пользователю или session id, обновить состав, TTL-очистка.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.carts_by_owner (
  owner_key text,
  cart_id uuid,
  status text,
  items list<frozen<map<text, text>>>,
  created_at timestamp,
  updated_at timestamp,
  expires_at timestamp,
  PRIMARY KEY ((owner_key), status, cart_id)
) WITH CLUSTERING ORDER BY (status ASC, cart_id ASC)
  AND default_time_to_live = 604800;
```

Partition key: `owner_key`. Он равномерно распределяет пользователей и гостей. Горячая партиция возможна только для одного очень активного владельца, что не является массовым сценарием.

#### orders_by_user

Запросы: история заказов пользователя с сортировкой по времени.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.orders_by_user (
  user_id text,
  order_month text,
  created_at timestamp,
  order_id uuid,
  status text,
  total_amount decimal,
  geo_zone text,
  items list<frozen<map<text, text>>>,
  PRIMARY KEY ((user_id, order_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

Partition key: `(user_id, order_month)`. Месячный бакет ограничивает размер партиции для активных пользователей и сохраняет эффективное чтение истории.

#### order_by_id

Запросы: актуальный статус заказа по id.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.order_by_id (
  order_id uuid PRIMARY KEY,
  user_id text,
  created_at timestamp,
  status text,
  total_amount decimal,
  geo_zone text,
  updated_at timestamp
);
```

Partition key: `order_id`. Даёт равномерное распределение и быстрый точечный доступ.

#### product_by_id

Запросы: карточка товара.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.product_by_id (
  product_id uuid PRIMARY KEY,
  name text,
  category text,
  price decimal,
  attributes map<text, text>,
  updated_at timestamp
);
```

Partition key: `product_id`. Карточки товаров читаются точечно и равномерно распределяются.

#### products_by_category_bucket

Запросы: каталог по категории, геозоне и цене. Чтобы «Электроника» не стала одной горячей партицией, категория разбивается на бакеты.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.products_by_category_bucket (
  category text,
  bucket int,
  geo_zone text,
  price_bucket int,
  price decimal,
  product_id uuid,
  name text,
  available_quantity int,
  PRIMARY KEY ((category, bucket, geo_zone), price_bucket, price, product_id)
) WITH CLUSTERING ORDER BY (price_bucket ASC, price ASC, product_id ASC);
```

Partition key: `(category, bucket, geo_zone)`. Для категории «Электроника» приложение делает параллельные запросы по `bucket = 0..31`. Нагрузка распределяется по множеству партиций и узлов.

#### inventory_reservations_by_product_geo_bucket

Запросы: резервирование остатков под экстремальной нагрузкой.

```sql
CREATE TABLE IF NOT EXISTS mobile_world.inventory_reservations_by_product_geo_bucket (
  product_id uuid,
  geo_zone text,
  bucket int,
  reservation_id uuid,
  order_id uuid,
  quantity int,
  status text,
  created_at timestamp,
  expires_at timestamp,
  PRIMARY KEY ((product_id, geo_zone, bucket), reservation_id)
) WITH default_time_to_live = 1800;
```

Partition key: `(product_id, geo_zone, bucket)`. Бакетирование снижает риск горячей партиции для популярного товара во время распродажи. Для строгого списания остатка используется quorum и, если необходимо, LWT на ограниченном контуре резервирования.

Пример условного резервирования:

```sql
INSERT INTO mobile_world.inventory_reservations_by_product_geo_bucket (
  product_id, geo_zone, bucket, reservation_id, order_id, quantity, status, created_at, expires_at
) VALUES (?, ?, ?, ?, ?, ?, 'reserved', toTimestamp(now()), ?)
IF NOT EXISTS;
```

### 10.3. Стратегии восстановления целостности

| Стратегия | Где использовать | Обоснование |
| --- | --- | --- |
| Hinted Handoff | Корзины, статусы заказов, каталог, история заказов | Помогает переживать кратковременную недоступность реплики без синхронного ожидания её восстановления |
| Read Repair | `order_by_id`, `product_by_id`, критичные чтения статуса | При чтении с quorum можно быстро исправлять расхождения между репликами, но это увеличивает latency |
| Anti-Entropy Repair | Все таблицы по расписанию, чаще для заказов и резервов | Полная фоновая сверка данных через Merkle trees, нужна для долгосрочной целостности |

Рекомендуемые уровни consistency:

| Сущность | Write consistency | Read consistency | Компромисс |
| --- | --- | --- | --- |
| `carts_by_owner` | `LOCAL_QUORUM` | `LOCAL_QUORUM` для активной корзины, `LOCAL_ONE` для фоновых задач | Свежесть активной корзины важнее минимальной задержки |
| `orders_by_user` | `LOCAL_QUORUM` | `LOCAL_QUORUM` для новых заказов, `LOCAL_ONE` для старой истории | История должна быть доступной, но новые заказы требуют read-your-writes |
| `order_by_id` | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Статус заказа должен быть свежим |
| `product_by_id` | `LOCAL_QUORUM` | `LOCAL_ONE` или `LOCAL_QUORUM` для админки | Каталог в пользовательском контуре допускает небольшую задержку |
| `products_by_category_bucket` | `LOCAL_QUORUM` | `LOCAL_ONE` | Витрина каталога высоконагруженная и кешируемая |
| `inventory_reservations_by_product_geo_bucket` | `LOCAL_QUORUM` + LWT для критичных операций | `LOCAL_QUORUM` | Снижение риска oversell важнее latency |

Примеры обслуживания:

```shell
nodetool repair mobile_world orders_by_user
nodetool repair mobile_world order_by_id
nodetool repair mobile_world inventory_reservations_by_product_geo_bucket
```

Пример настроек `cassandra.yaml`:

```yaml
hinted_handoff_enabled: true
max_hint_window: 3h
num_tokens: 256
```

Итоговая позиция: Cassandra хорошо решает горизонтальное масштабирование и отказоустойчивость для денормализованных моделей чтения/записи. Для денежных операций и окончательного списания остатков нужно сохранять отдельные механизмы строгой консистентности: quorum, LWT, идемпотентные reservation id и компенсационные процессы.
