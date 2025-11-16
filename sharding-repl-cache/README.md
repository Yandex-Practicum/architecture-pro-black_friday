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
- Инициализация шарда 1 с тремя репликами выполняется командой:
```bash
docker exec -it shard-1-master mongosh --port 27018 <<EOF
rs.initiate(
    {
      _id : "shard-1",
      members: [
        { _id : 0, host : 'shard-1-master:27018' },
        { _id : 1, host : 'shard-1-replica-1:27021'},
        { _id : 2, host : 'shard-1-replica-2:27022'}
      ]
    }
);
exit();
EOF
```

- Инициализация шарда 2 с тремя репликами выполняется командой:
```bash
docker exec -it shard-2-master mongosh --port 27019 <<EOF
rs.initiate(
    {
      _id : "shard-2",
      members: [
        { _id : 0, host : 'shard-2-master:27019' },
        { _id : 1, host : 'shard-2-replica-1:27023'},
        { _id : 2, host : 'shard-2-replica-2:27024'}
      ]
    }
  );
exit();
EOF
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

- Проверка наполнения шарда 1 и его реплик выполняется командой:
```bash
docker exec -it shard-1-master mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-1-replica-1 mongosh --port 27021 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-1-replica-2 mongosh --port 27022 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
```

- Проверка наполнения шарда 2 и его реплик выполняется командой:
```bash
docker exec -it shard-2-master mongosh --port 27019 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-2-replica-1 mongosh --port 27023 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker exec -it shard-2-replica-2 mongosh --port 27024 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
```