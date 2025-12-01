#!/bin/sh
set -eu

REDIS_NODES="redis01:6379 redis02:6379 redis03:6379 redis04:6379 redis05:6379 redis06:6379"

echo "🟡 Ожидание готовности всех узлов Redis..."

wait_for_redis_nodes() {
    for host_port in $REDIS_NODES; do
        host=${host_port%:*}
        port=${host_port#*:}
        until redis-cli -h "$host" -p "$port" ping 2>/dev/null | grep -q PONG; do
            printf '.'
            sleep 1
        done
        echo "🟢 Узел Redis $host_port доступен."
    done
}

wait_for_redis_nodes

echo ""
echo "==============================================="
echo "   Инициализация кластера Redis (2 мастера, 2 реплики) "
echo "==============================================="

# Если кластер уже инициализирован, выходим успешно
if redis-cli -h redis01 -p 6379 cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
  echo "✅ Кластер Redis уже инициализирован (cluster_state:ok)."
  exit 0
fi

# Создание кластера (2 мастера, 2 реплики)
echo "yes" | redis-cli --cluster create $REDIS_NODES --cluster-replicas 1

# Ожидание статуса OK
echo "⏳ Ожидаем, пока кластер перейдёт в состояние ok..."
ATTEMPTS=60
while [ $ATTEMPTS -gt 0 ]; do
  if redis-cli -h redis01 -p 6379 cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
    echo "🟢 Кластер готов: cluster_state:ok"
    exit 0
  fi
  ATTEMPTS=$((ATTEMPTS-1))
  sleep 1
done

echo "❌ Не удалось дождаться готовности кластера Redis"
exit 1