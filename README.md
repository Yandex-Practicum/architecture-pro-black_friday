# Проектная работа: Масштабирование MongoDB для онлайн-магазина "Мобильный мир"

## Описание проекта

Реализация высокодоступной архитектуры для онлайн-магазина с использованием:
- **MongoDB** с шардированием и репликацией
- **Redis** для кэширования
- **API Gateway** (nginx) для балансировки
- **Consul** для Service Discovery
- **CDN** для доставки статического контента

## Структура репозитория

```
├── diagrams/                    # Схемы архитектуры (draw.io)
│   ├── final_architecture.drawio   # Итоговая схема
│   ├── task1_step1_sharding.drawio
│   ├── task1_step2_replication.drawio
│   ├── task1_step3_caching.drawio
│   ├── task5_api_gateway.drawio
│   └── task6_cdn.drawio
├── docs/                        # Архитектурные документы (задания 7-10)
│   ├── architecture_document.md    # Единый архитектурный документ
│   ├── task7_sharding_design.md
│   ├── task8_hot_shards.md
│   ├── task9_read_preference.md
│   └── task10_cassandra_migration.md
├── mongo-sharding/              # Задание 2: Шардирование
├── mongo-sharding-repl/         # Задание 3: Шардирование + Репликация
├── sharding-repl-cache/         # Задание 4: + Redis Cache (финальная версия)
└── README.md
```

---

## Быстрый старт (финальная версия)

### Требования

- Docker и Docker Compose
- Минимум 4 GB RAM и 2 CPU

### Запуск проекта

```bash
cd sharding-repl-cache
docker compose up -d
```

### Инициализация MongoDB

Дождитесь запуска всех контейнеров (~15 секунд), затем:

```bash
./scripts/init-sharding.sh
```

Скрипт выполняет:
- Инициализацию Config Server Replica Set (3 ноды)
- Инициализацию Shard 1 Replica Set (3 ноды)
- Инициализацию Shard 2 Replica Set (3 ноды)
- Добавление шардов в кластер
- Включение шардирования для базы `somedb`
- Шардирование коллекции `helloDoc` по полю `age`

### Заполнение данными

```bash
./scripts/init-data.sh
```

Вставляет 1000 тестовых документов.

### Проверка работы

```bash
./scripts/check-shards.sh
```

---

## Проверка приложения

### Главная страница

Откройте в браузере: http://localhost:8080

Ожидаемый ответ (JSON):
```json
{
  "mongo_topology_type": "Sharded",
  "mongo_replicaset_name": null,
  "mongo_db": "somedb",
  "read_preference": "Primary()",
  "mongo_nodes": [...],
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018",
    "shard2": "shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018"
  },
  "cache_enabled": true,
  "status": "OK"
}
```

### Swagger документация

http://localhost:8080/docs

### Проверка кэширования

```bash
# Первый запрос (~1 сек)
time curl http://localhost:8080/helloDoc/users

# Второй запрос (<100 мс, из кэша)
time curl http://localhost:8080/helloDoc/users
```

---

## Архитектура

### Компоненты

| Сервис | Порт | Описание |
|--------|------|----------|
| pymongo_api | 8080 | API приложение |
| redis | 6379 | Кэш |
| mongos_router | 27020 | MongoDB Router |
| configSrv1/2/3 | 27017 | Config Server Replica Set |
| shard1-1/2/3 | 27018 | Shard 1 Replica Set |
| shard2-1/2/3 | 27018 | Shard 2 Replica Set |

### Схема

Итоговая схема: `diagrams/final_architecture.drawio`

```
Users → CDN → API Gateway (nginx) → pymongo_api → Redis (cache)
                                               ↓
                                        mongos_router
                                               ↓
                    ┌──────────────────────────┼──────────────────────────┐
                    ↓                          ↓                          ↓
            Config Server RS            Shard 1 RS                 Shard 2 RS
            (3 ноды)                   (3 ноды)                   (3 ноды)
```

---

## Проверка статуса сервисов

```bash
cd sharding-repl-cache
docker compose ps
```

Все сервисы должны быть в статусе `Up`.

---

## Остановка проекта

```bash
docker compose down
```

Для удаления данных:

```bash
docker compose down -v
```

---

## Документация

- [Архитектурный документ (задания 7-10)](docs/architecture_document.md)
- [Итоговая схема](diagrams/final_architecture.drawio)
