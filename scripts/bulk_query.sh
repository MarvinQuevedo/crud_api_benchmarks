#!/usr/bin/env bash
set -euo pipefail

# Many concurrent GET /api/items (paginated). Optional second phase: GET /api/items/:id.
#
#   ./scripts/bulk_query.sh
#   ROUNDS=800 PAGE_SIZE=100 PARALLEL=32 ./scripts/bulk_query.sh
#   SAMPLE_IDS=20 ./scripts/bulk_query.sh   # needs jq + existing rows

BASE_URL="${BASE_URL:-http://127.0.0.1:18080}"
ROUNDS="${ROUNDS:-400}"
PAGE_SIZE="${PAGE_SIZE:-50}"
PARALLEL="${PARALLEL:-24}"
SAMPLE_IDS="${SAMPLE_IDS:-0}"

export BASE_URL PAGE_SIZE

fetch_page() {
  local i="$1"
  # Vary offset a bit so caches do not hide real DB work entirely.
  local off=$((i * 97 % 100000))
  curl -sS -o /dev/null "${BASE_URL}/api/items?limit=${PAGE_SIZE}&offset=${off}"
}

export -f fetch_page

echo "GET /api/items: ${ROUNDS} requests, limit=${PAGE_SIZE}, parallel=${PARALLEL}"
start=$(date +%s)
seq 1 "$ROUNDS" | xargs -n 1 -P "$PARALLEL" bash -c 'fetch_page "$@"' _
end=$(date +%s)
echo "List phase done in $((end - start))s wall time."

if [[ "$SAMPLE_IDS" -gt 0 ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "SAMPLE_IDS requires jq; skipping."
    exit 0
  fi
  list_url="${BASE_URL}/api/items?limit=${SAMPLE_IDS}"
  ids=$(curl -sS "$list_url" | jq -r '.items[].id' | tr '\n' ' ')
  trimmed=$(echo "$ids" | tr -d '[:space:]')
  if [ -z "$trimmed" ]; then
    echo "No items returned; skipping id GETs."
    exit 0
  fi
  echo "GET by id: ${SAMPLE_IDS} ids, parallel=${PARALLEL}"
  start=$(date +%s)
  # Pipe ids through bash -c (same pattern as list phase) so zsh never parses URLs with `?` or @placeholders.
  export BASE_URL
  echo "$ids" | tr -s ' ' '\n' | grep -v '^$' | xargs -n 1 -P "$PARALLEL" bash -c 'curl -sS -o /dev/null "${BASE_URL}/api/items/${1}"' bash
  end=$(date +%s)
  echo "Id phase done in $((end - start))s wall time."
fi
