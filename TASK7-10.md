# Проектирование схем коллекций для шардирования данных

## Коллекция `orders`

### Схема и валидация
```javascript
db.createCollection("orders", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "_id",
        "user_id",
        "created_at",
        "items",
        "status",
        "total_amount",
        "geo_zone"
      ],
      properties: {
        _id: { bsonType: "objectId" },
        user_id: { bsonType: "objectId" },
        created_at: { bsonType: "date" },
        items: {
          bsonType: "array",
          minItems: 1,
          items: {
            bsonType: "object",
            required: ["product_id", "quantity", "price"],
            properties: {
              product_id: { bsonType: "objectId" },
              quantity: { bsonType: "int", minimum: 1 },
              price: { bsonType: "decimal", minimum: 0 }
            }
          }
        },
        status: {
          bsonType: "string",
          enum: ["created", "confirmed", "paid", "done", "cancelled"]
        },
        total_amount: { bsonType: "decimal", minimum: 0 },
        geo: { bsonType: "string", minLength: 1 }
      }
    }
  }
});
```

### Основные операции
- Быстрое создание заказов с одновременным списанием остатков.
- Поиск истории заказов конкретного пользователя.
- Отображение статуса заказа.

### Выбор стратегии шардирования и шард-ключа
- Кандидаты шард-ключа: `_id`, `user_id`.
- Выбор: хэшированное шардирование с шард-ключом `user_id`.
- Причина: высокая производительность создания заказов, а также равномерное распределение данных (все заказы пользователя в одном шарде), что эффективно при поиске.

## Коллекция `products`

### Схема и валидация
```javascript
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "_id",
        "name",
        "category",
        "price",
        "stock_by_geo"
      ],
      properties: {
        _id: { bsonType: "objectId" },
        name: { bsonType: "string", minLength: 1 },
        category: { bsonType: "string", minLength: 1 },
        price: { bsonType: "decimal", minimum: 0 },
        stock_by_geo: {
          bsonType: "object",
          additionalProperties: { bsonType: "int", minimum: 0 }
        },
        attrs: {
          bsonType: "object",
          additionalProperties: { bsonType: ["string", "int", "double", "bool"] }
        }
      }
    }
  }
});
```

### Основные операции
- Частые обновления остатков при покупках.
- Поиск товаров по категориям и фильтрация по диапазону цен.
- Описание товара на странице продукта.

### Выбор стратегии шардирования и шард-ключа
- Кандидаты шард-ключа: `_id`, `category`, `price`.
- Выбор: диапазонное шардирование с шард-ключом `price`.
- Причина: поиск товаров является наиболее важной операцией, поэтому необходима быстрота его выполнения.

## Коллекция `carts`

### Схема и валидация
```javascript
db.createCollection("carts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      oneOf: [
        {
          required: [
            "user_id",
            "items",
            "status",
            "created_at",
            "updated_at",
            "expires_at"
          ],
        },
        {
          required: [
            "session_id",
            "items",
            "status",
            "created_at",
            "updated_at",
            "expires_at"
          ],
        },
      ],
      properties: {
        user_id: { bsonType: "objectId" },
        session_id: { bsonType: "objectId" },
        items: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["product_id", "quantity"],
            properties: {
              product_id: { bsonType: "string" },
              quantity: { bsonType: "int", minimum: 1 }
            }
          }
        },
        status: { bsonType: "string", enum: ["active", "ordered", "abandoned"] },
        created_at: { bsonType: "date" },
        updated_at: { bsonType: "date" },
        expires_at: { bsonType: "date" }
      }
    }
  }
});
```

### Основные операции
- Создание корзины, когда заходит гость или новый пользователь.
- Получение текущей корзины по фильтру { session_id, status:"active" } или { - user_id, status:"active" }.
- Добавление или замена товара в корзине.
- Удаление товара из корзины.
- Слияние гостевой корзины в пользовательскую, если пользователь залогинится:
    - прочитать гостевую { session_id, status:"active" };
    - добавить её items в корзину { user_id, status:"active" };
    - отметить гостевую как abandoned.
- Отметка корзины как заказанной.

### Выбор стратегии шардирования и шард-ключа
- Кандидаты шард-ключа: `user_id`, `session_id`, `status`.
- Выбор: хэшированное шардирование с шард-ключом `status`.
- Причина: почти все операции подразумевают работу с корзиной в статусе `active`, поэтому такой выбор позволить повысить производительность операций.

# Выявление и устранение «горячих» шардов

## Проблема
В категории «Электроника» может быть больше всего запросов (например, около 70%).  
Из-за этого один из шардов начинает работать намного сильнее других: растет задержка и нагрузка.

## Что мониторить
- доля операций по шарду (read/write);
- средняя и p95 задержка по шардам;
- количество чанков и объем данных по шардам;
- репликационная задержка.

## Простые пороги для алертов
- один шард держит больше 50% операций дольше 10 минут;
- p95 задержка на одном шарде в 2 раза выше, чем у остальных;
- разница по количеству чанков между самым большим и самым маленьким шардом больше 20%.

## Как устранять дисбаланс
1. Проверить и включить балансировщик.
2. Если не помогает, добавить новый шард.
3. Если проблема повторяется, сменить шард-ключ у `products`.

## Примеры команд и настроек MongoDB
```javascript
use somedb

// Распределение данных по шардам
db.products.getShardDistribution()

// Количество чанков по шардам
use config

db.chunks.aggregate([
  { $group: { _id: "$shard", chunks: { $sum: 1 } } },
  { $sort: { chunks: -1 } }
])

// Балансировщик
sh.getBalancerState()
sh.isBalancerRunning()
sh.setBalancerState(true)
sh.startBalancer()

// Окно балансировки (ночью)
use settings

db.settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "01:00", stop: "06:00" } } },
  { upsert: true }
)

// Добавление нового шарда
sh.addShard("rs3/shard3_1:27025,shard3_2:27026,shard3_3:27027")

// Resharding products (пример более устойчивого ключа)
db.products.createIndex({ category: 1, _id: "hashed" })
db.adminCommand({
  reshardCollection: "somedb.products",
  key: { category: 1, _id: "hashed" }
})
```

# Настройка чтения с реплик и консистентность

## Таблица чтения по коллекциям

| Коллекция | Операция чтения | Откуда читать | Допустимая задержка репликации | Обоснование |
|---|---|---|---|---|
| `products` | Каталог (список товаров, фильтры по категории/цене) | `secondary` | до 30 сек | Каталог читается очень часто, небольшая задержка допустима, перенос чтения на secondary снижает нагрузку на primary. |
| `products` | Проверка доступности перед оформлением заказа | `primary` | 0 сек | Нужны строго актуальные остатки, иначе риск продать товар, которого уже нет. |
| `orders` | История заказов пользователя | `secondary` | до 5 сек | Для истории заказов небольшая задержка приемлема, можно разгрузить primary. |
| `orders` | Статус заказа сразу после оплаты | `primary` | 0 сек | Пользователь должен сразу видеть реальный статус, устаревшее значение недопустимо. |
| `carts` | Получение активной корзины (`status=active`) | `primary` | 0 сек | Корзина часто меняется, чтение с secondary может показать старые данные (неверный состав/количество товаров). |

# Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## 10.1. Какие данные переносить в Cassandra

| Данные | Критичность | Cassandra как основное хранилище | Обоснование |
|---|---|---|---|
| Заказы | высокая | нет | Операционный заказ связан со сменой статуса, оплатой и проверкой доступности товара; для него важнее строгая консистентность и простой сценарий обновления в текущей БД. |
| История заказов | высокая | да | История заказов append-only, хорошо ложится на денормализованные таблицы с бакетами по времени. |
| Корзины | высокая по latency | нет | Корзина естественно представляется одним документом, а атомарные обновления массива товаров и слияние гостевой/пользовательской корзины проще и безопаснее оставить в текущей БД. |
| Пользовательские сессии | высокая по latency | да | Короткоживущие данные, простое чтение по ключу, естественный TTL. |
| Товары | высокая по чтению | частично | Каталог и карточка товара хорошо подходят для Cassandra, но источник истины для актуальных остатков и проверки доступности перед оформлением заказа лучше оставить в текущей БД. |

## Целевая конфигурация кластера

| Параметр | Выбор |
|---|---|
| Keyspace | `somedb` |
| Стратегия репликации | `NetworkTopologyStrategy` |
| Репликация | `dc1: 3`, `dc2: 3` |
| Запись критичных данных | `LOCAL_QUORUM` |
| Чтение критичных данных | `LOCAL_QUORUM` |
| Чтение каталога и истории | `LOCAL_ONE` |
| Масштабирование | `vnodes` + `Murmur3Partitioner` |

```sql
CREATE KEYSPACE IF NOT EXISTS somedb
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
}
AND durable_writes = true;
```

Такой вариант сохраняет геораспределённость и уменьшает влияние изменения топологии: при добавлении ноды Cassandra переносит только часть token range, а не делает полное перераспределение всех данных, как в предыдущем решении.

## 10.2. Концептуальная модель

| Таблица | Основной запрос | Partition key | Clustering key | Ключевые поля | Защита от горячих партиций |
|---|---|---|---|---|---|
| `products_by_id` | Карточка товара и каталожные данные | `product_id` | — | `name`, `category`, `price`, `stock_preview`, `attrs_json`, `updated_at` | Равномерное распределение по `product_id`. |
| `products_by_category_bucket` | Каталог по категории и диапазону цены | `(category, catalog_bucket)` | `price`, `product_id` | `name`, `price`, `stock_preview`, `updated_at` | Горячая категория разбивается на 16 бакетов, чтение идёт fan-out по бакетам. |
| `order_history_by_user` | История заказов пользователя | `(user_id, month_bucket)` | `created_at DESC`, `order_id` | `status`, `total_amount`, `geo_zone` | Бакет `YYYYMM` ограничивает размер партиции даже у активных пользователей. |
| `sessions_by_id` | Поиск и валидация сессии | `session_id` | — | `user_id`, `created_at`, `last_seen_at`, `expires_at`, `device_json` | Случайный `session_id` и TTL дают равномерное распределение. |

Минимальные примеры таблиц:

```sql
CREATE TABLE IF NOT EXISTS somedb.products_by_id (
  product_id uuid PRIMARY KEY,
  name text,
  category text,
  price decimal,
  stock_preview map<text, int>,
  attrs_json text,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS somedb.products_by_category_bucket (
  category text,
  catalog_bucket smallint,
  price decimal,
  product_id uuid,
  name text,
  stock_preview map<text, int>,
  updated_at timestamp,
  PRIMARY KEY ((category, catalog_bucket), price, product_id)
) WITH CLUSTERING ORDER BY (price ASC, product_id ASC);

CREATE TABLE IF NOT EXISTS somedb.order_history_by_user (
  user_id uuid,
  month_bucket text,
  created_at timestamp,
  order_id uuid,
  status text,
  total_amount decimal,
  geo_zone text,
  PRIMARY KEY ((user_id, month_bucket), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);

CREATE TABLE IF NOT EXISTS somedb.sessions_by_id (
  session_id uuid PRIMARY KEY,
  user_id uuid,
  created_at timestamp,
  last_seen_at timestamp,
  expires_at timestamp,
  device_json text
);
```

## 10.3. Стратегии восстановления целостности

| Таблица/сущность | Чтение / запись | Стратегии | Обоснование |
|---|---|---|---|
| `order_history_by_user` | `LOCAL_ONE / LOCAL_QUORUM` | `Hinted Handoff` + `Read Repair` + ночной `Anti-Entropy Repair` | История может быть немного устаревшей, зато популярные разделы будут самовосстанавливаться при чтении. |
| `products_by_category_bucket` | `LOCAL_ONE / LOCAL_QUORUM` | `Hinted Handoff` + `Read Repair` + регулярный `Anti-Entropy Repair` | Для каталога допустима небольшая задержка, read repair подходит для read-heavy нагрузки. |
| `products_by_id` | `LOCAL_ONE / LOCAL_QUORUM` | `Hinted Handoff` + `Read Repair` + регулярный `Anti-Entropy Repair` | Карточка товара относится к каталожной read-model, поэтому допустима небольшая рассинхронизация. |
| `sessions_by_id` | `LOCAL_QUORUM / LOCAL_QUORUM` | `Hinted Handoff` + ежедневный `Anti-Entropy Repair`, без `Read Repair` | Сессии короткоживущие, лишний read repair только увеличит задержку в auth-path. |

Кратко по выбору стратегий:
- `Hinted Handoff` включён для всех таблиц: закрывает кратковременные недоступности узлов без участия клиента.
- `Read Repair` используется только там, где допустима небольшая добавка к latency и много повторных чтений: каталог и история заказов.
- `Anti-Entropy Repair` обязателен для всех таблиц, перенесённых в Cassandra; операционные заказы и корзины остаются под механизмами консистентности текущей БД.

Минимальные примеры команд:

```bash
nodetool repair somedb order_history_by_user
nodetool repair somedb products_by_category_bucket
nodetool repair somedb sessions_by_id
```

Что мониторить после миграции:
- `PendingHints` и объём hints по узлам: рост означает, что одна из реплик недоступна слишком долго.
- p95/p99 latency по таблицам и по consistency level: если растёт `LOCAL_QUORUM`, проблема уже влияет на критичные запросы.
- Возраст последнего successful repair по keyspace/table: если repair не выполнялся по графику, возрастает риск расхождения реплик.
- Размер partition и количество tombstones для `products_by_category_bucket` и `order_history_by_user`: рост означает, что бакеты выбраны слишком крупно.

Действия при проблемах:
1. При росте hints вернуть узел в кластер или перераспределить нагрузку, затем дождаться доставки hints.
2. При росте latency на каталоге увеличить число `catalog_bucket`.
3. При росте partition size у истории заказов уменьшить временной бакет, например перейти с `YYYYMM` на `YYYYWW`.
4. При отставании repair запустить внеочередной `nodetool repair` для проблемной таблицы.
