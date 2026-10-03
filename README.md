# Как поднять стенд sharding-repl-cache

Все команды выполняются из директории `sharding-repl-cache`:

```shell
cd sharding-repl-cache
```

1. Запускаем MongoDB, Redis и приложение:

```shell
docker compose up -d
```

2. Инициализируем репликацию и шардирование, заполняем БД `somedb` данными (1000 документов в коллекции `helloDoc`):

```shell
./scripts/mongo-init.sh
```

3. Открываем приложение: http://localhost:8080
