# mongo-sharding-repl

Шардированный MongoDB: **mongos**, **config server replica set**, два шарда, **каждый шард — replica set из трёх узлов** (один primary и две secondary). Приложение **pymongo-api** подключается к **mongos**.

База: `somedb`, коллекция: `helloDoc`.


## Запуск

Порты по умолчанию: **8080** (API), **27017** (mongos). Если параллельно запущен проект `mongo-sharding`, остановите его или измените проброс портов в `compose.yaml`.

Из каталога `mongo-sharding-repl`:

```shell
docker compose build
./scripts/init-cluster.sh
```

### Проверка данных и шардов

`curl -s http://localhost:8080/` — в JSON должны быть `collections.helloDoc.documents_count` (≥1000), `documents_per_shard`, поле **`shards`** и блок **`shard_replica_sets`**.

### Где видна репликация (задание 3)

Репликация **не** отображается в `mongo_replicaset_name` / `mongo_primary_host`: приложение подключено к **mongos**, это не replica set, поэтому там пусто или «No Replicas» — так и должно быть.

Репликация на шардах видна так:

1. **`shard_replica_sets`** — для каждого шарда: **`members`: 3**, **`secondaries`: 2** (один primary и две копии в RS).
2. **`shards`** — значение вида `shard1/shard1-1:27017,shard1-2:27017,shard1-3:27017`: в кластере зарегистрированы **три** узла replica set.
3. Поле **`note_replication`** в ответе API напоминает, куда смотреть.

Убедиться в ролях PRIMARY/SECONDARY на узле шарда (пример для первого шарда):

```shell
docker compose exec -T shard1-1 mongosh --port 27017 --quiet --eval 'rs.status().members.forEach(function(m) { print(m.name, m.stateStr); })'
```

Должны быть три строки: один **PRIMARY**, два **SECONDARY**.

Убедиться, что подняты **шесть** контейнеров шардов: `docker compose ps` (сервисы `shard1-1` … `shard2-3`).

Если вы запускали **`mongo-sharding`** (задание 2), там по **одному** узлу на шард — репликации на шардах там нет. Нужен каталог **`mongo-sharding-repl`**.