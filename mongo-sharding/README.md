# MongoDB Sharding

Шардированный кластер MongoDB с двумя шардами.

## Архитектура

- **mongos_router** — маршрутизатор запросов
- **configsvr** — сервер конфигурации (replica set из одного узла)
- **shard1, shard2** — шарды для хранения данных
- **pymongo_api** — приложение (FastAPI + Motor)

## Запуск

### 1. Поднять контейнеры

```bash
docker compose up -d
```

### 2. Инициализировать кластер

```bash
bash scripts/mongo-init.sh
```

Скрипт выполняет:
1. Инициализацию replica set для config server
2. Добавление shard1 и shard2 в кластер через mongos
3. Включение шардирования для БД `somedb`
4. Шардирование коллекции `helloDoc` по полю `age` (hashed)
5. Заполнение коллекции 1000 тестовыми документами

### 3. Проверить работу

```bash
# Статус приложения (покажет информацию о шардах)
curl http://localhost:8080/

# Количество документов
curl http://localhost:8080/helloDoc/count

# Проверить распределение данных по шардам
docker compose exec mongos_router mongosh --port 27017 --eval "use somedb; db.helloDoc.getShardDistribution()"
```

## Остановка

```bash
docker compose down -v
```
