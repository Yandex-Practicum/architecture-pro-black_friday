# Задание 8. Выявление и устранение горячих шардов

## Метрики для мониторинга

### Распределение данных

```javascript
db.products.getShardDistribution()
sh.status()
db.products.stats()
```

Проверить: количество документов на шардах, размер данных, количество chunks.

### Нагрузка

```javascript
db.serverStatus().opcounters
db.currentOp()

db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find().sort({ ts: -1 }).limit(10)
```

Проверить: операции в секунду, медленные запросы, очередь операций.

### Производительность

```javascript
db.serverStatus().connections
db.serverStatus().network
sh.getBalancerState()
sh.isBalancerRunning()
```

Проверить: CPU, активные соединения, статус балансировщика.


## Устранение горячих шардов

### Вариант 1: Ручное перемещение chunks

```javascript
// Найти большие chunks на перегруженном шарде
use config
db.chunks.find({ 
  ns: "shop.products", 
  shard: "shard1" 
}).sort({ min: 1 })

// Переместить chunk на другой шард
sh.moveChunk(
  "shop.products",
  { product_id: MinKey },
  "shard2"
)

// Проверить результат
db.products.getShardDistribution()
```

### Вариант 2: Включить автоматический балансировщик

```javascript
// Включить балансировщик
sh.startBalancer()

// Настроить окно балансировки
sh.setBalancerState(true)
use config
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { 
    activeWindow: { 
      start: "23:00", 
      stop: "06:00" 
    } 
  }},
  { upsert: true }
)

// Проверить статус
sh.getBalancerState()
sh.isBalancerRunning()
```

### Вариант 3: Изменить шард-ключ (для новых данных)

Если проблема в самом шард-ключе (например, category создает hot spots):

```javascript
// Текущий ключ: { product_id: "hashed" }
// Можно добавить category для лучшего распределения:
db.adminCommand({
  refineCollectionShardKey: "shop.products",
  key: { product_id: "hashed", category: 1 }
})
```

### Вариант 4: Zoned sharding

Распределить категории по зонам:

```javascript
// Создать зоны
sh.addShardTag("shard1", "electronics")
sh.addShardTag("shard2", "books")
sh.addShardTag("shard3", "other")

// Назначить диапазоны категориям (если шард-ключ включает category)
sh.addTagRange(
  "shop.products",
  { category: "electronics", product_id: MinKey },
  { category: "electronics", product_id: MaxKey },
  "electronics"
)
```
