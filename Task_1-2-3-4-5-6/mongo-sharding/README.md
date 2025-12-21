# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными и инициализируем роутер и конфиг

```shell
./scripts/mongo-init.sh
```

## Как проверить

Откройте в браузере http://localhost:8080 - топология MongoDB

Откройте в браузере http://localhost:8080/helloDoc/count - колличество записей в базе
