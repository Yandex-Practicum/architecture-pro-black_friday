# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init_configSrv.sh
./scripts/mongo-init_shard1.sh
./scripts/mongo-init_shard2.sh
./scripts/mongo-init_mongos_router.sh
./scripts/mongo-init.sh
```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080