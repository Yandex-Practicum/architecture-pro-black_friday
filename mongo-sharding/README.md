
## Запуск проекта.
1. Запускаем docker-compose:
```bash
    docker-compose -f mongo-sharding.yaml up -d 
```	
2. Теперь можно пользоваться, создадим шардированную коллекцию:
```bash
    docker composexec -T mongos1 mongosml exec -T mongos1 mongosh --port 27017 --quiet <<EOF
    use somedb
    db.createCollection("helloDoc")

    sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
    print("Collection sharded with hashed key on 'age' field");
    EOF
  ```  
3. Запишем в коллекцию данные:
```bash
    docker compos exec -T mongos1 mongosml exec -T mongos1 mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
```
4. Проверим как распределились данные:
```bash
    docker composexec -T mongos1 mongosml exec -T mongos1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```
5. Удаляем контейнеры:
```bash
  docker-compose -f mongo-sharding.yaml down -v
  ```