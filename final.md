# Задание 7. Проектирование схем коллекций для шардирования данных

## 1. Цель
Спроектировать коллекции `orders`, `products`, `carts` и выбрать шард-ключи, обеспечивающие:
- равномерное распределение нагрузки
- быстрые основные операции
- масштабируемость

## 2. Коллекция `orders`
### Схема
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": ISODate,
  "status": "created|paid|shipped|delivered|cancelled",
  "geo_zone": "MSK",
  "items": [
    {
      "product_id": ObjectId,
      "price": NumberDecimal,
      "quantity": Number,
      "line_total": NumberDecimal
    }
  ],
  "total_amount": NumberDecimal
}
```

Шард ключ { user_id: "hashed" }

#### Обоснование
- частые запросы по user_id (история заказов)
- равномерное распределение записей
- отсутствие горячих шардов при росте заказов

## 3. Коллекция `products`
### Схема
```json
{
  "_id": ObjectId,
  "sku": "string",
  "name": "string",
  "category": "string",
  "price": NumberDecimal,
  "attributes": {
    "color": "string",
    "size": "string"
  },
  "stock_by_geo": [
    { "geo_zone": "MSK", "quantity": Number }
  ],
  "updated_at": ISODate
}
```
Шард-ключ { _id: "hashed" }

#### Обоснование
- частые обновления остатков -> нужна равномерная запись
- быстрый доступ к товару по ID
- избегаем перекоса по категориям

## 4. Коллекция carts
### Схема
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "session_id": "string",
  "owner_key": "user:<id> | session:<id>",
  "status": "active|ordered|abandoned",
  "items": [
    { "product_id": ObjectId, "quantity": Number }
  ],
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate
}
```
Шард ключ { owner_key: "hashed" }

#### Обоснование
- единый доступ для гостей и пользователей
- точечные запросы к активной корзине
- равномерное распределение write-нагрузки

Индексы:

```
db.orders.createIndex({ user_id: 1, created_at: -1 })
db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ sku: 1 }, { unique: true })
db.carts.createIndex({ owner_key: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

Команды для шардинга

```
sh.enableSharding("mobile_world")

sh.shardCollection("mobile_world.orders", { user_id: "hashed" })
sh.shardCollection("mobile_world.products", { _id: "hashed" })
sh.shardCollection("mobile_world.carts", { owner_key: "hashed" })
```

# Задание 8. Выявление и устранение «горячих» шардов

## 1. Цель
- Разработайте набор метрик, чтобы отслеживать состояние шардов.
- Предложите механизмы автоматического перераспределения данных.

## 2. Метрики для поиска проблем

- количество запросов на шард: read/write ops per second
- среднюю и p95/p99 задержку запросов
- загрузку CPU и RAM по каждому шарду
- дисковый I/O и очередь операций
- размер чанков и их распределение по шардам
- количество документов и объём данных на каждом шарде
- частоту миграции чанков
- долю запросов по популярным категориям, например category = "electronics"

Для решения - настроить мониторинг и алертинг ^ 

Анализ распределения чанков

## 3. Механизмы автоматического перераспределения

- смена shard key или принудительное перераспределение данных
- добавление нового шарда

# Задание 9. Настройка чтения с реплик и консистентность

## Таблица чтения для products, orders, carts

| Коллекция  | Операция чтения                                              | Primary / Secondary | Допустимая задержка репликации | Обоснование                                                                                                                 |
| ---------- | ------------------------------------------------------------ | ------------------: | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `products` | Описание товара на странице                                  |         `secondary` | до **5–10 сек**                | Небольшое устаревание названия, атрибутов и цены обычно некритично, если покупка потом всё равно валидируется на `primary`. |
| `products` | Каталог: поиск по категории, фильтр по цене                  |         `secondary` | до **5–10 сек**                | Это read-heavy сценарий, можно разгрузить `primary`. Небольшая задержка приемлема для витрины.                              |
| `products` | Чтение остатков перед добавлением в корзину                  |           `primary` | **0 сек**                      | Остатки меняются часто. Чтение с `secondary` может показать товар доступным, хотя он уже закончился.                        |
| `products` | Проверка остатков перед оформлением заказа                   |           `primary` | **0 сек**                      | Критичный сценарий: риск oversell и продажи недоступного товара.                                                            |
| `orders`   | История заказов пользователя                                 |         `secondary` | до **1–3 сек**                 | Для списка прошлых заказов небольшая задержка допустима.                                                                    |
| `orders`   | Просмотр деталей уже завершённого заказа                     |         `secondary` | до **1–3 сек**                 | Если заказ не меняется активно, допустимо читать с реплики.                                                                 |
| `orders`   | Статус только что созданного / только что изменённого заказа |           `primary` | **0 сек**                      | Пользователь ожидает актуальный статус сразу после оплаты или смены состояния.                                              |
| `orders`   | Проверка заказа после создания                               |           `primary` | **0 сек**                      | Нельзя показывать, что заказ “не найден”, если он ещё не успел реплицироваться.                                             |
| `carts`    | Получение активной корзины пользователя                      |           `primary` | **0 сек**                      | Корзина часто меняется: добавление, удаление, merge, checkout. Устаревшие данные приведут к ошибкам в интерфейсе и заказе.  |
| `carts`    | Получение гостевой корзины по `session_id`                   |           `primary` | **0 сек**                      | Те же причины: корзина - высокочастотно обновляемая сущность.                                                               |
| `carts`    | Чтение корзины перед merge guest -> user                      |           `primary` | **0 сек**                      | Иначе можно потерять часть товаров или слить неактуальную версию.                                                           |
| `carts`    | Чтение корзины перед отметкой `ordered`                      |           `primary` | **0 сек**                      | Нужна строгая актуальность перед оформлением заказа.                                                                        |
| `carts`    | Чтение брошенных / старых корзин для аналитики               |         `secondary` | до **30–60 сек**               | Аналитика не требует строгой консистентности.                                                                               |

# Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## Задание 10.1

### Что будем переносить:
1. Orders - Много записей. Нужно выдерживать пик записей
2. Order history - Много чтения
3. Carts - Высокая write нагрузка. Данные короткоживущие, можно использовать TTL
4. User sessions - короткоживущие данные, большая частота записи, TTL
### Что не будем:
1. Products catalog - в каталоге требуются гибкие фильтры, наверно лучше оставить это в монге
2. inventory(остаток) - ошибка в консистентности может првиести к продаже уже проданного товара

## Задание 10.2

### 1. Orders by id
```
CREATE TABLE orders_by_id (
    order_id uuid,
    user_id uuid,
    created_at timestamp,
    status text,
    geo_zone text,
    total_amount decimal,
    items text,
    PRIMARY KEY ((order_id))
);
```

- заказ читается по точному идентификатору
- uuid хорошо распределяется по token ring
### 2. Order history by user
```
CREATE TABLE order_history_by_user (
    user_id uuid,
    bucket_month text,
    created_at timestamp,
    order_id uuid,
    status text,
    total_amount decimal,
    geo_zone text,
    PRIMARY KEY ((user_id, bucket_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```
partition key: (user_id, bucket_month)

Если сделать partition key только user_id, у активных пользователей может вырасти слишком большая партиция поэтому добавляется bucket по месяцу
### 3. Carts by user
```
CREATE TABLE carts_by_user (
    user_id uuid,
    cart_status text,
    updated_at timestamp,
    cart_id uuid,
    items text,
    expires_at timestamp,
    PRIMARY KEY ((user_id), cart_status, updated_at, cart_id)
) WITH CLUSTERING ORDER BY (cart_status ASC, updated_at DESC, cart_id ASC);
```
- Корзина почти всегда читается по конкретному пользователю
- горячей глобальной partition нет, так как пользователей много
### 4. Carts by session
```
CREATE TABLE carts_by_session (
    session_id text,
    cart_id uuid,
    items text,
    updated_at timestamp,
    expires_at timestamp,
    PRIMARY KEY ((session_id))
);
```
- равномерное распределение
### 5. User sessions

```
CREATE TABLE user_sessions (
    session_id text,
    user_id uuid,
    created_at timestamp,
    updated_at timestamp,
    payload text,
    PRIMARY KEY ((session_id))
)
```
- данные распределяются равномерно


| Сущность                   | Hinted Handoff | Read Repair   | Anti-Entropy Repair     | Обоснование                                          |
| -------------------------- | -------------- | ------------- | ----------------------- | ---------------------------------------------------- |
| `orders_by_id`             | да             | ограниченно   | да, обязательно         | заказ важен, нужна высокая вероятность сходимости    |
| `order_history_by_user`    | да             | да, умеренно  | да                      | денормализованная таблица должна регулярно сходиться |
| `carts_by_user`            | да             | нет / минимум | да, периодически        | важна низкая latency, read repair лучше не нагружать |
| `carts_by_session`         | да             | нет           | по остаточному принципу | short-lived данные, важнее скорость                  |
| `user_sessions`            | да             | нет           | редко                   | TTL-данные, важнее доступность и скорость            |

