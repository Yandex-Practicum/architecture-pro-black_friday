# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Запустите скрипт, чтобы настроить шардирование и заполнить mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

### Проверить, что api работает

Откройте в браузере http://localhost:8080

### Проверить, что шардирование работает

Можно посмотреть результаты в выводе скрипта, либо выполнить команды вручную (ниже).

Выполните команду, за какое количество времени выполнится первый и второй запрос:

```
echo "\n\n\nFirst request:"
curl -w "@curl-format.txt" -o /dev/null -s "http://localhost:8080/helloDoc/users"

echo "\n\n\nSecond request:"
curl -w "@curl-format.txt" -o /dev/null -s "http://localhost:8080/helloDoc/users"
```
