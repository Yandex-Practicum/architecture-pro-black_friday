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

Заходим в папку `sharding-repl-cache` и выполняем команды

```
docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker compose down -v  && docker compose up -d --build

./scripts/mongo-redis-init.sh
``` 

После этого можно проверить требания каждого задания

### Задание 2 - sharding

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

### Задание 3 - replication

Внутри роутера проверяем, что у всех шардов есть по три реплики
```
docker exec -it mongos_router mongosh --port 27021

sh.listShards()
```

Должно выйти что-то вроде:
```
[
  {
    _id: 'shard1',
    host: 'shard1/shard1-node1:27018,shard1-node2:27018,shard1-node3:27018',
    state: 1,
    topologyTime: Timestamp({ t: 1786651783, i: 27 }),
    replSetConfigVersion: Long('-1')
  },
  {
    _id: 'shard2',
    host: 'shard2/shard2-node1:27019,shard2-node2:27019,shard2-node3:27019',
    state: 1,
    topologyTime: Timestamp({ t: 1786651788, i: 32 }),
    replSetConfigVersion: Long('-1')
  },
  {
    _id: 'shard3',
    host: 'shard3/shard3-node1:27020,shard3-node2:27020,shard3-node3:27020',
    state: 1,
    topologyTime: Timestamp({ t: 1786651801, i: 24 }),
    replSetConfigVersion: Long('-1')
  }
]
```

Видно, что у каждого шарда перечислено по три ноды

### Задание 4 - caching

Можно проверить командой 
```
curl -v localhost:8080
curl -v localhost:8080/helloDoc/users
```