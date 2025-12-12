## Задание 1. Планирование
- [Sharding](./task1-single/task1_solutions-1-Sharding.jpg)
- [Sharding-Replication](./task1-single/task1_solutions-2-Sharding-Replication.jpg)
- [Sharding-Replication-Redis](./task1-single/task1_solutions-3-Sharding-Replication-Redis.jpg)

## Задание 2. Шардирование
- [ReadMe](./task2-mongo-sharding/README.md)
- Короткая альтернатива:
  - в каталог задания:
  ```cd task2-mongo-sharding```
  - запуск:
  ```docker compose up -d```
  - Инициализация (идемпотентная операция): 
  ```./scripts/mongo-sharding-init.sh```
  - Наполненение:
    ```./scripts/mongo-init.sh```

## Задание 3. Репликация
- [ReadMe](./task3-mongo-sharding-repl/README.md)
- Короткая альтернатива:
  - в каталог задания:
    ```cd task3-mongo-sharding-repl```
  - запуск:
    ```docker compose up -d```
  - Инициализация (идемпотентная операция):
    ```./scripts/mongo-sharding-repl-init.sh```
  - Наполненение:
    ```./scripts/mongo-init.sh```

## Задание 4. Кеширование
- [ReadMe](./task4-sharding-repl-cache/README.md)
- Короткая альтернатива:
  - в каталог задания:
    ```cd task4-sharding-repl-cache```
  - запуск:
    ```docker compose up -d```
  - Инициализация (идемпотентная операция):
    ```./scripts/mongo-sharding-repl-init.sh```
  - Наполненение:
    ```./scripts/mongo-init.sh```
  - Проверка (см время отклика первого и последующих):
```time curl -s http://localhost:8080/helloDoc/users > /dev/null```

## Задание 5. Service Discovery и балансировка с API Gateway
- [Sharding-Replication-Redis](./task5-Service-Discovery/task5_scaling_gateway_consul.jpg)

## Задание 6. CDN
- [CDN](./task6-CDN/task6_CDN.jpg)

## Задание 7. Проектирование схем коллекций для шардирования данных
- [sharding_collections_design](./task7-sharding/sharding_collections_design.md)

## Задание 8. Выявление и устранение «горячих» шардов
- [hot_shards_mitigation](./task8-hot-shards/hot_shards_mitigation.md)

## Задание 9. Настройка чтения с реплик и консистентность
- [read_pref_consistency](./task9-read-pref/read_pref_consistency.md)

## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования