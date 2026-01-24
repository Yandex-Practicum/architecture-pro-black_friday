# MongoDB Sharding with Replication - Проект "Мобильный мир"

Этот проект реализует шардированный MongoDB кластер с репликацией для обеспечения высокой производительности и отказоустойчивости интернет-магазина "Мобильный мир" во время "Черной пятницы".

## Архитектура

Кластер включает следующие компоненты с полной репликацией:

### Config Servers Replica Set (3 реплики)
- `repl-configSrv1` (Primary) - порт 27017
- `repl-configSrv2` (Secondary) - порт 27017
- `repl-configSrv3` (Secondary) - порт 27017

### Shard 1 Replica Set (3 реплики)
- `repl-shard1-1` (Primary) - порт 27018
- `repl-shard1-2` (Secondary) - порт 27018
- `repl-shard1-3` (Secondary) - порт 27018

### Shard 2 Replica Set (3 реплики)
- `repl-shard2-1` (Primary) - порт 27019
- `repl-shard2-2` (Secondary) - порт 27019
- `repl-shard2-3` (Secondary) - порт 27019

### Другие компоненты
- **Mongos Router** (1 шт): `repl-mongos` - маршрутизатор запросов к шардам
- **API Application**: `repl-pymongo_api` - FastAPI приложение для работы с базой данных

**Итого**: 9 инстансов MongoDB (3 config + 6 shard replicas) + 1 mongos + 1 API

### База данных и коллекции
- **База данных**: `somedb`
- **Коллекция**: `helloDoc`
- **Shard Key**: `_id` (hashed) - обеспечивает равномерное распределение данных

## Преимущества архитектуры

1. **Высокая производительность** - шардирование позволяет параллельно обрабатывать запросы
2. **Отказоустойчивость** - при падении одного узла в replica set автоматически происходит переключение на другой
3. **Масштабируемость** - можно добавить больше шардов и реплик при росте нагрузки
4. **Автоматическое восстановление** - при восстановлении упавшего узла он автоматически синхронизируется

## Как запустить проект

### Шаг 1: Запуск контейнеров

Запустите все сервисы MongoDB и приложение:

```bash
docker compose up -d
```

Дождитесь запуска всех контейнеров (примерно 15-20 секунд). Проверьте статус:

```bash
docker compose ps
```

Все 11 контейнеров должны быть в состоянии "running".

### Шаг 2: Инициализация шардирования с репликацией

После запуска контейнеров необходимо инициализировать кластер:

```bash
chmod +x scripts/init-sharding.sh
./scripts/init-sharding.sh
```

#### Что делает скрипт инициализации:

1. **Инициализация Config Server Replica Set**
   - Создает replica set из 3 config серверов
   - Выбирает Primary узел

2. **Инициализация Shard 1 Replica Set**
   - Создает replica set из 3 узлов для первого шарда
   - repl-shard1-1 имеет приоритет 2 (будет Primary)
   - repl-shard1-2 и repl-shard1-3 имеют приоритет 1 (Secondary)

3. **Инициализация Shard 2 Replica Set**
   - Создает replica set из 3 узлов для второго шарда
   - repl-shard2-1 имеет приоритет 2 (будет Primary)
   - repl-shard2-2 и repl-shard2-3 имеют приоритет 1 (Secondary)

4. **Добавление шардов в кластер**
   - Регистрирует оба replica set'а как шарды через mongos

5. **Настройка шардирования**
   - Включает шардирование для базы данных `somedb`
   - Настраивает шардирование для коллекции `helloDoc` с ключом `_id` (hashed)

6. **Вывод статуса**
   - Показывает статус всего кластера
   - Показывает статус каждого replica set

### Шаг 3: Заполнение базы данными

Загрузите тестовые данные в базу:

```bash
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт добавит 1500 документов в коллекцию `helloDoc` и покажет их распределение по шардам.

## Как проверить работу

### Проверка через веб-интерфейс

#### Если проект запущен на локальной машине:

Откройте в браузере: http://localhost:8081

Вы увидите информацию о:
- Топологии MongoDB (Sharded)
- Списке шардов
- Количестве документов в базе
- Primary и Secondary узлах

#### Если проект запущен на виртуальной машине:

Узнайте IP-адрес виртуальной машины:
```bash
curl --silent http://ifconfig.me
```

Откройте в браузере: http://<ip виртуальной машины>:8081

### API документация

Swagger документация доступна по адресу: http://localhost:8081/docs

### Проверка статуса репликации

#### Статус Config Server Replica Set:

```bash
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.status();
EOF
```

Вы увидите информацию о всех трех config серверах, их ролях (PRIMARY/SECONDARY) и состоянии здоровья.

#### Статус Shard 1 Replica Set:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

#### Статус Shard 2 Replica Set:

```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.status();
EOF
```

### Краткая информация о replica set:

#### Config Servers:
```bash
docker compose exec -T configSrv1 mongosh --port 27017 --quiet <<EOF
rs.conf();
EOF
```

#### Shard 1:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.conf();
EOF
```

#### Shard 2:
```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.conf();
EOF
```

### Проверка статуса кластера

Проверьте общий статус шардированного кластера:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

### Проверка количества документов

#### Общее количество документов через mongos:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Распределение документов по шардам:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

#### Количество документов на Primary узле Shard 1:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Количество документов на Primary узле Shard 2:

```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Тестирование отказоустойчивости

### Тест 1: Остановка Secondary узла

Остановите один из Secondary узлов:

```bash
docker compose stop repl-shard1-2
```

Проверьте статус replica set - кластер продолжит работать:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Запустите узел обратно:

```bash
docker compose start repl-shard1-2
```

Узел автоматически синхронизируется с Primary.

### Тест 2: Остановка Primary узла

Остановите Primary узел:

```bash
docker compose stop repl-shard1-1
```

Проверьте статус - произойдет автоматическое переключение (failover), и один из Secondary станет Primary:

```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.status();
EOF
```

Запустите узел обратно:

```bash
docker compose start repl-shard1-1
```

После восстановления он присоединится как Secondary.

## Мониторинг кластера

### Проверка состояния всех узлов:

```bash
docker compose ps
```

### Просмотр логов конкретного узла:

```bash
docker compose logs shard1-1
```

### Список всех шардов в кластере:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use admin
db.adminCommand({ listShards: 1 })
EOF
```

### Информация о балансировщике данных:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.getBalancerState()
sh.isBalancerRunning()
EOF
```

## Остановка проекта

### Остановка всех сервисов:

```bash
docker compose down
```

### Полная очистка (включая volumes с данными):

```bash
docker compose down -v
```

## Устранение неполадок

### Проблема: Контейнеры не запускаются

**Решение**: Убедитесь, что порт 8081 не занят другими процессами (порт 8080 используется проектом mongo-sharding).

Проверьте занятые порты:
```bash
lsof -i :8081
```

**Примечание**: Имена контейнеров имеют префикс `repl-`, поэтому проект mongo-sharding-repl может работать одновременно с mongo-sharding без конфликтов.

### Проблема: Ошибки при инициализации replica set

**Решение**: Убедитесь, что все контейнеры запущены и работают:
```bash
docker compose ps
```

Если какие-то контейнеры не запустились, проверьте их логи:
```bash
docker compose logs <service-name>
```

Попробуйте перезапустить:
```bash
docker compose restart
```

### Проблема: Replica set не может выбрать Primary

**Решение**: Увеличьте время ожидания между шагами инициализации. Отредактируйте `scripts/init-sharding.sh` и увеличьте значения `sleep`.

### Проблема: Данные не реплицируются

**Решение**: Проверьте статус репликации:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.printReplicationInfo()
EOF
```

Проверьте задержку репликации:
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.printSecondaryReplicationInfo()
EOF
```

### Проблема: Primary не восстанавливается после сбоя

**Решение**: Проверьте priority настройки в replica set:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
rs.conf()
EOF
```

Если нужно, вручную пересоберите приоритеты:
```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
cfg = rs.conf()
cfg.members[0].priority = 2
cfg.members[1].priority = 1
cfg.members[2].priority = 1
rs.reconfig(cfg)
EOF
```

## Полезные команды

### Узнать текущий Primary для каждого replica set:

```bash
# Config Servers
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use admin
db.adminCommand({ isMaster: 1 })
EOF

# Shard 1
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
db.isMaster().primary
EOF

# Shard 2
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
db.isMaster().primary
EOF
```

### Принудительная синхронизация Secondary узла:

```bash
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
db.adminCommand({ resync: 1 })
EOF
```

### Изменение приоритета члена replica set:

```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
cfg = rs.conf()
cfg.members[1].priority = 0.5
rs.reconfig(cfg)
EOF
```

## Архитектурные преимущества данного решения

1. **Горизонтальное масштабирование** - данные распределены между двумя шардами
2. **Вертикальная отказоустойчивость** - каждый шард имеет 3 реплики
3. **Автоматическое восстановление** - при падении узла автоматически выбирается новый Primary
4. **Отсутствие единой точки отказа** - отказ любого узла не приведет к недоступности системы
5. **Чтение с Secondary** - можно настроить чтение с Secondary узлов для снижения нагрузки
6. **Географическое распределение** - replica set можно разместить в разных дата-центрах

## Производительность и нагрузка

При текущей конфигурации система может обрабатывать:
- **Запросы на чтение**: распределяются между Primary и Secondary (если настроено)
- **Запросы на запись**: обрабатываются Primary узлами каждого шарда
- **Параллельная обработка**: запросы к разным шардам выполняются параллельно
- **Устойчивость к сбоям**: система продолжает работать даже при падении до 1 узла в каждом replica set

Для "Черной пятницы" эта архитектура обеспечит:
- Высокую пропускную способность за счет шардирования
- Отказоустойчивость за счет репликации
- Минимальное время простоя при сбоях
