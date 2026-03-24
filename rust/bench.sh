#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

N="${N:-10000}"
C="${C:-100}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-18080}"
PATHS="${PATHS:-/health /api/items?limit=50 /api/items?limit=1&offset=0}"
OUTDIR="${OUTDIR:-$SCRIPT_DIR/../benchmarks}"

mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="${OUTDIR}/bench_rust_${TS}.txt"
SERVER_LOG="${OUTDIR}/server_rust_${TS}.log"

echo "Building (release)..."
cargo build --release -q

BIN="$(cargo metadata --format-version 1 --no-deps 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['target_directory'])")/release/api_crud_rust"
if [[ ! -x "$BIN" ]]; then
  echo "Binary not found: $BIN" >&2
  exit 1
fi

echo "Starting server on ${HOST}:${PORT}..."
PORT="$PORT" "$BIN" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 1

{
  echo "=== Rust benchmark ${TS} ==="
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
