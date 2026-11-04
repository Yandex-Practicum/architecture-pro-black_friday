# Задание 10. Миграция на Cassandra

## 10.1. Выбор данных для миграции

В Cassandra переносим данные, которые часто читаются и записываются по известному ключу и требуют высокой производительности.

**Переносим в Cassandra:**

- **История заказов** — быстрый поиск заказов по `user_id`. Информацию о товарах храним внутри заказа (денормализация).
- **Корзины** — частые операции чтения и изменения по идентификатору пользователя или сессии.
- **Пользовательские сессии** — быстрый поиск по `session_id`, высокая нагрузка и автоматическое удаление устаревших данных через TTL.

**Оставляем в MongoDB:**

- **Товары** — требуют гибкого поиска по категориям, ценам и характеристикам.
- **Текущие заказы и остатки** — требуют согласованного изменения данных при покупке, что сложнее обеспечить в Cassandra.

Таким образом, Cassandra используется для высоконагруженных операций по ключу, а MongoDB — для гибких запросов и транзакционной обработки.

## 10.2. Модель данных Cassandra

Используем `NetworkTopologyStrategy` с тремя репликами на разных узлах:

```sql
CREATE KEYSPACE mobile_world
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'dc1': 3
};

USE mobile_world;
```

### История заказов

- **Partition key:** `(user_id, bucket_month)` — распределяет историю по пользователям и месяцам.
- **Clustering key:** `(created_at, order_id)` — сортирует заказы по дате.

```sql
CREATE TABLE order_history (
    user_id uuid,
    bucket_month text,
    order_id uuid,
    created_at timestamp,
    status text,
    total decimal,
    PRIMARY KEY ((user_id, bucket_month), created_at, order_id)
) WITH CLUSTERING ORDER BY (
    created_at DESC,
    order_id ASC
);
```

Разделение истории по месяцам ограничивает размер партиций и уменьшает риск горячих партиций.

### Корзины

- **Partition key:** `owner_id` — идентификатор пользователя или гостевой сессии.
- **Clustering key:** не требуется.

```sql
CREATE TABLE carts (
    owner_id text PRIMARY KEY,
    cart_id uuid,
    items map<uuid, int>,
    status text,
    updated_at timestamp
);
```

`owner_id` формируется как `user:<uuid>` или `session:<uuid>`.

### Пользовательские сессии

- **Partition key:** `session_id`.
- **Clustering key:** не требуется.

```sql
CREATE TABLE user_sessions (
    session_id uuid PRIMARY KEY,
    user_id uuid,
    created_at timestamp,
    last_activity timestamp
);
```

Для автоматического удаления сессий при записи устанавливаем TTL, например 24 часа:

```sql
INSERT INTO user_sessions (
    session_id, user_id, created_at, last_activity
)
VALUES (
    uuid(), uuid(), toTimestamp(now()), toTimestamp(now())
)
USING TTL 86400;
```

### Распределение данных

Cassandra использует consistent hashing и виртуальные узлы (vnodes). При добавлении нового узла переносится только часть данных, а не вся база.

Ключи с высокой кардинальностью обеспечивают равномерное распределение партиций. Для истории заказов дополнительно используется разделение по месяцам.

## 10.3. Репликация и согласованность

Используем три механизма восстановления согласованности:

**Hinted Handoff** — применяем для всех сущностей. При временной недоступности реплики Cassandra сохраняет информацию о пропущенных записях и пытается передать её после восстановления.

**Read Repair** — используем для истории заказов и корзин. При чтении с кворумом Cassandra может обнаружить расхождения между репликами и исправить их. Используем `BLOCKING`:

```sql
ALTER TABLE order_history
WITH read_repair = 'BLOCKING';

ALTER TABLE carts
WITH read_repair = 'BLOCKING';
```

**Anti-Entropy Repair** — периодически запускаем для всех сущностей, чтобы синхронизировать реплики:

```bash
nodetool repair mobile_world
```

### Уровни согласованности

- **История заказов и корзины:** `LOCAL_QUORUM` для чтения и записи. При трёх репликах требуется подтверждение от двух, что уменьшает вероятность получения устаревших данных.
- **Пользовательские сессии:** `LOCAL_ONE` для некритичных чтений и `LOCAL_QUORUM` для записи. Для проверки авторизации и отзыва сессии используем `LOCAL_QUORUM`.

Пример установки уровня согласованности:

```sql
CONSISTENCY LOCAL_QUORUM;
```
