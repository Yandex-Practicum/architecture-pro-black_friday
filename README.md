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

## Как проверить

Чтобы проверить задания, надо следовать последним пунктам инструкций (то, что после запуска скрипта `./scripts/mongo-init.sh`) каждой папочки: mongo-sharding, mongo-sharding-repl, sharding-repl-cache. Но запустить можно один раз из папки `sharding-repl-cache` - там финальная версия.