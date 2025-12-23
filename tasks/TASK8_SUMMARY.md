# Задание 8: Выявление и устранение "горячих" шардов

> 🔥 Стратегия мониторинга, выявления и устранения дисбаланса нагрузки в шардированном кластере  
> 🏠 [← Вернуться к README](../README.md) | 📐 [Задание 7: Проектирование коллекций](TASK7_SUMMARY.md)

---

## 📚 Содержание

1. [Проблема "горячих" шардов](#проблема-горячих-шардов)
2. [Метрики мониторинга](#метрики-мониторинга)
3. [Выявление "горячих" шардов](#выявление-горячих-шардов)
4. [Стратегии устранения дисбаланса](#стратегии-устранения-дисбаланса)
5. [Автоматическое перераспределение](#автоматическое-перераспределение)
6. [Превентивные меры](#превентивные-меры)
7. [Примеры команд MongoDB](#примеры-команд-mongodb)
8. [Настройка мониторинга](#настройка-мониторинга)

---

## Проблема "горячих" шардов

### Описание ситуации

**Контекст**: Интернет-магазин "Мобильный мир" использует шардирование по `{ category: 1, product_id: 1 }` для коллекции `products`.

**Проблема**:
- Категория **"Электроника"** составляет **70% запросов**
- Все товары этой категории находятся на **одном шарде** (из-за Range Sharding)
- Этот шард становится **"горячим"** (hot shard)

**Последствия**:
```
Shard 1 (electronics): 🔥
- CPU: 90%
- Операций/сек: 15,000
- Размер: 80GB

Shard 2 (books, audio): ✅
- CPU: 20%
- Операций/сек: 2,000
- Размер: 15GB

Shard 3 (appliances): ✅
- CPU: 30%
- Операций/сек: 3,000
- Размер: 25GB
```

**Почему это плохо**:
- ❌ Один шард перегружен → медленные ответы
- ❌ Другие шарды простаивают → неэффективное использование ресурсов
- ❌ Риск падения "горячего" шарда
- ❌ Невозможность горизонтального масштабирования

---

## Метрики мониторинга

### 1. Метрики производительности (Performance)

#### 1.1 Операции в секунду (ops/sec)

**Что измеряем**: Количество операций (read/write) на каждом шарде.

**Команда MongoDB**:
```javascript
// Подключиться к каждому шарду напрямую
mongosh --host shard1-1:27018

// Получить статистику операций
db.serverStatus().opcounters

// Результат:
{
  insert: 123456,
  query: 789012,
  update: 345678,
  delete: 12345,
  getmore: 56789,
  command: 234567
}

// Вычислить ops/sec (нужно замерить дважды с интервалом)
```

**Формула**:
```
ops/sec = (total_ops_now - total_ops_before) / time_interval

total_ops = insert + query + update + delete + getmore
```

**Пороговые значения**:
- ✅ Норма: < 5,000 ops/sec
- ⚠️ Внимание: 5,000 - 10,000 ops/sec
- 🔥 Критично: > 10,000 ops/sec

**MongoDB Atlas метрика**: `Operations/sec` (доступна в UI)

#### 1.2 Latency (задержка)

**Что измеряем**: Время ответа на запросы.

**Команда**:
```javascript
// Включить профилирование медленных запросов
db.setProfilingLevel(1, { slowms: 100 })

// Просмотр медленных запросов
db.system.profile.find({ millis: { $gt: 100 } }).sort({ ts: -1 }).limit(10)

// Средняя задержка
db.system.profile.aggregate([
  { $match: { ns: "mobile_world.products" } },
  { $group: { _id: null, avgLatency: { $avg: "$millis" } } }
])
```

**Пороговые значения**:
- ✅ Норма: < 50ms
- ⚠️ Внимание: 50-200ms
- 🔥 Критично: > 200ms

#### 1.3 Query Queue (очередь запросов)

**Что измеряем**: Количество запросов в очереди.

**Команда**:
```javascript
db.serverStatus().globalLock.currentQueue

// Результат:
{
  total: 15,      // Общая очередь
  readers: 10,    // Запросы на чтение
  writers: 5      // Запросы на запись
}
```

**Пороговые значения**:
- ✅ Норма: < 10
- ⚠️ Внимание: 10-50
- 🔥 Критично: > 50

### 2. Метрики ресурсов (Resources)

#### 2.1 CPU утилизация

**Что измеряем**: Загрузка процессора.

**Команда системная**:
```bash
# На хосте шарда
top -bn1 | grep mongod

# Или через ps
ps aux | grep mongod | awk '{print $3}'

# Мониторинг в реальном времени
vmstat 1
```

**MongoDB встроенная статистика**:
```javascript
db.serverStatus().extra_info.page_faults  // Page faults - косвенный индикатор CPU
```

**Пороговые значения**:
- ✅ Норма: < 60%
- ⚠️ Внимание: 60-80%
- 🔥 Критично: > 80%

#### 2.2 Memory (RAM)

**Что измеряем**: Использование оперативной памяти.

**Команда**:
```javascript
db.serverStatus().mem

// Результат:
{
  bits: 64,
  resident: 4096,    // RAM используется процессом (MB)
  virtual: 8192,     // Виртуальная память (MB)
  supported: true
}

// WiredTiger cache
db.serverStatus().wiredTiger.cache

// Результат:
{
  "bytes currently in the cache": 3221225472,  // ~3GB
  "maximum bytes configured": 4294967296,      // ~4GB (50% RAM по умолчанию)
  "bytes read into cache": 10737418240,
  "bytes written from cache": 5368709120,
  "pages evicted by application threads": 1024,
  "pages read into cache": 262144,
  "pages written from cache": 131072
}
```

**Формула**:
```
memory_usage_percent = (resident / total_ram) * 100
cache_usage_percent = (bytes_in_cache / max_cache) * 100
```

**Пороговые значения**:
- ✅ Норма: < 70% RAM
- ⚠️ Внимание: 70-85% RAM
- 🔥 Критично: > 85% RAM

#### 2.3 Disk I/O

**Что измеряем**: Скорость чтения/записи на диск.

**Команда системная**:
```bash
# iostat для мониторинга I/O
iostat -x 1

# Показывает:
# %util - утилизация диска
# r/s - чтений в секунду
# w/s - записей в секунду
# rkB/s - килобайт читается в секунду
# wkB/s - килобайт пишется в секунду
```

**MongoDB статистика**:
```javascript
db.serverStatus().wiredTiger.transaction

{
  "transaction checkpoint max time (msecs)": 500,
  "transaction checkpoint min time (msecs)": 100
}
```

**Пороговые значения**:
- ✅ Норма: %util < 70%
- ⚠️ Внимание: %util 70-90%
- 🔥 Критично: %util > 90%

### 3. Метрики распределения данных (Data Distribution)

#### 3.1 Размер данных на шардах

**Что измеряем**: Количество данных на каждом шарде.

**Команда**:
```javascript
// Подключиться к mongos
db.products.getShardDistribution()

// Результат:
Shard shard1 at shard1-1:27018,shard1-2:27018,shard1-3:27018
 data : 80GiB docs : 50000000 chunks : 120
 estimated data per chunk : 682MiB
 estimated docs per chunk : 416666

Shard shard2 at shard2-1:27018,shard2-2:27018,shard2-3:27018
 data : 15GiB docs : 10000000 chunks : 30
 estimated data per chunk : 512MiB
 estimated docs per chunk : 333333

Totals
 data : 95GiB docs : 60000000 chunks : 150
 Shard shard1 contains 84.2% data, 83.3% docs in cluster  🔥 ПРОБЛЕМА!
 Shard shard2 contains 15.8% data, 16.7% docs in cluster
```

**Идеальное распределение**: Каждый шард ~ 50% (для 2 шардов)

**Допустимое**: ±10% от идеального  
**Проблемное**: ±20% от идеального 🔥

#### 3.2 Количество чанков (chunks)

**Что измеряем**: Количество чанков на каждом шарде.

**Команда**:
```javascript
// Количество чанков по шардам
db.getSiblingDB("config").chunks.aggregate([
  { $match: { ns: "mobile_world.products" } },
  { $group: { _id: "$shard", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// Результат:
[
  { _id: "shard1", count: 120 },  // 80% чанков 🔥
  { _id: "shard2", count: 30 }    // 20% чанков
]

// Размер каждого чанка
db.getSiblingDB("config").chunks.find({ ns: "mobile_world.products" }).forEach(chunk => {
  print(`Chunk: ${chunk.min.category} - ${chunk.max.category}, Shard: ${chunk.shard}`)
})
```

**Идеальное**: Равномерное распределение чанков  
**Проблема**: Большой дисбаланс (80% vs 20%)

#### 3.3 Jumbo chunks (огромные чанки)

**Что измеряем**: Чанки, которые превысили максимальный размер и не могут быть split.

**Команда**:
```javascript
// Найти jumbo chunks
db.getSiblingDB("config").chunks.find({ 
  ns: "mobile_world.products",
  jumbo: true 
})

// Количество jumbo chunks
db.getSiblingDB("config").chunks.count({ 
  ns: "mobile_world.products",
  jumbo: true 
})
```

**Проблема**: Jumbo chunks нельзя переместить → невозможна балансировка

**Решение**: Refine shard key (см. ниже)

### 4. Метрики балансировки (Balancing)

#### 4.1 Balancer status

**Что измеряем**: Работает ли балансировщик, когда последний раз выполнялся.

**Команда**:
```javascript
sh.getBalancerState()  // true/false

sh.isBalancerRunning()  // true/false (прямо сейчас)

// Детальная информация
db.getSiblingDB("config").mongos.find().pretty()

// Время последней балансировки
db.getSiblingDB("config").actionlog.find({ what: "balancer.round" }).sort({ time: -1 }).limit(1)
```

#### 4.2 Migration failures

**Что измеряем**: Неудачные попытки миграции чанков.

**Команда**:
```javascript
// Логи миграций
db.getSiblingDB("config").changelog.find({ 
  what: /moveChunk/,
  "details.errmsg": { $exists: true }
}).sort({ time: -1 }).limit(10)
```

### 5. Метрики приложения (Application Level)

#### 5.1 Targeted vs Scatter-Gather queries

**Что измеряем**: Сколько запросов идут на один шард (targeted) vs все шарды (scatter-gather).

**Команда**:
```javascript
// Explain запроса
db.products.find({ category: "electronics" }).explain("executionStats")

// Если "stage": "SINGLE_SHARD" → targeted (хорошо) ✅
// Если "stage": "SHARD_MERGE" → scatter-gather (плохо) ❌

// Количество шардов, затронутых запросом
db.products.find({ category: "electronics" }).explain("executionStats").queryPlanner.winningPlan.shards.length

// 1 shard = targeted ✅
// 2+ shards = scatter-gather ❌
```

**Цель**: Максимизировать targeted queries (>80%)

#### 5.2 Распределение запросов по категориям

**Что измеряем**: Какие категории запрашиваются чаще всего.

**Команда (в приложении)**:
```python
# Логирование запросов
import logging
from collections import Counter

query_counter = Counter()

def query_products(category):
    query_counter[category] += 1
    return db.products.find({"category": category})

# Периодически выводить топ категорий
def print_hot_categories():
    for category, count in query_counter.most_common(10):
        percentage = (count / sum(query_counter.values())) * 100
        print(f"{category}: {count} queries ({percentage:.1f}%)")
        
        if percentage > 30:
            print(f"⚠️  WARNING: {category} is a hot category!")
```

---

## Выявление "горячих" шардов

### Алгоритм выявления

**Шаг 1**: Сравнить метрики всех шардов

```javascript
// Скрипт для сравнения шардов
const shards = ["shard1", "shard2", "shard3"]
const metrics = {}

for (const shard of shards) {
  // Подключиться к primary шарда
  const conn = connect(`${shard}-1:27018`)
  
  metrics[shard] = {
    ops: conn.serverStatus().opcounters,
    cpu: conn.serverStatus().extra_info.page_faults,
    memory: conn.serverStatus().mem.resident,
    connections: conn.serverStatus().connections.current,
    queueDepth: conn.serverStatus().globalLock.currentQueue.total
  }
}

// Сравнить
printjson(metrics)
```

**Шаг 2**: Вычислить дисбаланс

```javascript
function calculateImbalance(metrics) {
  const values = Object.values(metrics).map(m => m.ops.query)
  const avg = values.reduce((a, b) => a + b) / values.length
  const max = Math.max(...values)
  const min = Math.min(...values)
  
  const imbalance = ((max - avg) / avg) * 100
  
  print(`Среднее: ${avg} ops/sec`)
  print(`Максимум: ${max} ops/sec`)
  print(`Минимум: ${min} ops/sec`)
  print(`Дисбаланс: ${imbalance.toFixed(1)}%`)
  
  if (imbalance > 50) {
    print("🔥 КРИТИЧЕСКИЙ ДИСБАЛАНС!")
  } else if (imbalance > 25) {
    print("⚠️  Дисбаланс обнаружен")
  } else {
    print("✅ Балансировка в норме")
  }
}
```

**Шаг 3**: Идентифицировать "горячий" шард

```javascript
function identifyHotShard() {
  // 1. Распределение данных
  db.products.getShardDistribution()
  
  // 2. Проверка чанков
  const chunksPerShard = {}
  db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: "mobile_world.products" } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).forEach(doc => {
    chunksPerShard[doc._id] = doc.count
  })
  
  // 3. Найти шард с наибольшим количеством данных
  print("Распределение чанков:")
  printjson(chunksPerShard)
  
  // 4. Проверить jumbo chunks
  const jumboChunks = db.getSiblingDB("config").chunks.find({
    ns: "mobile_world.products",
    jumbo: true
  }).count()
  
  if (jumboChunks > 0) {
    print(`⚠️  Найдено ${jumboChunks} jumbo chunks - они могут быть причиной дисбаланса`)
  }
}
```

### Автоматизированный мониторинг

**Скрипт для регулярной проверки**:

```javascript
// monitor_shards.js

function monitorShards() {
  const timestamp = new Date()
  const report = {
    timestamp: timestamp,
    shards: {}
  }
  
  // Получить список шардов
  const shards = db.getSiblingDB("config").shards.find().toArray()
  
  for (const shard of shards) {
    const shardName = shard._id
    const host = shard.host.split("/")[1].split(",")[0]  // Первый хост
    
    try {
      const conn = connect(host)
      const status = conn.serverStatus()
      
      report.shards[shardName] = {
        host: host,
        opcounters: status.opcounters,
        memory: status.mem,
        connections: status.connections,
        queueDepth: status.globalLock.currentQueue
      }
    } catch (e) {
      report.shards[shardName] = { error: e.message }
    }
  }
  
  // Распределение данных
  report.distribution = {}
  db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: "mobile_world.products" } },
    { $group: { _id: "$shard", chunks: { $sum: 1 } } }
  ]).forEach(doc => {
    report.distribution[doc._id] = doc.chunks
  })
  
  // Сохранить в коллекцию мониторинга
  db.getSiblingDB("monitoring").shard_metrics.insertOne(report)
  
  // Анализ
  analyzeReport(report)
}

function analyzeReport(report) {
  // Вычислить дисбаланс чанков
  const chunks = Object.values(report.distribution)
  const avgChunks = chunks.reduce((a, b) => a + b) / chunks.length
  const maxChunks = Math.max(...chunks)
  
  const imbalance = ((maxChunks - avgChunks) / avgChunks) * 100
  
  if (imbalance > 30) {
    print(`🔥 ALERT: Chunk imbalance detected: ${imbalance.toFixed(1)}%`)
    print(`Recommendation: Run balancer or manual redistribution`)
    
    // Отправить алерт
    sendAlert({
      level: "CRITICAL",
      message: `Shard chunk imbalance: ${imbalance.toFixed(1)}%`,
      timestamp: new Date()
    })
  }
}

function sendAlert(alert) {
  // Интеграция с системой алертинга (PagerDuty, Slack, email)
  db.getSiblingDB("monitoring").alerts.insertOne(alert)
  print(`Alert sent: ${alert.message}`)
}

// Запускать каждые 5 минут
while (true) {
  monitorShards()
  sleep(5 * 60 * 1000)  // 5 минут
}
```

**Запуск мониторинга**:
```bash
mongosh --host mongos:27017 --file monitor_shards.js &
```

---

## Стратегии устранения дисбаланса

### Стратегия 1: Split Chunks (Разделение чанков)

**Когда использовать**: Большие чанки нужно разделить на меньшие для лучшей балансировки.

**Как работает**:
```
Было:
Chunk 1: { category: "electronics", product_id: MinKey } -> { category: "electronics", product_id: MaxKey }
Размер: 80GB на shard1 🔥

Стало:
Chunk 1a: { category: "electronics", product_id: MinKey } -> { category: "electronics", product_id: "PROD-50000" }
Chunk 1b: { category: "electronics", product_id: "PROD-50000" } -> { category: "electronics", product_id: MaxKey }
Можно переместить Chunk 1b на shard2
```

**Команды**:

```javascript
// 1. Найти точку split (средний product_id в категории)
db.products.aggregate([
  { $match: { category: "electronics" } },
  { $sort: { product_id: 1 } },
  { $skip: 25000000 },  // Половина документов
  { $limit: 1 },
  { $project: { _id: 0, product_id: 1 } }
])
// Результат: { product_id: "PROD-50000" }

// 2. Split chunk по этой точке
sh.splitAt("mobile_world.products", { 
  category: "electronics", 
  product_id: "PROD-50000" 
})

// Альтернатива: Auto-split по количеству документов
sh.splitFind("mobile_world.products", { 
  category: "electronics", 
  product_id: "PROD-50000" 
})

// 3. Проверить результат
db.getSiblingDB("config").chunks.find({ 
  ns: "mobile_world.products",
  "min.category": "electronics"
}).count()
// Было: 1 chunk
// Стало: 2+ chunks
```

**Автоматический split**:
```javascript
// Настроить автоматический split при превышении размера
db.getSiblingDB("config").settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 32 } },  // 32MB вместо 64MB по умолчанию
  { upsert: true }
)
```

### Стратегия 2: Move Chunks (Перемещение чанков)

**Когда использовать**: После split нужно переместить чанки на менее загруженные шарды.

**Команды**:

```javascript
// 1. Определить, какой чанк переместить
db.getSiblingDB("config").chunks.find({
  ns: "mobile_world.products",
  shard: "shard1",
  "min.category": "electronics"
}).sort({ "min.product_id": 1 }).pretty()

// 2. Переместить chunk на shard2
sh.moveChunk(
  "mobile_world.products",
  { category: "electronics", product_id: "PROD-50000" },  // Граница chunk
  "shard2"  // Целевой шард
)

// 3. Проверить статус миграции
db.getSiblingDB("config").changelog.find({ 
  what: "moveChunk.from",
  ns: "mobile_world.products"
}).sort({ time: -1 }).limit(1).pretty()

// 4. Проверить новое распределение
db.products.getShardDistribution()
```

**Batch перемещение** (несколько чанков):

```javascript
// Переместить 10 чанков с shard1 на shard2
const chunksToMove = db.getSiblingDB("config").chunks.find({
  ns: "mobile_world.products",
  shard: "shard1"
}).limit(10).toArray()

for (const chunk of chunksToMove) {
  print(`Moving chunk: ${chunk.min.category} - ${chunk.min.product_id}`)
  
  sh.moveChunk(
    "mobile_world.products",
    chunk.min,
    "shard2"
  )
  
  // Пауза между миграциями, чтобы не перегрузить сеть
  sleep(10000)  // 10 секунд
}
```

### Стратегия 3: Zone Sharding (Зонирование)

**Когда использовать**: Назначить определённые диапазоны данных на конкретные шарды.

**Сценарий**: Популярные категории на отдельные мощные шарды.

**Команды**:

```javascript
// 1. Создать зоны (tags)
sh.addShardTag("shard1", "hot_categories")   // Мощный шард
sh.addShardTag("shard2", "medium_categories")
sh.addShardTag("shard3", "cold_categories")

// 2. Назначить диапазоны категорий на зоны
//    Electronics (70% запросов) → hot_categories (shard1)
sh.addTagRange(
  "mobile_world.products",
  { category: "electronics", product_id: MinKey },
  { category: "electronics", product_id: MaxKey },
  "hot_categories"
)

//    Books, Audio (20% запросов) → medium_categories (shard2)
sh.addTagRange(
  "mobile_world.products",
  { category: "books", product_id: MinKey },
  { category: "books", product_id: MaxKey },
  "medium_categories"
)

sh.addTagRange(
  "mobile_world.products",
  { category: "audio", product_id: MinKey },
  { category: "audio", product_id: MaxKey },
  "medium_categories"
)

//    Остальные → cold_categories (shard3)
sh.addTagRange(
  "mobile_world.products",
  { category: "appliances", product_id: MinKey },
  { category: "appliances", product_id: MaxKey },
  "cold_categories"
)

// 3. Включить балансировщик для перемещения чанков в зоны
sh.startBalancer()

// 4. Проверить зоны
sh.status()
```

**Преимущества зонирования**:
- ✅ Контроль распределения данных
- ✅ Можно выделить мощный шард для популярных категорий
- ✅ Географическое распределение (US, EU, Asia)

### Стратегия 4: Refine Shard Key (Уточнение шард-ключа)

**Когда использовать**: Текущий шард-ключ недостаточно гранулярный (jumbo chunks).

**Проблема**:
```
Shard key: { category: 1, product_id: 1 }

Jumbo chunk:
{ category: "electronics", product_id: MinKey } -> { category: "electronics", product_id: MaxKey }
Размер: 80GB
Нельзя split дальше из-за низкой кардинальности category
```

**Решение**: Добавить поле с высокой кардинальностью.

**Новый шард-ключ**: `{ category: 1, product_id: 1, _id: 1 }`

**Команда (MongoDB 4.4+)**:
```javascript
db.adminCommand({
  refineCollectionShardKey: "mobile_world.products",
  key: { category: 1, product_id: 1, _id: 1 }
})
```

**Эффект**:
- Jumbo chunks теперь можно split по `_id`
- Более гранулярное распределение
- Лучшая балансировка

**Важно**: Нужно создать индекс перед refine:
```javascript
db.products.createIndex({ category: 1, product_id: 1, _id: 1 })
```

### Стратегия 5: Пересоздание коллекции с новым шард-ключом

**Когда использовать**: Refine не помогает, нужно полностью изменить стратегию.

**Новый подход**: Hashed Sharding по `{ category: "hashed", product_id: "hashed" }`

**План**:
```javascript
// 1. Создать новую коллекцию
db.createCollection("products_v2")

// 2. Создать хешированный индекс
db.products_v2.createIndex({ category: "hashed", product_id: "hashed" })

// 3. Шардировать с hashed ключом
sh.shardCollection("mobile_world.products_v2", { 
  category: "hashed", 
  product_id: "hashed" 
})

// 4. Мигрировать данные (постепенно, чтобы не перегрузить)
const cursor = db.products.find().batchSize(1000)
while (cursor.hasNext()) {
  const batch = []
  for (let i = 0; i < 1000 && cursor.hasNext(); i++) {
    batch.push(cursor.next())
  }
  db.products_v2.insertMany(batch, { ordered: false })
  sleep(100)  // Пауза
}

// 5. Переключить приложение на products_v2
// 6. Удалить старую коллекцию
db.products.drop()

// 7. Переименовать
db.products_v2.renameCollection("products")
```

**Недостатки**:
- ❌ Поиск по категории станет scatter-gather
- ❌ Downtime во время миграции

---

## Автоматическое перераспределение

### Встроенный Balancer MongoDB

**Как работает**:
- Автоматически перемещает чанки между шардами
- Работает в фоне
- Цель: равномерное распределение чанков

**Включить/выключить**:
```javascript
// Включить
sh.startBalancer()

// Выключить
sh.stopBalancer()

// Проверить статус
sh.getBalancerState()
sh.isBalancerRunning()
```

**Настройка окна балансировки** (чтобы не мешать продакшну):
```javascript
// Балансировка только ночью (02:00 - 06:00)
db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { 
    $set: { 
      activeWindow: {
        start: "02:00",
        stop: "06:00"
      }
    }
  },
  { upsert: true }
)

// Отключить окно (балансировка всегда)
db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { $unset: { activeWindow: "" } }
)
```

**Настройка скорости балансировки**:
```javascript
// Максимум параллельных миграций (по умолчанию 1)
db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { $set: { "_secondaryThrottle": false } },  // Быстрее, но больше нагрузка
  { upsert: true }
)

// Настроить размер чанка (меньше = более гранулярная балансировка)
db.getSiblingDB("config").settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 32 } },  // 32MB
  { upsert: true }
)
```

### Мониторинг балансировки

```javascript
// История балансировки
db.getSiblingDB("config").changelog.find({ 
  what: /balancer/ 
}).sort({ time: -1 }).limit(10).pretty()

// Статистика миграций
db.getSiblingDB("config").changelog.aggregate([
  { $match: { what: "moveChunk.from" } },
  { $group: {
      _id: "$details.from",
      migrations: { $sum: 1 },
      totalTime: { $sum: "$details.step6.millis" }
    }
  }
])
```

### Автоматический скрипт балансировки

**Проактивная балансировка** на основе метрик:

```javascript
// auto_balance.js

function autoBalance() {
  // 1. Проверить дисбаланс чанков
  const distribution = {}
  db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: "mobile_world.products" } },
    { $group: { _id: "$shard", chunks: { $sum: 1 } } }
  ]).forEach(doc => {
    distribution[doc._id] = doc.chunks
  })
  
  const chunks = Object.values(distribution)
  const avgChunks = chunks.reduce((a, b) => a + b) / chunks.length
  const maxChunks = Math.max(...chunks)
  const minChunks = Math.min(...chunks)
  
  const imbalance = ((maxChunks - minChunks) / avgChunks) * 100
  
  print(`Chunk distribution: ${JSON.stringify(distribution)}`)
  print(`Imbalance: ${imbalance.toFixed(1)}%`)
  
  // 2. Если дисбаланс > 20%, запустить балансировку
  if (imbalance > 20) {
    print("🔥 Imbalance detected! Starting balancer...")
    
    // Найти "горячий" шард (с максимальным количеством чанков)
    const hotShard = Object.keys(distribution).reduce((a, b) => 
      distribution[a] > distribution[b] ? a : b
    )
    
    // Найти "холодный" шард (с минимальным количеством чанков)
    const coldShard = Object.keys(distribution).reduce((a, b) => 
      distribution[a] < distribution[b] ? a : b
    )
    
    print(`Hot shard: ${hotShard} (${distribution[hotShard]} chunks)`)
    print(`Cold shard: ${coldShard} (${distribution[coldShard]} chunks)`)
    
    // Переместить несколько чанков с горячего на холодный
    const chunksToMove = Math.floor((distribution[hotShard] - avgChunks) / 2)
    
    print(`Moving ${chunksToMove} chunks from ${hotShard} to ${coldShard}`)
    
    const chunksToMigrate = db.getSiblingDB("config").chunks.find({
      ns: "mobile_world.products",
      shard: hotShard
    }).limit(chunksToMove).toArray()
    
    for (const chunk of chunksToMigrate) {
      try {
        print(`Migrating chunk: ${JSON.stringify(chunk.min)}`)
        sh.moveChunk("mobile_world.products", chunk.min, coldShard)
        sleep(5000)  // Пауза 5 сек между миграциями
      } catch (e) {
        print(`Error migrating chunk: ${e.message}`)
      }
    }
    
    print("✅ Rebalancing completed")
  } else {
    print("✅ Chunks are balanced")
  }
}

// Запускать каждые 30 минут
while (true) {
  autoBalance()
  sleep(30 * 60 * 1000)  // 30 минут
}
```

**Запуск**:
```bash
mongosh --host mongos:27017 --file auto_balance.js &
```

---

## Превентивные меры

### 1. Правильный выбор шард-ключа

**Принципы**:
- ✅ Высокая кардинальность
- ✅ Равномерное распределение запросов
- ✅ Targeted queries (не scatter-gather)

**Для products**: Вместо `{ category: 1, product_id: 1 }` рассмотреть:

**Вариант A**: Composite hashed
```javascript
// Добавить hash prefix
db.products.createIndex({ category_hash: "hashed", category: 1, product_id: 1 })

// category_hash = hash(category) % 10  // 10 bucket'ов

sh.shardCollection("mobile_world.products", { 
  category_hash: 1,  // Распределяет по bucket'ам
  category: 1,       // Локальность для запросов
  product_id: 1 
})
```

**Эффект**: "Electronics" распределится по 10 bucket'ам → на несколько шардов

**Вариант B**: Zone-based sharding с pre-split

```javascript
// Pre-split перед загрузкой данных
for (let i = 0; i < 100; i++) {
  sh.splitAt("mobile_world.products", {
    category: "electronics",
    product_id: `PROD-${i * 1000}`
  })
}

// Затем zone sharding для распределения
```

### 2. Monitoring & Alerting

**Настроить алерты** на:
- CPU > 80% на любом шарде
- Chunk imbalance > 30%
- Queue depth > 50
- Latency > 200ms

**Пример интеграции с Prometheus**:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mongodb'
    static_configs:
      - targets:
          - 'shard1-1:9216'
          - 'shard2-1:9216'
          - 'shard3-1:9216'
```

**Grafana dashboard**: Импортировать `MongoDB Overview` dashboard

### 3. Capacity Planning

**Предсказать рост** и добавить шарды заранее:

```javascript
// Текущий размер данных
db.products.stats().size / (1024 ** 3)  // GB

// Прогноз: если рост 20% в месяц
const monthlyGrowth = 0.20
const currentSize = 95  // GB
const projectedSize = currentSize * Math.pow(1 + monthlyGrowth, 12)  // Через год

print(`Projected size in 1 year: ${projectedSize.toFixed(0)} GB`)

// Если projected > threshold, добавить шарды
if (projectedSize > 500) {
  print("⚠️  WARNING: Add more shards within 6 months")
}
```

### 4. Read from Secondaries

**Распределить нагрузку чтения** на secondary ноды:

```javascript
// В приложении (Python/pymongo)
from pymongo import MongoClient, ReadPreference

client = MongoClient(
    'mongodb://mongos:27017/',
    readPreference=ReadPreference.SECONDARY_PREFERRED
)

# Или
db = client.get_database('mobile_world', read_preference=ReadPreference.SECONDARY)
```

**Эффект**: Primary разгружается для writes

### 5. Caching популярных категорий

**Redis для "горячих" данных**:

```python
import redis

redis_client = redis.Redis(host='redis', port=6379)

def get_products_by_category(category):
    # Проверить кеш
    cache_key = f"products:category:{category}"
    cached = redis_client.get(cache_key)
    
    if cached:
        return json.loads(cached)
    
    # Если нет в кеше, запросить MongoDB
    products = list(db.products.find({"category": category}))
    
    # Сохранить в кеш (TTL 5 минут)
    redis_client.setex(cache_key, 300, json.dumps(products))
    
    return products
```

**Эффект**: 90% запросов "electronics" идут в Redis, не в MongoDB

---

## Примеры команд MongoDB

### Диагностика

```javascript
// 1. Проверка дисбаланса
db.products.getShardDistribution()

// 2. Статус балансировщика
sh.getBalancerState()
sh.isBalancerRunning()

// 3. Список jumbo chunks
db.getSiblingDB("config").chunks.find({
  ns: "mobile_world.products",
  jumbo: true
}).count()

// 4. История миграций
db.getSiblingDB("config").changelog.find({
  what: "moveChunk.from"
}).sort({ time: -1 }).limit(10)

// 5. Размер чанков
db.getSiblingDB("config").settings.findOne({ _id: "chunksize" })

// 6. Окно балансировки
db.getSiblingDB("config").settings.findOne({ _id: "balancer" })
```

### Исправление

```javascript
// 1. Split большого чанка
sh.splitAt("mobile_world.products", {
  category: "electronics",
  product_id: "PROD-50000"
})

// 2. Переместить чанк
sh.moveChunk(
  "mobile_world.products",
  { category: "electronics", product_id: "PROD-50000" },
  "shard2"
)

// 3. Включить балансировщик
sh.startBalancer()

// 4. Изменить размер чанка
db.getSiblingDB("config").settings.updateOne(
  { _id: "chunksize" },
  { $set: { value: 32 } },
  { upsert: true }
)

// 5. Refine shard key
db.adminCommand({
  refineCollectionShardKey: "mobile_world.products",
  key: { category: 1, product_id: 1, _id: 1 }
})

// 6. Zone sharding
sh.addShardTag("shard1", "hot")
sh.addTagRange(
  "mobile_world.products",
  { category: "electronics", product_id: MinKey },
  { category: "electronics", product_id: MaxKey },
  "hot"
)
```

---

## Настройка мониторинга

### MongoDB Atlas (Cloud)

**Встроенный мониторинг**:
- Performance Advisor
- Real-time metrics
- Auto-scaling
- Automatic balancing

### Self-hosted: Prometheus + Grafana

**1. MongoDB Exporter**:
```bash
# docker-compose.yml
mongodb_exporter:
  image: percona/mongodb_exporter:latest
  command:
    - '--mongodb.uri=mongodb://shard1-1:27018'
  ports:
    - '9216:9216'
```

**2. Prometheus config**:
```yaml
scrape_configs:
  - job_name: 'mongodb_shard1'
    static_configs:
      - targets: ['mongodb_exporter_shard1:9216']
        labels:
          shard: 'shard1'
```

**3. Grafana alerts**:
```yaml
alerts:
  - alert: HighCPUUsage
    expr: mongodb_sys_cpu_usage > 80
    for: 5m
    annotations:
      summary: "High CPU on {{ $labels.shard }}"
      
  - alert: ChunkImbalance
    expr: (max(mongodb_chunks_count) - min(mongodb_chunks_count)) / avg(mongodb_chunks_count) > 0.3
    for: 10m
    annotations:
      summary: "Chunk imbalance detected"
```

### Custom monitoring script

```javascript
// save_metrics.js

function saveMetrics() {
  const metrics = {
    timestamp: new Date(),
    shards: {}
  }
  
  // Получить статус каждого шарда
  const shards = sh.status(true).shards
  for (const shardName in shards) {
    const host = shards[shardName].host
    const conn = connect(host)
    const status = conn.serverStatus()
    
    metrics.shards[shardName] = {
      opcounters: status.opcounters,
      connections: status.connections.current,
      memory: status.mem.resident,
      queueDepth: status.globalLock.currentQueue.total
    }
  }
  
  // Распределение чанков
  const chunksPerShard = {}
  db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: "mobile_world.products" } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).forEach(doc => {
    chunksPerShard[doc._id] = doc.count
  })
  
  metrics.chunk_distribution = chunksPerShard
  
  // Сохранить в коллекцию мониторинга
  db.getSiblingDB("monitoring").metrics.insertOne(metrics)
}

// Запускать каждые 5 минут
while (true) {
  saveMetrics()
  sleep(5 * 60 * 1000)
}
```

---

## Итоги

### Ключевые метрики

| Метрика | Норма | Внимание | Критично |
|---------|-------|----------|----------|
| **Ops/sec** | <5,000 | 5,000-10,000 | >10,000 |
| **CPU** | <60% | 60-80% | >80% |
| **Memory** | <70% | 70-85% | >85% |
| **Latency** | <50ms | 50-200ms | >200ms |
| **Queue depth** | <10 | 10-50 | >50 |
| **Chunk imbalance** | <10% | 10-30% | >30% |

### Стратегии устранения

| Стратегия | Когда использовать | Сложность | Время |
|-----------|-------------------|-----------|-------|
| **Split chunks** | Большие чанки | Низкая | Минуты |
| **Move chunks** | Дисбаланс чанков | Низкая | Часы |
| **Zone sharding** | Предсказуемая нагрузка | Средняя | Часы |
| **Refine shard key** | Jumbo chunks | Средняя | Часы |
| **Re-shard** | Неправильный ключ | Высокая | Дни |

### Превентивные меры

1. ✅ Правильный шард-ключ с высокой кардинальностью
2. ✅ Мониторинг метрик 24/7
3. ✅ Автоматические алерты
4. ✅ Capacity planning
5. ✅ Read from secondaries
6. ✅ Redis caching для популярных категорий
7. ✅ Zone sharding для предсказуемых паттернов

### Автоматизация

- ✅ Встроенный balancer MongoDB
- ✅ Окна балансировки (ночью)
- ✅ Автоматический split chunks
- ✅ Custom скрипты мониторинга
- ✅ Интеграция с Prometheus/Grafana

---

## 📚 Связанные документы

- 📐 [TASK7_SUMMARY.md](TASK7_SUMMARY.md) - проектирование коллекций
- 🏠 [README.md](../README.md) - главная страница
- ⚙️ [TASK2_SUMMARY.md](TASK2_SUMMARY.md) - реализация шардирования
- 🔧 [TASK2_SHARDING_SETUP.md](TASK2_SHARDING_SETUP.md) - настройка шардов

---

**✅ Задание 8 выполнено!**

**Разработана комплексная стратегия мониторинга и устранения "горячих" шардов для интернет-магазина "Мобильный мир".**

**🎉 Система готова к обработке неравномерной нагрузки!**

