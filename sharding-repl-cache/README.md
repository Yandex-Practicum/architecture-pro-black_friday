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
docker compose exec -T mongodb-router mongosh --host 127.0.0.1 --port 27020 --quiet --eval '
db = db.getSiblingDB("somedb");
print("Total docs:", db.helloDoc.countDocuments());
db.helloDoc.getShardDistribution();
'