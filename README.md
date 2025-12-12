# pymongo-api - Проектная работа Sprint 4

## Структура репозитория

```
├── api_app/                    # Исходный код API
├── mongo-sharding/             # Задание 2: Шардирование
├── mongo-sharding-repl/        # Задание 3: Шардирование + Репликация
├── sharding-repl-cache/        # Задание 4: Шардирование + Репликация + Redis Cache
├── task1.drawio                # Схема 1: Исходная архитектура
├── task2.drawio                # Схема 2: Шардирование
├── task3.drawio                # Схема 3: Шардирование + Репликация
├── task4.drawio                # Схема 4: + Redis Cache
├── task5.drawio                # Схема 5: + API Gateway, Consul, CDN
├── ARCHITECTURE_DOCUMENT.md    # Задания 7-10: Архитектурный документ
└── README.md                   # Этот файл
```

---

## Быстрый старт (Финальная конфигурация)

Для проверки финального решения (Задания 2-4) используйте директорию `sharding-repl-cache`:

```shell
cd sharding-repl-cache
docker compose up -d
```

Дождитесь запуска всех контейнеров (12 сервисов):

```shell
docker compose ps
```

### Инициализация кластера

1. Инициализация Config Server Replica Set:
```shell
docker compose exec -T configSrv1 mongosh --port 27017 --eval "rs.initiate({_id: 'config_rs', configsvr: true, members: [{_id: 0, host: 'configSrv1:27017'}, {_id: 1, host: 'configSrv2:27017'}, {_id: 2, host: 'configSrv3:27017'}]})"
```

2. Инициализация Shard 1 Replica Set:
```shell
docker compose exec -T shard1a mongosh --port 27018 --eval "rs.initiate({_id: 'shard1_rs', members: [{_id: 0, host: 'shard1a:27018'}, {_id: 1, host: 'shard1b:27018'}, {_id: 2, host: 'shard1c:27018'}]})"
```

3. Инициализация Shard 2 Replica Set:
```shell
docker compose exec -T shard2a mongosh --port 27019 --eval "rs.initiate({_id: 'shard2_rs', members: [{_id: 0, host: 'shard2a:27019'}, {_id: 1, host: 'shard2b:27019'}, {_id: 2, host: 'shard2c:27019'}]})"
```

4. Подождите 10 секунд, затем добавьте шарды в роутер:
```shell
docker compose exec -T mongos_router mongosh --port 27020 --eval "sh.addShard('shard1_rs/shard1a:27018,shard1b:27018,shard1c:27018'); sh.addShard('shard2_rs/shard2a:27019,shard2b:27019,shard2c:27019')"
```

5. Включите шардирование и создайте коллекцию:
```shell
docker compose exec -T mongos_router mongosh --port 27020 --eval "sh.enableSharding('somedb'); sh.shardCollection('somedb.helloDoc', {age: 'hashed'})"
```

6. Заполните базу данными:
```shell
docker compose exec -T mongos_router mongosh --port 27020 somedb --eval "for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:'ly'+i}); print('Count: ' + db.helloDoc.countDocuments())"
```

---

## Проверка работы

### API доступно по адресу:
- http://localhost:8080

### Swagger документация:
- http://localhost:8080/docs

### Ожидаемый ответ API:
```json
{
  "mongo_topology_type": "Sharded",
  "mongo_is_mongos": true,
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1_rs": "shard1_rs/shard1a:27018,shard1b:27018,shard1c:27018",
    "shard2_rs": "shard2_rs/shard2a:27019,shard2b:27019,shard2c:27019"
  },
  "cache_enabled": true,
  "status": "OK"
}
```

### Проверка распределения данных по шардам:
```shell
docker compose exec -T mongos_router mongosh --port 27020 somedb --eval "db.helloDoc.getShardDistribution()"
```

### Проверка статуса реплик:
```shell
docker compose exec -T shard1a mongosh --port 27018 --eval "rs.status().members.map(m => ({name: m.name, state: m.stateStr}))"
```

### Проверка кеширования (второй запрос < 100ms):
```shell
curl -w "\nTime: %{time_total}s\n" http://localhost:8080/helloDoc/users
curl -w "\nTime: %{time_total}s\n" http://localhost:8080/helloDoc/users
```

---

## Архитектура

### Компоненты финального решения:

| Компонент | Количество | Порт | Описание |
|-----------|------------|------|----------|
| configSrv1-3 | 3 | 27017 | Config Server Replica Set |
| shard1a-c | 3 | 27018 | Shard 1 Replica Set |
| shard2a-c | 3 | 27019 | Shard 2 Replica Set |
| mongos_router | 1 | 27020 | MongoDB Router |
| redis | 1 | 6379 | Redis Cache |
| pymongo_api | 1 | 8080 | Python API |

### Схемы (draw.io):
- `task1.drawio` - Исходная схема: pymongo-api → MongoDB
- `task2.drawio` - Шардирование: API → Router → Config + 2 Shards
- `task3.drawio` - Репликация: по 3 реплики на каждый компонент
- `task4.drawio` - Кеширование: добавлен Redis
- `task5.drawio` - Полная архитектура: User → CDN/API Gateway → Consul → API → Redis/MongoDB

---

## Остановка

```shell
docker compose down
```

Для удаления volumes:
```shell
docker compose down -v
```
