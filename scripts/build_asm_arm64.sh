#!/usr/bin/env bash
# Ensures cpp/build/api_crud_asm exists on Apple Silicon.
#
# CMakeLists.txt enables api_crud_asm when sysctl hw.optional.arm64=1 (even if CMake
# runs under Rosetta / uname x86_64) and sets OSX_ARCHITECTURES=arm64 on that target.
# So a normal `make -C cpp build` is enough — this script just triggers that if missing.
#
# cpp/build-arm64/ is only used as a fallback when the one-liner build fails (rare).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPP="${ROOT}/cpp"
BIN_DEFAULT="${CPP}/build/api_crud_asm"
BIN_ALT="${CPP}/build-arm64/api_crud_asm"

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]]; then
  exit 0
fi

if [[ -x "$BIN_DEFAULT" ]]; then
  echo "api_crud_asm OK: ${BIN_DEFAULT}"
  exit 0
fi

if [[ -x "$BIN_ALT" ]]; then
  echo "api_crud_asm OK: ${BIN_ALT}"
  exit 0
fi

echo "Building C++ targets (api_crud_asm is enabled by CMake on Apple Silicon)…"
if ! make -C "$CPP" build; then
  echo "Note: cpp build failed." >&2
  exit 0
fi

if [[ -x "$BIN_DEFAULT" ]]; then
  echo "OK: ${BIN_DEFAULT}"
  exit 0
fi

# Fallback: second build dir + arm64-capable CMake (see script history in git if needed)
cmake_runs_as_arm64() {
  local c="$1"
  [[ -x "$c" ]] || return 1
  arch -arm64 "$c" --version >/dev/null 2>&1
}

collect_candidates() {
  printf '%s\n' "${CMAKE_ARM64_BIN:-}" \
    /opt/homebrew/bin/cmake \
    /opt/homebrew/opt/cmake/bin/cmake \
    "$(PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" arch -arm64 /bin/bash -lc 'command -v cmake' 2>/dev/null)" \
    "$(command -v cmake 2>/dev/null)" \
    /usr/local/bin/cmake \
    /Applications/CMake.app/Contents/bin/cmake
}

echo "api_crud_asm still missing after main build; trying build-arm64 fallback…"
CMAKE_BIN=""
while IFS= read -r c; do
  [[ -z "$c" || ! -x "$c" ]] && continue
  if cmake_runs_as_arm64 "$c"; then
    CMAKE_BIN="$c"
    break
  fi
done < <(collect_candidates | awk '!seen[$0]++' || true)

if [[ -z "$CMAKE_BIN" ]]; then
  cat >&2 <<'EOF'
Could not produce api_crud_asm. Re-run from repo root:
  rm -rf cpp/build && make -C cpp build

If that still skips asm, install arm64 CMake (e.g. brew install cmake under /opt/homebrew).
EOF
  exit 0
fi

[[ -d /opt/homebrew ]] && export PATH="/opt/homebrew/bin:${PATH}" CMAKE_PREFIX_PATH="/opt/homebrew${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"

cd "$CPP"
arch -arm64 "$CMAKE_BIN" -B build-arm64 -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  && arch -arm64 "$CMAKE_BIN" --build build-arm64 -j 8 --target api_crud_asm \
  && echo "OK: ${BIN_ALT}" || echo "Note: fallback build failed." >&2
exit 0
