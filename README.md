# pymongo-api

## Задание 1

Схемы:
- Изначальная: ![](./task1-initial.drawio.png)
- Шардирование: ![](./task1-shards.drawio.png)
- Репликация: ![](./task1-replicas.drawio.png)
- Кеш: ![](./task1-cache.drawio.png)


## Задание 2

```shell
cd mongo-sharding
docker compose up -d
./scripts/mongo-init.sh
```

Открыть: http://localhost:8080


## Задание 3

```shell
cd mongo-sharding-repl
docker compose up -d
./scripts/mongo-init.sh
```

Открыть: http://localhost:8080


## Задание 4

```shell
cd sharding-repl-cache
docker compose up -d
./scripts/mongo-init.sh
```

Открыть: http://localhost:8080

Проверка кеширования:
```bash
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

## Задание 5

Схема: ![](./task1-gw.drawio.png)


## Задание 6

Схема: ![](./task1-cdn.drawio.png)


## Задание 7

[Проектирование схем коллекций для шардирования](./task7/README.md)


## Задание 8

[Выявление и устранение горячих шардов](./task8/README.md)


## Задание 9

[Настройка чтения с реплик и консистентность](./task9/README.md)


## Задание 10

[Миграция на Cassandra](./task10/README.md)
