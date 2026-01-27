## Запуск проекта.
1. Запускаем docker-compose:
```bash
    docker-compose -f sharding-repl-cache.yaml up -d 
```	
В результате у нас запустился кластер mongodb, база заполнена тестовыми данными.

2. Проверим как распределились данные:
```bash
    docker-compose -f mongo-sharding-repl.yaml exec -T mongos1 mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF
```
3. Проверяем состояние реплик:
```bash
for shard in shard1 shard2 shard3; do
  echo "=== $shard ==="
  docker-compose -f mongo-sharding-repl.yaml exec $shard mongosh --port 27018 --quiet --eval "
    try {
      const status = rs.status();
      print('Members:', status.members.length);
      status.members.forEach(m => {
        print('  -', m.name.split(':')[0], 
              '| State:', m.stateStr.padEnd(10),
              '| Health:', m.health === 1 ? '✅' : '❌',
              '| Uptime:', Math.round(m.uptime/60) + 'min');
      });
    } catch(e) {
      print('Error:', e.message);
    }
  "
  echo ""
done
```

4. Удаляем контейнеры:
```bash
  docker-compose -f sharding-repl-cache.yaml down -v
  ```
  
## Исправление ошибок.

1. Ошибка в контейнерах mongos возникала из-за того, что config server не отвечал роутеру. Поскольку ошибка не воспроизвелась на локальной машине, было решено изменить подход:
Теперь создается replica set config серверов состоящий из одного инстанса, а затем добавляются остальные. 
Если ошибка всё равно будет воспроизводиться, нужны будут логи init-config и контейнеров config серверов.
2. Инициализация тестовых данных была перенесена в скрипты init-shards, теперь они заполняются при запуске контейнеров.
3. Команды для проверки были приведены к единому виду.