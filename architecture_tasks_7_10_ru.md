# Архитектурный отчёт: MongoDB и Cassandra — Задания 7–10

## Оглавление
1. Введение  
2. Задание 7 — Архитектура данных MongoDB и выбор shard‑ключей  
   - 2.1 Структуры коллекций  
   - 2.2 Выбор shard‑ключей  
   - 2.3 Примеры команд шардирования MongoDB  
   - 2.4 ASCII‑диаграммы  
3. Задание 8 — Обнаружение «горячих» шардов и устранение дисбаланса  
   - 3.1 Метрики  
   - 3.2 Диагностические запросы  
   - 3.3 Стратегии устранения дисбаланса  
   - 3.4 ASCII‑диаграммы  
4. Задание 9 — Настройки чтения с реплик и консистентность  
   - 4.1 Матрица операций Primary/Secondary  
   - 4.2 Допустимые задержки  
   - 4.3 Примеры конфигураций  
5. Задание 10 — Архитектура миграции в Cassandra  
   - 5.1 Какие данные переносить и почему  
   - 5.2 Модели данных Cassandra  
   - 5.3 Partition‑ключи и предотвращение горячих партиций  
   - 5.4 Стратегии согласованности и восстановления  
   - 5.5 ASCII‑диаграммы  
6. Итоговое резюме  

---

# 1. Введение

Этот документ объединяет результаты заданий **7–10**, посвящённых:

- проектированию коллекций MongoDB,
- выбору оптимальных shard‑ключей,
- обнаружению и устранению «горячих» шардов,
- настройке консистентности при чтении,
- миграции высоконагруженных данных в Cassandra,
- проектированию моделей данных для горизонтального масштабирования.

Все диаграммы представлены в виде **ASCII-схем**, чтобы максимально упростить восприятие.

---

# 2. Задание 7 — Архитектура данных MongoDB и выбор shard‑ключей

## 2.1 Структуры коллекций

### Коллекция `products`
```
{
  "_id": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "stock": { "<geo_zone>": Number },
  "attributes": { "color": String, "size": String }
}
```

### Коллекция `orders`
```
{
  "_id": UUID,
  "user_id": UUID,
  "created_at": Date,
  "items": [
    { "product_id": UUID, "price": Number, "qty": Number }
  ],
  "status": "new"|"paid"|"shipped"|"delivered",
  "total": Number,
  "geo_zone": String
}
```

### Коллекция `carts`
```
{
  "_id": UUID,
  "user_id": UUID,
  "session_id": String,
  "items": [
    { "product_id": UUID, "quantity": Number }
  ],
  "status": "active"|"ordered"|"abandoned",
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date
}
```

---

## 2.2 Выбор shard‑ключей

### `products`
Shard‑key:
```
{ category: 1, _id: "hashed" }
```

**Преимущества:**
- равномерное распределение внутри категории,
- отсутствие горячих шардов по популярным категориям.

---

### `orders`
Shard‑key:
```
{ user_id: 1, created_at: 1 }
```

Позволяет эффективно получать историю заказов пользователя, не создавая гигантских партиций.

---

### `carts`
Используется derived key:
```
owner_key = "user:<id>" или "session:<id>"
```

Shard‑key:
```
{ owner_key: "hashed" }
```

Гарантирует равномерное распределение нагрузки по множеству пользователей и сессий.

---

## 2.3 Примеры команд MongoDB

```
sh.shardCollection("shop.products", { category: 1, _id: "hashed" });
sh.shardCollection("shop.orders", { user_id: 1, created_at: 1 });
sh.shardCollection("shop.carts", { owner_key: "hashed" });
```

---

## 2.4 ASCII‑диаграмма шардированного кластера MongoDB

```
                   +----------------+
                   |     mongos     |
                   +--------+-------+
                            |
                 -------------------------
                 |                       |
        +--------v--------+     +--------v--------+
        |   Shard 1       |     |    Shard 2      |
        |  (RS: 1-1,1-2)  |     |  (RS: 2-1,2-2)  |
        +--------+--------+     +--------+--------+
                 |                       |
                 -------------------------
                            |
                    +-------v-------+
                    | Config Server |
                    +---------------+
```

---

# 3. Задание 8 — Горячие шарды: Метрики и устранение

## 3.1 Метрики

| Метрика | Назначение |
|--------|------------|
| CPU per shard | понять перегруженную ноду |
| Disk IOPS | выявить дисковые узкие места |
| Network throughput | трафиковые аномалии |
| Chunk count | дисбаланс шардов |
| Объём данных per shard | прямой индикатор смещения |
| Latency | рост задержек |
| Ops/sec | тип нагрузки |

---

## 3.2 Диагностические запросы

### Распределение чанков:

```
use config
db.chunks.aggregate([
  { $match: { ns: "shop.products" }},
  { $group: { _id: "$shard", count: { $sum: 1 }}}
])
```

### Статистика коллекции:

```
db.products.aggregate([{ $collStats: { storageStats: {} } }])
```

---

## 3.3 Методы устранения

### Resharding
```
db.adminCommand({
  reshardCollection: "shop.products",
  key: { category: 1, _id: "hashed" }
})
```

### split
```
sh.splitAt("shop.products", { category: "electronics", price: 500 })
```

### moveChunk
```
sh.moveChunk("shop.products",
    { category: "electronics", price: 500 },
    "shard02"
)
```

---

## 3.4 ASCII‑диаграмма «горячего» шарда

```
          +-----------+
          |  Shard 1  |  <--- HOT (70% запросов "electronics")
          +-----------+
                ^
                |
   неравномерное распределение из-за range shard key
                |
          +-----------+
          |  Shard 2  |
          +-----------+
```

После применения hashed‑ключа:

```
electronics -> распределены равномерно по всем шардам
```

---

# 4. Задание 9 — Чтение с реплик и консистентность

## 4.1 Матрица чтений

| Коллекция | Операция | Target | Причина |
|-----------|----------|--------|---------|
| products | просмотр каталога | secondary | eventual OK |
| products | добавление в корзину | primaryPreferred | уточнение цен |
| products | checkout | primary | строгая консистентность |
| orders | история | secondaryPreferred | допускается лаг |
| orders | оплата | primary | критичность |
| carts | текущая корзина | primary | не допускается рассинхрон |
| carts | TTL‑очистка | secondary | не влияет на UX |

---

## 4.2 Допустимый лаг

| Операция | Лаг |
|----------|------|
| каталог | 3–10s |
| история заказов | 3–5s |
| проверка остатков | 1–2s |
| checkout | 0s |
| корзины | 0s |

---

## 4.3 Пример конфигурации клиента

```
MongoClient(uri, readPreference="secondaryPreferred")
MongoClient(uri, readPreference="primary")
```

---

# 5. Задание 10 — Миграция в Cassandra

## 5.1 Какие данные переносить

| Данные | Переносить? | Причина |
|--------|-------------|----------|
| carts | Да | высокая нагрузка, TTL |
| sessions | Да | огромный поток данных |
| order history | Да | append‑only |
| product stock | Да/Опционально | частые обновления |
| payments | Нет | требуется строгая консистентность |

---

## 5.2 Модели данных Cassandra

### orders_by_user
```
CREATE TABLE orders_by_user (
    user_id uuid,
    year_month text,
    order_ts timeuuid,
    order_id uuid,
    status text,
    total decimal,
    PRIMARY KEY ((user_id, year_month), order_ts)
) WITH CLUSTERING ORDER BY (order_ts DESC);
```

### carts
```
CREATE TABLE carts (
    owner_key text,
    cart_id uuid,
    status text,
    items map<uuid,int>,
    updated_at timestamp,
    PRIMARY KEY(owner_key)
);
```

### sessions
```
CREATE TABLE sessions (
    session_id uuid,
    user_id uuid,
    created_at timestamp,
    last_seen timestamp,
    PRIMARY KEY(session_id)
) WITH default_time_to_live=86400;
```

### product_stock_by_geo
```
CREATE TABLE product_stock_by_geo (
    product_id uuid,
    geo_zone text,
    stock int,
    updated_at timestamp,
    PRIMARY KEY((product_id, geo_zone))
);
```

---

## 5.3 Выбор partition‑ключей

- Максимальная кардинальность → равномерность.  
- Избегать широких партиций.  
- Использовать bucketing (`year_month`).  
- owner_key → идеальный ключ для carts.  

---

## 5.4 Стратегии согласованности

| Сущность | Write CL | Read CL | Repair |
|----------|----------|---------|--------|
| carts | LOCAL_ONE | LOCAL_ONE | редко |
| sessions | LOCAL_ONE | LOCAL_ONE | редко |
| orders | LOCAL_QUORUM | LOCAL_QUORUM | регулярно |
| product_stock | зависит от SLA | зависит | периодически |

Hinted Handoff → включён.

---

## 5.5 ASCII‑диаграмма Cassandra Ring

```
                 +-----------+
                 |  Node A   |
                 +-----------+
                      |
              -----------------
              |               |
        +-----------+   +-----------+
        |  Node B   |   |  Node C   |
        +-----------+   +-----------+

Кольцевое распределение данных по hash‑пространству
```

---

# 6. Итоговое резюме

Документ описывает:

- архитектуру MongoDB для коллекций products, orders, carts,  
- выбор shard‑ключей и предотвращение hotspots,  
- метрики мониторинга и действия по устранению дисбаланса,  
- правила чтения с реплик, SLA по лагу,  
- модели Cassandra, partition‑ключи, стратегии согласованности,  
- рекомендации по миграции высоконагруженных доменов.

Решение обеспечивает устойчивость, скорость и горизонтальное масштабирование при экстремальной нагрузке.

