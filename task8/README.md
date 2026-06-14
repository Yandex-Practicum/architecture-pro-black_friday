# Задание 8. Выявление и устранение «горячих» шардов

Архитектурный документ для онлайн-магазина «Мобильный мир».

**Инцидент:** ~70% запросов — категория «Электроника» → перегруз шарда (legacy-ключ `category` или scatter-gather каталога при `{ _id: "hashed" }` ).

Схема: [diagrams/hot-shard-runbook.drawio](diagrams/hot-shard-runbook.drawio)
---

## 1. Легенда

| Термин | Значение |
|--------|----------|
| **Hot shard** | Шард с аномально высокой нагрузкой или объёмом chunks |
| **Chunk** | Диапазон шард-ключа на одном RS (`rs-shard1` / `rs-shard2`) |
| **Scatter-gather** | Запрос без шард-ключа в фильтре → все шарды (каталог `{ category, price }`) |
| **Targeted** | Запрос по шард-ключу → один шард (`_id`, `customer_id`, `owner_key`) |
| **Skew** | Дисбаланс между шардами (данные или QPS) |
| **Balancer** | Автоперенос chunks между rs-shard1 ↔ rs-shard2 |
| **Ветвление (◇)** | Только если «да» и «нет» ведут к **разным** исходам |
| **Условное действие** | Внутри шага □: «→ если …» — не ветвление, следующий шаг всё равно |

---

## 2. Ключевые метрики (уровень шарда) — §1.1

| Метрика | Описание | Целевое значение (SLA) |
|---------|----------|------------------------|
| **Chunks Distribution** | Количество и размер chunks на каждом шарде | Коэфф. вариации **< 10%** (разница в кол-ве не более 10%) |
| **Query/Load per Shard** | ops/s read/write на Primary шарда | Отклонение **≤ 20%** от среднего по кластеру |
| **Read/Write Latency (p99)** | Время операций на проблемном шарде | **≤ 100 ms**, не более **2×** других шардов |
| **CPU / IOPS** | Утилизация хоста шарда | **< 70%** в пиковые часы |
| **Balancer State** | Балансировщик и миграции chunks | **State: true**, **inBalancerRound: false** |


---

## 3. Команды снятия метрик
### Chunks Distribution

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
sh.status(true)
use mobile_world
db.products.getShardDistribution()
db.orders.getShardDistribution()
db.carts.getShardDistribution()
EOF

# стенд (somedb)
docker compose exec -T mongos-router mongosh --port 27020 --quiet --eval \
  'use somedb; db.helloDoc.getShardDistribution()'
```

```javascript
use config
db.chunks.aggregate([
  { $match: { ns: /^mobile_world\./ } },
  { $group: { _id: "$shard", chunks: { $sum: 1 }, jumbo: { $sum: { $cond: ["$jumbo", 1, 0] } } } },
])
```

### Query/Load per Shard

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet --eval 'db.serverStatus().opcounters'
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'db.serverStatus().opcounters'

docker compose exec -T shard1-1 mongostat --port 27019 'insert query update command' 5
docker compose exec -T shard2-1 mongostat --port 27019 'insert query update command' 5
```

```shell
# сводка по шардам из API
curl -s http://localhost:8080/ | jq '{shards_documents_count, shards_replicas_count}'
```

### Read/Write Latency (p99)

```javascript
// mongos
db.products.aggregate([{ $collStats: { latencyStats: { histograms: true } } }])

db.adminCommand({ currentOp: true, active: true, secs_running: { $gte: 0.1 } })
```

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet --eval \
  'db.setProfilingLevel(1, { slowms: 100 }); db.system.profile.find().sort({millis:-1}).limit(5)'
```

### CPU / IOPS

На хосте (node_exporter / `docker stats`) — по контейнерам `shard1-1`, `shard2-1`.

### Balancer State

```javascript
sh.getBalancerState()
sh.getBalancerStatus()
```

---

## 4. Универсальная проверка шардов (схема)

[Runbook](diagrams/hot-shard-runbook.drawio) — **одна колонка**, один ромб в начале, дальше строго **1 → 2 → 3 → 4 → 5**:

```
Начало → Снять метрики (§3)
       → 5 вопросов «в норме?» (§2)
       → ◇ Все 5 ответов «да»?
              ├─ да  → Вывод: SLA OK → Конец · В норме
              └─ нет → Вывод: ≥1 вне SLA → 1→5 (да→OK / нет→fix) → Повторно
                       → ◇ Все 5 снова «да»?
                              ├─ да  → Вывод: SLA восстановлен → END
                              └─ нет → Вывод: эскалация → Конец · Эскалация
```

**Промежуточные выводы:** на каждой ветке «да»/«нет» — блок «Вывод» перед следующим шагом или концом. На шагах 1–5 справа: «да → OK · нет → fix → следующий шаг».

| Шаг | Метрика | Вопрос §2 | Команды (§3) | Если «нет» |
|-----|---------|-----------|--------------|------------|
| Снять метрики | все 5 | — | все команды §3 | — |
| 5 вопросов | все 5 | «в норме?» × 5 | сравнить с §2 | все «да» → OK |
| 1 | Chunks Distribution | CV < 10%? | `getShardDistribution`, `config.chunks.aggregate` | Balancer, split, moveRange |
| 2 | Query/Load per Shard | skew ≤ 20%? | `mongostat`, `opcounters`, `curl :8080/` | currentOp, explain, reshard, hot key |
| 3 | Read/Write Latency (p99) | ≤ 100 ms, ≤ 2×? | `$collStats`, profiler, `currentOp` | индексы, read-model |
| 4 | CPU / IOPS | < 70%? | `docker stats` | масштаб, repl lag, disk |
| 5 | Balancer State | State: true? | `sh.getBalancerState/Status()` | `sh.startBalancer()`, ошибки миграций |
| Повторно | все 5 | снова все «да»? | §3 | да → END · нет → эскалация |

**Пример (инцидент «Электроника»):** на шаге 2 — scatter-gather каталога `{ category, price }`, reshard с `{ category }` на `{ _id: "hashed" }`, hot SKU при `$inc stock`.
