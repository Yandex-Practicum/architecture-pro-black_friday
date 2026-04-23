# sharding-repl-cache

## Запуск

1. Запустить все сервисы:
```bash
   docker compose up -d
```

2. Инициализировать конфиг-сервер:
```bash
   docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
   rs.initiate({ _id: "config_server", configsvr: true, members: [{ _id: 0, host: "configSrv:27017" }] })
   EOF
```

3. Инициализировать реплики шардов (см. предыдущие README).

4. Добавить шарды в роутер и инициализировать базу:
```bash
   ./scripts/mongo-init.sh
```

## Проверка кеша

- Первый запрос: `time curl http://localhost:8080/helloDoc/users` → ~1с
- Повторный запрос: `time curl http://localhost:8080/helloDoc/users` → <100мс
- Статус кеша: `curl http://localhost:8080` → `"cache_enabled": true`