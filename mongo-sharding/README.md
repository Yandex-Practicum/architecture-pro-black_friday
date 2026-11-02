# pymongo-api-sharding

## Как запустить

# 1. Запускаем Config Server и два шарда
docker compose up -d configSrv shard1 shard2

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
docker compose up -d pymongo_api_sharding