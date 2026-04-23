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

Выполните команду, чтобы увидеть сколько записей в первом шарде:
```
docker compose exec -T shard1 mongosh --port 27018 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF
```

Выполните команду, чтобы увидеть сколько записей во втором шарде:
```
docker compose exec -T shard2 mongosh --port 27019 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF
```

Сложите оба значения. В сумме должно получиться 1000 записей.
