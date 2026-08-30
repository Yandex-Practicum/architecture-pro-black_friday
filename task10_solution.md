# Задание 10. Миграция на Cassandra

## Задание 10.1. Какие данные переносить

| Данные | Критичность | Cassandra подходит | Почему |
| --- | --- | --- | --- |
| История заказов пользователя | высокая | да | Много чтений по пользователю, данные почти не меняются после создания |
| События заказов и статусы | высокая | да | Хорошо ложатся в append-only модель, можно быстро писать события |
| Пользовательские сессии | средняя | да | Много быстрых чтений/записей по `session_id`, подходит TTL |
| Корзины | высокая | частично | Хорошо для активной корзины по ключу, но оформление заказа требует аккуратной проверки остатков |
| Остатки товаров | очень высокая | осторожно | Частые обновления, риск oversell. Нужны легковесные транзакции или отдельный сервис резервирования |
| Каталог товаров | средняя | частично | Для чтения по категориям подходит, но сложные фильтры и поиск лучше оставить в поисковом движке |
| Платежи | очень высокая | нет как основная БД | Нужна строгая консистентность и транзакционная модель |

Для Cassandra выбираем:

- `orders_by_user` — история заказов пользователя;
- `order_by_id` — быстрый доступ к заказу по идентификатору;
- `order_events_by_order` — события и история статусов заказа;
- `products_by_category` — чтение каталога по категории и цене;
- `product_by_id` — карточка товара;
- `carts_by_owner` — активная корзина пользователя или гостя;
- `sessions_by_id` — пользовательские сессии с TTL.

## Задание 10.2. Модель данных и ключи

### orders_by_user

Запрос: показать историю заказов пользователя.

```sql
CREATE TABLE orders_by_user (
  user_id text,
  order_month text,
  created_at timestamp,
  order_id uuid,
  status text,
  total_amount decimal,
  geo_zone text,
  items text,
  PRIMARY KEY ((user_id, order_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

Ключи:

- partition key: `(user_id, order_month)`;
- clustering key: `created_at`, `order_id`.

Почему так:

- запрос истории конкретного пользователя попадает в одну партицию за месяц;
- `order_month` ограничивает размер партиции, чтобы у активных пользователей история не росла бесконечно;
- сортировка по `created_at DESC` сразу отдает последние заказы первыми.

### order_by_id

Запрос: открыть конкретный заказ по `order_id`.

```sql
CREATE TABLE order_by_id (
  order_id uuid PRIMARY KEY,
  user_id text,
  created_at timestamp,
  status text,
  total_amount decimal,
  geo_zone text,
  items text
);
```

Почему так:

- `order_id` равномерно распределяется по token ring, если используется UUID;
- быстрый point lookup без обхода истории пользователя.

### order_events_by_order

Запрос: посмотреть события и статусы заказа.

```sql
CREATE TABLE order_events_by_order (
  order_id uuid,
  event_time timestamp,
  event_id timeuuid,
  event_type text,
  status text,
  payload text,
  PRIMARY KEY ((order_id), event_time, event_id)
) WITH CLUSTERING ORDER BY (event_time ASC, event_id ASC);
```

Почему так:

- события заказа пишутся append-only;
- чтение всех событий конкретного заказа идет по одному partition key;
- модель хорошо подходит для восстановления текущего статуса и аудита.

### products_by_category

Запрос: показать товары категории с фильтром по цене.

```sql
CREATE TABLE products_by_category (
  category_id text,
  price_bucket int,
  price decimal,
  product_id uuid,
  name text,
  attributes map<text, text>,
  PRIMARY KEY ((category_id, price_bucket), price, product_id)
) WITH CLUSTERING ORDER BY (price ASC, product_id ASC);
```

Ключи:

- partition key: `(category_id, price_bucket)`;
- clustering key: `price`, `product_id`.

Почему так:

- каталог обычно читается по категории;
- `price_bucket` дробит популярную категорию, например `electronics`, чтобы не получить одну огромную горячую партицию;
- сортировка по цене работает внутри бакета.

Пример бакетов:

| Цена | `price_bucket` |
| --- | --- |
| 0-9999 | `0` |
| 10000-19999 | `1` |
| 20000-29999 | `2` |

Риск: если 70% запросов идут в `electronics` и один ценовой бакет, эта партиция тоже может стать горячей. Тогда добавляем дополнительный read bucket:

```sql
PRIMARY KEY ((category_id, price_bucket, bucket_id), price, product_id)
```

`bucket_id` можно считать от `product_id`, например `hash(product_id) % 16`.

### product_by_id

Запрос: открыть карточку товара.

```sql
CREATE TABLE product_by_id (
  product_id uuid PRIMARY KEY,
  category_id text,
  name text,
  price decimal,
  attributes map<text, text>,
  updated_at timestamp
);
```

Почему так:

- карточка товара читается по `product_id`;
- UUID хорошо распределяет данные;
- таблица не зависит от категории, поэтому популярная категория не перегружает одну партицию.

### carts_by_owner

Запрос: получить активную корзину пользователя или гостя.

```sql
CREATE TABLE carts_by_owner (
  owner_key text,
  status text,
  updated_at timestamp,
  cart_id uuid,
  items map<uuid, int>,
  expires_at timestamp,
  PRIMARY KEY ((owner_key), status, cart_id)
);
```

`owner_key`:

- для пользователя: `user:user_12345`;
- для гостя: `session:8f53b2e1`.

Почему так:

- активная корзина читается по одному ключу;
- гостевые и пользовательские корзины работают одинаково;
- Cassandra TTL можно использовать для автоматического удаления старых гостевых корзин.

Пример записи гостевой корзины на 2 дня:

```sql
INSERT INTO carts_by_owner (
  owner_key, status, updated_at, cart_id, items, expires_at
)
VALUES (
  'session:8f53b2e1',
  'active',
  toTimestamp(now()),
  uuid(),
  {},
  '2026-09-01T10:00:00Z'
)
USING TTL 172800;
```

### sessions_by_id

Запрос: найти сессию пользователя.

```sql
CREATE TABLE sessions_by_id (
  session_id text PRIMARY KEY,
  user_id text,
  created_at timestamp,
  updated_at timestamp,
  expires_at timestamp,
  data map<text, text>
);
```

Пример записи с TTL:

```sql
INSERT INTO sessions_by_id (
  session_id, user_id, created_at, updated_at, expires_at, data
)
VALUES (
  '8f53b2e1',
  'user_12345',
  toTimestamp(now()),
  toTimestamp(now()),
  '2026-09-01T10:00:00Z',
  {'device': 'mobile'}
)
USING TTL 172800;
```

Почему так:

- `session_id` хорошо распределяется;
- сессии короткоживущие, TTL подходит естественно;
- чтение всегда point lookup.

## Как модель снижает риск горячих партиций

| Таблица | Что защищает от hot partition |
| --- | --- |
| `orders_by_user` | месячный бакет `order_month` |
| `order_by_id` | UUID как partition key |
| `order_events_by_order` | события ограничены одним заказом |
| `products_by_category` | `price_bucket`, при необходимости `bucket_id` |
| `product_by_id` | UUID как partition key |
| `carts_by_owner` | `owner_key` распределяет пользователей и гостей |
| `sessions_by_id` | `session_id` распределяет сессии |

При добавлении Cassandra-узлов не нужно полностью перераспределять все данные вручную. Узел получает часть token range, а кластер постепенно стримит только нужные диапазоны. Это заметно мягче, чем активное перемещение range-based chunks в пиковую нагрузку.

## Задание 10.3. Стратегии восстановления целостности

### Hinted Handoff

Hinted Handoff помогает, когда реплика временно недоступна. Координатор сохраняет hint и позже доставляет запись на восстановившийся узел.

Где использовать:

| Сущность | Использовать | Почему |
| --- | --- | --- |
| `sessions_by_id` | да | Сессии короткоживущие, важна доступность записи |
| `carts_by_owner` | да | Корзина должна сохраняться даже при временной проблеме реплики |
| `orders_by_user` | да | Заказ должен попасть на все реплики после восстановления |
| `order_events_by_order` | да | События заказа важны для аудита |
| `products_by_category` | да | Обновления каталога должны доехать до реплик |

Пример настройки:

```yaml
hinted_handoff_enabled: true
max_hint_window: 3h
```

Компромисс: latency почти не растет, но если узел лежит дольше окна hints, нужна repair-процедура.

### Read Repair

Read Repair исправляет расхождения во время чтения. Подходит для данных, которые часто читаются и где полезно быстро лечить небольшие расхождения.

Где использовать:

| Сущность | Стратегия |
| --- | --- |
| `product_by_id` | можно использовать, карточки часто читаются |
| `products_by_category` | можно использовать осторожно, чтобы не ухудшить latency каталога |
| `orders_by_user` | осторожно, лучше полагаться на `LOCAL_QUORUM` и repair |
| `sessions_by_id` | обычно не нужно, TTL и частые обновления создают лишнюю нагрузку |
| `carts_by_owner` | лучше не делать ставку на read repair, нужна свежесть через `LOCAL_QUORUM` |

Компромисс: помогает консистентности, но может увеличить latency чтения. Для горячего каталога лучше не перегружать чтения, а использовать `LOCAL_QUORUM`, кеш и регулярный repair.

### Anti-Entropy Repair

Anti-Entropy Repair сравнивает данные между репликами и восстанавливает расхождения. Это основная регулярная процедура для долгосрочной целостности.

Где использовать:

| Сущность | Частота |
| --- | --- |
| `orders_by_user` | регулярно, например ежедневно или по расписанию вне пика |
| `order_by_id` | регулярно |
| `order_events_by_order` | регулярно, особенно важно для аудита |
| `products_by_category` | регулярно после массовых обновлений каталога |
| `product_by_id` | регулярно |
| `carts_by_owner` | можно реже, так как данные короткоживущие |
| `sessions_by_id` | обычно не нужно часто, из-за TTL |

Пример команды:

```shell
nodetool repair mobile_world orders_by_user
nodetool repair mobile_world order_by_id
nodetool repair mobile_world order_events_by_order
```

Для больших таблиц лучше запускать repair по диапазонам и не в пик:

```shell
nodetool repair -pr mobile_world products_by_category
```

Компромисс: repair потребляет CPU, сеть и диск, поэтому его нельзя запускать без расписания во время максимальной нагрузки.
