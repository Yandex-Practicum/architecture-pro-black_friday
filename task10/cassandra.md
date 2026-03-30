# Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## Задание 10.1

### Что будем переносить:
1. Order history - Много чтения
2. Carts - Высокая write нагрузка. Данные короткоживущие, можно использовать TTL
3. User sessions - короткоживущие данные, большая частота записи, TTL
### Что не будем:
1. Orders - важна транзакционность чтобы не продать уже проданный товар (Спасибо за это замечание, ведь действительно в inventory товар должен резервироваться для orders и лучше это делать в одну транзакцию)
2. Products catalog - в каталоге требуются гибкие фильтры, наверно лучше оставить это в монге
3. inventory(остаток) - ошибка в консистентности может првиести к продаже уже проданного товара

## Задание 10.2

### 1. Order history by user
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
### 2. Carts by user
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
### 3. Carts by session
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
### 4. User sessions

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
| `order_history_by_user`    | да             | да, умеренно  | да                      | денормализованная таблица должна регулярно сходиться |
| `carts_by_user`            | да             | нет / минимум | да, периодически        | важна низкая latency, read repair лучше не нагружать |
| `carts_by_session`         | да             | нет           | по остаточному принципу | short-lived данные, важнее скорость                  |
| `user_sessions`            | да             | нет           | редко                   | TTL-данные, важнее доступность и скорость            |

