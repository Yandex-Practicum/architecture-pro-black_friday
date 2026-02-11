# pymongo-api-sharding

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

При успешном заполнении будет выведена информация о распределении по шардам:

```
[direct: mongos] somedb> Shard shard1 at shard1/shard1:27018
{
  data: '22KiB',
  docs: 492,
  chunks: 1,
  'estimated data per chunk': '22KiB',
  'estimated docs per chunk': 492
}
---
Shard shard2 at shard2/shard2:27019
{
  data: '23KiB',
  docs: 508,
  chunks: 1,
  'estimated data per chunk': '23KiB',
  'estimated docs per chunk': 508
}
---
Totals
{
  data: '45KiB',
  docs: 1000,
  chunks: 2,
  'Shard shard1': [
    '49.17 % data',
    '49.2 % docs in cluster',
    '46B avg obj size on shard'
  ],
  'Shard shard2': [
    '50.82 % data',
    '50.8 % docs in cluster',
    '46B avg obj size on shard'
  ]
}
[direct: mongos] somedb> That's all

```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs