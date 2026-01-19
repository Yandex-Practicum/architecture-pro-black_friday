# pymongo-api

## Как запустить

Запускаем mongodb и приложение:

```shell
docker compose up -d
```

Для инициализации шардирование и заполнения mongodb данными выполните следующий скрипт:

```shell
./mongo-init.sh
```
Скрипт выполняет следующие действия:
1. Инициализирует сервер конфигурации **configSrv** (порт 27019)
2. Инициализирует шард **shart1** (порт 27021)
3. Инициализирует шард **shart2** (порт 27022)
4. Инициализируем роутер **mongos_router** (порт 27017)
5. Наполняет БД тестовыми данными

## Как проверить

### Проверка распределение документов по шардам

Подсчитаем общее количество документов. Подключитесь к mongosh в контейнере docker:
```
docker exec -it mongos_router mongosh --port 27017
```
Выполните следующие команды в mongosh:
```
use somedb
db.helloDoc.countDocuments()
exit
```

Подсчитаем количество документов в первом шарде. Подключитесь к mongosh в контейнере docker:
```
docker exec -it shard1 mongosh --port 27021
```
Выполните следующие команды в mongosh:
```
use somedb
db.helloDoc.countDocuments()
exit
``` 

Подсчитаем количество документов во втором шарде. Подключитесь к mongosh в контейнере docker:
```
docker exec -it shard2 mongosh --port 27022
```
Выполните следующие команды в mongosh:
```
use somedb
db.helloDoc.countDocuments()
exit
``` 
### Проверка приложения

#### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

#### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

## Примеры команд

Если вы запускаете проект на локальной машине:

Информация о базе данных:
```
curl http://localhost:8080               
{"mongo_topology_type":"Sharded","mongo_replicaset_name":null,"mongo_db":"somedb","read_preference":"Primary()","mongo_nodes":[["mongos_router",27017]],"mongo_primary_host":null,"mongo_secondary_hosts":[],"mongo_is_primary":true,"mongo_is_mongos":true,"collections":{"helloDoc":{"documents_count":1000}},"shards":{"shard1":"shard1/shard1:27021","shard2":"shard2/shard2:27022"},"cache_enabled":false,"status":"OK"}
```

Общее количество документов в коллекции helloDoc:
```
curl http://localhost:8080/helloDoc/count
{"status":"OK","mongo_db":"somedb","items_count":1000}%
```

Список пользователей в коллекции helloDoc:
```
curl http://localhost:8080/helloDoc/users
{"users":[{"id":"696809706823ec10083f118c","age":0,"name":"ly0"}
...
```

Со остальными командами вы можете ознакомиться, открыв в браузере спецификацию OpenAPI по адресу http://localhost:8080/docs