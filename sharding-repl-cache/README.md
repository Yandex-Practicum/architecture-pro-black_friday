Из папки `mongo-sharding` запускаем 

Удаляю контейнеры во избежание конфликтов
```
docker stop $(docker ps -aq) && docker rm $(docker ps -aq) && docker compose down -v  && docker compose up -d --build
```

Далее надо настроить сервер с конфигурацией, шарды и роутер для монги. Также создаем кластер редиса. Запускаем sh скрипт
```
./scripts/mongo-redis-init.sh
``` 

Можно проверить командой 
```
curl -v localhost:8080/helloDoc/users
```