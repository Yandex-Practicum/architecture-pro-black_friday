# Cпринт 4 (приложение сервиса "Мобильный мир")

## Задание 2. Шардирование
Реализация шардирования в MongoDB

  1. Запуск контейнеров:
    ```docker-compose -f compose.yaml up -d ```

  2. Подключение к серверу конфигурации и инициализация
  ```docker exec -it config-srv mongosh --port 27017 ```

  инициализация:
    ```shell rs.initiate({ _id : "config-server", configsvr: true, members: [{ _id : 0, host : "config-srv:27017" }] }); ```
    ``` exit();```

  3. Подключение к шардам и инициализация:
  шард №1
  ``` docker exec -it shard-1 mongosh --port 27018 ```
  ``` rs.initiate({ _id : "shard-1", members: [{ _id : 0, host : "shard-1:27018" },]}); ```
  ``` exit() ```

  шард №2
  ``` docker exec -it shard-2 mongosh --port 27019 ```
  ``` rs.initiate({ _id : "shard-2", members: [{ _id : 1, host : "shard-2:27019" }] }); ```
  ``` exit() ```
  
  4. Подлючение и инициализация роутера:
  ``` docker exec -it mongos-router mongosh --port 27020 ```
  ``` sh.addShard( "shard-1/shard-1:27018"); sh.addShard( "shard-2/shard-2:27019"); ```
  
  5. Создание БД и документа:
  ``` sh.enableSharding("somedb");  ```
  ``` sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } ); ```
  заполнение тестовыми данными:
  ``` use somedb; ```
  ``` for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i}); ```
  ``` exit() ```

-----
ТЕСТИРОВАНИЕ 

1. Проверка работы сервиса осуществляется через swagger:
     отображение информации о развертывании монго в браузере ``` http://localhost:8082 ``` 
     [картинка хоста монги](/images/отображение%20информации%20о%20развертывании%20монго%20в%20браузере.png)
     
     запуск свагера ``` http://localhost:8082/docs ```
     [свагер](/images/свагер.png)

2. Выполнение запроса на получение списка документов в шардах (общее кол-во записей) ``` http://localhost:8082/docs/count/helloDoc ```
   [общее кол-во записей в БД](/images/запрос%20общего%20кол-ва%20записей%20в%20бд.png)

   [общая информация](/images/общая%20информация.png)
   Видно, что имеются два шарда (**shard-1**, **shard-2**), а общее количество записей **1000**.
     
3. Проверка работы шардирования:
   Проверка общего количества записей через команды:
   ``` docker exec -it mongos-router mongosh --port 27020 ```
   ``` use somedb; ```
   ``` db.helloDoc.countDocuments(); ```
  Общее количество - **1000**

  ![роутер информация о записях](/images/роутер%20-%20число%20записей%20в%20БД.png)

4. Проверка работы каждого из шардов в отдельности
  4.1 Проверка количества записей в шарде **shard-1**
    ``` docker exec -it shard-1 mongosh --port 27018 ```
    ``` use somedb; ```
    ```db.helloDoc.countDocuments(); ```
    Количество **492**
 
     ![шард-1 количество записей](/images/шард1%20-%20число%20записей.png)

  4.2 Проверка количества записей в шарде **shard-2**
    ``` docker exec -it shard-2 mongosh --port 27019 ```
    ``` use somedb; ```
    ```db.helloDoc.countDocuments(); ```
    Количество **508**
 
     ![шард-2 количество записей](/images/шард2%20-%20число%20записей.png)


## Вывод: шардирование работает корректно, данные распределяются роутером по шардам