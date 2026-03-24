#!/usr/bin/env bash
set -euo pipefail

# Insert many items via POST /api/items.
# Requires: curl, optional jq for nicer summary.
#
#   ./scripts/bulk_insert.sh
#   BASE_URL=http://127.0.0.1:18080 COUNT=5000 PARALLEL=32 ./scripts/bulk_insert.sh

BASE_URL="${BASE_URL:-http://127.0.0.1:18080}"
COUNT="${COUNT:-2000}"
PARALLEL="${PARALLEL:-16}"
PREFIX="${PREFIX:-bulk}"

export BASE_URL COUNT PREFIX

insert_one() {
  local i="$1"
  local payload code
  payload=$(printf '{"name":"%s-%d","description":"auto bulk","quantity":%d}' "$PREFIX" "$i" "$((i % 200))")
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "${BASE_URL}/api/items" \
    -H "Content-Type: application/json" \
    -d "$payload")
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    echo "$code"
  fi
  if [[ "$code" != "201" ]]; then
    echo "WARN: expected 201, got ${code} for i=${i}" >&2
  fi
}

export -f insert_one

echo "Inserting ${COUNT} items to ${BASE_URL} (parallel=${PARALLEL})..."
start=$(date +%s)
seq 1 "$COUNT" | xargs -n 1 -P "$PARALLEL" bash -c 'insert_one "$@"' _
end=$(date +%s)
echo "Done in $((end - start))s wall time."

if command -v jq >/dev/null 2>&1; then
  total=$(curl -sS "${BASE_URL}/api/items?limit=1" | jq '.total')
  echo "API reports total items: ${total}"
fi
