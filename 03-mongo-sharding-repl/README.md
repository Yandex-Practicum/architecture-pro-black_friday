# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Запустите скрипт, чтобы настроить шардирование и заполнить mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

### Проверить, что api работает

Откройте в браузере http://localhost:8080

### Проверить, что шардирование работает

Можно посмотреть результаты в выводе скрипта, либо выполнить команды вручную (ниже).

Выполните команду, чтобы увидеть сколько записей в первом шарде. Количество записей должно быть одинаковым во всех репликах (M):
```
docker compose exec -T shard1_master mongosh --port 27018 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard1_repl1 mongosh --port 27019 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard1_repl2 mongosh --port 27020 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF
```

Выполните команду, чтобы увидеть сколько записей во втором шарде. Количество записей должно быть одинаковым во всех репликах (M):
```
docker compose exec -T shard2_master mongosh --port 27021 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard2_repl1 mongosh --port 27022 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard2_repl2 mongosh --port 27023 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF
```

Сложите оба значения (M + N). В сумме должно получиться 1000 записей.
