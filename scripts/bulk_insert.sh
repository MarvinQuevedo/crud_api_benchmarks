#!/usr/bin/env bash
set -euo pipefail

# Insert many items via POST /api/items.
# Requires: curl, optional jq for nicer summary.
#
#   ./scripts/bulk_insert.sh
#   BASE_URL=http://127.0.0.1:18080 COUNT=5000 PARALLEL=32 ./scripts/bulk_insert.sh
#
# Optional: PAYLOAD_FILE — one JSON POST body per line (e.g. fortran/build/gen_bulk_payloads).
# When set and the file exists, COUNT is capped to the number of lines.

BASE_URL="${BASE_URL:-http://127.0.0.1:18080}"
COUNT="${COUNT:-2000}"
PARALLEL="${PARALLEL:-16}"
PREFIX="${PREFIX:-bulk}"

USE_PAYLOAD_FILE=0
if [[ -n "${PAYLOAD_FILE:-}" && -f "${PAYLOAD_FILE}" ]]; then
  PAYLOAD_LINES="$(wc -l < "${PAYLOAD_FILE}" | tr -d ' ')"
  if [[ "${PAYLOAD_LINES}" -ge 1 ]]; then
    USE_PAYLOAD_FILE=1
    if [[ "${COUNT}" -gt "${PAYLOAD_LINES}" ]]; then
      echo "WARN: COUNT=${COUNT} > ${PAYLOAD_LINES} lines in PAYLOAD_FILE; using ${PAYLOAD_LINES}" >&2
      COUNT="${PAYLOAD_LINES}"
    fi
  fi
fi

export BASE_URL COUNT

if [[ "${USE_PAYLOAD_FILE}" -eq 1 ]]; then
  export PAYLOAD_FILE
  insert_one() {
    local i="$1"
    local payload code
    payload=$(sed -n "${i}p" "${PAYLOAD_FILE}")
    code=$(curl -sS -o /dev/null -w "%{http_code}" \
      -X POST "${BASE_URL}/api/items" \
      -H "Content-Type: application/json" \
      -d "${payload}")
    if [[ "${VERBOSE:-0}" == "1" ]]; then
      echo "$code"
    fi
    if [[ "$code" != "201" ]]; then
      echo "WARN: expected 201, got ${code} for i=${i}" >&2
    fi
  }
else
  export PREFIX
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
fi

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
