# Задание 2. Шардирование на MongoDB

Согласно заданию, подготовлен новый файл Docker Compose.

## Запуск приложения
Запуск инфраструктуры и приложения выполняется командой:
```bash
docker compose up -d
```

## Инициализация

Инициализация выполняется скриптом:
```bash
./init-sharding.sh
```
или
```shell
./init-sharding.ps1
```

В составе скрипта (на примере `bash`):
- Инициализация сервера конфигураций выполняется командой:
```bash
docker compose exec -it configSrv mongosh --port 27017

> rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
> exit(); 
```

- Инициализация шарда 1 выполняется командой:
```bash
docker exec -it shard1 mongosh --port 27018

> rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1:27018" },
       // { _id : 1, host : "shard2:27019" }
      ]
    }
);
> exit();
```

- Инициализация шарда 2 выполняется командой:
```bash
docker exec -it shard2 mongosh --port 27019

> rs.initiate(
    {
      _id : "shard2",
      members: [
       // { _id : 0, host : "shard1:27018" },
        { _id : 1, host : "shard2:27019" }
      ]
    }
  );
> exit();
```

- Инициализация маршрутизатора (роутера) выполняется командой:
```bash
docker exec -it mongos_router mongosh --port 27020

> sh.addShard( "shard1/shard1:27018");
> sh.addShard( "shard2/shard2:27019");

> sh.enableSharding("somedb");
> sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

> use somedb

> for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})

> db.helloDoc.countDocuments() 
> exit();
```

## Проверка наполнения базы данных 

Проверка наполнения выполняется скриптом
```bash
./sharding-check.sh
```
или
```shell
./sharding-check.ps1
```

В составе скрипта (на примере `bash`):

- Проверка наполнения базы данных: 
```bash
 docker exec -it router mongosh --port 27020
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
```

- Проверка наполнения шарда 1:
```bash
docker exec -it shard-1 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
```

- Проверка наполнения шарда 2:
```bash
 docker exec -it shard-2 mongosh --port 27019
 > use somedb;
 > db.helloDoc.countDocuments();
 > exit();
```