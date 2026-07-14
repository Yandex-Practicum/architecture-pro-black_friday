# Архитектура данных «Мобильный мир»: шардирование, hot shards, read preference и миграция на Cassandra

Документ покрывает задания 7–10 проектной работы: схемы коллекций MongoDB для шардирования
(`products`, `orders`, `carts`), выявление и устранение «горячих» шардов, read preference для
чтения с реплик и частичную миграцию на Cassandra.

Контекст: онлайн-магазин «Мобильный мир» вырос — теперь помимо аксессуаров для смартфонов
продаются электроника, аудио- и бытовая техника и другие категории товаров. Данные о заказах,
товарах и корзинах хранятся в трёх коллекциях MongoDB (база `mobilnyMir`): `orders`, `products`,
`carts`.

## Оглавление

1. [Задание 7 — Схемы коллекций и шард-ключи](#задание-7--схемы-коллекций-и-шард-ключи)
2. [Задание 8 — Hot shards: метрики и устранение](#задание-8--hot-shards-метрики-и-устранение)
3. [Задание 9 — Read preference](#задание-9--read-preference)
4. [Задание 10 — Миграция на Cassandra](#задание-10--миграция-на-cassandra)

## Задание 7 — Схемы коллекций и шард-ключи

### `orders`

**Атрибуты:**

```json
{
  "_id": "ObjectId",
  "order_id": "string (uuid, генерируется приложением, уникален)",
  "customer_id": "string, индексирован",
  "order_datetime": "ISODate",
  "items": [
    { "product_id": "string", "name": "string", "qty": "number", "price_at_order": "number" }
  ],
  "status": "string enum: created|paid|shipped|delivered|cancelled",
  "total": "number",
  "geo_zone": "string enum: moscow|ekb|kaliningrad|..."
}
```

**Рассмотренные варианты шард-ключа:**

| Вариант | Плюсы | Минусы |
|---|---|---|
| `{order_id: "hashed"}` | Равномерная запись | «История заказов пользователя» превращается в scatter-gather по всем шардам, хотя это одна из частых операций |
| `{geo_zone: 1}` (range) | Удобно для региональной аналитики | Гео-зоны неравномерны (Москва ≫ Калининграда) — воспроизводит тот же риск hot-шарда, что и `category` у `products` (см. Задание 8); региональная аналитика не входит в частые операции |
| **`{customer_id: "hashed"}`** (выбрано) | Равномерная запись новых заказов; «история заказов пользователя» — точечный запрос к одному шарду | «Последние заказы по всем клиентам» требуют scatter-gather, но такой запрос не указан среди основных |

**Выбор:** `{customer_id: "hashed"}`.

```javascript
sh.enableSharding("mobilnyMir")
db.orders.createIndex({ customer_id: "hashed" })
sh.shardCollection("mobilnyMir.orders", { customer_id: "hashed" })
```

**Быстрое создание заказа с одновременным списанием остатков:** заказ (`orders`) и товар
(`products`) шардируются независимо и почти всегда лежат на разных шардах. Вместо кросс-шардовой
ACID-транзакции (поддерживается с MongoDB 4.2, но дороже по latency из-за two-phase commit)
подходит такой порядок: (1) создать заказ; (2) списать остаток условным обновлением
`db.products.updateOne({product_id, category, "stock_by_geozone.<zone>": {$gte: qty}}, {$inc: {"stock_by_geozone.<zone>": -qty}})`
— атомарно на уровне одного документа, не даёт продать больше, чем есть; (3) при неудаче списания
(нет остатка) — пометить заказ `status: "failed"` и вернуть ошибку. Идемпотентность по `order_id`
позволяет безопасно повторить шаг (2) при сетевом сбое.

### `products`

**Атрибуты:**

```json
{
  "_id": "ObjectId",
  "product_id": "string, уникален",
  "name": "string",
  "category": "string enum: electronics|books|audio|appliances|...",
  "price": "number",
  "stock_by_geozone": { "ekb": 50, "kaliningrad": 30 },
  "attributes": { "color": "string", "size": "string" }
}
```

**Рассмотренные варианты шард-ключа:**

| Вариант | Плюсы | Минусы |
|---|---|---|
| `{category: 1}` (range) | Отличная маршрутизация «поиск по категории + диапазон цен» | Низкая кардинальность + сильный перекос трафика (Электроника — 70% запросов, см. Задание 8) → классический hot shard |
| `{product_id: "hashed"}` | Равномерное распределение | «Поиск по категории» требует scatter-gather по всему кластеру на каждый просмотр каталога |
| **`{category: 1, product_id: "hashed"}`** (выбрано) | Range-префикс направляет запросы по категории на нужные шарды; hashed-суффикс дробит диапазон одной категории, поэтому балансировщик может разнести даже «горячую» категорию по нескольким шардам | Для точечного обновления остатка нужно передавать и `category`, и `product_id`, иначе операция станет broadcast-запросом ко всем шардам |

**Выбор:** `{category: 1, product_id: "hashed"}`.

```javascript
db.products.createIndex({ category: 1, product_id: "hashed" })
sh.shardCollection("mobilnyMir.products", { category: 1, product_id: "hashed" })
```

**Важный нюанс составного ключа:** так как `category` — префикс шард-ключа, любая операция
(в том числе обновление остатка при покупке) обязана указывать `category` вместе с `product_id`,
иначе mongos не сможет определить целевой шард и разошлёт запрос по всем шардам (broadcast) —
корректно, но менее эффективно. На уровне приложения `category` всегда должен быть известен рядом
с `product_id` (кешируется вместе с карточкой товара), поэтому это не проблема на практике, но
важно для тех, кто пишет запросы к коллекции напрямую.

**Поиск по категории с фильтром по цене:**

```javascript
db.products.createIndex({ category: 1, price: 1 })
db.products.find({ category: "electronics", price: { $gte: 10000, $lte: 50000 } })
```

Такой запрос маршрутизируется только на шарды, владеющие диапазоном `category: "electronics"`
(не на весь кластер), а вторичный индекс `{category, price}` ускоряет фильтрацию на каждом из них.

### `carts`

**Атрибуты:**

```json
{
  "_id": "ObjectId",
  "owner_key": "string — равен user_id, если пользователь залогинен, иначе session_id",
  "user_id": "string | null",
  "session_id": "string | null",
  "items": [ { "product_id": "string", "quantity": "number" } ],
  "status": "active | ordered | abandoned",
  "created_at": "ISODate",
  "updated_at": "ISODate",
  "expires_at": "ISODate"
}
```

**Рассмотренные варианты шард-ключа:**

| Вариант | Плюсы | Минусы |
|---|---|---|
| `{session_id: "hashed"}` | Точечный запрос для гостей | Не работает для залогиненных пользователей, у которых ищем по `user_id`, а не `session_id` |
| `{user_id: "hashed"}` | Точечный запрос для пользователей | Не работает для гостей (`user_id` ещё нет) |
| **`{owner_key: "hashed"}`** (выбрано) | Единое поле `owner_key` (=`user_id` либо `session_id`) даёт точечный запрос «текущая корзина» независимо от статуса логина | Требует сопровождающей логики в приложении для вычисления `owner_key` при записи |

**Выбор:** `{owner_key: "hashed"}`.

```javascript
db.carts.createIndex({ owner_key: "hashed" })
sh.shardCollection("mobilnyMir.carts", { owner_key: "hashed" })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

Запрос текущей активной корзины — гость или пользователь, одинаково:

```javascript
db.carts.findOne({ owner_key: sessionIdOrUserId, status: "active" })
```

**Слияние гостевой корзины в пользовательскую при логине:** два точечных запроса на, вероятно,
разных шардах (`owner_key = session_id` и `owner_key = user_id`) — не единая кросс-шардовая
транзакция. Порядок: прочитать гостевую `{owner_key: session_id, status: "active"}` → объединить
её `items` с корзиной `{owner_key: user_id, status: "active"}` (создать, если не было) → записать
объединённую пользовательскую корзину → пометить гостевую `status: "abandoned"`. Операция
идемпотентна (повторное слияние того же товара увеличивает `quantity`, а не создаёт дубликат),
поэтому не атомарная кросс-шардовая транзакция — оправданный компромисс ради латентности; в
худшем случае при сбое между шагами гостевая корзина останется `active` и будет обработана снова
или очищена по TTL.

## Задание 8 — Hot shards: метрики и устранение

Сценарий: категория «Электроника» создаёт 70% запросов к `products`, поэтому один или несколько
шардов, владеющих её диапазоном, начинают отвечать медленнее остальных. Hashed-суффикс в
шард-ключе из Задания 7 снижает риск, но перекос трафика всё равно нужно отслеживать.

### Метрики мониторинга

| Метрика | Что показывает | Источник | Порог алерта |
|---|---|---|---|
| ops/sec на шард (read/write раздельно) | Нагрузка по операциям на конкретный шард | `db.serverStatus().opcounters` на каждом shard primary → агрегация в Prometheus/Grafana | Шард > 1.5–2× среднего по кластеру на устойчивом 5-минутном окне |
| Число и размер чанков на шард | Балансировка данных между шардами | `sh.status()`; `db.getSiblingDB("config").chunks.aggregate([{ $group: { _id: "$shard", count: { $sum: 1 } } }])` | Расхождение > 20% от равномерного распределения |
| Replication lag на репликах шарда | Задержка вторичных реплик | `rs.printSecondaryReplicationInfo()` на replica set каждого шарда | Устойчиво > 10 сек |
| WiredTiger cache eviction rate | Давление на память шарда | `db.serverStatus().wiredTiger.cache` | Рост eviction rate непропорционально росту ops/sec |
| Доля медленных запросов на шард | Локальные проблемы производительности | `system.profile` (профайлер, `slowms`) на каждом шарде | > 5% запросов дольше 100 мс на одном шарде против <1% на остальных |
| % трафика по категориям (бизнес-метрика) | Реальный источник перекоса нагрузки | Кастомная метрика в приложении → Prometheus/Grafana | Одна категория > 50% суммарного трафика к `products` |
| Состояние балансировщика | Не throttled ли перераспределение | `sh.getBalancerState()`, `sh.isBalancerRunning()` | Balancer window слишком узкий во время пиковой нагрузки |

### Механизмы устранения

1. **Составной шард-ключ с hashed-суффиксом** (уже заложен в Задании 7) — структурная защита с
   самого начала: даже «горячая» категория физически размазана по многим чанкам.
2. **Zone sharding** — выделить горячей категории больше зон/шардов:

```javascript
sh.addShardToZone("shard3", "hotCategoryZone")
sh.addShardToZone("shard4", "hotCategoryZone")
sh.updateZoneKeyRange(
  "mobilnyMir.products",
  { category: "electronics", product_id: MinKey },
  { category: "electronics", product_id: MaxKey },
  "hotCategoryZone"
)
```

3. **Ручное перераспределение**, если балансировщик не успевает за всплеском:

```javascript
sh.splitFind("mobilnyMir.products", { category: "electronics", product_id: "p-500000" })
sh.moveChunk("mobilnyMir.products", { category: "electronics", product_id: "p-500000" }, "shard4")
```

4. **Redis-кеш перед горячей категорией** для read-hot паттернов — в этом же проекте кеширование
   уже реализовано для `GET /{collection}/users` (`api_app/app.py`, TTL 60 сек через
   `fastapi-cache` + Redis); для листинга горячей категории `products` стоит применить тот же
   приём — кешировать результат `find({category: "electronics", ...})` на короткий TTL.
5. **Настройки балансировщика** — во время ожидаемых пиков заранее расширить окно балансировки,
   а вне пиков возвращать более спокойный режим, чтобы фоновое перемещение чанков не мешало
   обычной нагрузке.

## Задание 9 — Read preference

| Коллекция | Операция | Read target | Допустимая задержка репликации | Обоснование |
|---|---|---|---|---|
| `products` | Проверка остатка перед оплатой (checkout) | `primary` | 0 | Устаревший остаток → риск продать то, чего уже нет — консистентность важнее латентности |
| `products` | Списание остатка при покупке (запись) | `primary` (все записи идут туда) | — | Запись всегда на primary, read preference неприменим |
| `products` | Листинг/поиск по категории, фильтр по цене | `secondaryPreferred` | до ~5–10 сек | Цена и остаток меняются нечасто; лёгкое устаревание каталога не влияет на бизнес-логику |
| `products` | Страница товара (описание, цена, индикатор «в наличии»/«мало») | `secondaryPreferred` | до ~5–10 сек | Точная проверка остатка всё равно происходит на этапе checkout — здесь достаточно приблизительного индикатора |
| `orders` | Создание заказа (запись) | `primary` | — | Запись |
| `orders` | Немедленное отображение подтверждения сразу после создания заказа | `primary` | 0 | Read-your-write: секундная задержка репликации может показать «заказ не найден» |
| `orders` | История заказов пользователя (уже оформленные, не текущие) | `secondaryPreferred` | до ~30 сек | Согласованные исторические записи, staleness не меняет бизнес-логику |
| `orders` | Статус заказа на клиентской странице «трекинг» в первые минуты после смены статуса | `primary` | 0–2 сек | Устаревший статус подрывает доверие пользователя к магазину |
| `orders` | Операционные дашборды склада/курьеров (агрегаты, не единичный заказ) | `secondaryPreferred` | до ~5 сек | Аналитическая read-нагрузка не должна создавать конкуренцию на primary и не требует real-time точности |
| `carts` | Чтение/обновление активной корзины во время сессии | `primary` | 0 | Read-your-write: добавление товара должно немедленно отражаться при следующем рендере корзины |
| `carts` | Слияние гостевой корзины в пользовательскую при логине | `primary` | 0 | Корректность критична — устаревшее чтение гостевой корзины рискует потерять товары при слиянии |
| `carts` | Фоновая очистка просроченных/`abandoned` корзин (batch-джоба) | `secondaryPreferred` | минуты | Не пользовательская операция в реальном времени, устаревание не критично |

**Как задавать read preference (пример для `pymongo`/`motor`):**

```python
from pymongo import ReadPreference

# Для листинга каталога — допустима задержка
db = client.get_database(
    "mobilnyMir", read_preference=ReadPreference.SECONDARY_PREFERRED
)

# Для проверки остатка перед оплатой — только primary (эквивалентно read_preference по умолчанию)
db_primary = client.get_database("mobilnyMir", read_preference=ReadPreference.PRIMARY)
```

## Задание 10 — Миграция на Cassandra

### 10.1 Какие данные переносим

| Сущность | Мигрируем? | Обоснование |
|---|---|---|
| `orders` (история + статус) | Да, частично | Резкий рост записи в пик (50 000 запросов/сек), естественный time-series доступ («последние заказы пользователя»), нужна масштабируемость записи без полного решардинга; целостность обеспечивается через consistency level (`QUORUM`), а не отказом от неё |
| `carts` / пользовательские сессии | Да | Очень высокая частота чтения/записи на каждое действие пользователя, естественный TTL, ценность leaderless geo-репликации при географическом росте магазина |
| `products` (каталог) | Нет, остаётся в MongoDB | Нужны гибкие ad hoc фильтры по категории и диапазону цен — сильная сторона MongoDB; Cassandra требует query-first моделирования (отдельная таблица под каждый паттерн доступа), что делает произвольную фильтрацию неудобной; каталог не является write-heavy во время распродажи |

Почему Cassandra решает исходную проблему: MongoDB с range-шардированием при добавлении новых
шардов полностью перераспределяла данные между всеми узлами, проседая по latency в пик нагрузки.
Cassandra использует consistent hashing (кольцо токенов): при добавлении узла перемещается только
часть соседних диапазонов токенов, а не весь набор данных. Поэтому масштабирование меньше влияет
на latency во время нагрузки.

### 10.2 Концептуальная модель

Cassandra требует моделирования «от паттерна доступа» — одна таблица на каждый нужный запрос,
данные денормализуются (дублируются) между таблицами, а не нормализуются.

**История заказов пользователя** — партиционируем по `(customer_id, year_month)` (бакетирование
по месяцу защищает от неограниченного роста партиции самых активных клиентов), кластеризуем по
`order_datetime DESC` для естественного «последние заказы сверху»:

```sql
CREATE KEYSPACE IF NOT EXISTS mobilny_mir
  WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': 3};

CREATE TABLE mobilny_mir.orders_by_customer (
    customer_id   text,
    year_month    text,
    order_datetime timestamp,
    order_id      text,
    status        text,
    total         decimal,
    geo_zone      text,
    items         list<frozen<map<text, text>>>,
    PRIMARY KEY ((customer_id, year_month), order_datetime, order_id)
) WITH CLUSTERING ORDER BY (order_datetime DESC, order_id ASC);
```

**Точечный статус заказа по `order_id`** (например, для вебхуков/дашбордов) — отдельная таблица,
партиционированная напрямую по `order_id`:

```sql
CREATE TABLE mobilny_mir.orders_by_id (
    order_id       text PRIMARY KEY,
    customer_id    text,
    order_datetime timestamp,
    status         text,
    total          decimal,
    geo_zone       text,
    items          list<frozen<map<text, text>>>
);
```

Запись заказа пишется в обе таблицы (denormalization on write) — либо последовательно из
приложения, либо через `BATCH` (логический, не atomic-cross-partition — Cassandra `BATCH` для
разных партиций не даёт атомарности между ними, лишь группирует отправку):

```sql
BEGIN BATCH
  INSERT INTO mobilny_mir.orders_by_customer (customer_id, year_month, order_datetime, order_id, status, total, geo_zone, items)
  VALUES ('cust-42', '2026-07', '2026-07-13T10:00:00Z', 'ord-9001', 'created', 4990.00, 'ekb', [{'product_id': 'p-1', 'qty': '1'}]);
  INSERT INTO mobilny_mir.orders_by_id (order_id, customer_id, order_datetime, status, total, geo_zone, items)
  VALUES ('ord-9001', 'cust-42', '2026-07-13T10:00:00Z', 'created', 4990.00, 'ekb', [{'product_id': 'p-1', 'qty': '1'}]);
APPLY BATCH;
```

**Корзины** — партиционируем по тому же `owner_key`, что и в MongoDB-дизайне Задания 7 (единая
архитектурная идея на оба хранилища), кластеризуем по `product_id`, чтобы добавление/удаление
одного товара было точечной операцией без чтения-модификации всего документа корзины; TTL —
нативно на уровне строки:

```sql
CREATE TABLE mobilny_mir.cart_items (
    owner_key  text,
    product_id text,
    quantity   int,
    added_at   timestamp,
    PRIMARY KEY (owner_key, product_id)
) WITH default_time_to_live = 2592000;  -- 30 дней, соответствует expires_at из MongoDB-дизайна

UPDATE mobilny_mir.cart_items USING TTL 2592000
  SET quantity = 2, added_at = toTimestamp(now())
  WHERE owner_key = 'sess-abc123' AND product_id = 'p-42';
```

**Горячие партиции и решардинг:** партиционирование по `customer_id`/`owner_key` (высококардинальные,
близкие к равномерному распределению при большой базе клиентов) в сочетании с бакетированием по
месяцу для `orders_by_customer` ограничивает рост отдельной партиции даже для самых активных
клиентов. Consistent hashing (Murmur3Partitioner по умолчанию) не требует ручного выбора
hash-суффикса, как в MongoDB, — партиционер сам равномерно распределяет партиции по кольцу токенов;
при добавлении узла перемещается лишь часть диапазона токенов соседних узлов, а не полный пересчёт.

### 10.3 Стратегии восстановления целостности

| Стратегия | Применяем к | Обоснование |
|---|---|---|
| **Hinted Handoff** | Все таблицы (`orders_by_*`, `cart_items`) | Работает по умолчанию для любой записи при кратковременной недоступности реплики — сохраняет доступность записи без немедленного full repair; нет причин отключать где-либо |
| **Read Repair** | `orders_by_customer`, `orders_by_id` — через выбор consistency level `QUORUM` на чтение | В современной Cassandra (4.0+) read repair встроен в чтения на `QUORUM`+: реплика с устаревшими данными чинится попутно с обычным запросом. Заказы читаются часто сразу после записи (страница подтверждения) — такое «самолечение» почти бесплатно и держит `orders_by_*` консистентными без отдельного фонового процесса |
| **Anti-Entropy Repair** (`nodetool repair`) | Все таблицы, но с разной частотой: `cart_items` — раз в 2–3 дня; `orders_by_*` — раз в 7 дней | `cart_items` использует построчный TTL → активный churn tombstone'ов от истёкших записей; частый repair держит их количество под контролем и укладывается в `gc_grace_seconds` (по умолчанию 10 дней), не давая просроченным данным «воскреснуть» после восстановления упавшей ноды. Для `orders_by_*` штатной еженедельной частоты достаточно — данные почти не удаляются |

**Consistency level по операциям:**

```sql
-- Заказ: целостность важнее задержки — QUORUM на запись и на чтение
cqlsh> CONSISTENCY QUORUM;
cqlsh> INSERT INTO mobilny_mir.orders_by_id (order_id, customer_id, order_datetime, status, total, geo_zone)
       VALUES ('ord-9001', 'cust-42', toTimestamp(now()), 'created', 4990.00, 'ekb');

-- Корзина: задержка важнее строгой консистентности — LOCAL_ONE
cqlsh> CONSISTENCY LOCAL_ONE;
cqlsh> UPDATE mobilny_mir.cart_items SET quantity = 2
       WHERE owner_key = 'sess-abc123' AND product_id = 'p-42';
```

В драйвере приложения (например, `cassandra-driver` для Python) уровень консистентности задаётся
per-request через `ConsistencyLevel.QUORUM` / `ConsistencyLevel.LOCAL_ONE` в объекте `Statement`,
а не в самом CQL-запросе — синтаксис `CONSISTENCY ...;` выше специфичен для интерактивного
`cqlsh` и приведён здесь для иллюстрации.
