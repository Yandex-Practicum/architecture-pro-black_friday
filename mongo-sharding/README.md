# MongoDB Sharding - Проект "Мобильный мир"

Этот проект реализует шардированный MongoDB кластер для обеспечения высокой производительности интернет-магазина "Мобильный мир" во время "Черной пятницы".

## Архитектура

Кластер включает следующие компоненты:

- **Config Servers** (3 шт): `configSrv1`, `configSrv2`, `configSrv3` - хранят метаданные и конфигурацию кластера
- **Mongos Router** (1 шт): `mongos` - маршрутизатор запросов к шардам
- **Shards** (2 шт): `shard1`, `shard2` - хранят данные
- **API Application**: `pymongo_api` - FastAPI приложение для работы с базой данных

### База данных и коллекции

- **База данных**: `somedb`
- **Коллекция**: `helloDoc`
- **Shard Key**: `_id` (hashed) - обеспечивает равномерное распределение данных

## Как запустить проект

### Шаг 1: Запуск контейнеров

Запустите все сервисы MongoDB и приложение:

```bash
docker compose up -d
```

Дождитесь запуска всех контейнеров (примерно 10-15 секунд).

### Шаг 2: Инициализация шардирования

После запуска контейнеров необходимо инициализировать кластер:

```bash
chmod +x scripts/init-sharding.sh
./scripts/init-sharding.sh
```

Скрипт выполнит следующие действия:
1. Инициализирует Config Server Replica Set
2. Инициализирует Replica Set для каждого шарда
3. Добавит шарды в кластер через mongos
4. Включит шардирование для базы данных `somedb`
5. Настроит шардирование для коллекции `helloDoc` с ключом `_id` (hashed)
6. Выведет статус кластера

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

Откройте в браузере: http://localhost:8080

#### Если проект запущен на виртуальной машине:

Узнайте IP-адрес виртуальной машины:
```bash
curl --silent http://ifconfig.me
```

Откройте в браузере: http://<ip виртуальной машины>:8080

### API документация

Swagger документация доступна по адресу: http://localhost:8080/docs

### Проверка статуса шардирования

Выполните команду для проверки статуса кластера:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

### Проверка количества документов

Общее количество документов в базе:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Распределение документов по шардам:

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

### Проверка данных на конкретном шарде

Для Shard 1:
```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Для Shard 2:
```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

## Остановка проекта

Для остановки всех сервисов:

```bash
docker compose down
```

Для полной очистки (включая volumes с данными):

```bash
docker compose down -v
```

## Устранение неполадок

### Проблема: Контейнеры не запускаются

Решение: Убедитесь, что порты 8080, 27017-27019 не заняты другими процессами.

### Проблема: Ошибки при инициализации шардирования

Решение: Убедитесь, что все контейнеры запущены и работают:
```bash
docker compose ps
```

Если какие-то контейнеры не запустились, перезапустите их:
```bash
docker compose restart
```

### Проблема: Данные не распределяются по шардам

Решение: Проверьте, что шардирование включено и настроено правильно:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```

## Примеры команд для работы с кластером

### Список всех баз данных

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
show dbs
EOF
```

### Информация о шардах

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use admin
db.adminCommand({ listShards: 1 })
EOF
```

### Статус балансировщика

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.getBalancerState()
EOF
```

## Архитектурные преимущества

1. **Высокая производительность** - данные распределены между двумя шардами, что позволяет параллельно обрабатывать запросы
2. **Масштабируемость** - можно добавить больше шардов при росте нагрузки
3. **Hashed Sharding** - использование хешированного ключа `_id` обеспечивает равномерное распределение данных
