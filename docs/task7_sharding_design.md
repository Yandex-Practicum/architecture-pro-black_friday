# Задание 7. Проектирование схем коллекций для шардирования данных

## 1. Обзор архитектуры

Онлайн-магазин "Мобильный мир" использует MongoDB с шардированием для хранения данных о заказах, товарах и корзинах. Кластер состоит из:
- 2 шардов с репликацией (3 ноды на шард)
- Config Server Replica Set (3 ноды)
- Mongos Router

---

## 2. Коллекция orders (Заказы)

### 2.1 Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор заказа
  user_id: ObjectId,                // Идентификатор клиента
  order_date: ISODate,              // Дата и время оформления
  items: [                          // Список товаров
    {
      product_id: ObjectId,
      name: String,
      quantity: Number,
      price: Decimal128
    }
  ],
  status: String,                   // "pending" | "paid" | "shipped" | "delivered" | "cancelled"
  total_amount: Decimal128,         // Общая сумма заказа
  geo_zone: String                  // Геозона: "moscow", "spb", "ekb", "kaliningrad"
}
```

### 2.2 Выбор Shard Key

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `_id` (hashed) | Равномерное распределение | Scatter-gather при поиске по user_id |
| `user_id` (hashed) | Все заказы пользователя на одном шарде | Hotspot для активных пользователей |
| `geo_zone` | Локальность данных по региону | Неравномерное распределение (Москва >> остальные) |
| **`{user_id: 1, _id: 1}`** | Баланс локальности и распределения | Сложнее миграция чанков |

**Выбор: Compound Shard Key `{user_id: 1, _id: 1}`**

### 2.3 Обоснование

1. **Локальность запросов**: История заказов пользователя (`user_id`) находится на одном шарде — targeted query
2. **Избежание hotspot**: Добавление `_id` обеспечивает уникальность и распределение внутри пользователя
3. **Масштабируемость**: Новые заказы распределяются по шардам благодаря монотонно растущему `_id`

### 2.4 Индексы

```javascript
// Shard key index (создаётся автоматически)
db.orders.createIndex({ user_id: 1, _id: 1 })

// Поиск по статусу для конкретного пользователя
db.orders.createIndex({ user_id: 1, status: 1 })

// Поиск по дате для аналитики
db.orders.createIndex({ order_date: -1 })

// Поиск по геозоне (для региональных отчётов)
db.orders.createIndex({ geo_zone: 1, order_date: -1 })
```

### 2.5 Команды настройки шардирования

```javascript
// Включение шардирования для БД
sh.enableSharding("mobile_world")

// Создание индекса для shard key
db.orders.createIndex({ user_id: 1, _id: 1 })

// Шардирование коллекции
sh.shardCollection("mobile_world.orders", { user_id: 1, _id: 1 })
```

---

## 3. Коллекция products (Товары)

### 3.1 Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор товара
  name: String,                     // Наименование
  category: String,                 // Категория: "electronics", "audio", "appliances", "books"
  price: Decimal128,                // Цена
  stock: {                          // Остатки по геозонам
    moscow: Number,
    spb: Number,
    ekb: Number,
    kaliningrad: Number
  },
  attributes: {                     // Дополнительные атрибуты
    color: String,
    size: String,
    brand: String
  },
  updated_at: ISODate
}
```

### 3.2 Выбор Shard Key

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `_id` (hashed) | Равномерное распределение | Scatter-gather для категорий |
| `category` | Локальность по категориям | Неравномерное распределение |
| **`{category: 1, _id: 1}`** | Баланс категорий и распределения | — |

**Выбор: Compound Shard Key `{category: 1, _id: 1}`**

### 3.3 Обоснование

1. **Поиск по категориям**: Основной паттерн — фильтрация товаров по категории, targeted query
2. **Фильтрация по цене**: После отбора по категории фильтрация происходит на шарде
3. **Равномерность**: `_id` обеспечивает распределение товаров внутри категории
4. **Обновление остатков**: Операции update по `_id` эффективны

### 3.4 Индексы

```javascript
// Shard key index
db.products.createIndex({ category: 1, _id: 1 })

// Поиск по категории и цене
db.products.createIndex({ category: 1, price: 1 })

// Полнотекстовый поиск по названию
db.products.createIndex({ name: "text" })

// Поиск товаров с остатками в конкретной геозоне
db.products.createIndex({ "stock.moscow": 1 })
db.products.createIndex({ "stock.spb": 1 })
```

### 3.5 Команды настройки шардирования

```javascript
// Создание индекса для shard key
db.products.createIndex({ category: 1, _id: 1 })

// Шардирование коллекции
sh.shardCollection("mobile_world.products", { category: 1, _id: 1 })
```

---

## 4. Коллекция carts (Корзины)

### 4.1 Схема коллекции

```javascript
{
  _id: ObjectId,                    // Уникальный идентификатор корзины
  user_id: ObjectId,                // ID пользователя (null для гостей)
  session_id: String,               // ID сессии для гостей
  items: [                          // Товары в корзине
    {
      product_id: ObjectId,
      quantity: Number
    }
  ],
  status: String,                   // "active" | "ordered" | "abandoned"
  created_at: ISODate,
  updated_at: ISODate,
  expires_at: ISODate               // TTL для автоочистки
}
```

### 4.2 Выбор Shard Key

| Кандидат | Плюсы | Минусы |
|----------|-------|--------|
| `user_id` | Локальность для пользователей | null для гостей → hotspot |
| `session_id` | Хорошо для гостей | Scatter для залогиненных |
| `_id` (hashed) | Равномерное распределение | Scatter-gather |
| **`{status: 1, _id: "hashed"}`** | Разделение active/abandoned | — |

**Выбор: Hashed Shard Key `{_id: "hashed"}`**

### 4.3 Обоснование

1. **Разнородность запросов**: Корзины ищутся по `session_id` (гости) и `user_id` (пользователи)
2. **Равномерное распределение**: Hashed `_id` обеспечивает баланс нагрузки
3. **TTL индекс**: Автоматическая очистка старых корзин по `expires_at`
4. **Слияние корзин**: При логине читаем обе корзины (scatter), но это редкая операция

### 4.4 Индексы

```javascript
// Shard key (hashed)
// Создаётся автоматически при шардировании

// Поиск активной корзины гостя
db.carts.createIndex({ session_id: 1, status: 1 })

// Поиск активной корзины пользователя
db.carts.createIndex({ user_id: 1, status: 1 })

// TTL индекс для автоудаления
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

### 4.5 Команды настройки шардирования

```javascript
// Шардирование с hashed ключом
sh.shardCollection("mobile_world.carts", { _id: "hashed" })

// Настройка TTL
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

---

## 5. Сводная таблица Shard Keys

| Коллекция | Shard Key | Тип | Обоснование |
|-----------|-----------|-----|-------------|
| orders | `{user_id: 1, _id: 1}` | Compound Range | Локальность истории пользователя |
| products | `{category: 1, _id: 1}` | Compound Range | Локальность товаров в категории |
| carts | `{_id: "hashed"}` | Hashed | Равномерное распределение разнородных корзин |

---

## 6. Диаграмма распределения данных

```
┌─────────────────────────────────────────────────────────────────┐
│                         mongos_router                           │
└─────────────────────────┬───────────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
┌─────────────────────┐         ┌─────────────────────┐
│      Shard 1        │         │      Shard 2        │
├─────────────────────┤         ├─────────────────────┤
│ orders:             │         │ orders:             │
│  user_id: A-M       │         │  user_id: N-Z       │
├─────────────────────┤         ├─────────────────────┤
│ products:           │         │ products:           │
│  electronics, audio │         │  appliances, books  │
├─────────────────────┤         ├─────────────────────┤
│ carts:              │         │ carts:              │
│  hashed(_id) 50%    │         │  hashed(_id) 50%    │
└─────────────────────┘         └─────────────────────┘
```

---

## 7. Риски и митигация

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Hotspot на популярных категориях (products) | Средняя | Мониторинг chunk distribution, pre-splitting |
| Scatter-gather при поиске корзин | Низкая | Индексы на session_id и user_id |
| Jumbo chunks для активных пользователей | Низкая | Compound key с _id предотвращает |
| Неравномерное распределение geo_zone | — | Не используем как shard key |

---

## 8. Команды мониторинга

```javascript
// Статус шардирования
sh.status()

// Распределение данных по шардам
db.orders.getShardDistribution()
db.products.getShardDistribution()
db.carts.getShardDistribution()

// Статистика чанков
db.adminCommand({ listChunks: "mobile_world.orders" })
```

