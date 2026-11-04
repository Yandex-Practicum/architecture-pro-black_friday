# pymongo-api-sharding-repl

## Как запустить

# 1. Запускаем Config Server и все реплики
docker compose up -d \
  configsrv \
  shard1-1 shard1-2 shard1-3 \
  shard2-1 shard2-2 shard2-3


# 1.1 Проверяем что контейнеры healthy
docker compose ps 

# 2. После готовности MongoDB инициализируем узлы
bash scripts/init-cluster.sh

# 3. Запускаем роутер
docker compose up -d mongos_router

# 3.1 Проверяем что контейнеры healthy
docker compose ps 

# 4. После готовности роутера настраиваем шардирование
bash scripts/init-data.sh

# 5. Запускаем приложение
docker compose up -d pymongo_api