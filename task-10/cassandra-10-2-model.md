# Задание 10.2. Модель в Cassandra: ключи и таблицы

## Кратко

- Партиция — кусок данных на одном "логическом месте", по ней идёт основной запрос. Ключ партиции лучше делать "широким" (много разных значений).
- Кластеризация — порядок строк внутри партиции (сначала новые, по дате и т.д.).

## 1. `orders_by_order_id` — заказ по номеру

```sql
CREATE TABLE orders_by_order_id (
  order_id uuid, customer_id uuid, order_no text, created_at timestamp,
  status text, total decimal, geo_zone text, items text,
  PRIMARY KEY (order_id)
);
```

Обоснование:

- Partition key: `order_id` — один заказ = одна партиция, удобно сразу взять весь заказ по id.
- Clustering key: не нужен, если в одной строке лежит весь снимок заказа (как в примере).

## 2. `orders_by_user` — список "мои заказы"

```sql
CREATE TABLE orders_by_user (
  user_id uuid, created_at timestamp, order_id uuid, status text, total decimal,
  PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC);
```

Обоснование:

- Partition key: `user_id` — все заказы одного покупателя лежат в одной партиции, список отдаётся одним запросом по пользователю.
- Clustering: `дата_заказа` + `order_id` — сортировка внутри партиции, удобна пагинация; `order_id` снимает неоднозначность, если в одну секунду два заказа.
- Сортировка: `DESC` по дате — сначала новые заказы.

(Данные в обе таблицы пишем из сервиса/саги по одному событию оформления, чтобы пути "по id" и "по списку" согласовались по смыслу.)

## 3. `product_stock` — остаток по товару и зоне

```sql
CREATE TABLE product_stock (
  product_id uuid, geo_zone text, qty int, ver bigint,
  PRIMARY KEY ((product_id, geo_zone))
);
```

Обоснование:

- Partition key: `product_id` + `geo_zone` — не вся "Электроника" в одной куче, а отдельно каждый товар в каждой зоне склада; иначе одна категория = одна перегруженная партиция.
- Clustering: не используем — в партиции одна строка "остаток в этой зоне" (при росте логики можно вынести в отдельные поля, здесь — учебный минимум).

## 4. `product_by_id` — витрина, карточка товара (снимок)

```sql
CREATE TABLE product_by_id (
  product_id uuid,
  name text, category text, price decimal, description text, attrs text,
  PRIMARY KEY (product_id)
);
```

Обоснование:

- Partition key: `product_id` — открытие одной карточки = один запрос; размазка по id лучше, чем "вся витрина в одной партиции".
- Листинг "всё в категории X" в учебной схеме — отдельная тема (часто кэш/поиск), чтобы не ловить горячую партию "Электроника".

## 5. `carts` — корзина

```sql
CREATE TABLE carts (
  user_id uuid, line_id timeuuid, product_id uuid, quantity int, status text, updated_at timestamp,
  PRIMARY KEY ((user_id), line_id)
) WITH CLUSTERING ORDER BY (line_id ASC);
```

Обоснование:

- Partition key: `user_id` (или id сессии-гостя в том же виде) — вся корзина одного человека в одной партиции.
- Clustering: `line_id` (время+уникальность) — позиции в корзине по порядку, можно добавлять строки без коллизий.

(Возможен вариант одна строка на корзину с картой "товар → количество"; для курса достаточно явных строк.)

## 6. Про нагрузку и "горячие" партиции (по сути)

| Ситуация | Смысл |
|----------|--------|
| Категория = одна партиция | Плохо: вся нагрузка в одно место. У нас: stock — по (товар+зона), не по категории. |
| Очень длинный список одного `user_id` | Партиция разрастается: позже — резать по годам/архив, на курсе достаточно знать риск. |
| Смена сервера/ноды | Данные подтянутся кусками; смена самой схемы ключа = новая таблица + перенос, "не в один клик как в уроке про Mongo". |

## 7. Сводка ключей

| Таблица | Partition | Clustering |
|---------|-----------|------------|
| `orders_by_order_id` | `order_id` | — |
| `orders_by_user` | `user_id` | `created_at` (новые сверху), `order_id` |
| `product_stock` | `product_id` + `geo_zone` | — |
| `product_by_id` | `product_id` | — |
| `carts` | `user_id` | `line_id` по возрастанию |
