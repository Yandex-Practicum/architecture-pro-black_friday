## Задание 1. Планирование
- [Sharding](./task1-single/task1_solutions-1-Sharding.jpg)
- [Sharding-Replication](./task1-single/task1_solutions-2-Sharding-Replication.jpg)
- [Sharding-Replication-Redis](./task1-single/task1_solutions-3-Sharding-Replication-Redis.jpg)

## Задание 2. Шардирование
- [ReadMe](./task2-mongo-sharding/README.md)
- Короткая альтернатива:
  - в каталоги задания:
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
  - в каталоги задания:
    ```cd task3-mongo-sharding-repl```
  - запуск:
    ```docker compose up -d```
  - Инициализация (идемпотентная операция):
    ```./scripts/mongo-sharding-repl-init.sh```
  - Наполненение:
    ```./scripts/mongo-init.sh```

## Задание 4. Кеширование
## Задание 5. Service Discovery и балансировка с API Gateway
## Задание 6. CDN
## Задание 7. Проектирование схем коллекций для шардирования данных
## Задание 8. Выявление и устранение «горячих» шардов
## Задание 9. Настройка чтения с реплик и консистентность
## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования