#!/usr/bin/env bash
# Optional second CMake tree: Apple Silicon + Rosetta x86_64 primary build leaves no
# api_crud_asm in cpp/build/. This script configures cpp/build-arm64 under
# `arch -arm64` so CMake sees uname=arm64 and produces api_crud_asm (arm64).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPP="${ROOT}/cpp"
OUT_DIR="${CPP}/build-arm64"
BIN_DEFAULT="${CPP}/build/api_crud_asm"
BIN_ARM64="${OUT_DIR}/api_crud_asm"

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]]; then
  exit 0
fi

if [[ -x "$BIN_DEFAULT" ]]; then
  echo "api_crud_asm already present: ${BIN_DEFAULT}"
  exit 0
fi

if [[ -x "$BIN_ARM64" ]]; then
  echo "api_crud_asm already present: ${BIN_ARM64}"
  exit 0
fi

if ! arch -arm64 uname -m 2>/dev/null | grep -q arm64; then
  echo "Note: arch -arm64 unavailable; cannot build api_crud_asm here." >&2
  exit 0
fi

echo "Building api_crud_asm in ${OUT_DIR} (arch -arm64 CMake; Rosetta workaround)…"

if [[ -d /opt/homebrew ]]; then
  export CMAKE_PREFIX_PATH="/opt/homebrew${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
fi

cd "$CPP"
if ! arch -arm64 cmake -B build-arm64 -S . -DCMAKE_BUILD_TYPE=Release; then
  echo "Note: arm64 CMake configure failed (OpenSSL/SDK paths?). ASM compare will be skipped." >&2
  exit 0
fi

if ! arch -arm64 cmake --build build-arm64 -j 8 --target api_crud_asm; then
  echo "Note: api_crud_asm (arm64) build failed. ASM compare will be skipped." >&2
  exit 0
fi

if [[ -x "$BIN_ARM64" ]]; then
  echo "OK: ${BIN_ARM64}"
else
  echo "Note: expected binary missing after build." >&2
fi
exit 0
