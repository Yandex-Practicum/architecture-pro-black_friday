#!/bin/bash

set -euo pipefail

CONSUL_URL="${CONSUL_URL:-http://localhost:8500}"
APISIX_ADMIN_URL="${APISIX_ADMIN_URL:-http://localhost:9180}"
APISIX_ADMIN_KEY="${APISIX_ADMIN_KEY:-edd1c9f034335f136f87ad84b625c8f1}"
SERVICE_NAME="${SERVICE_NAME:-pymongo-api}"
API_PORT="${API_PORT:-8080}"
ROUTE_ID="${ROUTE_ID:-pymongo-api-route}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
MIN_DOCUMENTS="${MIN_DOCUMENTS:-1000}"

API_CONTAINERS=(pymongo_api_1 pymongo_api_2)

wait_for_http() {
  local url="$1"
  local name="$2"

  echo "Waiting for ${name}..."
  for _ in {1..60}; do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo "${name} is ready."
      return 0
    fi
    sleep 1
  done

  echo "$name did not become available at $url in time" >&2
  return 1
}

wait_for_apisix() {
  echo "Waiting for APISIX Admin API..."
  for _ in {1..60}; do
    if curl -sf "${APISIX_ADMIN_URL}/apisix/admin/routes" \
      -H "X-API-KEY: ${APISIX_ADMIN_KEY}" >/dev/null 2>&1; then
      echo "APISIX Admin API is ready."
      return 0
    fi
    sleep 1
  done

  echo "APISIX Admin API did not become available at ${APISIX_ADMIN_URL} in time" >&2
  return 1
}

wait_for_mongodb() {
  echo "Checking MongoDB sharding (expect >= ${MIN_DOCUMENTS} docs in helloDoc)..."
  for _ in {1..30}; do
    count=$(docker compose exec -T mongos-router mongosh --port 27020 --quiet --eval \
      'try { db.getSiblingDB("somedb").helloDoc.countDocuments() } catch (e) { 0 }' 2>/dev/null || echo 0)
    count="${count//$'\r'/}"
    count="${count//$'\n'/}"

    if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= MIN_DOCUMENTS )); then
      echo "MongoDB is ready (${count} documents in helloDoc)."
      return 0
    fi
    sleep 2
  done

  echo "MongoDB is not initialized." >&2
  echo "Run './scripts/init-sharding.sh' first and wait until it finishes." >&2
  echo "If init was interrupted: docker compose down -v && docker compose up -d --build && ./scripts/init-sharding.sh" >&2
  return 1
}

wait_for_api_container() {
  local container="$1"

  echo "Waiting for ${container} (GET ${HEALTH_PATH})..."
  for _ in {1..30}; do
    if docker compose exec -T "$container" python -c \
      "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${API_PORT}${HEALTH_PATH}', timeout=3)" \
      >/dev/null 2>&1; then
      echo "${container} is ready."
      return 0
    fi
    sleep 1
  done

  echo "$container did not respond on port ${API_PORT} in time" >&2
  return 1
}

get_container_ip() {
  local container_name="$1"
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name"
}

register_service() {
  local service_id="$1"
  local address="$2"

  curl -sf "${CONSUL_URL}/v1/agent/service/register" -X PUT \
    -H "Content-Type: application/json" \
    -d "{
      \"ID\": \"${service_id}\",
      \"Name\": \"${SERVICE_NAME}\",
      \"Address\": \"${address}\",
      \"Port\": ${API_PORT},
      \"Tags\": [\"fastapi\", \"somedb\", \"helloDoc\"],
      \"Weights\": {
        \"Passing\": 10,
        \"Warning\": 1
      }
    }"
}

wait_for_mongodb
wait_for_http "${CONSUL_URL}/v1/status/leader" "Consul"
wait_for_apisix

for container in "${API_CONTAINERS[@]}"; do
  wait_for_api_container "$container"

  ip="$(get_container_ip "$container")"
  if [[ -z "$ip" ]]; then
    echo "Container $container has no IP address" >&2
    exit 1
  fi

  register_service "$container" "$ip"
  echo "Registered $container at ${ip}:${API_PORT} as ${SERVICE_NAME}"
done

echo "Configuring APISIX route ${ROUTE_ID}..."
curl -sf "${APISIX_ADMIN_URL}/apisix/admin/routes/${ROUTE_ID}" \
  -H "X-API-KEY: ${APISIX_ADMIN_KEY}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${ROUTE_ID}\",
    \"uri\": \"/*\",
    \"upstream\": {
      \"service_name\": \"${SERVICE_NAME}\",
      \"type\": \"roundrobin\",
      \"discovery_type\": \"consul\"
    }
  }"

echo "Gateway configured. Check: curl http://localhost:9080/helloDoc/count"
