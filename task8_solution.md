# Задание 8. Выявление и устранение горячих шардов

## Метрики мониторинга

### Метрики

| Метрика | Что показывает | Как использовать |
| --- | --- | --- |
| CPU per node | Перегрузку конкретного узла | Алерт при стабильных `> 75%` |
| Memory / WiredTiger cache | Хватает ли памяти под рабочий набор | Алерт при частом вытеснении страниц из cache |
| Disk IOPS | Упирается ли MongoDB в диск | Сравнивать IOPS между шардами |
| Network in/out | Перекос сетевой нагрузки | Искать shard, через который идет большая часть трафика |
| opcounters | Количество insert/query/update/delete | Сравнивать операции по шардам |
| operation latency p95/p99 | Пользовательская деградация | Алерт при росте p95/p99 |
| currentOp queue | Очередь активных операций | Искать долгие операции и блокировки |

Пример команды:

```javascript
db.serverStatus().opcounters
db.serverStatus().wiredTiger.cache
db.serverStatus().connections
```

Долгие операции:

```javascript
db.currentOp({
  active: true,
  secs_running: { $gte: 3 }
})
```

### Метрики распределения данных

| Метрика | Что показывает |
| --- | --- |
| Количество chunks на shard | Равномерность распределения chunks |
| Размер данных на shard | Равномерность по объему |
| Количество документов на shard | Равномерность по документам |
| jumbo chunks | Chunks, которые MongoDB не может нормально перенести |
| migrations | Активность балансировщика |

Команды:

```javascript
sh.status()

use somedb
db.products.getShardDistribution()
db.orders.getShardDistribution()
db.carts.getShardDistribution()
```

Проверка chunks по коллекции:

```javascript
use config

db.chunks.aggregate([
  { $match: { ns: "somedb.products" } },
  { $group: { _id: "$shard", chunks: { $sum: 1 } } },
  { $sort: { chunks: -1 } }
])
```

### Метрики по популярным категориям

Так как проблема возникла из-за `electronics`, важно смотреть не только на физическое распределение документов, но и на бизнес-нагрузку.

Метрики:

- запросы каталога по категориям: `electronics`, `books`, `home`, `audio`;
- p95 latency по каждой категории;
- cache hit ratio по каждой категории;
- количество обновлений остатков по категории;
- доля запросов категории, попавшая на каждый шард;
- топ product_id по просмотрам и обновлениям.

Пример агрегации для оценки объема товаров по категориям:

```javascript
use somedb

db.products.aggregate([
  {
    $group: {
      _id: "$category_id",
      products: { $sum: 1 },
      avg_price: { $avg: "$price" }
    }
  },
  { $sort: { products: -1 } }
])
```

## Диагностика горячей категории

### 1. Проверить shard key

```javascript
use config

db.collections.find(
  { _id: "somedb.products" },
  { key: 1, unique: 1 }
)
```

Если у `products` shard key выглядит так:

```javascript
{ category_id: 1 }
```

то это рискованный вариант: популярная категория может создать горячий диапазон.

Лучше использовать ключ из задания 7:

```javascript
{ category_id: 1, product_id: "hashed" }
```

Так категория остается частью ключа, но товары внутри популярной категории распределяются лучше.

### 2. Проверить распределение коллекции

```javascript
use somedb
db.products.getShardDistribution()
```

Если один шард держит большую часть `products`, нужно проверить chunks:

```javascript
use config

db.chunks.find(
  { ns: "somedb.products" },
  { min: 1, max: 1, shard: 1, jumbo: 1 }
).sort({ shard: 1 })
```

### 3. Проверить балансировщик

```javascript
sh.getBalancerState()
sh.isBalancerRunning()
sh.status()
```

Включить балансировщик:

```javascript
sh.setBalancerState(true)
```

## Механизмы устранения дисбаланса

### 1. Автоматический balancer MongoDB

MongoDB умеет переносить chunks между шардами. Это базовый механизм перераспределения.

Команды:

```javascript
sh.setBalancerState(true)
sh.startBalancer()
sh.status()
```

Для production лучше ограничить окно балансировки, чтобы миграции не мешали пиковым продажам:

```javascript
use config

db.settings.updateOne(
  { _id: "balancer" },
  {
    $set: {
      activeWindow: {
        start: "02:00",
        stop: "05:00"
      }
    }
  },
  { upsert: true }
)
```

### 2. Правильный shard key для products

Если перегрузка связана с `electronics`, главный способ профилактики - не шардировать товары только по категории.

Рекомендуемый ключ:

```javascript
{ category_id: 1, product_id: "hashed" }
```

Команды для новой коллекции:

```javascript
use somedb

db.products.createIndex({ category_id: 1, product_id: "hashed" })
sh.shardCollection("somedb.products", { category_id: 1, product_id: "hashed" })
```

Если коллекция уже зашардирована неудачно, нужно делать resharding:

```javascript
sh.reshardCollection(
  "somedb.products",
  { category_id: 1, product_id: "hashed" }
)
```

После resharding нужно проверить распределение:

```javascript
use somedb
db.products.getShardDistribution()
```

### 3. Предварительное разбиение chunks

Для больших коллекций полезно заранее подготовить chunks, чтобы MongoDB не создавала их только после роста нагрузки.

Для hashed shard key MongoDB обычно распределяет chunks автоматически. Если используется range shard key, можно использовать split:

```javascript
sh.splitAt(
  "somedb.products",
  { category_id: "electronics", product_id: "product_500000" }
)
```

Потом chunk можно перенести:

```javascript
sh.moveChunk(
  "somedb.products",
  { category_id: "electronics", product_id: "product_500000" },
  "shard2"
)
```

### 4. Zone sharding для региональной нагрузки

Если перегрузка связана не только с категорией, но и с геозоной, можно добавить отдельную модель распределения по зонам. Например, товары и остатки для разных регионов можно держать ближе к нужным shard replica set.

Пример настройки зон:

```javascript
sh.addShardToZone("shard1", "msk")
sh.addShardToZone("shard2", "ekb")
```

Пример диапазонов:

```javascript
sh.updateZoneKeyRange(
  "somedb.products",
  { geo_zone: "msk", category_id: MinKey },
  { geo_zone: "msk", category_id: MaxKey },
  "msk"
)
```

### 5. Кеширование популярных категорий

Даже при правильном распределении данных `electronics` может создавать много одинаковых чтений. Поэтому для каталога нужен кеш:

- кешировать список товаров категории с фильтрами;
- отдельно кешировать карточку товара;
- делать короткий TTL, например `30-60 секунд`;
- инвалидировать кеш при изменении цены или остатков.

Пример ключей Redis:

```text
catalog:electronics:price_10000_60000:page_1
product:product_100
stock:product_100:ekb
```

## Автоматическое реагирование

### Правило 1. Включить balancer постоянно

Balancer должен быть включен, но активное окно можно поставить на ночь:

```javascript
sh.setBalancerState(true)
```

### Правило 2. Алерты по перекосу нагрузки

Пример условий для алерта:

- `opcounters.query` на одном шарде больше `2x` среднего по шардам в течение 10 минут;
- p95 latency чтения на shard primary больше `100 мс` в течение 10 минут;
- CPU primary больше `80%` в течение 10 минут;
- один shard хранит больше `60%` chunks коллекции `products`;
- cache hit ratio для категории `electronics` меньше `70%`.

### Правило 3. Автоматический runbook

При алерте по горячему шарду:

1. Проверить `db.products.getShardDistribution()`.
2. Проверить `sh.status()` и состояние balancer.
3. Проверить, не появились ли jumbo chunks.
4. Если balancer выключен - включить.
5. Если shard key неудачный - запланировать `reshardCollection`.
6. Если проблема срочная - вручную split/moveChunk для горячего диапазона.
7. Проверить cache hit ratio для популярных категорий.

## Пример итоговой настройки для products

```javascript
use somedb

db.products.createIndex({ category_id: 1, product_id: "hashed" })
db.products.createIndex({ category_id: 1, price: 1 })
db.products.createIndex({ product_id: 1 })

sh.shardCollection(
  "somedb.products",
  { category_id: 1, product_id: "hashed" }
)
```

Проверка:

```javascript
sh.status()
db.products.getShardDistribution()
```
