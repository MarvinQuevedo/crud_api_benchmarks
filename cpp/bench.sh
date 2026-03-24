#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Benchmarks the C++ API (ApacheBench must be installed: ab).
# Usage:
#   ./bench.sh
#   N=20000 C=100 ./bench.sh

N="${N:-10000}"
C="${C:-100}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-18080}"
PATHS="${PATHS:-/health /api/items?limit=50 /api/items?limit=1&offset=0}"
OUTDIR="${OUTDIR:-$SCRIPT_DIR/../benchmarks}"

mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="${OUTDIR}/bench_cpp_${TS}.txt"
SERVER_LOG="${OUTDIR}/server_cpp_${TS}.log"

echo "Building..."
make build >/dev/null

echo "Starting server on ${HOST}:${PORT}..."
PORT="$PORT" ./build/api_crud_server >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 1

{
  echo "=== C++ benchmark ${TS} ==="
  echo "Host: ${HOST}:${PORT}"
  echo "Requests per scenario (N): ${N}"
  echo "Concurrency (C): ${C}"
  echo
} | tee "$LOG"

for p in $PATHS; do
  URL="http://${HOST}:${PORT}${p}"
  echo "--- ${URL} ---" | tee -a "$LOG"
  ab -n "$N" -c "$C" "$URL" | tee -a "$LOG"
  echo | tee -a "$LOG"
done

echo "Saved report: ${LOG}"
