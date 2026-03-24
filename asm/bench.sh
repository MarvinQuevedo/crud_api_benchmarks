#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPP_DIR="${SCRIPT_DIR}/../cpp"
cd "$CPP_DIR"

echo "Building (api_crud_asm + deps)..."
cmake --build build -j 8 --target api_crud_asm 2>/dev/null || cmake --build build -j 8
chmod +x "${SCRIPT_DIR}/../scripts/build_asm_arm64.sh"
"${SCRIPT_DIR}/../scripts/build_asm_arm64.sh"

if [[ -x ./build/api_crud_asm ]]; then
  BIN="${BIN:-./build/api_crud_asm}"
elif [[ -x ./build-arm64/api_crud_asm ]]; then
  BIN="${BIN:-./build-arm64/api_crud_asm}"
else
  echo "Missing api_crud_asm in build/ or build-arm64/. See asm/README.md." >&2
  exit 1
fi

N="${N:-10000}"
C="${C:-100}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-18080}"
PATHS="${PATHS:-/health /api/items?limit=50 /api/items?limit=1&offset=0}"
OUTDIR="${OUTDIR:-$SCRIPT_DIR/../benchmarks}"

mkdir -p "$OUTDIR"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="${OUTDIR}/bench_asm_${TS}.txt"
SERVER_LOG="${OUTDIR}/server_asm_${TS}.log"

echo "Starting ASM entry + C++ stack on ${HOST}:${PORT}..."
PORT="$PORT" "$BIN" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
sleep 1

{
  echo "=== ASM entry benchmark ${TS} ==="
  echo "Binary: $CPP_DIR/$BIN"
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
