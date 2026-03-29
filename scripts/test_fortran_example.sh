#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/fortran/api_example.f90"
GEN_SRC="${ROOT}/fortran/gen_bulk_payloads.f90"

if [[ ! -f "${SRC}" || ! -f "${GEN_SRC}" ]]; then
  echo "Missing Fortran sources under fortran/" >&2
  exit 1
fi

echo "Checking Fortran API example source..."
SRC_CONTENT="$(<"${SRC}")"
[[ "${SRC_CONTENT}" == *"handle_request('GET', '/health'"* ]]
[[ "${SRC_CONTENT}" == *"handle_request('POST', '/api/items'"* ]]
[[ "${SRC_CONTENT}" == *"handle_request('PUT', '/api/items/1'"* ]]
[[ "${SRC_CONTENT}" == *"handle_request('DELETE', '/api/items/1'"* ]]

if ! command -v gfortran >/dev/null 2>&1; then
  echo "SKIP: gfortran is not installed. Source-level checks passed."
  exit 0
fi

echo "Building Fortran targets (fortran/build/)…"
make -C "${ROOT}/fortran" all

API_BIN="${ROOT}/fortran/build/api_example"
GEN_BIN="${ROOT}/fortran/build/gen_bulk_payloads"
if [[ ! -x "${API_BIN}" || ! -x "${GEN_BIN}" ]]; then
  echo "Expected binaries missing after build" >&2
  exit 1
fi

echo "Running API simulation (api_example)…"
OUTPUT="$("${API_BIN}")"

[[ "${OUTPUT}" == *"GET /health -> 200"* ]]
[[ "${OUTPUT}" == *"POST /api/items -> 201"* ]]
[[ "${OUTPUT}" == *"PUT /api/items/1 -> 200"* ]]
[[ "${OUTPUT}" == *"DELETE /api/items/1 -> 200"* ]]
[[ "${OUTPUT}" == *"GET /api/items/1 -> 404"* ]]

echo "Checking gen_bulk_payloads output…"
TMPND="$(mktemp)"
trap 'rm -f "${TMPND}"' EXIT
"${GEN_BIN}" 10 bulk >"${TMPND}"
LINES="$(wc -l < "${TMPND}" | tr -d ' ')"
[[ "${LINES}" -eq 10 ]]
LINE1="$(head -n 1 "${TMPND}")"
[[ "${LINE1}" == *'"name":"bulk-1"'* ]]
[[ "${LINE1}" == *'"quantity":1'* ]]

echo "Fortran API example test OK."
