# Задание 8. Выявление и устранение «горячих» шардов

## 1. Проблема

Категория "Электроника" генерирует 70% запросов, что приводит к перегрузке шарда, содержащего эти данные. При текущем shard key `{category: 1, _id: 1}` все товары категории "electronics" находятся на одном шарде.

---

## 2. Метрики мониторинга шардов

### 2.1 Ключевые метрики

| Метрика | Описание | Порог алерта |
|---------|----------|--------------|
| **opcounters** | Количество операций (query, insert, update, delete) | Разница между шардами > 50% |
| **connections.current** | Текущие подключения к шарду | > 80% от max |
| **mem.resident** | Используемая RAM | > 80% |
| **globalLock.activeClients** | Активные клиенты в очереди | > 100 |
| **wiredTiger.cache.bytes currently in the cache** | Использование кэша | > 80% |
| **repl.network.bytesRead** | Сетевой трафик репликации | Аномальный рост |
| **chunks count per shard** | Количество чанков | Разница > 20% |

### 2.2 Команды сбора метрик

```javascript
// Статистика операций на каждом шарде
db.adminCommand({ serverStatus: 1 }).opcounters

// Распределение чанков по шардам
db.getSiblingDB("config").chunks.aggregate([
  { $match: { ns: "mobile_world.products" } },
  { $group: { _id: "$shard", count: { $sum: 1 } } }
])

// Распределение данных
db.products.getShardDistribution()

// Статистика по коллекции
db.products.stats()

// Текущие операции (найти долгие запросы)
db.currentOp({ "secs_running": { $gte: 5 } })

// Логи медленных запросов
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find().sort({ ts: -1 }).limit(10)
```

### 2.3 Мониторинг с Prometheus + MongoDB Exporter

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'mongodb'
    static_configs:
      - targets: 
        - 'shard1-1:9216'
        - 'shard1-2:9216'
        - 'shard2-1:9216'
        - 'shard2-2:9216'
```

**Ключевые метрики Prometheus:**
```
# Операции в секунду
rate(mongodb_opcounters_total{type="query"}[5m])

# Разница нагрузки между шардами
mongodb_opcounters_total{instance="shard1"} - mongodb_opcounters_total{instance="shard2"}

# Размер данных на шарде
mongodb_dbstats_dataSize
```

---

## 3. Диагностика горячего шарда

### 3.1 Скрипт диагностики

```javascript
// Проверка баланса чанков
function checkChunkBalance(namespace) {
  const chunks = db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: namespace } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).toArray();
  
  const total = chunks.reduce((sum, s) => sum + s.count, 0);
  
  chunks.forEach(s => {
    const pct = ((s.count / total) * 100).toFixed(1);
    print(`${s._id}: ${s.count} chunks (${pct}%)`);
    if (pct > 60) {
      print(`  ⚠️  WARNING: Shard ${s._id} is HOT!`);
    }
  });
}

checkChunkBalance("mobile_world.products");
```

### 3.2 Выявление jumbo chunks

```javascript
// Найти jumbo chunks (слишком большие для миграции)
db.getSiblingDB("config").chunks.find({
  ns: "mobile_world.products",
  jumbo: true
})

// Размер чанков
db.getSiblingDB("config").chunks.aggregate([
  { $match: { ns: "mobile_world.products" } },
  { $lookup: {
      from: "collections",
      localField: "ns",
      foreignField: "_id",
      as: "coll"
  }}
])
```

---

## 4. Механизмы устранения дисбаланса

### 4.1 Решение 1: Изменение Shard Key (рекомендуется)

**Проблема**: `{category: 1, _id: 1}` группирует "electronics" на одном шарде.

**Решение**: Использовать hashed compound key.

```javascript
// 1. Создать новую коллекцию с правильным shard key
db.createCollection("products_v2")

// 2. Создать hashed индекс
db.products_v2.createIndex({ category: 1, _id: "hashed" })

// 3. Шардировать с hashed suffix
sh.shardCollection("mobile_world.products_v2", { category: 1, _id: "hashed" })

// 4. Мигрировать данные
db.products.aggregate([
  { $merge: { into: "products_v2" } }
])

// 5. Переименовать коллекции
db.products.renameCollection("products_old")
db.products_v2.renameCollection("products")
```

### 4.2 Решение 2: Pre-splitting популярных категорий

```javascript
// Разделить категорию "electronics" на несколько чанков заранее
sh.splitAt("mobile_world.products", { category: "electronics", _id: ObjectId("000000000000000000000000") })
sh.splitAt("mobile_world.products", { category: "electronics", _id: ObjectId("400000000000000000000000") })
sh.splitAt("mobile_world.products", { category: "electronics", _id: ObjectId("800000000000000000000000") })
sh.splitAt("mobile_world.products", { category: "electronics", _id: ObjectId("c00000000000000000000000") })

// Переместить чанки на разные шарды
sh.moveChunk("mobile_world.products", 
  { category: "electronics", _id: ObjectId("400000000000000000000000") }, 
  "shard2"
)
```

### 4.3 Решение 3: Добавление Tag-Aware Sharding

```javascript
// Создать зоны для распределения категорий
sh.addShardTag("shard1", "electronics_zone_1")
sh.addShardTag("shard2", "electronics_zone_2")

// Распределить диапазоны electronics по зонам
sh.addTagRange(
  "mobile_world.products",
  { category: "electronics", _id: MinKey },
  { category: "electronics", _id: ObjectId("800000000000000000000000") },
  "electronics_zone_1"
)

sh.addTagRange(
  "mobile_world.products",
  { category: "electronics", _id: ObjectId("800000000000000000000000") },
  { category: "electronics", _id: MaxKey },
  "electronics_zone_2"
)
```

### 4.4 Решение 4: Настройка балансировщика

```javascript
// Включить балансировщик (если отключён)
sh.startBalancer()

// Настроить окно балансировки (ночью)
db.getSiblingDB("config").settings.update(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)

// Увеличить скорость миграции
db.adminCommand({ 
  setParameter: 1, 
  chunkMigrationConcurrency: 2 
})

// Уменьшить размер чанка для более гранулярного распределения
db.getSiblingDB("config").settings.save({
  _id: "chunksize",
  value: 64  // MB (по умолчанию 128)
})
```

---

## 5. Автоматическое перераспределение

### 5.1 Скрипт автобалансировки

```javascript
// auto_balance.js - запускать по cron
function autoBalanceCheck() {
  const threshold = 0.2; // 20% разница
  
  const distribution = db.getSiblingDB("config").chunks.aggregate([
    { $match: { ns: "mobile_world.products" } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).toArray();
  
  const total = distribution.reduce((s, d) => s + d.count, 0);
  const avg = total / distribution.length;
  
  distribution.forEach(shard => {
    const diff = Math.abs(shard.count - avg) / avg;
    if (diff > threshold) {
      print(`Imbalance detected on ${shard._id}: ${(diff * 100).toFixed(1)}% deviation`);
      // Можно отправить алерт или триггернуть ребалансировку
    }
  });
}

autoBalanceCheck();
```

### 5.2 Интеграция с Alertmanager

```yaml
# alertmanager rules
groups:
  - name: mongodb_sharding
    rules:
      - alert: ShardImbalance
        expr: |
          (max(mongodb_chunks_total) - min(mongodb_chunks_total)) 
          / avg(mongodb_chunks_total) > 0.3
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "MongoDB shard imbalance detected"
          
      - alert: HotShard
        expr: |
          rate(mongodb_opcounters_total{type="query"}[5m]) 
          > 2 * avg(rate(mongodb_opcounters_total{type="query"}[5m]))
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Hot shard detected: {{ $labels.instance }}"
```

---

## 6. Превентивные меры

### 6.1 Рекомендации по выбору Shard Key

| Паттерн данных | Рекомендуемый Shard Key |
|----------------|------------------------|
| Популярные категории | `{category: 1, _id: "hashed"}` |
| Равномерный доступ | `{_id: "hashed"}` |
| Геораспределение | `{region: 1, _id: 1}` с zone sharding |

### 6.2 Новый Shard Key для products

```javascript
// Рекомендуемое решение для products
sh.shardCollection("mobile_world.products", { _id: "hashed" })

// Или с compound для частичной локальности
sh.shardCollection("mobile_world.products", { category: "hashed" })
```

### 6.3 Чек-лист предотвращения hotspot

- [ ] Анализ распределения данных перед выбором shard key
- [ ] Мониторинг opcounters на каждом шарде
- [ ] Настройка алертов на дисбаланс > 30%
- [ ] Pre-splitting для известных "горячих" диапазонов
- [ ] Регулярный аудит chunk distribution
- [ ] Использование hashed keys для равномерного распределения

---

## 7. Сводка действий при обнаружении горячего шарда

```
┌─────────────────────────────────────────────────────────────────┐
│                    ОБНАРУЖЕН ГОРЯЧИЙ ШАРД                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. ДИАГНОСТИКА                                                  │
│    - db.products.getShardDistribution()                         │
│    - Проверить jumbo chunks                                     │
│    - Анализ slow queries                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. КРАТКОСРОЧНЫЕ МЕРЫ                                           │
│    - sh.splitAt() для разделения больших чанков                 │
│    - sh.moveChunk() для ручной миграции                         │
│    - Увеличить реплики для read scaling                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. ДОЛГОСРОЧНЫЕ МЕРЫ                                            │
│    - Пересмотреть shard key (миграция на hashed)                │
│    - Настроить zone sharding                                    │
│    - Добавить новые шарды                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. ПРЕВЕНЦИЯ                                                    │
│    - Настроить мониторинг и алерты                              │
│    - Регулярный аудит распределения                             │
│    - Pre-splitting для новых категорий                          │
└─────────────────────────────────────────────────────────────────┘
```

