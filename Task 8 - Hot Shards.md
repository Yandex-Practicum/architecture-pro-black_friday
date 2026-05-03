# Выявление и устранение «горячих» шардов

## Проблема

При ranged-шардировании коллекции `products` по ключу `{ category: 1, _id: 1 }` все товары категории «Электроника» попадают в смежные чанки на одном шарде. 70% запросов приходится на эту категорию, создавая hot shard.

---

## 1. Метрики мониторинга

### 1.1. Распределение данных по шардам

```javascript
// Распределение чанков и объёма данных по шардам
db.products.getShardDistribution()

// Общий статус кластера: чанки, шарды, базы
sh.status()

// Количество чанков на каждом шарде
db.getSiblingDB("config").chunks.aggregate([
  { $match: { ns: "mobilnyimir.products" } },
  { $group: { _id: "$shard", count: { $sum: 1 } } }
])
```

**Что отслеживать:**
- Количество чанков на шарде — перекос > 20% сигнализирует о дисбалансе
- Объём данных (dataSize) на шарде — разброс > 30% требует внимания

### 1.2. Нагрузка на шарды (операции)

```javascript
// Счётчики операций на каждом шарде
db.serverStatus().opcounters
// { insert: N, query: N, update: N, delete: N, getmore: N, command: N }

// Текущие активные операции
db.currentOp({ active: true, secs_running: { $gt: 1 } })

// Статистика по коллекции
db.products.stats()
```

**Что отслеживать:**
- `opcounters.query` — кол-во запросов в секунду на шард
- `opcounters.update` — частота обновлений (списание остатков)
- Соотношение операций между шардами — при равномерной нагрузке должно быть ~равным

### 1.3. Латентность и очереди

```javascript
// Задержки на блокировках
db.serverStatus().globalLock
// { currentQueue: { total, readers, writers }, activeClients: { total, readers, writers } }

// Статистика WiredTiger (кеш, I/O)
db.serverStatus().wiredTiger.cache
```

**Что отслеживать:**
- `globalLock.currentQueue.total` — очередь > 0 стабильно → шард перегружен
- `wiredTiger.cache["bytes read into cache"]` — резкий рост → данные не помещаются в RAM
- Время ответа (p95, p99) на запросы к каждому шарду

### 1.4. Активность балансировщика

```javascript
// История миграций чанков
db.getSiblingDB("config").changelog.find({ what: "moveChunk.commit" }).sort({ time: -1 }).limit(10)

// Состояние балансировщика
sh.getBalancerState()
sh.isBalancerRunning()
```

**Что отслеживать:**
- Частота миграций — слишком частые миграции = постоянный дисбаланс
- Ошибки миграций — неуспешные попытки перемещения чанков

### Сводная таблица метрик

| Метрика | Команда / источник | Порог тревоги |
|---------|-------------------|---------------|
| Перекос чанков между шардами | `getShardDistribution()` | > 20% разницы |
| Перекос объёма данных | `getShardDistribution()` | > 30% разницы |
| Кол-во запросов/сек на шард | `serverStatus().opcounters` | Один шард > 2x среднего |
| Очередь блокировок | `serverStatus().globalLock` | `currentQueue.total` > 0 постоянно |
| Латентность p95 | Мониторинг (Prometheus/Grafana) | > 100ms при норме < 20ms |
| Cache miss WiredTiger | `serverStatus().wiredTiger.cache` | `pages read into cache` растёт |
| Replication lag | `rs.status().members[].optimeDate` | Lag > 10 сек |

---

## 2. Механизмы устранения дисбаланса

### 2.1. Ручное разбиение и миграция чанков (быстрое решение)

Если категория «Электроника» сконцентрирована в нескольких крупных чанках на одном шарде, можно разбить их и мигрировать часть на другие шарды.

```javascript
// Найти чанки категории "electronics"
db.getSiblingDB("config").chunks.find({
  ns: "mobilnyimir.products",
  "min.category": { $lte: "electronics" },
  "max.category": { $gte: "electronics" }
})

// Разбить крупный чанк пополам
sh.splitAt("mobilnyimir.products", { category: "electronics", _id: ObjectId("mid_point_id") })

// Мигрировать чанк на другой шард
sh.moveChunk("mobilnyimir.products", { category: "electronics", _id: ObjectId("...") }, "shard2ReplSet")
```

### 2.2. Зонное шардирование (tag-aware sharding)

Распределить категорию «Электроника» по нескольким шардам, назначив зоны.

```javascript
// Добавить теги шардам
sh.addShardTag("shard1ReplSet", "electronics_A")
sh.addShardTag("shard2ReplSet", "electronics_B")
sh.addShardTag("shard1ReplSet", "other")
sh.addShardTag("shard2ReplSet", "other")

// Назначить диапазоны: первая половина электроники на shard1, вторая на shard2
sh.addTagRange("mobilnyimir.products",
  { category: "electronics", _id: MinKey },
  { category: "electronics", _id: ObjectId("mid_point_id") },
  "electronics_A"
)
sh.addTagRange("mobilnyimir.products",
  { category: "electronics", _id: ObjectId("mid_point_id") },
  { category: "electronics", _id: MaxKey },
  "electronics_B"
)
```

Балансировщик автоматически мигрирует чанки в соответствии с зонами.

### 2.3. Изменение шард-ключа (кардинальное решение)

Если проблема горячих категорий системная, стоит перейти на хэшированный ключ для равномерного распределения.

```javascript
// MongoDB 7.0+: unshardCollection + повторное шардирование
db.adminCommand({ unshardCollection: "mobilnyimir.products" })

// Пересоздать с хэшированным ключом
sh.shardCollection("mobilnyimir.products", { _id: "hashed" })
```

**Компромисс:** запросы по категории станут scatter-gather, но нагрузка будет равномерной. Для компенсации — использовать Redis-кеш для популярных категорий.

### 2.4. Настройка балансировщика

```javascript
// Уменьшить размер чанка для более гранулярного распределения (по умолчанию 128 МБ)
db.getSiblingDB("config").settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 64 } },
  { upsert: true }
)

// Настроить окно балансировки (чтобы миграции шли в нерабочее время)
db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)
```

### 2.5. Добавление шардов

При стабильном росте нагрузки — горизонтальное масштабирование:

```javascript
// Добавить третий шард
sh.addShard("shard3ReplSet/shard3-1:27017,shard3-2:27017,shard3-3:27017")

// Балансировщик автоматически начнёт перемещать чанки на новый шард
```

---

## 3. Рекомендуемый план действий

| Шаг | Действие | Когда применять |
|-----|----------|-----------------|
| 1 | Настроить мониторинг метрик (opcounters, latency, chunk distribution) | Сразу, превентивно |
| 2 | Уменьшить размер чанка до 64 МБ | При первых признаках перекоса |
| 3 | Разбить крупные чанки и мигрировать вручную | Быстрое снятие нагрузки с hot shard |
| 4 | Настроить зонное шардирование для горячих категорий | Устойчивое решение при ranged-ключе |
| 5 | Добавить шард | При общем росте нагрузки |
| 6 | Перешардировать на hashed-ключ | Если hot spots возникают регулярно в разных категориях |
