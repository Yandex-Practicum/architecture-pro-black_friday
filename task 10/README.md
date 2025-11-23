## Миграция на Cassandra: стратегия и модель данных

### 10.1. Критически важные данные и обоснование выбора Cassandra

**Критически важные сущности** (приоритет по нагрузке и влиянию на бизнес):

1. **Корзины пользователей (`carts`)**  
   *Почему критично:*  
   - Высокая частота обновлений (добавление/удаление товаров).  
   - Требование мгновенного отклика (пользователь ждёт < 300 мс).  
   - Потеря данных = потеря продаж.  
   *Cassandra подходит:*  
   - Быстрая запись (log-structured storage).  
   - Возможность локального чтения/записи в геораспределённом кластере.  
   - Масштабирование без простоя.

2. **Заказы (`orders`)**  
   *Почему критично:*  
   - Фиксация платежей требует надёжности.  
   - Высокие пики нагрузки (например, «чёрная пятница»).  
   *Cassandra подходит:*  
   - Гарантированная доступность (quorum-согласованность).  
   - Отказоустойчивость при падении узлов.

3. **Остатки товаров (`stock`)**  
   *Почему критично:*  
   - Риск oversell (продажа отсутствующего товара).  
   - Частые обновления при покупках.  
   *Cassandra подходит:*  
   - Atomic compare-and-swap через Lightweight Transactions (LWT).  
   - Низкая задержка при чтении остатков.

4. **Пользовательские сессии (`sessions`)**  
   *Почему критично:*  
   - Требуется быстрая аутентификация.  
   - Высокая нагрузка при входе/выходе.  
   *Cassandra подходит:*  
   - Key-value модель с O(1) доступом.  
   - TTL для автоматической очистки.

**Сущности, где Cassandra *менее* предпочтительна:**
- **История заказов** (редкие чтения, можно хранить в аналитической БД).  
- **Описания товаров** (низкая частота обновлений, лучше MongoDB/Elasticsearch для полнотекстового поиска).

---

### 10.2. Концептуальная модель данных

#### 1. Корзины (`carts`)
```sql
CREATE TABLE carts (
    user_id UUID,                -- Partition key
    session_id TEXT,            -- Clustering key
    items MAP<UUID, INT>,       -- product_id → quantity
    total_amount DECIMAL,
    updated_at TIMESTAMP,
    PRIMARY KEY (user_id, session_id)
) WITH CLUSTERING ORDER BY (session_id DESC);
```
*Обоснование:*  
- `user_id` как partition key обеспечивает локальность данных пользователя.  
- `session_id` позволяет хранить несколько корзин (гостевая + авторизованная).  
- Равномерное распределение: UUID user_id избегает «горячих» партиций.  
- Чтение по `user_id` → все корзины пользователя за O(1).

#### 2. Заказы (`orders`)
```sql
CREATE TABLE orders (
    order_id UUID,              -- Partition key
    user_id UUID,
    items LIST<TEXT>,
    total DECIMAL,
    status TEXT,
    created_at TIMESTAMP,
    geo_zone TEXT,
    PRIMARY KEY (order_id)
);
```
*Обоснование:*  
- `order_id` гарантирует уникальность и равномерное распределение (UUID v4).  
- Запросы по `order_id` идут на один узел → минимальная задержка.  
- Для поиска по `user_id` создаём Materialized View:  
  ```sql
  CREATE MATERIALIZED VIEW orders_by_user AS
      SELECT * FROM orders
      WHERE user_id IS NOT NULL AND order_id IS NOT NULL
      PRIMARY KEY (user_id, order_id)
      WITH CLUSTERING ORDER BY (order_id DESC);
  ```

#### 3. Остатки товаров (`stock`)
```sql
CREATE TABLE stock (
    product_id UUID,            -- Partition key
    geo_zone TEXT,             -- Clustering key
    available_count INT,
    last_updated TIMESTAMP,
    PRIMARY KEY (product_id, geo_zone)
) WITH CLUSTERING ORDER BY (geo_zone ASC);
```
*Обоснование:*  
- `product_id` распределяет нагрузку между узлами.  
- `geo_zone` позволяет хранить остатки по регионам в одной партиции.  
- Для популярных товаров (риск «горячей» партиции):  
  - Использовать композитный partition key: `(hash(product_id), geo_zone)`.  
  - Настроить `num_tokens=256` для лучшей балансировки.

#### 4. Сессии (`sessions`)
```sql
CREATE TABLE sessions (
    session_id TEXT,            -- Partition key
    user_id UUID,
    expires_at TIMESTAMP,
    data MAP<TEXT, TEXT>,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400;  -- TTL 1 день
```
*Обоснование:*  
- Прямой доступ по `session_id` → O(1).  
- TTL автоматически очищает устаревшие сессии.  
- Равномерное распределение благодаря случайной генерации `session_id`.

**Защита от «горячих» партиций:**  
- Использовать **композитные partition key** (например, `(user_id, shard_id)`).  
- Применять **солирование** (salting): добавлять случайный суффикс к ключу.  
- Мониторить load на узлы через `nodetool tpstats` и `nodetool tablestats`.

---

### 10.3. Стратегии обеспечения целостности

#### 1. Hinted Handoff
*Как работает:*  
- Если узел недоступен, другие узлы временно хранят записи («hints»).  
- После восстановления узла данные доставляются.  
*Где применять:*  
- **Корзины (`carts`)** и **сессии (`sessions`)** — терпимы к кратковременной несогласованности.  
*Компромисс:*  
- + Доступность (writes succeed даже при падении узла).  
- − Возможная задержка доставки (до 3 часов по умолчанию).


#### 2. Read Repair
*Как работает:*  
- При чтении сравниваются версии данных на репликах.  
- Если найдены расхождения, выполняется синхронизация.  
*Где применять:*  
- **Заказы (`orders`)** — критичны для платежей.  
- **Остатки (`stock`)** — предотвращение oversell.  
*Компромисс:*  
- + Повышенная согласованность.  
- − Небольшой overhead на чтение (проверка реплик).

#### 3. Anti-Entropy Repair
*Как работает:*  
- Периодический запуск `nodetool repair` для полной синхронизации реплик.  
*Где применять:*  
- Все таблицы, но с разной частотой:  
  - `orders`, `stock`: еженедельно.  
  - `carts`, `sessions`: раз в 2 недели (менее критично).  
*Компромисс:*  
- + Полная консистентность.  
- − Высокая нагрузка на сеть/CPU во время ремонта.

#### Итоговая матрица стратегий

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy | Уровень согласованности |
|--------|---------------|-----------|-------------|-----------------------|
| `carts` | ✅ (вкл.) | ❌ | Раз в 2 нед. | **Eventual** (доступность важнее) |
| `orders` | ✅ | ✅ (quorum) | Еженедельно | **Strong** (quorum reads/writes) |
| `stock` | ✅ | ✅ (LWT) | Еженедельно | **Linearizable** (через LWT) |
| `sessions` | ✅ | ❌ | Раз в 2 нед. | **Eventual** |

**Обоснование выбора уровней согласованности:**  
- **Eventual Consistency** (`carts`, `sessions`): допустимы кратковременные расхождения (корзина обновится при следующем запросе).  
- **Strong Consistency** (`orders`): платежи требуют quorum (RF=3, CL=QUORUM).  
- **Linearizable Consistency** (`stock`): Lightweight Transactions гарантируют атомарность обновлений остатков.

**Компромиссы:**  
- Для `orders` и `stock` жертвуем latency (quorum требует 2/3 реплик) ради целостности.  
- Для `carts` и `sessions` выбираем доступность — потеря корзины менее критична, чем простой сервиса.