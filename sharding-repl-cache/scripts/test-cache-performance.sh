#!/bin/bash

echo "=========================================="
echo "Testing Cache Performance"
echo "=========================================="
echo ""

API_URL="http://localhost:8082"
ENDPOINT="/helloDoc/users"

# Check if the API is ready
echo "Checking if API is ready..."
for i in {1..30}; do
  if curl -s -f "${API_URL}" > /dev/null; then
    echo "API is ready!"
    break
  fi
  echo "Waiting for API... ($i/30)"
  sleep 2
done

echo ""
echo "=========================================="
echo "Test 1: First request (without cache)"
echo "=========================================="

echo "Making first request to ${API_URL}${ENDPOINT}..."
RESPONSE_TIME_1=$(curl -o /dev/null -s -w '%{time_total}\n' "${API_URL}${ENDPOINT}")
echo "Response time: ${RESPONSE_TIME_1} seconds"

# Convert to milliseconds for display
RESPONSE_TIME_1_MS=$(echo "$RESPONSE_TIME_1 * 1000" | bc)
echo "Response time: ${RESPONSE_TIME_1_MS} ms"

echo ""
echo "Waiting 2 seconds before next request..."
sleep 2

echo ""
echo "=========================================="
echo "Test 2: Second request (from cache)"
echo "=========================================="

echo "Making second request to ${API_URL}${ENDPOINT}..."
RESPONSE_TIME_2=$(curl -o /dev/null -s -w '%{time_total}\n' "${API_URL}${ENDPOINT}")
echo "Response time: ${RESPONSE_TIME_2} seconds"

# Convert to milliseconds for display
RESPONSE_TIME_2_MS=$(echo "$RESPONSE_TIME_2 * 1000" | bc)
echo "Response time: ${RESPONSE_TIME_2_MS} ms"

echo ""
echo "=========================================="
echo "Test 3: Third request (from cache)"
echo "=========================================="

echo "Making third request to ${API_URL}${ENDPOINT}..."
RESPONSE_TIME_3=$(curl -o /dev/null -s -w '%{time_total}\n' "${API_URL}${ENDPOINT}")
echo "Response time: ${RESPONSE_TIME_3} seconds"

# Convert to milliseconds for display
RESPONSE_TIME_3_MS=$(echo "$RESPONSE_TIME_3 * 1000" | bc)
echo "Response time: ${RESPONSE_TIME_3_MS} ms"

echo ""
echo "=========================================="
echo "Test 4: Fourth request (from cache)"
echo "=========================================="

echo "Making fourth request to ${API_URL}${ENDPOINT}..."
RESPONSE_TIME_4=$(curl -o /dev/null -s -w '%{time_total}\n' "${API_URL}${ENDPOINT}")
echo "Response time: ${RESPONSE_TIME_4} seconds"

# Convert to milliseconds for display
RESPONSE_TIME_4_MS=$(echo "$RESPONSE_TIME_4 * 1000" | bc)
echo "Response time: ${RESPONSE_TIME_4_MS} ms"

echo ""
echo "=========================================="
echo "Performance Summary"
echo "=========================================="
echo "Request 1 (no cache):    ${RESPONSE_TIME_1_MS} ms"
echo "Request 2 (cached):      ${RESPONSE_TIME_2_MS} ms"
echo "Request 3 (cached):      ${RESPONSE_TIME_3_MS} ms"
echo "Request 4 (cached):      ${RESPONSE_TIME_4_MS} ms"
echo ""

# Calculate speedup
SPEEDUP=$(echo "scale=2; $RESPONSE_TIME_1 / $RESPONSE_TIME_2" | bc)
echo "Cache speedup: ${SPEEDUP}x faster"

echo ""
echo "Checking Redis cache status..."
docker compose exec -T redis redis-cli INFO stats | grep keyspace

echo ""
echo "=========================================="
echo "Cache test completed!"
echo "=========================================="
