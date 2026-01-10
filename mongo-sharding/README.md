# Стенд Black Friday - вариант 1

## Требования

* `docker-compose-v2` - обёртка вокруг docker, повторяющая функциональность
  `docker-compose` и добавляющая подкоманду `compose`.
* `curl`
* `jq`

## Запуск

```bash
docker compose up -d && sleep 15
```

Все операции по построению кластера автоматизированы в скрипте
`scripts/mongodb-bootstrap.sh`. Его руками выполнять не надо, он запускается
автоматически в стеке специальным контейнером `mongodb-bootstrap`.

Команда `sleep 15` добавлена для ожидания, когда весь кластер точно построится.

## Просмотр логов

```bash
docker compose logs -f
```

## Заливка данных

Для заливки данных в коллекцию `helloDoc` необходимо воспользоваться скриптом
`scrtips/mongodb-insert-data.sh`:

```bash
cd scripts
./mongodb-insert-data.sh
```


## Проверка работы

```bash
curl -s -X GET http://localhost:8080/helloDoc/count | jq .
```

Должно вывести следующее:

```json
{
  "status": "OK",
  "mongo_db": "somedb",
  "items_count": 1000
}
```

```bash
curl -s -X GET http://localhost:8080/helloDoc/users | jq .
```

Должно вывести следующее:

```json
{
  "users": [
    {
      "id": "6962277c2f8b9c4b679dc29d",
      "age": 0,
      "name": "ly0"
    },
    {
      "id": "6962277c2f8b9c4b679dc29e",
      "age": 1,
      "name": "ly1"
    },
    {
      "id": "6962277c2f8b9c4b679dc29f",
      "age": 2,
      "name": "ly2"
    },
    {
      "id": "6962277c2f8b9c4b679dc2a0",
      "age": 3,
      "name": "ly3"
    },
    {
      "id": "6962277c2f8b9c4b679dc2a1",
      "age": 4,
      "name": "ly4"
    },
    {
      "id": "6962277c2f8b9c4b679dc2a2",
      "age": 5,
      "name": "ly5"
    },
    ...
  ]
}
```

## Очистка стенда для последующего перезапуска с нуля

Если нужно перезапустить стенд полностью, с нуля, то необходимо не только
остановить контейнеры, но и очистить созданные для стенда тома с данными.

1. Остановим стенд:
   ```bash
   docker compose down
   ```
2. Удалим анонимные тома с данными (создаются для каждого контейнера в отдельности):
   ```bash
   docker volume prune -f
   ```
3. Удалим тома стенда для MongoDB:
   ```bash
   for vol in $(docker volume ls --filter 'dangling=true' --filter 'name=mongo' -q); do
       docker volume rm $vol;
   done;
   ```

Если просто остановить стенд, а потом заново запустить его, то подтянутся
данные из томов и кластер продолжит свою работу.
