# Задание 3: Шардирование с Репликацией

В этой директории находится решение для **Задания 3**. Мы развиваем архитектуру из предыдущего задания, добавляя **отказоустойчивость (High Availability)**.

**Цель:** Обеспечить непрерывную работу базы данных даже при выходе из строя отдельных узлов. Для этого каждый компонент кластера (Config Server и каждый Shard) преобразуется в **Replica Set**.

## Архитектура решения

Теперь каждый логический узел в нашей шардированной топологии состоит из **трех физических инстансов**, объединенных в Replica Set. Это обеспечивает автоматическое переключение на резервный узел (failover) в случае сбоя.

*   **`mongos` (Router):** Как и раньше, единая точка входа.
*   **Config Server Replica Set (CSRS):** 3 узла, хранящие метаданные. Теперь этот компонент отказоустойчив.
*   **Shard 1 Replica Set:** 3 узла, хранящие первую половину данных.
*   **Shard 2 Replica Set:** 3 узла, хранящие вторую половину данных.

```mermaid
graph TD
    %% Стили
    classDef app fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef router fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
    classDef config fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5;
    classDef shard fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef secondary fill:#ffcdd2,stroke:#ef5350,stroke-width:1px;

    Client((User)) -->|HTTP| API[pymongo_api]:::app

    subgraph DC ["Sharded Cluster with High Availability"]
        API -->|Connection String| Mongos[mongos Router]:::router
        
        %% Config Server Replica Set
        subgraph CSRS [Config Server Replica Set]
            Config1[Config Primary]:::config
            Config2[Config Sec]:::config
            Config3[Config Sec]:::config
        end
        
        Mongos -.->|Metadata Ops| CSRS
        
        %% Shard 1 Replica Set
        subgraph RS1 [Shard 1 Replica Set]
            S1_P[Primary]:::shard
            S1_S1[Secondary]:::secondary
            S1_S2[Secondary]:::secondary
        end
        
        %% Shard 2 Replica Set
        subgraph RS2 [Shard 2 Replica Set]
            S2_P[Primary]:::shard
            S2_S1[Secondary]:::secondary
            S2_S2[Secondary]:::secondary
        end

        Mongos -->|Write/Read| RS1
        Mongos -->|Write/Read| RS2
    end
```

## Инструкция по запуску и настройке

Процесс запуска аналогичен предыдущему заданию, но включает большее количество контейнеров.

### Шаг 1: Запуск базовой инфраструктуры (все 9 узлов БД)

```bash
docker compose up -d configSrv1 configSrv2 configSrv3 shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3
```
Дождитесь, пока все контейнеры перейдут в статус `healthy` (проверить можно командой `docker compose ps`).

### Шаг 2: Инициализация Replica Set для серверов

Запускаем скрипт, который объединит узлы в три независимых Replica Set'а.

```bash
chmod +x init-sharding.sh
./init-sharding.sh
```

### Шаг 3: Запуск роутера и приложения

```bash
docker compose up -d
```

### Шаг 4: Финальная настройка кластера

Запускаем скрипт инициализации повторно. Он свяжет Replica Set'ы шардов с роутером. Ошибки `already initialized` для реплик являются ожидаемыми.

```bash
./init-sharding.sh
```

## Проверка работоспособности

**1. Загрузка тестовых данных**

```bash
chmod +x load-data.sh
./load-data.sh
```

**2. Проверка распределения данных по шардам**

```bash
chmod +x check-shards.sh
./check-shards.sh
```
Результат должен показать примерно равное распределение документов (например, `492 / 508`).

**3. (Опционально) Тест на отказоустойчивость**

Вы можете симулировать сбой, остановив один из `primary` узлов (например, `shard1-1`), и убедиться, что система продолжает работать.

```bash
docker kill shard1-1
sleep 15 # Даем время на выборы нового primary
./check-shards.sh # Скрипт должен отработать успешно, показав те же 1000 документов
```

## Остановка и очистка

```bash
docker compose down -v
```
