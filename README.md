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



Задание №1 - из каталога `mongo-sharding`:

```shell
cd mongo-sharding
docker compose build
./scripts/init-cluster.sh
```

Задание №2 - из каталога `mongo-sharding-repl`:

```shell
cd mongo-sharding-repl
docker compose build
./scripts/init-cluster.sh
```

Задание №3 - из каталога `sharding-repl-cache`:

```shell
cd sharding-repl-cache
docker compose build
./scripts/init-cluster.sh
```

Если скрипт долго пишет «Ожидание shard1…», чаще всего в фоне **докачивается образ `mongo:7`** или MongoDB ещё не принял соединения — подождите до таймаута (~3 мин) или посмотрите логи: `docker compose logs -f shard1` (из того же каталога проекта).