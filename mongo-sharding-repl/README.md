# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Инициализируем конфиг
```shell
docker compose up -d
```

Инициализуруем конфигурации и шардов

```shell
docker compose exec -T config_srv_1 sh -c mongosh < mongo/init-config.js
docker compose exec -T shard1_1 mongosh --port 27018 < mongo/init-shard1.js 
docker compose exec -T shard2_1 mongosh --port 27019 < mongo/init-shard2.js 
sleep 15s
docker compose exec -T mongo_router mongosh < mongo/init-router.js
```

Заполнить данные
```shell
sh ./scripts/mongo-init.sh  

```

## Как проверить

### Проверка статуса реплик и шардов
```shell
docker compose exec -T shard1_1  bash -c "echo 'rs.status()' | mongosh --port 27018"
docker compose exec -T shard2_1  bash -c "echo 'rs.status()' | mongosh --port 27019"
```

#### Удалить все контейнеры

```shell
docker compose down -v --rmi all --remove-orphans
```

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs