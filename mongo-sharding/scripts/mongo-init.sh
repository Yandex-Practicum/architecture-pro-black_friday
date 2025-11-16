#!/bin/bash

###
# Инициализируем бд и заполняем данными
# Этот скрипт можно запускать как внутри Docker контейнера, так и с хоста
###

# Проверяем, запущен ли скрипт внутри контейнера
if [ -f /.dockerenv ]; then
  # Запуск внутри контейнера - используем прямое подключение
  MONGOSH_CMD="mongosh --host mongos-router"
else
  # Запуск с хоста - используем docker compose exec
  MONGOSH_CMD="docker compose exec -T mongos-router mongosh"
fi

$MONGOSH_CMD <<EOF
use somedb
// Создаем коллекцию helloDoc если её нет
if (db.getCollectionNames().indexOf("helloDoc") === -1) {
  db.createCollection("helloDoc");
}

// Заполняем коллекцию данными (≥ 1000 документов)
for(var i = 0; i < 1000; i++) { 
  db.helloDoc.insertOne({age: i, name: "user" + i, created: new Date()}); 
}

// Выводим статистику
print("Total documents in helloDoc: " + db.helloDoc.countDocuments());
EOF

