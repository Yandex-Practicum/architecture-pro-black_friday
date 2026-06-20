# Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

Архитектурный документ для онлайн-магазина «Мобильный мир».

**Контекст:** при 50 000 запросов/сек. MongoDB с range-based sharding при добавлении шардов полностью перераспределяла данные → просадка latency в пик. Cassandra выбрана за leaderless-репликацию, горизонтальное масштабирование без полного reshuffle и равномерное распределение через consistent hashing.

Связанные схемы MongoDB — [task7/README.md](../task7/README.md), политика чтения — [task9/README.md](../task9/README.md).

Диаграммы в [`diagrams/`](../diagrams/) показывают **исходную MongoDB-модель до миграции**: `products`, `orders`, `carts`, `stock_by_zone` внутри `products`. В этом документе описана целевая модель после выноса write-heavy данных в Cassandra.

---

## 1. Задание 10.1 — Какие данные переносим в Cassandra

### 1.1. Классификация сущностей

| Сущность | Критичность (целостность / скорость) | Паттерн нагрузки в Black Friday | Cassandra? |
|----------|--------------------------------------|----------------------------------|------------|
| **Заказы** (`orders`) | Высокая / высокая | Массовая запись при checkout, чтение истории и статуса | **Да** |
| **Корзины** (`carts`) | Высокая / очень высокая | Постоянные add/remove, read-your-writes | **Да** |
| **Остатки по зонам** (`stock_by_zone`) | Критическая / очень высокая | `$inc` на hot SKU — источник hot shard (задание 8) | **Да** |
| **История заказов** (snapshot в `orders.items`) | Средняя / средняя | Append-only после оплаты, редкие правки | **Да** (вместе с заказами) |
| **Каталог товаров** (`products` — name, category, описание) | Средняя / средняя | Тяжёлые фильтры `{ category, price }`, scatter-gather | **Нет** — оставляем MongoDB + кэш/CDN |
| **Пользовательские сессии** | Средняя / высокая | TTL, частые point read/write | **Нет** — оставляем в Redis/cache layer |
| **Платежи** | Критическая / низкая | ACID, мало записей | **Нет** — внешний payment-провайдер; в БД только `payment_id` и статус в заказе |

### 1.2. Обоснование выбора

**Переносим в Cassandra** сущности с **высокой скоростью записи**, **предсказуемым ключом доступа** (point read/write по `customer_id`, `owner_key`, `product_id`) и допустимостью **eventual consistency** с точечным усилением через `QUORUM` / LWT:

1. **Заказы** — в пик десятки тысяч insert/update в секунду; после создания заказ append-only. Cassandra масштабирует запись линейно, новые узлы получают только свои token ranges без полной миграции всех chunks (в отличие от MongoDB balancer).
2. **Корзины** — один владелец = одна партиция (`owner_key`), все CRUD targeted. TTL на брошенные корзины — нативная фича Cassandra.
3. **Остатки** — самая «горячая» запись в системе; вынос в отдельную таблицу с partition key `(product_id, geo_zone)` разносит нагрузку hot SKU по зонам и не блокирует каталог.
4. **Сессии** — короткий жизненный цикл, TTL и быстрый доступ по `session_id`. В текущем стенде уже есть Redis, поэтому хранить сессии в Cassandra не нужно: Redis проще, быстрее для cache-сценария и автоматически очищает ключи по TTL.

**Оставляем вне Cassandra:**

- **Каталог** — запросы по вторичным полям (`category`, `price`, `is_active`) в Cassandra = full scan или дублирование таблиц под каждый access pattern. В MongoDB уже есть индекс `{ category, price }` и CDN для статики (задание 6).
- **Сессии** — остаются в Redis: это короткоживущие данные с TTL, потеря которых приводит максимум к повторному логину, а не к финансовой ошибке.
- **Платежи** — списание денег и PCI-DSS на стороне внешнего провайдера (ЮKassa, CloudPayments и т.п.). В нашей системе храним только ссылку `payment_id` и статус `paid` / `refunded` в `orders`; отдельной БД для платежей в стенде нет.
- **Транзакции checkout** (корзина → заказ → списание остатка) — Cassandra не даёт multi-partition ACID; оркестрируем через **saga** с компенсирующими шагами и идемпотентностью.

### 1.3. Целевая топология кластера

```text
DC1 (moscow)     : 3 nodes, RF=3
DC2 (ekaterinburg): 3 nodes, RF=3  — локальные чтения для Урала
```

```cql
CREATE KEYSPACE mobile_world
  WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'moscow': 3,
    'ekaterinburg': 3
  }
  AND durable_writes = true;
```

`NetworkTopologyStrategy` + `LOCAL_QUORUM` дают геораспределённость без cross-DC latency на каждый запрос.

---

## 2. Задание 10.2 — Модель данных и ключи

### 2.1. Принципы проектирования

| Принцип | Как применяем |
|---------|---------------|
| Запрос определяет модель | Одна таблица = один основной access pattern |
| Partition key = равномерность | UUID / hashed id / составной ключ с высокой кардинальностью |
| Избегаем hot partition | Не кладём `category` или `created_at` без bucket в partition key |
| Денормализация | `orders_by_id` дублирует заказ для lookup без `customer_id` |
| Решардинг | Добавление узла → перераспределение только ~1/N token ranges, без полного rebalance всех данных |

### 2.2. Таблица `orders_by_customer`

**Access pattern:** история заказов пользователя, создание заказа, статус текущего заказа.

| Ключ | Поле | Зачем |
|------|------|-------|
| **Partition key** | `customer_id` | Все заказы одного клиента на одной партиции — targeted read/write |
| **Clustering key** | `created_at DESC`, `order_id` | Сортировка по дате без отдельного индекса; `order_id` уникализирует строку |

**Hot partition:** B2B-клиент с миллионом заказов раздувает партицию → для таких аккаунтов добавляем bucket: `customer_id = 'corp_xxx|2026-06'` (месячный bucket) или переходим на `customer_id` = hash prefix.

```cql
-- UDT создаём до таблиц, которые на него ссылаются
CREATE TYPE mobile_world.order_item (
  product_id  text,
  name        text,
  category    text,
  quantity    int,
  unit_price  decimal,
  line_total  decimal
);
```

```cql
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
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 7};
```

```cql
-- История заказов (targeted, один узел-координатор)
SELECT * FROM orders_by_customer
WHERE customer_id = 'user_10482'
LIMIT 20;

-- Статус заказа сразу после оплаты
SELECT status, updated_at FROM orders_by_customer
WHERE customer_id = 'user_10482'
  AND created_at = '2026-06-14 11:02:33+0000'
  AND order_id = 'ord_a91f0042';
```

### 2.3. Таблица `orders_by_id`

**Access pattern:** поиск заказа по `order_id` из email/SMS без `customer_id`.

| Ключ | Поле | Зачем |
|------|------|-------|
| **Partition key** | `order_id` | Равномерное распределение UUID-подобных id |
| **Clustering key** | — | Одна строка на заказ |

Денормализация: при создании заказа пишем в обе таблицы в одной saga.

```cql
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

### 2.4. Таблица `carts_by_owner`

**Access pattern:** активная корзина гостя/пользователя, add/remove, merge при логине.

| Ключ | Поле | Зачем |
|------|------|-------|
| **Partition key** | `owner_key` | `user:user_10482` / `session:sess_9f2caa01` — как в MongoDB |
| **Clustering key** | `cart_id` | Одна активная корзина; при необходимости несколько статусов |

```cql
-- UDT создаём до таблицы carts_by_owner
CREATE TYPE mobile_world.cart_item (
  product_id  text,
  quantity    int
);
```

```cql
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
) WITH default_time_to_live = 1209600;  -- 14 дней, как expires_at в MongoDB
```

```cql
-- Активная корзина
SELECT * FROM carts_by_owner
WHERE owner_key = 'user:user_10482'
  AND cart_id = 'cart_7c2e9f11';
```

**Hot partition:** маловероятна — корзина на владельца, кардинальность `owner_key` ≈ число активных сессий/пользователей.

### 2.5. Таблица `inventory_by_product_zone`

**Access pattern:** чтение и списание остатка перед резервом (критичный путь checkout).

| Ключ | Поле | Зачем |
|------|------|-------|
| **Partition key** | `(product_id, geo_zone)` | Hot SKU «Смартфон X» распределяется по зонам (`moscow`, `ekaterinburg`, …), а не сходится в одну партицию |
| **Clustering key** | — | Одна строка на товар+зону |

**Hot partition:** один SKU в одной зоне в пик — всё ещё hot. Митигация: counter-таблица с sharding bucket `product_id#0..7` или очередь резервирования через Kafka + итоговый counter.

```cql
CREATE TABLE mobile_world.inventory_by_product_zone (
  product_id   text,
  geo_zone     text,
  stock        int,
  reserved     int,
  updated_at   timestamp,
  PRIMARY KEY ((product_id, geo_zone))
);
```

```cql
-- 1. Читаем текущий остаток
SELECT stock, reserved FROM inventory_by_product_zone
WHERE product_id = 'prod_8f3a2c1b' AND geo_zone = 'moscow';

-- 2. Приложение считает новые значения и пишет их через LWT.
-- SET stock = stock - 1 для обычного int в Cassandra нельзя.
UPDATE inventory_by_product_zone
SET stock = 49, reserved = 1, updated_at = toTimestamp(now())
WHERE product_id = 'prod_8f3a2c1b' AND geo_zone = 'moscow'
IF stock = 50 AND reserved = 0;
```

Для максимальной скорости записи без LWT — отдельная таблица `inventory_events` (append-only) и материализация остатка асинхронно; для checkout оставляем LWT на `inventory_by_product_zone`.

### 2.6. Пользовательские сессии — Redis, не Cassandra

Сессии не включаем в Cassandra-модель. Для них важны TTL, быстрый доступ по `session_id` и автоматическое удаление, а не долговременная репликация и repair. В текущем приложении уже есть Redis, поэтому используем его как cache/session layer.

```text
session:{session_id} -> {
  user_id,
  geo_zone,
  created_at,
  last_seen_at
}
TTL: 24 ч
```

Если Redis недоступен, пользователь перелогинится. Это приемлемый компромисс: потеря сессии не создаёт oversell, неверный заказ или финансовое расхождение.

### 2.7. Сводка ключей

| Таблица | Partition key | Clustering key | Риск hot partition | Решардинг |
|---------|---------------|----------------|--------------------|-----------|
| `orders_by_customer` | `customer_id` | `created_at`, `order_id` | B2B-аккаунты | Новый узел → только его tokens |
| `orders_by_id` | `order_id` | — | Низкий | То же |
| `carts_by_owner` | `owner_key` | `cart_id` | Низкий | То же |
| `inventory_by_product_zone` | `(product_id, geo_zone)` | — | Hot SKU в одной зоне | То же; bucket при необходимости |

### 2.8. Уровни консистентности на запись/чтение

| Операция | CL write | CL read | Почему |
|----------|----------|---------|--------|
| Создание заказа | `QUORUM` | — | Данные на большинстве реплик |
| Статус заказа после оплаты | `QUORUM` | `QUORUM` | Read-your-writes |
| История заказов | — | `LOCAL_ONE` | Допустимо eventual (как secondary в задании 9) |
| Активная корзина | `QUORUM` | `QUORUM` | Нельзя показать устаревший состав |
| Остаток перед резервом | LWT + `QUORUM` | `QUORUM` | Защита от oversell |

---

## 3. Задание 10.3 — Стратегии восстановления целостности

### 3.1. Кратко о механизмах

| Стратегия | Когда срабатывает | Latency | Гарантия |
|-----------|-------------------|---------|----------|
| **Hinted Handoff (HH)** | Запись при временно недоступной реплике | Нулевая для клиента | Восстанавливает пропущенные записи после возврата узла |
| **Read Repair** | Чтение обнаружило расхождение версий | +latency на этот read | Синхронно чинит реплики, с которых читали |
| **Anti-Entropy Repair** | Плановый `nodetool repair` | Фоново, без влияния на user path | Полное сравнение Merkle trees между репликами |

### 3.2. Матрица применения по сущностям

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy Repair | Обоснование |
|----------|----------------|-------------|---------------------|-------------|
| **Заказы** (текущий статус) | Вкл. (default) | **Вкл.** (`QUORUM` read) | Вкл., окно 7 дней | Статус `paid`/`cancelled` критичен; read repair ловит расхождение при чтении; AE — страховка для редко читаемых заказов |
| **Заказы** (история) | Вкл. | Выкл. / редко | **Вкл.**, еженедельно | История читается с `LOCAL_ONE`; не платим latency read repair на каждый list; AE восстановит «тихие» расхождения |
| **Корзины** | Вкл. | **Вкл.** | Вкл., 3–7 дней | Активная корзина — read-your-writes; stale items ломают checkout |
| **Остатки** | Вкл. | **Вкл.** + LWT | **Вкл.**, ежедневно в off-peak | Самые критичные данные; AE сверяет counter с фактом продаж; HH покрывает кратковременные падения узла в пик |

### 3.3. Настройки и компромиссы

**Hinted Handoff** — оставляем включённым для всех таблиц (дефолт Cassandra). `max_hint_window_in_ms = 10800000` (3 ч) достаточно для кратковременных сбоев в Black Friday. HH не заменяет repair: hints могут потеряться при долгом outage.

**Read Repair** — включаем выборочно там, где цена stale read выше latency:

```cql
-- Драйвер: read repair по умолчанию для QUORUM
-- Для истории заказов снижаем CL, чтобы не триггерить repair на каждый list
SELECT * FROM orders_by_customer
WHERE customer_id = ? LIMIT 20
-- consistency: LOCAL_ONE
```

Компромисс: read repair добавляет ~1–5 ms при обнаружении расхождения, но только на «горячих» чтениях (корзина, статус, остаток). На каталоге истории экономим latency.

**Anti-Entropy Repair** — обязателен для финансово значимых данных:

```bash
# Остатки — каждую ночь (off-peak)
nodetool repair -full mobile_world inventory_by_product_zone

# Заказы — еженедельно, инкрементально
nodetool repair mobile_world orders_by_customer orders_by_id

# Корзины — раз в 3 дня (TTL 14 дней, данные короткоживущие)
nodetool repair mobile_world carts_by_owner
```

`-full` для остатков оправдан: расхождение stock = oversell или недопродажа. Для заказов достаточно инкрементального repair по gc_grace_seconds.

### 3.4. Итог по компромиссам latency ↔ консистентность

```text
Высокая консистентность, выше latency:
  inventory (LWT + QUORUM + read repair + daily AE)
  carts checkout (QUORUM + read repair)
  order status после оплаты (QUORUM + read repair)

Допустима eventual, ниже latency:
  order history list (LOCAL_ONE + weekly AE)
  sessions в Redis (TTL, без Cassandra repair)
```

---

## 4. Итог

| Что | Решение |
|-----|---------|
| **В Cassandra** | заказы, корзины, остатки по зонам |
| **Вне Cassandra** | каталог товаров (MongoDB + CDN), сессии (Redis), платежи (внешний payment-провайдер) |
| **Partition keys** | `customer_id`, `order_id`, `owner_key`, `(product_id, geo_zone)` |
| **Hot partitions** | зонирование остатков; bucket для B2B-заказов; без `category` в partition key |
| **Решардинг** | добавление узла → только перенос token ranges, без полного rebalance MongoDB |
| **Целостность** | HH везде; read repair на checkout-пути; AE по расписанию, чаще для остатков |
| **MongoDB после миграции** | `orders`/`carts` — удалить после миграции; `products` — оставить шард и индекс `{ category, price }` — см. §5 |

Checkout остаётся **saga**: Cassandra — хранилище с высокой пропускной способностью записи; атомарность «корзина + заказ + stock» обеспечивается на уровне приложения с идемпотентными шагами и компенсацией.

---

## 5. Изменения в MongoDB после миграции

Полностью пересоздавать шардированный кластер MongoDB **не нужно**. После переноса write-heavy данных в Cassandra конфигурацию упрощаем: убираем коллекции, которые больше не храним в MongoDB, а `products` оставляем как read-heavy каталог.

### 5.1. Что меняется по коллекциям

| Коллекция | Было (задание 7) | После миграции |
|-----------|------------------|----------------|
| `orders` | Шард `{ customer_id, created_at }` | Данные в Cassandra → **drop**; `unshard` нужен только если оставляем архив |
| `carts` | Шард `{ owner_key }` | Данные в Cassandra → **drop**; `unshard` нужен только если оставляем архив |
| `products` | Шард `{ _id: "hashed" }`, поле `stock_by_zone` | **Остаётся**; `stock_by_zone` убираем — остатки в Cassandra |

### 5.2. Шардинг

**Пересоздавать с нуля не надо.** Если `orders` и `carts` после миграции больше не нужны в MongoDB, достаточно удалить коллекции:

```javascript
use mobile_world

db.orders.drop()
db.carts.drop()
```

Если бизнес хочет оставить `orders` / `carts` в MongoDB как архив, тогда можно снять их с шардирования, но это зависит от версии MongoDB и не требуется для сценария `drop`:

```javascript
db.adminCommand({ unshardCollection: "mobile_world.orders" })
db.adminCommand({ unshardCollection: "mobile_world.carts" })
```

**`products`** — шардирование `{ _id: "hashed" }` **оставляем**:

- карточка товара по `_id` — targeted read;
- каталог `{ category, price }` — scatter-gather, но без горячих `$inc` по остаткам нагрузка на шарды падает (источник hot shard из задания 8 ушёл в Cassandra).

Опционально: если каталог целиком влезает в один replica set и сильно кэшируется (Redis + CDN), можно отказаться от sharded cluster для MongoDB и оставить один RS — это упрощение, не обязательный шаг.

### 5.3. Индексы

| Индекс | Действие |
|--------|----------|
| `products`: `{ category: 1, price: 1 }` | **Оставить** — основной запрос каталога |
| `orders`: `{ customer_id: 1, _id: 1 }`, `{ _id: 1 }` | **Удаляются** вместе с коллекцией |
| `carts`: `{ owner_key, status }`, TTL по `expires_at`, индексы по `session_id` / `user_id` | **Удаляются** вместе с коллекцией |

Пересоздавать индекс `{ category: 1, price: 1 }` не нужно, если коллекция `products` не пересоздавалась.

Убираем поле `stock_by_zone` из документов каталога — остатки читаем из Cassandra:

```javascript
db.products.updateMany(
  {},
  { $unset: { stock_by_zone: "" } }
)
```

Перед checkout приложение запрашивает остаток из `inventory_by_product_zone` (Cassandra), а цену и `is_active` — из `products` (MongoDB).

### 5.4. Итог по MongoDB

| Вопрос | Ответ |
|--------|-------|
| Пересоздать шардирование целиком? | **Нет** |
| Удалить `orders` / `carts` из MongoDB после миграции? | **Да** |
| Делать `unshardCollection` для `orders` / `carts`? | **Только если оставляем их как архив** |
| Менять шард-ключ `products`? | **Нет** (можно оставить `{ _id: "hashed" }`) |
| Пересоздать индексы `products`? | **Нет** |
| Удалить индексы `orders` / `carts`? | **Да** (вместе с коллекциями) |

После миграции MongoDB — **read-heavy каталог**; write-heavy нагрузка (заказы, корзины, остатки) — в Cassandra.
