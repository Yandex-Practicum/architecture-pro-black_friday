Из папки `mongo-sharding` запускаем 

Удаляю контейнеры во избежание конфликтов
```
docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker compose down -v  && docker compose up -d --build
```

Далее надо настроить сервер с конфигурацией, шарды и роутер. Запускаем sh скрипт
```
./scripts/mongo-init.sh
```

Внутри роутера проверяем, что все документы вставились
```
docker exec -it mongos_router mongosh --port 27021

use somedb;
db.helloDoc.countDocuments() 
```

Командой ниже можно убедиться, что тысяча записей равномерно распределена между тремя шардами
```
sh.getShardedDataDistribution()
```

Должно выйти что-то вроде
```
{
    ns: 'somedb.helloDoc',
    shards: [
      {
        shardName: 'shard3',
        numOrphanedDocs: 0,
        numOwnedDocuments: 336,
        ownedSizeBytes: 15456,
        orphanedSizeBytes: 0
      },
      {
        shardName: 'shard2',
        numOrphanedDocs: 0,
        numOwnedDocuments: 346,
        ownedSizeBytes: 15916,
        orphanedSizeBytes: 0
      },
      {
        shardName: 'shard1',
        numOrphanedDocs: 0,
        numOwnedDocuments: 318,
        ownedSizeBytes: 14628,
        orphanedSizeBytes: 0
      }
    ]
  }
```