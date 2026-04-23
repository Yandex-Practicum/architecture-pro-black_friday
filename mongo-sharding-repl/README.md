# Шардирование + репликация (задание 3)

Схема: `pymongo_api` → `mongos` (`172.30.0.7:27020`) → **два шарда, в каждом 3 реплики** (`replSet` `shard1` — узлы `shard1-1`…`shard1-3` на `27018` в контейнерах; `shard2` — `shard2-1`…`shard2-3` на `27019`); `configSrv` (`172.30.0.10:27017`, `config_server`).

Порты на хосте: `27017` config, `27018/27021/27022` — ноды шарда 1, `27019/27023/27024` — шарда 2, `27020` — mongos, `8080` — API.

## Быстрый старт

```bash
cd mongo-sharding-repl
docker-compose up -d --build
chmod +x init-sharding.sh
./init-sharding.sh
```

## Проверка

- [http://localhost:8080/](http://localhost:8080/) — `collections.helloDoc.documents_count` ≥ 1000, `shards`, **`replica_member_counts`: `shard1` и `shard2` = 3** (запрос `replSetGetStatus` к каждому набору реплик; в `compose` — `SHARD1_REPL_URI` / `SHARD2_REPL_URI`).
- Расклад по шардам в `mongos`:

```bash
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```

- Состав реплик на одной ноде шарда (должно быть 3 `members`):

  ```bash
  docker-compose exec -T shard1-1 mongosh --port 27018 --eval 'rs.status().members.length'
  docker-compose exec -T shard2-1 mongosh --port 27019 --eval 'rs.status().members.length'
  ```

## Вручную (по шагам)

1. `docker-compose up -d --build`  
2. Инициализация `config_server` на `configSrv:27017` (как в [init-sharding.sh](./init-sharding.sh)).  
3. На **одной** ноде каждого шарда (`shard1-1`, `shard2-1`) — `rs.initiate` с **тремя** `members` (см. скрипт).  
4. Пауза, `docker-compose restart mongos_router`.  
5. В `mongos`: `sh.addShard("shard1/shard1-1:27018")`, `sh.addShard("shard2/shard2-1:27019")`, `sh.enableSharding("somedb")`, `sh.shardCollection("somedb.helloDoc", { _id: "hashed" })`.  
6. Вставка ≥ 1000 документов (в скрипте — 1200) через `mongos` в `somedb.helloDoc`.
