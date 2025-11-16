# Шардирование

Этот проект реализует MongoDB кластер с шардированием.

## Архитектура

- **Mongos Router**: точка входа в кластер
- **Config Servers**: 3 узла в реплика-сете `cfgReplSet`
- **Shard 1**: шард
- **Shard 2**: шард

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

   **Примечание:** Если нужно заполнить базу данных вручную с хоста, можно использовать скрипт `scripts/mongo-init.sh` :
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
- `shards_info` - информация о каждом шарде с количеством документов в каждом
- `replicas_count` - количество реплик для каждого шарда
- `collections` - информация о коллекциях

### Пример ответа:

```json
{
   "mongo_topology_type": "Sharded",
   "mongo_replicaset_name": null,
   "mongo_db": "somedb",
   "read_preference": "Primary()",
   "mongo_nodes": [
      [
         "mongos-router",
         27017
      ]
   ],
   "mongo_primary_host": null,
   "mongo_secondary_hosts": [],
   "mongo_is_primary": true,
   "mongo_is_mongos": true,
   "shards": {
      "shard1RS": "shard1RS/shard1-1:27018",
      "shard2RS": "shard2RS/shard2-1:27018"
   },
   "shards_info": {
      "shard1RS": {
         "host": "shard1RS/shard1-1:27018",
         "documents_count": 486,
         "status": "ok"
      },
      "shard2RS": {
         "host": "shard2RS/shard2-1:27018",
         "documents_count": 514,
         "status": "ok"
      }
   },
   "total_documents": 1000,
   "replicas_count": {
      "shard1RS": 1,
      "shard2RS": 1
   },
   "collections": {
      "helloDoc": {
         "documents_count": 1000
      }
   },
   "cache_enabled": false,
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

### Добавление шардов в mongos

После настройки репликации для обоих шардов, необходимо добавить их в mongos:

1. **Подключитесь к mongos:**
   ```bash
   docker exec -it mongos-router mongosh
   ```

2. **Добавьте шарды:**
   ```bash
   sh.addShard("shard1RS/shard1-1:27018")
   sh.addShard("shard2RS/shard2-1:27018")
   ```
   MongoDB автоматически обнаружит все узлы реплика-сета через указанный узел.

3. **Включите шардирование для базы данных:**
   ```bash
   sh.enableSharding("somedb")
   ```

4. **Проверьте статус кластера:**
   ```bash
   sh.status()
   ```

### Проверка через mongos

```bash
docker exec -it mongos-router mongosh --eval "sh.status()"
```


