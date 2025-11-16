# MongoDB Sharding с репликацией

Этот проект реализует MongoDB кластер с шардированием и репликацией для каждого шарда.

## Архитектура

- **Mongos Router**: точка входа в кластер
- **Config Servers**: 3 узла в реплика-сете `cfgReplSet`
- **Shard 1**: 3 узла в реплика-сете `shard1RS` (primary + 2 secondary)
- **Shard 2**: 3 узла в реплика-сете `shard2RS` (primary + 2 secondary)

## Настройка репликации для каждого шарда

### Автоматическая настройка

#### Запуск проекта

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

3. **Заполнение базы данных тестовыми данными:**
Заполнение базы данных происходит автоматически через сервис `mongo-data-init` после успешной инициализации кластера. Сервис использует скрипт `scripts/mongo-init.sh`, который автоматически определяет, запущен ли он внутри Docker контейнера или на хосте, и использует соответствующий способ подключения к MongoDB.

Проверьте логи:
```bash
docker compose logs mongo-data-init
```
Дождитесь сообщения об успешном завершении инициализации данных.

**Примечание:** 
Если нужно заполнить базу данных вручную, можно использовать скрипт `scripts/mongo-init.sh`:
```bash
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт `mongo-init.sh` универсален и работает как внутри Docker контейнера (через прямое подключение к `mongos-router`), так и с хоста (через `docker compose exec`).


Проект автоматически настроит все реплика-сеты и добавит шарды в mongos через сервис `cluster-init`.
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

## Остановка проекта

```bash
docker compose down
```

Для полной очистки данных (включая volumes):

```bash
docker compose down -v
```

### Ручная настройка репликации для Shard 1
При запуске проекта через `docker compose up`, репликация настраивается автоматически через сервис `cluster-init`. Однако, если вам нужно настроить репликацию вручную, следуйте инструкциям ниже.

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
   // Проверка статуса реплика-сета
   rs.status()
   
   // Проверка, что текущий узел стал PRIMARY
   rs.isMaster()
   ```

4. **Проверьте, что все узлы подключены:**
   ```javascript
   rs.status()
   ```
   Убедитесь, что все три узла (shard1-1, shard1-2, shard1-3) имеют статус `PRIMARY` или `SECONDARY`.

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
   // Проверка статуса реплика-сета
   rs.status()
   
   // Проверка, что текущий узел стал PRIMARY
   rs.isMaster()
   ```

4. **Проверьте, что все узлы подключены:**
   ```javascript
   rs.status()
   ```
   Убедитесь, что все три узла (shard2-1, shard2-2, shard2-3) имеют статус `PRIMARY` или `SECONDARY`.

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
   MongoDB автоматически обнаружит все узлы реплика-сета через указанный узел.

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


