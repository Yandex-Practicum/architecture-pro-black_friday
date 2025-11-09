# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose --project-directory ./sharding-repl-cache/ up -d 
```

Заполняем mongodb данными

```shell
./sharding-repl-cache/init-sharding.sh
```

или

```shell
./sharding-repl-cache/init-sharding.ps1
```

*Примечание*. Тестирование bash-скриптов не проводилось, поскольку домашняя машина работает под Windows. Тестировались
только PowerShell-скрипты.

## Как проверить

### Наполнение данными и статус кэша

Наполнение данными и статус кэша можно проверить скриптами

```shell
./sharding-repl-cache/sharding-check.sh
```

или

```shell
./sharding-repl-cache/sharding-check.ps1
```

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