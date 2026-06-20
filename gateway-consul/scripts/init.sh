#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Step 1/2: MongoDB sharding ==="
"${SCRIPT_DIR}/init-sharding.sh"

echo ""
echo "=== Step 2/2: APISIX + Consul ==="
"${SCRIPT_DIR}/init-gateway.sh"

echo ""
echo "Done. Open http://localhost:9080/ or run: curl http://localhost:9080/helloDoc/count"
