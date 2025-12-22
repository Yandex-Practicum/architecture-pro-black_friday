# Задание 9. Настройка чтения с реплик и консистентность

## 1. Обзор Read Preference в MongoDB

| Read Preference | Описание | Консистентность |
|-----------------|----------|-----------------|
| `primary` | Только с primary | Строгая (strong) |
| `primaryPreferred` | Primary, fallback на secondary | Строгая с fallback |
| `secondary` | Только с secondary | Eventual |
| `secondaryPreferred` | Secondary, fallback на primary | Eventual с fallback |
| `nearest` | Ближайшая нода | Eventual |

---

## 2. Коллекция products (Товары)

### 2.1 Анализ операций

| Операция | Read Preference | Допустимая задержка | Обоснование |
|----------|-----------------|---------------------|-------------|
| **Каталог товаров** (список по категории) | `secondaryPreferred` | 5-10 сек | Отображение списка товаров некритично к актуальности |
| **Карточка товара** (описание, цена) | `secondaryPreferred` | 5-10 сек | Описание и цена меняются редко |
| **Проверка остатков перед покупкой** | `primary` | 0 | Критично! Риск продажи отсутствующего товара |
| **Поиск товаров** | `secondary` | 10-30 сек | Поисковая выдача может быть eventual |
| **Фильтрация по цене** | `secondaryPreferred` | 5 сек | Небольшое расхождение цен допустимо |

### 2.2 Обоснование

**Почему `secondaryPreferred` для каталога:**
- Каталог — read-heavy операция (90% трафика)
- Изменения описаний/цен редки (раз в день/неделю)
- Разгрузка primary для критичных операций

**Почему `primary` для остатков:**
- Остатки меняются при каждой покупке
- Риск overselling — продажа товара, которого нет
- Финансовые потери и негатив клиентов

### 2.3 Примеры кода

```javascript
// Каталог товаров — с реплик
db.products.find({ category: "electronics" })
  .readPref("secondaryPreferred", [{ maxStalenessSeconds: 10 }])

// Проверка остатков — только primary
db.products.findOne(
  { _id: productId },
  { projection: { stock: 1 } }
).readPref("primary")

// Карточка товара — с реплик
db.products.findOne({ _id: productId })
  .readPref("secondaryPreferred")
```

---

## 3. Коллекция orders (Заказы)

### 3.1 Анализ операций

| Операция | Read Preference | Допустимая задержка | Обоснование |
|----------|-----------------|---------------------|-------------|
| **Создание заказа** | `primary` (write) | 0 | Запись всегда на primary |
| **Статус заказа для клиента** | `primaryPreferred` | 1-2 сек | Клиент ожидает актуальный статус |
| **История заказов** | `secondaryPreferred` | 30-60 сек | Исторические данные не меняются |
| **Список заказов в админке** | `secondary` | 30 сек | Админ может подождать |
| **Отчёты и аналитика** | `secondary` | 60 сек+ | Аналитика не требует real-time |
| **Проверка заказа перед оплатой** | `primary` | 0 | Критично для бизнес-логики |

### 3.2 Обоснование

**Почему `primaryPreferred` для статуса:**
- Пользователь только что оформил заказ и хочет видеть статус
- Задержка 1-2 сек приемлема (UX)
- При недоступности primary — fallback на secondary лучше, чем ошибка

**Почему `secondary` для истории:**
- Старые заказы не меняются
- Нет риска бизнес-ошибок
- Значительная разгрузка primary

### 3.3 Примеры кода

```javascript
// Статус заказа — предпочтительно primary
db.orders.findOne(
  { _id: orderId, user_id: userId },
  { projection: { status: 1, updated_at: 1 } }
).readPref("primaryPreferred", [{ maxStalenessSeconds: 2 }])

// История заказов — с реплик
db.orders.find({ user_id: userId })
  .sort({ order_date: -1 })
  .readPref("secondaryPreferred", [{ maxStalenessSeconds: 60 }])

// Аналитика — только secondary
db.orders.aggregate([
  { $match: { order_date: { $gte: startDate } } },
  { $group: { _id: "$status", count: { $sum: 1 } } }
]).readPref("secondary")
```

---

## 4. Коллекция carts (Корзины)

### 4.1 Анализ операций

| Операция | Read Preference | Допустимая задержка | Обоснование |
|----------|-----------------|---------------------|-------------|
| **Получение активной корзины** | `primary` | 0 | Критично! Пользователь должен видеть актуальную корзину |
| **Добавление товара** | `primary` (write) | 0 | Запись |
| **Проверка перед оформлением** | `primary` | 0 | Проверка актуального состояния |
| **Слияние гостевой корзины** | `primary` | 0 | Критичная операция с несколькими документами |
| **Статистика abandoned carts** | `secondary` | 5 мин | Аналитика, не критично |

### 4.2 Обоснование

**Почему `primary` для корзины:**
- Корзина — часто обновляемый объект
- Пользователь ожидает мгновенную реакцию UI
- Риск потери товаров при чтении устаревших данных
- Race condition при параллельных обновлениях

**Почему eventual consistency неприемлема:**
- Сценарий: Пользователь добавил товар → читает с secondary → не видит товар → думает, что сломано
- Потеря конверсии и негативный UX

### 4.3 Примеры кода

```javascript
// Получение корзины — только primary
db.carts.findOne({
  user_id: userId,
  status: "active"
}).readPref("primary")

// Гостевая корзина — только primary
db.carts.findOne({
  session_id: sessionId,
  status: "active"
}).readPref("primary")

// Статистика abandoned — с реплик
db.carts.countDocuments({
  status: "abandoned",
  updated_at: { $lt: new Date(Date.now() - 86400000) }
}).readPref("secondary")
```

---

## 5. Сводная таблица

| Коллекция | Операция | Read Preference | Задержка | Риск при eventual |
|-----------|----------|-----------------|----------|-------------------|
| **products** | Каталог | secondaryPreferred | 10 сек | Низкий |
| **products** | Карточка | secondaryPreferred | 10 сек | Низкий |
| **products** | Остатки | **primary** | 0 | **Overselling** |
| **products** | Поиск | secondary | 30 сек | Низкий |
| **orders** | Статус | primaryPreferred | 2 сек | Устаревший статус |
| **orders** | История | secondaryPreferred | 60 сек | Низкий |
| **orders** | Проверка | **primary** | 0 | **Двойная оплата** |
| **orders** | Аналитика | secondary | 5 мин | Нет |
| **carts** | Активная | **primary** | 0 | **Потеря товаров** |
| **carts** | Слияние | **primary** | 0 | **Race condition** |
| **carts** | Статистика | secondary | 5 мин | Нет |

---

## 6. Настройка допустимой задержки репликации

### 6.1 maxStalenessSeconds

```javascript
// Настройка на уровне клиента (connection string)
mongodb://mongos:27020/?readPreference=secondaryPreferred&maxStalenessSeconds=10

// Настройка на уровне операции
db.collection.find().readPref("secondaryPreferred", [{ maxStalenessSeconds: 10 }])
```

### 6.2 Рекомендуемые значения

| Тип данных | maxStalenessSeconds | Обоснование |
|------------|---------------------|-------------|
| Критичные (остатки, корзина) | Не применимо (primary) | — |
| Оперативные (статус заказа) | 2-5 | Пользователь ожидает актуальность |
| Справочные (каталог) | 10-30 | Редко меняется |
| Аналитические | 60-300 | Не требует real-time |

### 6.3 Мониторинг replication lag

```javascript
// Проверка задержки репликации
rs.printSecondaryReplicationInfo()

// Алерт если lag > порога
db.adminCommand({ replSetGetStatus: 1 }).members.forEach(m => {
  if (m.stateStr === "SECONDARY") {
    const lagSeconds = (new Date() - m.optimeDate) / 1000;
    if (lagSeconds > 10) {
      print(`WARNING: ${m.name} lag = ${lagSeconds}s`);
    }
  }
});
```

---

## 7. Диаграмма потоков чтения

```
                                    ┌─────────────────┐
                                    │     Client      │
                                    └────────┬────────┘
                                             │
                                             ▼
                                    ┌─────────────────┐
                                    │  pymongo-api    │
                                    └────────┬────────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
                    ▼                        ▼                        ▼
           ┌────────────────┐       ┌────────────────┐       ┌────────────────┐
           │ Остатки/Корзина│       │  Каталог/Поиск │       │   Аналитика    │
           │   (primary)    │       │ (secondary)    │       │  (secondary)   │
           └───────┬────────┘       └───────┬────────┘       └───────┬────────┘
                   │                        │                        │
                   ▼                        ▼                        ▼
           ┌────────────────┐       ┌────────────────┐       ┌────────────────┐
           │    PRIMARY     │       │   SECONDARY    │       │   SECONDARY    │
           │   shard1-1     │       │   shard1-2     │       │   shard1-3     │
           └────────────────┘       └────────────────┘       └────────────────┘
```

---

## 8. Конфигурация приложения

```python
# Python (pymongo) пример
from pymongo import MongoClient, ReadPreference
from pymongo.read_preferences import Secondary, SecondaryPreferred

client = MongoClient("mongodb://mongos:27020/")
db = client["mobile_world"]

# Каталог — secondaryPreferred с max staleness
catalog_collection = db.get_collection(
    "products",
    read_preference=SecondaryPreferred(max_staleness=10)
)

# Остатки — primary
def check_stock(product_id):
    return db.products.with_options(
        read_preference=ReadPreference.PRIMARY
    ).find_one({"_id": product_id}, {"stock": 1})

# Корзина — primary
def get_cart(user_id):
    return db.carts.with_options(
        read_preference=ReadPreference.PRIMARY
    ).find_one({"user_id": user_id, "status": "active"})
```

---

## 9. Риски и митигация

| Риск | Вероятность | Последствия | Митигация |
|------|-------------|-------------|-----------|
| Overselling при чтении остатков с secondary | Высокая | Финансовые потери, возвраты | Всегда primary для остатков |
| Устаревший статус заказа | Средняя | Негативный UX | primaryPreferred + maxStaleness=2 |
| Потеря товаров в корзине | Высокая | Потеря конверсии | Всегда primary для корзин |
| Высокая нагрузка на primary | Средняя | Деградация производительности | Разгрузка через secondary для каталога |

