# mongo-sharding

## Инструкция по запуску

```
   Все команды для cli указаны относительно директории `mongo-sharding`, т.е. той, в которой находился данный файл на момент клонирования репозитория.
```

1. Начальную инициацию приложения выполнять с помощью команы:
    ```shell
    ./mongo-init.sh
    ```
   После её выполнения будут запущены требуемые контейнеры и БД будет заполнена данными.
   Скрипт содержит следующие шаги (они не требуют отдельного выполнения):
    1. Запуск docker compose и ожидание пока контейнеры с сервером конфигурации и шардами станут `healthed`:
         ```shell
         docker compose up -d

         until docker exec configSrv mongosh --port 27017 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
         until docker exec shard1   mongosh --port 27018 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
         until docker exec shard2   mongosh --port 27019 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
          ```
    2. Инициализация сервера конфигурации:
         ```shell
         docker exec configSrv mongosh --port 27017 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"config_server",configsvr:true,members:[{_id:0,host:"configSrv:27017"}]}) }'
       ```
    3. Инициализация сервера шардов:
         ```shell
         docker exec shard1 mongosh --port 27018 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"shard1",members:[{_id:0,host:"shard1:27018"}]}) }'
         docker exec shard2 mongosh --port 27019 --quiet --eval 'try { rs.status() } catch(e) { rs.initiate({_id:"shard2",members:[{_id:0,host:"shard2:27019"}]}) }'
         ```
    4. Ожидание пока роутер станет `healthed`:
         ```shell
         until docker exec mongos_router mongosh --port 27020 --quiet --eval 'db.adminCommand("ping").ok' | grep -q 1; do sleep 1; done
         ```
    5. Инициализация роутера:
         ```shell
         docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.addShard("shard1/shard1:27018");'
         docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.addShard("shard2/shard2:27019");'
         docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.enableSharding("somedb");'
         docker exec mongos_router mongosh --port 27020 --quiet --eval 'sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });'
         ```
    6. Наполнение тестовыми данными:
         ```shell
         docker exec mongos_router mongosh --port 27020 --quiet --eval '
         const dbx = db.getSiblingDB("somedb");
         for (let i = 0; i < 1000; i++) dbx.helloDoc.insertOne({age:i, name:"ly"+i});
         print("inserted:", dbx.helloDoc.countDocuments());
         '
         ```
2. Для отсановки можно использовать одну из следующих команд:
    * Остановка всех контейнеров и удаление созданных томов:
      ```shell
      ./mongo-down.sh
      ```
    * Остановка всех контейнеров:
        ```shell
       docker compose down
       ```
