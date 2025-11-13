# Шардирование с репликацией и кэшированием

Этот проект реализует MongoDB кластер с шардированием, репликацией для каждого шарда и кэшированием через Redis.

## Архитектура

- **Mongos Router**: точка входа в кластер
- **Redis**: кеш для приложения
- **Config Servers**: 3 узла в реплика-сете `cfgReplSet`
- **Shard 1**: 3 узла в реплика-сете `shard1RS` (primary + 2 secondary)
- **Shard 2**: 3 узла в реплика-сете `shard2RS` (primary + 2 secondary)

## Запуск проекта

1. **Запустите все сервисы:**
   ```bash
   docker compose up -d
   ```

2. **Дождитесь инициализации кластера:**
   Проверьте логи сервиса `cluster-init`:
   ```bash
   docker compose logs cluster-init
   ```
   Дождитесь сообщения `===> Cluster initialization complete`

3. **Заполните базу данных тестовыми данными (≥ 1000 документов):**
   ```bash
   chmod +x scripts/mongo-init.sh
   ./scripts/mongo-init.sh
   ```

## Проверка работы

### Проверка через API

Откройте в браузере или выполните запрос:
```bash
curl http://localhost:8080/
```

Ответ должен содержать:
- `total_documents` - общее количество документов в базе (≥ 1000)
- `shards` - информация о каждом шарде с количеством документов в каждом
- `replicas_count` - количество реплик для каждого шарда
- `collections` - информация о коллекциях

### Пример ответа:

```json
{
  "total_documents": 1000,
  "shards": {
    "shard1RS": {
      "host": "shard1RS/shard1-1:27018,shard1-2:27018,shard1-3:27018",
      "documents_count": 500
    },
    "shard2RS": {
      "host": "shard2RS/shard2-1:27018,shard2-2:27018,shard2-3:27018",
      "documents_count": 500
    }
  },
  "replicas_count": {
    "shard1RS": 3,
    "shard2RS": 3
  },
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "status": "OK"
}
```

При первом запуске получения списка `users` запрос выполняется около секунды, а следующие запросы выполняются быстрее.

![Скриншот прогона теста GET /{collection_name}/users](optimisation-result.png)

## Настройка репликации для каждого шарда

Репликация настраивается автоматически при запуске проекта через сервис `cluster-init`. Однако, если вам нужно настроить репликацию вручную, следуйте инструкциям ниже.

### Ручная настройка репликации для Shard 1

1. **Подключитесь к первому узлу шарда 1:**
   ```bash
   docker exec -it shard1-1 mongosh --port 27018
   ```

2. **Инициализируйте реплика-сет:**
   ```javascript
   rs.initiate({
     _id: "shard1RS",
     members: [
       { _id: 0, host: "shard1-1:27018" },
       { _id: 1, host: "shard1-2:27018" },
       { _id: 2, host: "shard1-3:27018" }
     ]
   })
   ```

3. **Дождитесь выбора PRIMARY узла:**
   ```javascript
   rs.status()
   rs.isMaster()
   ```

### Ручная настройка репликации для Shard 2

1. **Подключитесь к первому узлу шарда 2:**
   ```bash
   docker exec -it shard2-1 mongosh --port 27018
   ```

2. **Инициализируйте реплика-сет:**
   ```javascript
   rs.initiate({
     _id: "shard2RS",
     members: [
       { _id: 0, host: "shard2-1:27018" },
       { _id: 1, host: "shard2-2:27018" },
       { _id: 2, host: "shard2-3:27018" }
     ]
   })
   ```

3. **Дождитесь выбора PRIMARY узла:**
   ```javascript
   rs.status()
   rs.isMaster()
   ```

### Добавление шардов в mongos

После настройки репликации для обоих шардов, необходимо добавить их в mongos:

1. **Подключитесь к mongos:**
   ```bash
   docker exec -it mongos-router mongosh
   ```

2. **Добавьте шарды:**
   ```javascript
   sh.addShard("shard1RS/shard1-1:27018")
   sh.addShard("shard2RS/shard2-1:27018")
   ```

3. **Включите шардирование для базы данных:**
   ```javascript
   sh.enableSharding("somedb")
   ```

4. **Проверьте статус кластера:**
   ```javascript
   sh.status()
   ```

## Проверка репликации

### Проверка статуса реплика-сета Shard 1

```bash
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"
```

### Проверка статуса реплика-сета Shard 2

```bash
docker exec -it shard2-1 mongosh --port 27018 --eval "rs.status()"
```

### Проверка через mongos

```bash
docker exec -it mongos-router mongosh --eval "sh.status()"
```

## Остановка проекта

```bash
docker compose down
```

Для полной очистки данных (включая volumes):

```bash
docker compose down -v
```

## Доступные эндпоинты

- `GET /` - информация о кластере, количестве документов, шардах и репликах
- `GET /{collection_name}/count` - количество документов в коллекции
- `GET /{collection_name}/users` - список пользователей (с кешированием)
- `GET /{collection_name}/users/{name}` - получить пользователя по имени
- `POST /{collection_name}/users` - создать нового пользователя
- `GET /docs` - Swagger документация

