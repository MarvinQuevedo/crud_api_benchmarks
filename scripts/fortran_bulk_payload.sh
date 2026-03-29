#!/usr/bin/env bash
# Shared helpers: generate one JSON body per line for scripts/bulk_insert.sh (PAYLOAD_FILE).
# Expects: ROOT, COUNT; optional PREFIX (default bulk). Defines:
#   fortran_prepare_bulk_payload_file

fortran_prepare_bulk_payload_file() {
  mkdir -p "${ROOT}/fortran/data"
  local gen="${ROOT}/fortran/build/gen_bulk_payloads"
  export FORT_PAYLOAD_GEN_SEC=""
  if [[ -x "$gen" ]]; then
    local out="${ROOT}/fortran/data/last_bulk.ndjson"
    local start end
    start=$(python3 -c 'import time; print(time.time())')
    "$gen" "${COUNT}" "${PREFIX:-bulk}" >"$out"
    end=$(python3 -c 'import time; print(time.time())')
    FORT_PAYLOAD_GEN_SEC=$(python3 -c "print(round(float('${end}') - float('${start}'), 4))")
    export PAYLOAD_FILE="$out"
    export FORT_PAYLOAD_GEN_SEC
    echo "Bulk payloads: Fortran → ${out} (${COUNT} lines, PREFIX=${PREFIX:-bulk}, gen ${FORT_PAYLOAD_GEN_SEC}s)"
  else
    unset PAYLOAD_FILE
    echo "Bulk payloads: inline JSON (build Fortran: make build-fortran; needs gfortran)"
  fi
}
