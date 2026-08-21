Из папки `mongo-sharding` запускаем 

Удаляю контейнеры во избежание конфликтов
```
docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker compose down -v  && docker compose up -d --build
```

Далее надо настроить сервер с конфигурацией, шарды и роутер. Запускаем sh скрипт
```
./scripts/mongo-init.sh
```

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