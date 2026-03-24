#!/usr/bin/env bash
set -euo pipefail

# Build everything (C++, Rust, asm check) then run integration tests from repo root.
#
#   ./scripts/build_and_test.sh              # default: compare C++ + ASM (if built) + Rust
#   ./scripts/build_and_test.sh --cpp-rust   # only C++ vs Rust (faster, no asm row)
#   ./scripts/build_and_test.sh --quick      # smaller COUNT/PARALLEL (faster)
#   ./scripts/build_and_test.sh --smoke      # only build + curl /health on C++ binary
#
# Env (optional): PORT, COUNT, PARALLEL — passed through to compare scripts unless --quick.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="compare-all"
QUICK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpp-rust)
      MODE="compare"
      shift
      ;;
    --all)
      MODE="compare-all"
      shift
      ;;
    --quick)
      QUICK=1
      shift
      ;;
    --smoke)
      MODE="smoke"
      shift
      ;;
    -h | --help)
      cat <<'EOF'
Usage: ./scripts/build_and_test.sh [options]

  (default)   make build-all, then compare_all: C++ + ASM (if api_crud_asm exists) + Rust
  --all       same as default (kept for clarity)
  --cpp-rust  only C++ vs Rust (compare_load — no assembly row in the report)
  --quick     COUNT=500 PARALLEL=16 (override with env COUNT / PARALLEL)
  --smoke     build only, then curl /health and /api/items on C++ server

Env: PORT, COUNT, PARALLEL — forwarded to compare scripts (except --quick defaults).

ASM: built only on Apple arm64 with native arm64 CMake (not Rosetta x86_64). If the
binary is missing, compare_all still runs C++ and Rust and prints a skip notice.

From repo root you can also run: make test
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 2
      ;;
  esac
done

if [[ "$QUICK" -eq 1 ]]; then
  export COUNT="${COUNT:-500}"
  export PARALLEL="${PARALLEL:-16}"
fi

kill_port() {
  lsof -ti "tcp:${PORT:-18080}" | xargs kill -9 2>/dev/null || true
}

wait_health() {
  local port="${1:-18080}"
  local n=0
  while ! curl -sS --max-time 1 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; do
    n=$((n + 1))
    if [[ "$n" -gt 60 ]]; then
      echo "Timeout waiting for http://127.0.0.1:${port}/health" >&2
      return 1
    fi
    sleep 0.2
  done
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 1/2  Build (make build-all)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
make build-all

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 2/2  Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$MODE" == "smoke" ]]; then
  PORT="${PORT:-18080}"
  kill_port
  CPP_BIN="${ROOT}/cpp/build/api_crud_server"
  if [[ ! -x "$CPP_BIN" ]]; then
    echo "Missing $CPP_BIN" >&2
    exit 1
  fi
  (
    cd "${ROOT}/cpp"
    PORT="${PORT}" DB_PATH="data/smoke_test.db" exec "${CPP_BIN}"
  ) &
  PID=$!
  trap 'kill_port; kill "${PID}" 2>/dev/null || true' EXIT
  wait_health "${PORT}"
  echo "GET /health"
  curl -sS "http://127.0.0.1:${PORT}/health"
  echo ""
  echo "GET /api/items?limit=2"
  curl -sS "http://127.0.0.1:${PORT}/api/items?limit=2"
  echo ""
  kill "${PID}" 2>/dev/null || true
  wait "${PID}" 2>/dev/null || true
  kill_port
  trap - EXIT
  echo ""
  echo "Smoke OK."
  exit 0
fi

chmod +x "${ROOT}/scripts/compare_load.sh" "${ROOT}/scripts/compare_all.sh"

export SKIP_BUILD=1

if [[ "$MODE" == "compare" ]]; then
  "${ROOT}/scripts/compare_load.sh"
else
  "${ROOT}/scripts/compare_all.sh"
fi
