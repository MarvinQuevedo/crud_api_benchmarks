#!/usr/bin/env bash
set -euo pipefail

# Same bulk_insert load test against three servers: C++ main, ASM entry + C++ libs, Rust.
# Usage: ./scripts/compare_all.sh
#        COUNT=8000 PARALLEL=32 PORT=18080 ./scripts/compare_all.sh
#        SKIP_BUILD=1 ./scripts/compare_all.sh   # after a prior full build

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
  echo "Building C++ (cmake, includes api_crud_asm when configure sees arm64)…"
  make -C "${ROOT}/cpp" build

  chmod +x "${ROOT}/scripts/build_asm_arm64.sh"
  "${ROOT}/scripts/build_asm_arm64.sh"

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
  exit 1
fi

CPP_SRV="${ROOT}/cpp/build/api_crud_server"
ASM_SRV=""
for _asm in "${ROOT}/cpp/build/api_crud_asm" "${ROOT}/cpp/build-arm64/api_crud_asm"; do
  if [[ -x "$_asm" ]]; then
    ASM_SRV="$_asm"
    break
  fi
done
T_CPP=""
T_ASM=""
T_RUST=""
RAN_ASM=0

# shellcheck disable=SC1090
source "${ROOT}/scripts/fortran_bulk_payload.sh"
fortran_prepare_bulk_payload_file

kill_port

# --- 1) C++ (classic main) ---
echo ""
echo "--- C++ (api_crud_server) ---"
rm -f "${ROOT}/cpp/data/compare_pure.db"
(
  cd "${ROOT}/cpp"
  PORT="${PORT}" DB_PATH="data/compare_pure.db" exec "${CPP_SRV}"
) &
PID=$!
trap 'kill_port; kill "${PID}" 2>/dev/null || true' EXIT
wait_http
run_bulk "C++ api_crud_server" T_CPP
kill "${PID}" 2>/dev/null || true
wait "${PID}" 2>/dev/null || true
kill_port

# --- 2) ASM entry + same C++ stack ---
echo ""
echo "--- ASM entry (api_crud_asm) ---"
if [[ -n "${ASM_SRV}" ]]; then
  rm -f "${ROOT}/cpp/data/compare_asm.db"
  (
    cd "${ROOT}/cpp"
    PORT="${PORT}" DB_PATH="data/compare_asm.db" exec "${ASM_SRV}"
  ) &
  PID=$!
  trap 'kill_port; kill "${PID}" 2>/dev/null || true' EXIT
  wait_http
  run_bulk "ASM + C++ libs" T_ASM
  RAN_ASM=1
  kill "${PID}" 2>/dev/null || true
  wait "${PID}" 2>/dev/null || true
  kill_port
else
  echo "Skipped: no api_crud_asm in cpp/build/ or cpp/build-arm64/ (Apple Silicon + arm64 CMake only)."
  echo "  Tip: on M1/M2/M3 under Rosetta this repo runs scripts/build_asm_arm64.sh after the main build;"
  echo "  ensure /opt/homebrew OpenSSL if linking fails, or open a native arm64 terminal and use cpp/build only."
fi

# --- 3) Rust ---
echo ""
echo "--- Rust ---"
rm -f "${ROOT}/rust/data/compare_rust.db"
(
  cd "${ROOT}/rust"
  PORT="${PORT}" DB_PATH="data/compare_rust.db" exec "${RUST_BIN}"
) &
PID=$!
trap 'kill_port; kill "${PID}" 2>/dev/null || true' EXIT
wait_http
run_bulk "Rust" T_RUST
kill "${PID}" 2>/dev/null || true
wait "${PID}" 2>/dev/null || true
kill_port

trap - EXIT
echo ""
echo "Done. SQLite files:"
ls -la "${ROOT}/cpp/data/compare_pure.db" "${ROOT}/cpp/data/compare_asm.db" "${ROOT}/rust/data/compare_rust.db" 2>/dev/null || true

REPORT_ARGS=( "C++:${T_CPP}:${CPP_SRV}" )
if [[ "${RAN_ASM}" -eq 1 ]]; then
  REPORT_ARGS+=( "ASM + C++ libs:${T_ASM}:${ASM_SRV}" )
fi
REPORT_ARGS+=( "Rust:${T_RUST}:${RUST_BIN}" )

GEN_BIN="${ROOT}/fortran/build/gen_bulk_payloads"
if [[ -x "$GEN_BIN" ]]; then
  REPORT_ARGS+=( "Fortran (payload NDJSON):${FORT_PAYLOAD_GEN_SEC}:${GEN_BIN}" )
else
  REPORT_ARGS+=( "Fortran (not built)::" )
fi

REPORT_DIR="${ROOT}/benchmarks/reports"
mkdir -p "${REPORT_DIR}"
REPORT_MD="${REPORT_DIR}/compare_all_$(date +%Y%m%d_%H%M%S).md"
NOTE="COUNT=${COUNT} PARALLEL=${PARALLEL} PORT=${PORT}"$'\n'"Fortran row: time = gen_bulk_payloads only (not an HTTP server); excluded from fastest/slowest bulk_insert ranking."

echo ""
python3 "${ROOT}/scripts/emit_compare_report.py" \
  --write-md "${REPORT_MD}" \
  --title "compare_all.sh — C++, ASM (if run), Rust, Fortran" \
  --note "${NOTE}" \
  "${REPORT_ARGS[@]}"
echo "Saved: ${REPORT_MD}"
