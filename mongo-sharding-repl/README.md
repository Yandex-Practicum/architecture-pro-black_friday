
## Запуск проекта.
1. Запускаем docker-compose:
```bash
    docker-compose -f mongo-sharding-repl.yaml up -d 
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
5. Проверяем состояние реплик:
```bash
for shard in shard1 shard2 shard3; do
  echo "=== $shard ==="
  docker exec mongodb-$shard mongosh --port 27018 --quiet --eval "
    try {
      const status = rs.status();
      print('Members:', status.members.length);
      status.members.forEach(m => {
        print('  -', m.name.split(':')[0], 
              '| State:', m.stateStr.padEnd(10),
              '| Health:', m.health === 1 ? '✅' : '❌',
              '| Uptime:', Math.round(m.uptime/60) + 'min');
      });
    } catch(e) {
      print('Error:', e.message);
    }
  "
  echo ""
done
```

6. Удаляем контейнеры:
```bash
  docker-compose -f mongo-sharding-repl.yaml down -v
  ```