#!/bin/bash

echo "🧐 Checking data distribution..."

# 1. Спрашиваем Роутер (общий вид)
TOTAL=$(docker compose exec -T mongos mongosh --port 27020 somedb --quiet --eval 'db.helloDoc.countDocuments()')
echo "🌍 Total in Mongos: $TOTAL"

# 2. Спрашиваем Shard 1 напрямую (через первую ноду реплики)
C1=$(docker compose exec -T shard1-1 mongosh --port 27018 somedb --quiet --eval 'db.helloDoc.countDocuments()')
echo "📦 Shard 1 count:  $C1"

# 3. Спрашиваем Shard 2 напрямую (через первую ноду реплики)
C2=$(docker compose exec -T shard2-1 mongosh --port 27019 somedb --quiet --eval 'db.helloDoc.countDocuments()')
echo "📦 Shard 2 count:  $C2"

echo "---------------------------------"
if [[ "$TOTAL" =~ ^[0-9]+$ ]] && [ "$TOTAL" -eq 1000 ] && [ "$C1" -gt 0 ] && [ "$C2" -gt 0 ]; then
  echo "✅ SUCCESS: Data is sharded!"
else
  echo "⚠️  WARNING: Something looks uneven or empty. Raw values: T='$TOTAL', C1='$C1', C2='$C2'"
fi