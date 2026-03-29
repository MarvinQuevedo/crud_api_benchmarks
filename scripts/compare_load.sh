#!/usr/bin/env bash
set -euo pipefail

# Build both servers and time bulk_insert against each (same COUNT/PARALLEL/PORT).
# Usage from repo root (api_test):
#   ./scripts/compare_load.sh
#   COUNT=10000 PARALLEL=32 PORT=18080 ./scripts/compare_load.sh
#   SKIP_BUILD=1 ./scripts/compare_load.sh   # ya compilado (usa build_and_test.sh)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-18080}"
COUNT="${COUNT:-5000}"
PARALLEL="${PARALLEL:-32}"

rust_binary() {
  local dir
  dir=$(cd "${ROOT}/rust" && cargo metadata --format-version 1 --no-deps 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['target_directory'])")
  echo "${dir}/release/api_crud_rust"
}

kill_port() {
  lsof -ti "tcp:${PORT}" | xargs kill -9 2>/dev/null || true
}

wait_http() {
  local n=0
  while ! curl -sS --max-time 1 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; do
    n=$((n + 1))
    if [[ "$n" -gt 60 ]]; then
      echo "Timeout waiting for http://127.0.0.1:${PORT}/health" >&2
      return 1
    fi
    sleep 0.2
  done
}

run_bulk() {
  local label="$1"
  local outvar="$2"
  echo ""
  echo "=== ${label} (COUNT=${COUNT}, PARALLEL=${PARALLEL}) ==="
  local start end elapsed
  start=$(python3 -c 'import time; print(time.time())')
  BASE_URL="http://127.0.0.1:${PORT}" COUNT="${COUNT}" PARALLEL="${PARALLEL}" \
    "${ROOT}/scripts/bulk_insert.sh"
  end=$(python3 -c 'import time; print(time.time())')
  elapsed=$(python3 -c "print(round(float('${end}') - float('${start}'), 3))")
  echo "Wall time ${label}: ${elapsed}s"
  eval "${outvar}=${elapsed}"
}

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building C++ (cmake)…"
  make -C "${ROOT}/cpp" build

  echo "Building Rust (release)…"
  cargo build --release --manifest-path "${ROOT}/rust/Cargo.toml"

  echo "Building Fortran tools (optional)…"
  make -C "${ROOT}/fortran" build-optional
else
  echo "SKIP_BUILD=1 — assuming binaries are already built."
fi

RUST_BIN="$(rust_binary)"
if [[ ! -x "$RUST_BIN" ]]; then
  echo "Rust binary not found at: $RUST_BIN" >&2
  echo "Run: cd ${ROOT}/rust && cargo build --release" >&2
  exit 1
fi

CPP_SRV="${ROOT}/cpp/build/api_crud_server"
T_CPP=""
T_RUST=""

# shellcheck disable=SC1090
source "${ROOT}/scripts/fortran_bulk_payload.sh"
fortran_prepare_bulk_payload_file

kill_port

echo ""
echo "--- C++ ---"
rm -f "${ROOT}/cpp/data/compare_load.db"
(
  cd "${ROOT}/cpp"
  PORT="${PORT}" DB_PATH="data/compare_load.db" ./build/api_crud_server
) &
CPP_PID=$!
trap 'kill_port; kill "${CPP_PID}" 2>/dev/null || true' EXIT
wait_http
run_bulk "C++ bulk_insert" T_CPP
kill "${CPP_PID}" 2>/dev/null || true
wait "${CPP_PID}" 2>/dev/null || true
kill_port

echo ""
echo "--- Rust ---"
rm -f "${ROOT}/rust/data/compare_load.db"
(
  cd "${ROOT}/rust"
  PORT="${PORT}" DB_PATH="data/compare_load.db" exec "${RUST_BIN}"
) &
RUST_PID=$!
trap 'kill_port; kill "${RUST_PID}" 2>/dev/null || true' EXIT
wait_http
run_bulk "Rust bulk_insert" T_RUST
kill "${RUST_PID}" 2>/dev/null || true
wait "${RUST_PID}" 2>/dev/null || true
kill_port

trap - EXIT
echo ""
echo "Done. SQLite files:"
ls -la "${ROOT}/cpp/data/compare_load.db" "${ROOT}/rust/data/compare_load.db" 2>/dev/null || true
REPORT_DIR="${ROOT}/benchmarks/reports"
mkdir -p "${REPORT_DIR}"
REPORT_MD="${REPORT_DIR}/compare_load_$(date +%Y%m%d_%H%M%S).md"
NOTE="COUNT=${COUNT} PARALLEL=${PARALLEL} PORT=${PORT}"$'\n'"Fortran row: time = gen_bulk_payloads only (not an HTTP server); excluded from fastest/slowest bulk_insert ranking."

GEN_BIN="${ROOT}/fortran/build/gen_bulk_payloads"
FORT_ROW_EXTRA=()
if [[ -x "$GEN_BIN" ]]; then
  FORT_ROW_EXTRA=( "Fortran (payload NDJSON):${FORT_PAYLOAD_GEN_SEC}:${GEN_BIN}" )
else
  FORT_ROW_EXTRA=( "Fortran (not built)::" )
fi

echo ""
python3 "${ROOT}/scripts/emit_compare_report.py" \
  --write-md "${REPORT_MD}" \
  --title "compare_load.sh — C++ vs Rust (+ Fortran payload tool)" \
  --note "${NOTE}" \
  "C++:${T_CPP}:${CPP_SRV}" \
  "Rust:${T_RUST}:${RUST_BIN}" \
  "${FORT_ROW_EXTRA[@]}"
echo "Saved: ${REPORT_MD}"
echo "Note: Rust uses bundled SQLite (rusqlite); C++ uses the system SQLite on macOS. Throughput is comparable in magnitude, not byte-for-byte identical."
