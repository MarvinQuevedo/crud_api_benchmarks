# Assembly entry + C++ stack (ARM64)

Same HTTP API and SQLite behavior as [`../cpp/`](../cpp/) and [`../rust/`](../rust/): only the process entry is hand-written ARM64 in [`entry.s`](entry.s). The server logic lives in C++ (`asm_bridge.cpp`, httplib, repositories).

## Requirements

- **macOS Apple Silicon** (`sysctl hw.optional.arm64` = 1) — Intel Macs skip `api_crud_asm`.
- **Normal build:** [`../cpp/CMakeLists.txt`](../cpp/CMakeLists.txt) enables this target from **hardware sysctl**, not only `uname -m`, so **x86_64 CMake under Rosetta** still produces **`cpp/build/api_crud_asm`** (arm64) next to **`api_crud_server`** (often x86_64). No separate arm64 CMake install is required.
- [`../scripts/build_asm_arm64.sh`](../scripts/build_asm_arm64.sh) runs `make -C cpp build` if the binary is missing; a rare **fallback** may use `cpp/build-arm64/` plus an arm64-capable CMake.
- Same C++ toolchain as `cpp/` (Xcode CLT, CMake). First configure may fetch httplib/json (network).

## Build and run

```bash
cd asm
make build
make run
```

From the monorepo root:

```bash
make build-asm
make run-asm
```

The binary is normally **`../cpp/build/api_crud_asm`** (arm64 slice); **`../cpp/build-arm64/api_crud_asm`** only if the fallback path ran.

Environment: `PORT`, `DB_PATH`. Default `DB_PATH` is relative to the **working directory** — `make run` starts the process from `cpp/` with `data/app.db`, matching the C++ server.

## Benchmarks

```bash
./bench.sh
```

Output: `../benchmarks/bench_asm_*.txt` (ApacheBench `ab` required).

Root shortcut: `make bench-asm` (same as legacy `make bench-cpp-asm`).

## How it links

- [`entry.s`](entry.s) — `_main`, `getenv` / `atoi`, then `_asm_crud_run`.
- [`../cpp/src/asm/asm_bridge.cpp`](../cpp/src/asm/asm_bridge.cpp) — C++ bridge to `http_api::run()`.

More context: **[../README.md](../README.md)** and **[../docs/BUILD_AND_TEST.md](../docs/BUILD_AND_TEST.md)**.
