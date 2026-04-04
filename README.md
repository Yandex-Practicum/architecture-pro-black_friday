# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

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


## Запуск

Задание №1 - из каталога `mongo-sharding`:

```shell
docker compose build
./scripts/init-cluster.sh
```

Задание №2 - из каталога `mongo-sharding-repl`:

```shell
docker compose build
./scripts/init-cluster.sh
```

Задание №3 - из каталога `sharding-repl-cache`:

```shell
docker compose build
./scripts/init-cluster.sh
```