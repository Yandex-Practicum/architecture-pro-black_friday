# Шардирование MongoDB (docker-compose)

Схема: клиент `pymongo_api` → `mongos` (`172.30.0.7:27020`) → шарды `shard1` (`172.30.0.9:27018`, replSet `shard1`), `shard2` (`172.30.0.8:27019`, replSet `shard2`); сервер конфигурации `configSrv` (`172.30.0.10:27017`, replSet `config_server`).

## скрипт

```bash
cd mongo-sharding
docker-compose up -d --build
chmod +x init-sharding.sh
./init-sharding.sh
```

[init-sharding.sh](./init-sharding.sh) вызывает **`docker-compose`** (как в примерах с `exec -T` в инструкции).

Скрипт рассчитан на пустой кластер (свежие `volume`’ы). Повторная инициализация: `docker-compose down -v`, снова `up` и скрипт.

Счётчики вручную в `mongos`: `use somedb`, затем `db.helloDoc.countDocuments()` и `db.helloDoc.getShardDistribution()` — примеры в разделе 7 ниже.

Ниже — те же шаги по кускам, если удобнее вводить вручную.

## 1. Запуск контейнеров

```bash
docker-compose up -d --build
```

После первого запуска `mongos` может перезапускаться, пока не инициализирована replica set сервера конфигурации. Ниже по шагам: сначала `config_server`, затем шарды. Когда `config` готов, при необходимости перезапустите маршрутизатор.

```bash
docker-compose restart mongos_router
```

## 2. Инициализация replica set сервера конфигурации

`configsvr: true` обязателен для `configsvr`-процесса.

```bash
docker-compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
});
EOF
```

## 3. Инициализация шардов (по одному)

Шард 1

```bash
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
});
EOF
```

Шард 2

```bash
docker-compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
});
EOF
```

Подождите 10–20 секунд, пока на всех трёх кластерах пройдут выборы. При необходимости снова:

```bash
docker-compose restart mongos_router
```

## 4. Подключение шардов к кластеру (через `mongos`)

```bash
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
EOF
```

## 5. Включение шардирования БД и коллекции

База — `somedb`, коллекция — `helloDoc`. Ключ `hashed` по `_id` равномерно распределяет документы по шардам.

```bash
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```

## 6. Вставка данных (не меньше 1000 документов)

```bash
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
const ndocs = 1200;
const batch = 300;
const dbn = db.getSiblingDB("somedb");
for (let s = 0; s * batch < ndocs; s++) {
  const n = Math.min(batch, ndocs - s * batch);
  const docs = Array.from(
    { length: n },
    (_, i) => ({ n: s * batch + i, t: "seed" })
  );
  dbn.helloDoc.insertMany(docs, { ordered: false });
}
EOF
```

## 7. Проверка: общее число и распределение по шардам

Через `mongos` (итоговое распределение)

```bash
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF
```

С прямой проверки шарда (только кусок коллекции на конкретном `mongod`, для отладки):

```bash
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

## 8. HTTP API

После инициализации откройте [http://localhost:8080/](http://localhost:8080/):

- `collections.helloDoc.documents_count` — всего документов в `somedb.helloDoc`;
- `shards` — зарегистрированные в кластере шарды.

Расклад документов по шардам смотрите в разделе 7 (`getShardDistribution()` в `mongos`).