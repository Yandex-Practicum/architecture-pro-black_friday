# pymongo-api

## Инструкция по запуску

1. Перейти в директорию `sharding-repl-cache`:
    ```shell
    cd ./sharding-repl-cache
    ```

2. Начальную инициацию приложения выполнять с помощью команды:
    ```shell
    ./mongo-init.sh
    ```
   После её выполнения будут запущены требуемые контейнеры и БД будет заполнена данными.
   Скрипт содержит следующие шаги (они не требуют отдельного выполнения):
    1. Запуск docker compose и ожидание пока контейнеры с сервером конфигурации и шардами станут `healthed`:
         ```shell
         docker compose up -d

        wait_ping configSrv 27017
        wait_ping shard1-1 27018
        wait_ping shard1-2 27018
        wait_ping shard1-3 27018
        wait_ping shard2-1 27019
        wait_ping shard2-2 27019
        wait_ping shard2-3 27019
          ```
    2. Инициализация сервера конфигурации:
         ```shell
         docker exec configSrv mongosh --port 27017 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"config_server",configsvr:true,members:[{_id:0,host:"configSrv:27017"}]}) }'
       ```
    3. Инициализация двух шардов и трёх реплик для каждого шарда:
         ```shell
        docker exec shard1-1 mongosh --port 27018 --quiet --eval '
        try { rs.status() } catch(e) {
        rs.initiate({
        _id:"shard1",
        members:[
        {_id:0, host:"shard1-1:27018"},
        {_id:1, host:"shard1-2:27018"},
        {_id:2, host:"shard1-3:27018"}
        ]
        })
        }
        '

        docker exec shard2-1 mongosh --port 27019 --quiet --eval '
        try { rs.status() } catch(e) {
        rs.initiate({
        _id:"shard2",
        members:[
        {_id:0, host:"shard2-1:27019"},
        {_id:1, host:"shard2-2:27019"},
        {_id:2, host:"shard2-3:27019"}
        ]
        })
        }
        '
         ```
    4. Ожидание пока роутер станет `healthed`:
         ```shell
         wait_ping mongos_router 27020
         ```
    5. Инициализация роутера:
         ```shell
         docker exec mongos_router mongosh --port 27020 --quiet --eval '
        sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
        sh.addShard("shard2/shard2-2:27019,shard2-2:27019,shard2-3:27019");
        sh.enableSharding("somedb");
        sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });
        '
         ```
    6. Наполнение тестовыми данными:
         ```shell
         docker exec mongos_router mongosh --port 27020 --quiet --eval '
         const dbx = db.getSiblingDB("somedb");
         for (let i = 0; i < 1000; i++) dbx.helloDoc.insertOne({age:i, name:"ly"+i});
         print("inserted:", dbx.helloDoc.countDocuments());
         '
         ```
    7. Кеширование не требует дополнительной настройки, т.к. в задании не было явного требования о поднятии кластера
       Redis.

3. Остановка всех контейнеров и удаление созданных томов:
      ```shell
      ./mongo-down.sh
      ```
