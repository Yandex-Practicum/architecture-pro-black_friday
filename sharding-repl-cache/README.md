# Задание 4: Шардирование, Репликация и Кеширование

В этой директории находится финальное архитектурное решение для первого блока заданий. 

Мы объединяем все изученные подходы:

* Шардирование (горизонтальное масштабирование).
* Репликацию (отказоустойчивость).
* Кеширование (высокая производительность чтения).

**Цель:** Ускорить обработку запросов на чтение, минимизируя нагрузку на базу данных с помощью Redis, сохраняя при этом надежность и масштабируемость основного хранилища MongoDB.

**Архитектура решения**

В дополнение к отказоустойчивому кластеру MongoDB (из Задания 3), мы внедряем сервис Redis. Приложение использует паттерн Cache-Aside:

Приложение сначала ищет данные в Redis.
Если данных нет (Cache Miss), оно идет в MongoDB (через mongos).
Полученные данные сохраняются в Redis для будущих запросов.
Unable to render rich display

Parse error on line 12:
... API -->|2. Read (Cache Miss)| Mongos
-----------------------^
Expecting 'SQE', 'DOUBLECIRCLEEND', 'PE', '-)', 'STADIUMEND', 'SUBROUTINEEND', 'PIPE', 'CYLINDEREND', 'DIAMOND_STOP', 'TAGEND', 'TRAPEND', 'INVTRAPEND', 'UNICODE_TEXT', 'TEXT', 'TAGSTART', got 'PS'

For more information, see https://docs.github.com/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams#creating-mermaid-diagrams

graph TD
    %% Стили
    classDef app fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef router fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef config fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5;
    classDef shard fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef redis fill:#d1c4e9,stroke:#512da8,stroke-width:2px;

    Client((User)) -->|HTTP| API[pymongo_api]:::app

    %% Caching Flow
    API <-->|1. Get / 3. Set| Redis[Redis Cache]:::redis

    subgraph DC ["Sharded Cluster with High Availability"]
        API -->|2. Read (Cache Miss)| Mongos[mongos Router]:::router
        
        %% Config Server Replica Set
        subgraph CSRS [Config Server RS]
            Config1[Config 1]:::config
            Config2[Config 2]:::config
            Config3[Config 3]:::config
        end
        
        Mongos -.-> CSRS
        
        %% Shard 1 Replica Set
        subgraph RS1 [Shard 1 RS]
            S1_P[Primary]:::shard
            S1_S1[Sec]:::shard
            S1_S2[Sec]:::shard
        end
        
        %% Shard 2 Replica Set
        subgraph RS2 [Shard 2 RS]
            S2_P[Primary]:::shard
            S2_S1[Sec]:::shard
            S2_S2[Sec]:::shard
        end

        Mongos --> RS1
        Mongos --> RS2
    end

**Инструкция по запуску**

**Шаг 1:** Запуск инфраструктуры данных

Поднимаем все узлы MongoDB (9 контейнеров) и Redis.

docker compose up -d configSrv1 configSrv2 configSrv3 shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3 redis
Убедитесь, что контейнеры перешли в статус healthy (docker compose ps).

**Шаг 2:** Инициализация Replica Sets

Скрипт объединяет разрозненные узлы MongoDB в наборы реплик.

chmod +x init-sharding.sh
./init-sharding.sh

**Шаг 3:** Запуск приложения и роутера

Поднимаем mongos и API приложение. API автоматически подключится к Redis (через переменную REDIS_URL).

docker compose up -d

**Шаг 4: Финальная связка**

Скрипт настроит шардинг в mongos. Сообщения already initialized для реплик — норма.

./init-sharding.sh

**Проверка работоспособности**

1. Проверка шардинга и данных
   
Загружаем тестовые данные и проверяем их распределение по шардам.

chmod +x load-data.sh check-shards.sh
./load-data.sh
./check-shards.sh
Ожидаемый результат: данные распределены примерно поровну (например, ~492/508).

2. Тестирование кеширования (Performance Test)
   
В коде приложения искусственно добавлена задержка sleep(1) при обращении к базе данных. Кеш позволяет обойти её.

Запрос 1 (Холодный старт): Данные берутся из БД.

time curl -s "http://localhost:8080/helloDoc/users" > /dev/null
Время выполнения: > 1.0 сек

Запрос 2 (Горячий кеш): Данные берутся из Redis.

time curl -s "http://localhost:8080/helloDoc/users" > /dev/null
Время выполнения: < 0.05 сек (Мгновенно)

Если вы видите эту разницу, значит кеширование работает корректно.

**Остановка**
docker compose down -v
