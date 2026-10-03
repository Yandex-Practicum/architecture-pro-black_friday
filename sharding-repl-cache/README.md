# sharding-repl-cache

Приложение `pymongo-api`, шардированный кластер MongoDB, в котором каждый шард — replica set из трёх узлов, и Redis для кеширования запросов приложения:

| Сервис                           | Роль                                               | Порт  |
|----------------------------------|----------------------------------------------------|-------|
| `configSrv`                      | сервер конфигурации (replica set `config_server`)  | 27017 |
| `shard1-1`, `shard1-2`, `shard1-3` | 1-й шард, replica set `shard1` (1 PRIMARY + 2 SECONDARY) | 27018 |
| `shard2-1`, `shard2-2`, `shard2-3` | 2-й шард, replica set `shard2` (1 PRIMARY + 2 SECONDARY) | 27019 |
| `mongos_router`                  | роутер `mongos`                                    | 27020 |
| `pymongo_api`                    | приложение (`kazhem/pymongo_api:1.0.0`), ходит в MongoDB через `mongos_router`, кеширует ответы в `redis` | 8080  |
| `redis`                          | кеш (`REDIS_URL: "redis://redis:6379"`)            | 6379  |

БД — `somedb`, коллекция — `helloDoc`, ключ шардирования — `{ name: "hashed" }`.

Узлы одного шарда работают в разных контейнерах, поэтому слушают один и тот же порт (27018 для `shard1`, 27019 для `shard2`). Наружу опубликованы только порты `mongos_router` (27020), `redis` (6379) и приложения (8080).

## Как запустить

Все команды выполняются из директории `sharding-repl-cache`.

Запускаем MongoDB, Redis и приложение:

```shell
docker compose up -d
```

Инициализируем репликацию и шардирование, заполняем MongoDB данными (скрипт выполняет все шаги из раздела ниже автоматически):

```shell
./scripts/mongo-init.sh
```

## Шаги настройки репликации и шардирования (вручную)

1. Инициализируем сервер конфигурации:

```shell
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF
```

2. Настраиваем репликацию для 1-го шарда — объединяем `shard1-1`, `shard1-2`, `shard1-3` в replica set `shard1`. Команду достаточно выполнить на одном узле, остальные получат конфигурацию автоматически:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF
```

3. Настраиваем репликацию для 2-го шарда — объединяем `shard2-1`, `shard2-2`, `shard2-3` в replica set `shard2`:

```shell
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
})
EOF
```

4. Ждём 10–15 секунд, пока в каждом replica set будет выбран PRIMARY. Проверить можно так (должно вернуть `true`):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "db.hello().isWritablePrimary"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval "db.hello().isWritablePrimary"
```

5. Добавляем шарды в роутер, указывая все реплики каждого replica set, и включаем шардирование:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF
```

6. Заполняем коллекцию тестовыми данными через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
db.helloDoc.countDocuments()
EOF
```

## Как проверить

Откройте в браузере http://localhost:8080. В ответе будут:

- `"collections": {"helloDoc": {"documents_count": 1000}}` — общее количество документов;
- `"shards"` — оба шарда со списком их реплик, например `"shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018"`.

Количество документов на каждом шарде (в сумме 1000, например 492 и 508):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

Количество и состояние реплик каждого шарда (по 3: один `PRIMARY` и два `SECONDARY`):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.forEach(m => print(m.name + " " + m.stateStr))'
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.forEach(m => print(m.name + " " + m.stateStr))'
```

Проверка отказоустойчивости — останавливаем PRIMARY первого шарда, приложение продолжает отвечать, а один из SECONDARY становится PRIMARY:

```shell
docker compose stop shard1-1
curl http://localhost:8080/helloDoc/count
docker compose exec -T shard1-2 mongosh --port 27018 --quiet --eval 'rs.status().members.forEach(m => print(m.name + " " + m.stateStr))'
docker compose start shard1-1
```

## Как проверить кеширование

Кеширование включается переменной окружения `REDIS_URL` у сервиса `pymongo_api` и работает для эндпоинта `/<collection_name>/users` (время жизни кеша — 60 секунд).

Проверяем, что кеш включён — в ответе http://localhost:8080 должно быть `"cache_enabled": true`.

Выполняем один и тот же запрос несколько раз и смотрим время ответа:

```shell
for i in 1 2 3; do curl -s -o /dev/null -w "запрос $i: %{time_total}s
" http://localhost:8080/helloDoc/users; done
```

Первый запрос идёт в MongoDB и выполняется больше секунды, повторные берутся из Redis и выполняются за < 100 мс:

```
запрос 1: 1.043660s
запрос 2: 0.008518s
запрос 3: 0.008406s
```

Ключи кеша в Redis:

```shell
docker compose exec -T redis redis-cli keys '*'
```

Если проект запущен на виртуальной машине, узнайте её белый IP (`curl --silent http://ifconfig.me`) и откройте `http://<ip виртуальной машины>:8080`.

## Доступные эндпоинты

Список доступных эндпоинтов, swagger: http://localhost:8080/docs

## Остановка

```shell
docker compose down -v
```
