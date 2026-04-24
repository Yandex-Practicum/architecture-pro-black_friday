# pymongo-api

## Схемы

### Для задания 1

<details>

![Схема](./mongo-sharding/schema1.png)

</details>

### Для задания 3

<details>

![Схема](./mongo-sharding-repl/schema2.png)

</details>

### Для задания 4

<details>

![Схема](./sharding-repl-cache/schema3.png)

</details>

### Для задания 5

<details>

![Схема](./docs/scale.png)

</details>

### Для задания 6

<details>

![Схема](./docs/cdn.png)

</details>

### Финальная схема

<details>

![Схема](./docs/cdn.png)

</details>

или по ссылке
[Схема drawio](./docs/final-schema.drawio)

## Как запустить

Перейти в папку mongo-sharding-repl

```shell
cd mongo-sharding-repl
```

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

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
