# Проектная работа 4 спринта

## Заданий 1-6

- `asis/diagrams` — Задание 1. Планирование
- `mongo-sharding` — Задание 2. Шардирование
- `mongo-sharding-repl` — Задание 3. Репликация
- `sharding-repl-cache` — Задание 4. Кеширование
- `gateway-consul` — Задание 5. Service Discovery и балансировка с API Gateway
- `task6/diagrams` — Задание 6. CDN 

## Схемы

- `diagrams/01-sharding-task1-to-be.drawio`
- `diagrams/02-replication-task1-to-be.drawio`
- `diagrams/03-caching-task1-to-be.drawio`
- `diagrams/04-gateway-service-discovery-task1-to-be.drawio`
- `diagrams/05-cdn-task1-to-be.drawio`

## Архитектурные документы для заданий 7-10

- `ARCHITECTURE_TASKS_7_10.md` — единый архитектурный документ для заданий 7-10
- `task7/README.md` — Задание 7. Проектирование схем коллекций для шардирования данных
- `task8/README.md` — Задание 8. Выявление и устранение «горячих» шардов
- `task9/README.md` — Задание 9. Настройка чтения с реплик и консистентность
- `task10/README.md` — Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## Быстрый запуск стенда заданий 2, 3, 4

```shell
cd sharding-repl-cache
docker compose up -d --build
./scripts/init-sharding.sh
```

Если запуск был прерван или остались старые volume:

```shell
docker compose down -v
docker compose up -d --build
./scripts/init-sharding.sh
```

```shell
curl http://localhost:8080/
curl http://localhost:8080/helloDoc/count
```

Проверить распределение документов через `mongos-router`:

```shell
docker compose exec -T mongos-router mongosh --port 27020 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
db.adminCommand({ listShards: 1 })
EOF
```

Проверить количество реплик:

```shell
docker compose exec -T shard1-1 mongosh --port 27019 --quiet --eval 'rs.status().members.length'
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.length'
```

## Проверка Redis-кеша

```shell
time curl -s http://localhost:8080/helloDoc/users > /dev/null
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```



Запуск стенда задание 5  `gateway-consul`:

```shell
cd gateway-consul
docker compose up -d --build
./scripts/init.sh
curl http://localhost:9080/
```
Список зарегистрированных инстансов FastAPI:

```shell
curl -s http://localhost:8500/v1/catalog/service/pymongo-api | python3 -m json.tool
```

## Проверка балансировки

Запросы идут через APISIX. В ответе `/` поле `instance_id` показывает, какой инстанс обработал запрос:

```shell
for i in $(seq 1 10); do
  curl -s http://localhost:9080/ | grep -o '"instance_id":"[^"]*"'
done
```


