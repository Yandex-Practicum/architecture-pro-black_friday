# Mongo Sharding (With Replica Sets and Caching)

Порядок запуска и проверки работы шардирования в MongoDB с репликацией и слоем кэширования:

1. Перейти в директорию стенда:
   ```bash
   cd sharding-repl-cache
   ```

2. Запустить контейнеры:
   ```bash
   docker compose up -d
   ```

3. Выполнить скрипт инициализации:
   ```bash
   sh init.sh
   ```

4. Выполнить проверку распределения данных по шардам:
   ```bash
   sh check.sh
   ```

5. Задания с 7 по 10 в файле `./RESULT.md`