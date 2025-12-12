# Предотвращение и устранение «горячих» шардов в MongoDB

## 1. Контекст проблемы

В коллекции `products` есть популярная категория **«Электроника»**, на которую приходится **~70% запросов**.  
Это создает дисбаланс нагрузки и перегружает отдельный шард.

Цель документа:

1. Определить **метрики для выявления горячих шардов**.
2. Предложить **механизмы перераспределения и устранения дисбаланса**.
3. Описать **стратегии предотвращения** перегрузки в будущем.

---

## 2. Метрики для отслеживания состояния шардов

### 2.1. Метрики уровня шардов

Рекомендуется собирать следующую статистику для каждого `mongod` на shard-сервере:

- **CPU**
  - `cpu_usage_percent`
- **Память**
  - `memory_rss_bytes`
- **Диск**
  - `disk_io_reads/sec`, `disk_io_writes/sec`
  - `disk_latency_read_ms`, `disk_latency_write_ms`
- **Сеть**
  - `network_bytes_in/out`
- **MongoDB операции**
  - `ops_per_sec` (`query`, `insert`, `update`, etc.)
  - `latency_read_ms`, `latency_write_ms`
- **Балансировка**
  - количество миграций чанков
  - длительность миграций
  - очереди миграций

**Признаки горячего шарда:**

- CPU выше на 30–50% относительно других шардов,
- рост латентности,
- повышенный IOPS,
- увеличение трафика.

---

### 2.2. Распределение данных и чанков

#### Количество чанков на шард:

```
use config

db.chunks.aggregate([
  { $match: { ns: "mobile_store.products" } },
  { $group: { _id: "$shard", chunks: { $sum: 1 } } }
])
```

#### Статистика коллекции по шардам:

```
use mobile_store

db.products.aggregate([
  { $collStats: { storageStats: {} } },
  {
    $project: {
      shard: "$shard",
      count: "$count",
      size: "$storageStats.size",
      avgObjSize: "$storageStats.avgObjSize"
    }
  }
])
```

Метрики:
- `count` — количество документов,
- `size` — размер данных,
- `chunks` — количество чанков на каждом шарде.

---

### 2.3. Нагрузка по категориям

#### Распределение товаров по категориям:

```
db.products.aggregate([
  { $group: { _id: "$category", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
```

#### Распределение категории по шардам:

```
db.products.aggregate([
  { $match: { category: "electronics" } },
  { $collStats: { storageStats: {} } },
  {
    $project: {
      shard: "$shard",
      count: "$count",
      size: "$storageStats.size"
    }
  }
])
```

#### Профайлер MongoDB:

```
db.setProfilingLevel(1, { slowms: 50 })
```

---

## 3. Механизмы устранения дисбаланса

### 3.1. Коррекция shard key

Если используется неудачный ключ:

```
{ category: 1 }  
{ category: 1, geo_zone: 1 }
```

— данные категории «Электроника» концентрируются на одном шарде.

### 3.2. Resharding коллекции `products` (MongoDB 4.4+)

Рекомендуемый ключ:

```
{ category: 1, _id: "hashed" }
```
или
```
{ _id: "hashed" }
```

#### Пример:

```js
db.adminCommand({
  reshardCollection: "mobile_store.products",
  key: { category: 1, _id: "hashed" }
})
```

Преимущества:

- равномерное распределение внутри категории,
- устранение hotspot,
- распределение запросов по всем шардам.

---

### 3.3. Ручное управление чанками

#### Разделение чанка:

```
sh.splitAt(
  "mobile_store.products",
  { category: "electronics", price: 5000 }
)
```

#### Перемещение чанка:

```
sh.moveChunk(
  "mobile_store.products",
  { category: "electronics", price: 5000 },
  "shard02"
)
```

---

### 3.4. Zonal sharding

Пример:

```
sh.addShardTag("shard01", "electronics")
sh.addShardTag("shard02", "electronics")

sh.updateZoneKeyRange(
  "mobile_store.products",
  { category: "electronics" },
  { category: "electronics" },
  "electronics"
)
```

Результат: товары «Электроника» распределены между несколькими шардами, а не на одном.

---

### 3.5. Добавление новых шардов

```
sh.addShard("shard03/host1:27018,host2:27018,host3:27018")
```

Балансировщик автоматически перераспределит данные.

---

### 3.6. Кэширование и CDN

Чтобы разгрузить MongoDB:

- использовать Redis для горячих запросов,
- выносить статику товаров в CDN,
- кешировать популярные категории.

---

## 4. Превентивные меры

### 4.1. Правильный дизайн shard key

- избегать низко-кардинальных ключей (`category`, `status`),
- использовать hashed или составные ключи:

```
{ _id: "hashed" }
{ category: 1, _id: "hashed" }
```

### 4.2. Регулярный аудит шардов

Команды:

```
db.chunks.aggregate([...])
db.products.aggregate([...])
```

Сравниваем:

- количество чанков,
- DocumentCount,
- Size.

### 4.3. Автоматизированное сравнение порогов

Пример правила:

```
max(doc_count) / min(doc_count) > 2  →  ALARM
```

---

## 5. Пример готового решения для «Электроники»

### Метрики:

- CPU/latency per shard
- chunks per shard
- docCount per shard (только для products)
- доля запросов по категории electronics

### Стратегия:

1. Включить профайлер на время анализа.
2. Выявить шард с наибольшим количеством документов категории.
3. Выполнить `reshardCollection` на ключ `{ category: 1, _id: "hashed" }`.
4. Включить Redis-кэш и CDN.

---

## 6. Итог

Предложенная система мониторинга и перераспределения позволяет:

- своевременно обнаруживать горячие шарды,
- равномерно распределять данные,
- предотвращать деградацию производительности,
- безопасно масштабировать магазин при росте популярных категорий.
