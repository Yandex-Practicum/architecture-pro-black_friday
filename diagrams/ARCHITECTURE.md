# Архитектура MongoDB Sharding Optimization

> 📊 Этот документ содержит визуализацию всех архитектурных схем с интерактивным рендерингом  
> 🏠 [← Вернуться к README](../README.md) | 📖 [Подробное планирование →](../PLANNING.md)

## Схема 1: Базовое шардирование

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "MongoDB Sharded Cluster"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers"
            configSrv1[configSrv1<br/>Config Server]
            configSrv2[configSrv2<br/>Config Server]
            configSrv3[configSrv3<br/>Config Server]
        end
        
        subgraph "Shard 1"
            shard1[shard1<br/>Primary Shard 1]
        end
        
        subgraph "Shard 2"
            shard2[shard2<br/>Primary Shard 2]
        end
    end

    Client -->|HTTP| API
    API -->|MongoDB Protocol| mongos
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    mongos -->|Data Queries| shard1
    mongos -->|Data Queries| shard2

    style API fill:#4CAF50
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1 fill:#9C27B0
    style shard2 fill:#9C27B0
```

### Компоненты:
- **pymongo-api** - Flask приложение
- **mongos** - Query Router для маршрутизации запросов
- **configSrv1, configSrv2, configSrv3** - Config Servers для хранения метаданных кластера
- **shard1, shard2** - Шарды для хранения данных

### Сетевые взаимодействия:
- Client → API (HTTP)
- API → mongos (MongoDB Protocol)
- mongos → Config Servers (Metadata queries)
- mongos → Shards (Data queries)

---

## Схема 2: Шардирование + Репликация

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "MongoDB Sharded Cluster with Replication"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers Replica Set"
            configSrv1[configSrv1<br/>Config Primary]
            configSrv2[configSrv2<br/>Config Secondary]
            configSrv3[configSrv3<br/>Config Secondary]
        end
        
        subgraph "Shard 1 Replica Set"
            shard1_1[shard1-1<br/>Primary]
            shard1_2[shard1-2<br/>Secondary]
            shard1_3[shard1-3<br/>Secondary]
        end
        
        subgraph "Shard 2 Replica Set"
            shard2_1[shard2-1<br/>Primary]
            shard2_2[shard2-2<br/>Secondary]
            shard2_3[shard2-3<br/>Secondary]
        end
    end

    Client -->|HTTP| API
    API -->|MongoDB Protocol| mongos
    
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    
    configSrv1 -.->|Replication| configSrv2
    configSrv1 -.->|Replication| configSrv3
    
    mongos -->|Read/Write| shard1_1
    mongos -->|Read| shard1_2
    mongos -->|Read| shard1_3
    
    shard1_1 -.->|Replication| shard1_2
    shard1_1 -.->|Replication| shard1_3
    
    mongos -->|Read/Write| shard2_1
    mongos -->|Read| shard2_2
    mongos -->|Read| shard2_3
    
    shard2_1 -.->|Replication| shard2_2
    shard2_1 -.->|Replication| shard2_3

    style API fill:#4CAF50
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1_1 fill:#9C27B0
    style shard1_2 fill:#9C27B0
    style shard1_3 fill:#9C27B0
    style shard2_1 fill:#E91E63
    style shard2_2 fill:#E91E63
    style shard2_3 fill:#E91E63
```

### Компоненты:
- **Config Servers Replica Set**: configSrv1 (Primary), configSrv2, configSrv3 (Secondaries)
- **Shard 1 Replica Set**: shard1-1 (Primary), shard1-2, shard1-3 (Secondaries)
- **Shard 2 Replica Set**: shard2-1 (Primary), shard2-2, shard2-3 (Secondaries)

### Репликация:
- Пунктирные стрелки показывают репликацию данных от Primary к Secondary нодам
- Primary ноды обрабатывают запись (Write)
- Secondary ноды могут обрабатывать чтение (Read)
- При падении Primary автоматически выбирается новая из Secondary (Failover)

---

## Схема 3: Шардирование + Репликация + Кеширование

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "Caching Layer"
        Redis[redis<br/>Redis Cache]
    end

    subgraph "MongoDB Sharded Cluster with Replication"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers Replica Set"
            configSrv1[configSrv1<br/>Config Primary]
            configSrv2[configSrv2<br/>Config Secondary]
            configSrv3[configSrv3<br/>Config Secondary]
        end
        
        subgraph "Shard 1 Replica Set"
            shard1_1[shard1-1<br/>Primary]
            shard1_2[shard1-2<br/>Secondary]
            shard1_3[shard1-3<br/>Secondary]
        end
        
        subgraph "Shard 2 Replica Set"
            shard2_1[shard2-1<br/>Primary]
            shard2_2[shard2-2<br/>Secondary]
            shard2_3[shard2-3<br/>Secondary]
        end
    end

    Client -->|HTTP| API
    API -->|Cache Check| Redis
    API -->|MongoDB Protocol| mongos
    
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    
    configSrv1 -.->|Replication| configSrv2
    configSrv1 -.->|Replication| configSrv3
    
    mongos -->|Read/Write| shard1_1
    mongos -->|Read| shard1_2
    mongos -->|Read| shard1_3
    
    shard1_1 -.->|Replication| shard1_2
    shard1_1 -.->|Replication| shard1_3
    
    mongos -->|Read/Write| shard2_1
    mongos -->|Read| shard2_2
    mongos -->|Read| shard2_3
    
    shard2_1 -.->|Replication| shard2_2
    shard2_1 -.->|Replication| shard2_3

    style API fill:#4CAF50
    style Redis fill:#DC382D
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1_1 fill:#9C27B0
    style shard1_2 fill:#9C27B0
    style shard1_3 fill:#9C27B0
    style shard2_1 fill:#E91E63
    style shard2_2 fill:#E91E63
    style shard2_3 fill:#E91E63
```

### Новый компонент:
- **redis** - Redis Cache для кеширования частых запросов

### Кеширование:
- Приложение сначала проверяет наличие данных в Redis
- При cache hit - данные возвращаются из Redis (быстрее)
- При cache miss - данные запрашиваются из MongoDB и сохраняются в Redis
- Снижение нагрузки на MongoDB и ускорение ответов

---

## Схема 4: Шардирование + Репликация + Кеширование + API Gateway & Service Discovery

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Client/Browser]
    end

    subgraph "API Gateway & Service Discovery"
        APIGateway[API Gateway<br/>nginx/Kong<br/>:80]
        Consul[Consul Server<br/>Service Discovery<br/>:8500]
    end

    subgraph "Application Layer (3 instances)"
        API1[pymongo-api-1<br/>:8081]
        API2[pymongo-api-2<br/>:8082]
        API3[pymongo-api-3<br/>:8083]
    end

    subgraph "Cache Layer"
        Redis[Redis Cache<br/>:6379]
    end

    subgraph "MongoDB Router"
        Mongos[mongos<br/>Query Router<br/>:27017]
    end

    subgraph "Config Servers Replica Set"
        ConfigSrv1[configSrv1<br/>:27019]
        ConfigSrv2[configSrv2<br/>:27019]
        ConfigSrv3[configSrv3<br/>:27019]
    end

    subgraph "Shard 1 Replica Set"
        Shard1_1[shard1-1<br/>Primary<br/>:27018]
        Shard1_2[shard1-2<br/>Secondary<br/>:27018]
        Shard1_3[shard1-3<br/>Secondary<br/>:27018]
    end

    subgraph "Shard 2 Replica Set"
        Shard2_1[shard2-1<br/>Primary<br/>:27018]
        Shard2_2[shard2-2<br/>Secondary<br/>:27018]
        Shard2_3[shard2-3<br/>Secondary<br/>:27018]
    end

    %% Client to API Gateway
    Client -->|HTTP Request| APIGateway

    %% API Gateway to Application Instances (Load Balancing)
    APIGateway -->|Round Robin| API1
    APIGateway -->|Round Robin| API2
    APIGateway -->|Round Robin| API3

    %% Application Instances register with Consul
    API1 -.->|Register/Health Check| Consul
    API2 -.->|Register/Health Check| Consul
    API3 -.->|Register/Health Check| Consul

    %% API Gateway queries Consul for service discovery
    APIGateway -.->|Service Discovery| Consul

    %% Application Instances to Redis (Cache)
    API1 -->|Cache Check| Redis
    API2 -->|Cache Check| Redis
    API3 -->|Cache Check| Redis

    %% Application Instances to Mongos
    API1 -->|Query| Mongos
    API2 -->|Query| Mongos
    API3 -->|Query| Mongos

    %% Mongos to Config Servers
    Mongos -->|Metadata| ConfigSrv1
    Mongos -->|Metadata| ConfigSrv2
    Mongos -->|Metadata| ConfigSrv3

    %% Config Servers Replication
    ConfigSrv1 -.->|Replicate| ConfigSrv2
    ConfigSrv2 -.->|Replicate| ConfigSrv3
    ConfigSrv3 -.->|Replicate| ConfigSrv1

    %% Mongos to Shards
    Mongos -->|Route Data| Shard1_1
    Mongos -->|Route Data| Shard2_1

    %% Shard 1 Replication
    Shard1_1 -.->|Replicate| Shard1_2
    Shard1_1 -.->|Replicate| Shard1_3

    %% Shard 2 Replication
    Shard2_1 -.->|Replicate| Shard2_2
    Shard2_1 -.->|Replicate| Shard2_3

    %% Styling
    classDef clientStyle fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef gatewayStyle fill:#fff3e0,stroke:#e65100,stroke-width:3px
    classDef consulStyle fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    classDef appStyle fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef cacheStyle fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef routerStyle fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef configStyle fill:#e0f7fa,stroke:#006064,stroke-width:2px
    classDef shardStyle fill:#fce4ec,stroke:#880e4f,stroke-width:2px

    class Client clientStyle
    class APIGateway gatewayStyle
    class Consul consulStyle
    class API1,API2,API3 appStyle
    class Redis cacheStyle
    class Mongos routerStyle
    class ConfigSrv1,ConfigSrv2,ConfigSrv3 configStyle
    class Shard1_1,Shard1_2,Shard1_3,Shard2_1,Shard2_2,Shard2_3 shardStyle
```

### Новые компоненты:

**API Gateway (nginx/Kong):**
- Единая точка входа для клиентов
- Балансировка нагрузки между инстансами приложения (Round Robin)
- Порт 80 для HTTP трафика

**Consul Server:**
- Service Discovery - динамическое обнаружение сервисов
- Health Checks - мониторинг состояния инстансов приложения
- Автоматическое добавление/удаление инстансов из балансировки

**Множественные инстансы приложения (3 шт):**
- **pymongo-api-1** (порт 8081)
- **pymongo-api-2** (порт 8082)
- **pymongo-api-3** (порт 8083)

### Взаимодействия:

**Service Discovery:**
- Каждый инстанс приложения регистрируется в Consul при запуске
- Consul проводит health checks для определения доступности инстансов
- API Gateway получает список доступных инстансов из Consul
- При падении инстанса Consul автоматически исключает его из списка

**Load Balancing:**
- Клиент отправляет запрос на API Gateway (единая точка входа)
- API Gateway распределяет запросы между доступными инстансами (Round Robin)
- Если инстанс недоступен, запрос направляется на другой инстанс

**Horizontal Scaling:**
- Можно запустить любое количество инстансов приложения
- Новые инстансы автоматически регистрируются в Consul
- API Gateway автоматически начинает направлять на них трафик
- Нет необходимости в ручной настройке балансировки

### Преимущества:

1. **Нет simple point of failure для приложения**
   - При падении одного инстанса остальные продолжают работать
   - Обновления можно делать по одному инстансу (rolling updates)

2. **Горизонтальное масштабирование приложения**
   - Легко добавить новые инстансы при росте нагрузки
   - Можно масштабировать независимо от MongoDB

3. **Автоматическое обнаружение сервисов**
   - Не нужно вручную настраивать список инстансов
   - Динамическая балансировка при изменении количества инстансов

4. **Высокая доступность**
   - Zero-downtime deployments
   - Graceful degradation при проблемах

---

## Схема 5: + CDN (Content Delivery Network)

```mermaid
graph TB
    subgraph "Users in Different Regions"
        ClientUS[Client<br/>North America]
        ClientEU[Client<br/>Europe]
        ClientAsia[Client<br/>Asia]
    end

    subgraph "CDN Layer (CloudFlare/Cloudfront)"
        CDNUS[CDN Node<br/>US Region<br/>Static Content]
        CDNEU[CDN Node<br/>EU Region<br/>Static Content]
        CDNAsia[CDN Node<br/>Asia Region<br/>Static Content]
    end

    subgraph "Origin Server"
        StaticServer[Static Content Server<br/>nginx<br/>HTML/CSS/JS/Images<br/>:8090]
    end

    subgraph "API Gateway & Service Discovery"
        APIGateway[API Gateway<br/>nginx/Kong<br/>Dynamic API<br/>:80]
        Consul[Consul Server<br/>Service Discovery<br/>:8500]
    end

    subgraph "Application Layer (3 instances)"
        API1[pymongo-api-1<br/>:8081]
        API2[pymongo-api-2<br/>:8082]
        API3[pymongo-api-3<br/>:8083]
    end

    subgraph "Cache Layer"
        Redis[Redis Cache<br/>:6379]
    end

    subgraph "MongoDB Router"
        Mongos[mongos<br/>Query Router<br/>:27017]
    end

    subgraph "Config Servers Replica Set"
        ConfigSrv1[configSrv1<br/>:27019]
        ConfigSrv2[configSrv2<br/>:27019]
        ConfigSrv3[configSrv3<br/>:27019]
    end

    subgraph "Shard 1 Replica Set"
        Shard1_1[shard1-1<br/>Primary<br/>:27018]
        Shard1_2[shard1-2<br/>Secondary<br/>:27018]
        Shard1_3[shard1-3<br/>Secondary<br/>:27018]
    end

    subgraph "Shard 2 Replica Set"
        Shard2_1[shard2-1<br/>Primary<br/>:27018]
        Shard2_2[shard2-2<br/>Secondary<br/>:27018]
        Shard2_3[shard2-3<br/>Secondary<br/>:27018]
    end

    %% Users to CDN (geographically distributed)
    ClientUS -->|GET /static/*<br/>HTML/CSS/JS/Images| CDNUS
    ClientEU -->|GET /static/*<br/>HTML/CSS/JS/Images| CDNEU
    ClientAsia -->|GET /static/*<br/>HTML/CSS/JS/Images| CDNAsia

    %% CDN to Origin Server (cache miss)
    CDNUS -.->|Cache Miss<br/>Fetch Static Content| StaticServer
    CDNEU -.->|Cache Miss<br/>Fetch Static Content| StaticServer
    CDNAsia -.->|Cache Miss<br/>Fetch Static Content| StaticServer

    %% Users to API Gateway (dynamic API requests)
    ClientUS -->|GET /api/*<br/>Dynamic Data| APIGateway
    ClientEU -->|GET /api/*<br/>Dynamic Data| APIGateway
    ClientAsia -->|GET /api/*<br/>Dynamic Data| APIGateway

    %% API Gateway to Application Instances (Load Balancing)
    APIGateway -->|Round Robin| API1
    APIGateway -->|Round Robin| API2
    APIGateway -->|Round Robin| API3

    %% Application Instances register with Consul
    API1 -.->|Register/Health Check| Consul
    API2 -.->|Register/Health Check| Consul
    API3 -.->|Register/Health Check| Consul

    %% API Gateway queries Consul for service discovery
    APIGateway -.->|Service Discovery| Consul

    %% Application Instances to Redis (Cache)
    API1 -->|Cache Check| Redis
    API2 -->|Cache Check| Redis
    API3 -->|Cache Check| Redis

    %% Application Instances to Mongos
    API1 -->|Query| Mongos
    API2 -->|Query| Mongos
    API3 -->|Query| Mongos

    %% Mongos to Config Servers
    Mongos -->|Metadata| ConfigSrv1
    Mongos -->|Metadata| ConfigSrv2
    Mongos -->|Metadata| ConfigSrv3

    %% Config Servers Replication
    ConfigSrv1 -.->|Replicate| ConfigSrv2
    ConfigSrv2 -.->|Replicate| ConfigSrv3
    ConfigSrv3 -.->|Replicate| ConfigSrv1

    %% Mongos to Shards
    Mongos -->|Route Data| Shard1_1
    Mongos -->|Route Data| Shard2_1

    %% Shard 1 Replication
    Shard1_1 -.->|Replicate| Shard1_2
    Shard1_1 -.->|Replicate| Shard1_3

    %% Shard 2 Replication
    Shard2_1 -.->|Replicate| Shard2_2
    Shard2_1 -.->|Replicate| Shard2_3

    %% Styling
    classDef clientStyle fill:#e3f2fd,stroke:#01579b,stroke-width:2px
    classDef cdnStyle fill:#fff9c4,stroke:#f57f17,stroke-width:3px
    classDef originStyle fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef gatewayStyle fill:#ffe0b2,stroke:#e65100,stroke-width:2px
    classDef consulStyle fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    classDef appStyle fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef cacheStyle fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef routerStyle fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef configStyle fill:#e0f7fa,stroke:#006064,stroke-width:2px
    classDef shardStyle fill:#fce4ec,stroke:#880e4f,stroke-width:2px

    class ClientUS,ClientEU,ClientAsia clientStyle
    class CDNUS,CDNEU,CDNAsia cdnStyle
    class StaticServer originStyle
    class APIGateway gatewayStyle
    class Consul consulStyle
    class API1,API2,API3 appStyle
    class Redis cacheStyle
    class Mongos routerStyle
    class ConfigSrv1,ConfigSrv2,ConfigSrv3 configStyle
    class Shard1_1,Shard1_2,Shard1_3,Shard2_1,Shard2_2,Shard2_3 shardStyle
```

### Новый компонент:

**CDN (Content Delivery Network):**
- Глобальная сеть доставки контента
- 3 узла в разных регионах: North America, Europe, Asia
- Кеширование статического контента (HTML, CSS, JS, Images)
- Быстрая доставка пользователям из любой точки мира

**Static Content Server:**
- Origin сервер для CDN
- Nginx на порту 8090
- Хранит оригиналы статических файлов
- CDN обращается сюда при cache miss

**Пользователи из разных регионов:**
- Client (North America) - подключается к CDN US
- Client (Europe) - подключается к CDN EU
- Client (Asia) - подключается к CDN Asia

### Разделение контента:

**Статический контент (через CDN):**
- `/static/*` - HTML, CSS, JavaScript, Images, Fonts
- Кешируется в CDN на длительное время
- Быстрая загрузка из ближайшего CDN узла (~5-20мс)
- Снижение нагрузки на origin сервер

**Динамический контент (через API Gateway):**
- `/api/*` - REST API запросы
- Не кешируется в CDN
- Проксируется через API Gateway к приложению
- Обрабатывается с использованием Redis кеша и MongoDB

### Взаимодействия:

**CDN Flow:**
1. Пользователь (любой регион) → Ближайший CDN узел
2. CDN проверяет кеш:
   - **Cache Hit**: Отдаёт файл из кеша (~10мс) ✅
   - **Cache Miss**: Запрашивает у Static Content Server → Кеширует → Отдаёт клиенту

**API Flow:**
1. Пользователь (любой регион) → API Gateway (через CDN, но не кешируется)
2. API Gateway → Service Discovery (Consul) → Load Balancing
3. Application → Redis Cache → MongoDB (если нужно)

### Преимущества:

1. **Глобальная производительность**
   - Пользователи из США: загрузка страницы ~350мс (было 3000мс)
   - Пользователи из Азии: загрузка страницы ~400мс (было 4000мс)
   - Улучшение: 8-10x для международной аудитории

2. **Снижение нагрузки на origin**
   - CDN Hit Rate: 95-99%
   - Origin обрабатывает только 1-5% запросов статики
   - Экономия bandwidth и CPU

3. **DDoS защита**
   - CDN поглощает атаки на edge
   - Origin сервер защищён

4. **Автоматическое масштабирование**
   - CDN автоматически справляется с пиковыми нагрузками
   - Нет необходимости настраивать дополнительные серверы

---

## Преимущества итоговой архитектуры

### 1. Горизонтальная масштабируемость (Sharding)
- Данные распределены между несколькими шардами
- Возможность добавления новых шардов при росте нагрузки
- Параллельная обработка запросов на разных шардах

### 2. Отказоустойчивость (Replication)
- Каждый компонент имеет реплики
- Автоматическое восстановление при отказе (Automatic Failover)
- Нулевое время простоя при падении одной ноды

### 3. Производительность (Caching)
- Redis кеширует частые запросы
- Снижение latency для популярных данных
- Уменьшение нагрузки на MongoDB

### 4. Готовность к "черной пятнице"
- Способность обрабатывать высокий трафик
- Отсутствие single point of failure
- Быстрые ответы даже при пиковой нагрузке

