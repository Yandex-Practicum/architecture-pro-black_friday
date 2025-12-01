# Используем базовый образ, который содержит redis-cli
FROM redis:latest

# Копируем скрипт инициализации в контейнер
COPY ./scripts/init-redis-cluster.sh /usr/local/bin/init-redis-cluster.sh
RUN chmod +x /usr/local/bin/init-redis-cluster.sh

# Точка входа: запускаем скрипт
CMD ["/usr/local/bin/init-redis-cluster.sh"]