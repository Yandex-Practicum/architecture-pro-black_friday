![Схема архитектуры](./schema1.png)

# Инициализация шардирования

поднять Docker compose

```shell
docker compose up -d
```

запустить mongo-init.sh

```shell
./scripts/mongo-init.sh
```

Скрипт запускает инициализацию сервера конфигурации и шардов.

```shell
# Пример
docker exec -it configsvr mongosh --port 27019 --eval 'rs.initiate({_id:"configReplSet",configsvr:true,members:[{_id:0,host:"configsvr:27019"}]})'
docker exec -it shard1 mongosh --port 27018 --eval 'rs.initiate({_id:"shard1",members:[{_id:0,host:"shard1:27018"}]})'
docker exec -it shard2 mongosh --port 27018 --eval 'rs.initiate({_id:"shard2",members:[{_id:0,host:"shard2:27018"}]})'
```

После этого ожидает стаблизации конейнера и добавляет шарды в кластер и настраивает шардирование коллекции

```shell
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard1/shard1:27018")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.addShard("shard2/shard2:27018")'

docker exec -it mongos mongosh --port 27017 --eval 'sh.enableSharding("somedb")'
docker exec -it mongos mongosh --port 27017 --eval 'sh.shardCollection("somedb.helloDoc", {name: "hashed"})'
```

Команды можно выполнить вручную если конейнеры сликшом долго стартуют.

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
