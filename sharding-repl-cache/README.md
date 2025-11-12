# sharding-repl-cache

Инструкция по запуску sharding-repl-cache — та же схема как в `mongo-sharding-repl`, но с Redis для кеширования.

По сравнению с `mongo-sharding-repl`:
- сервис `redis` (порт 6379)
- у `pymongo_api` в переменных окружения задано `REDIS_URL: "redis://redis:6379"`

1) Запустить контейнеры в директории `sharding-repl-cache`

```bash
docker compose -f compose.yaml up -d
```

2) Создать Redis-кластер

```bash
docker exec -it master1 redis-cli --cluster create \
  173.17.2.2:6379 173.17.2.3:6379 173.17.2.4:6379 \
  173.17.2.5:6379 173.17.2.6:6379 173.17.2.7:6379 \
  --cluster-replicas 1
```

3) Инициализировать Replica Set для config server

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({_id: 'config_server', members: [{_id: 0, host: 'configSrv:27017'}]})
rs.status()
EOF
```

4) Инициализировать Replica Set для шардов

Shard1:

```bash
docker compose exec -T shard1a mongosh --port 27018 --quiet <<'EOF'
rs.initiate({_id: 'shard1', members: [
  {_id: 0, host: 'shard1a:27018'},
  {_id: 1, host: 'shard1b:27018'},
  {_id: 2, host: 'shard1c:27018'}
]})
rs.status()
EOF
```

Shard2:

```bash
docker compose exec -T shard2a mongosh --port 27019 --quiet <<'EOF'
rs.initiate({_id: 'shard2', members: [
  {_id: 0, host: 'shard2a:27019'},
  {_id: 1, host: 'shard2b:27019'},
  {_id: 2, host: 'shard2c:27019'}
]})
rs.status()
EOF
```

5) Зарегистрировать шарды в `mongos`

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard('shard1/shard1a:27018,shard1b:27018,shard1c:27018')
sh.addShard('shard2/shard2a:27019,shard2b:27019,shard2c:27019')
sh.status()
EOF
```

6) Включить шардирование и заполнить коллекцию

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.enableSharding('somedb')
sh.shardCollection('somedb.helloDoc', {_id: 'hashed'})
EOF

./scripts/mongo-init.sh
```

7) Проверка кеша и времени ответа

- API доступно по http://localhost:8080/
- Повторный вызов `/helloDoc/users` быстрее.

```bash
# первый из запроса к БД
time curl -s http://localhost:8080/helloDoc/users > /dev/null

# второй из кеша
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```