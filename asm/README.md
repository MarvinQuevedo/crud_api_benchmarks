# Assembly entry + C++ stack (ARM64)

Same HTTP API and SQLite behavior as [`../cpp/`](../cpp/) and [`../rust/`](../rust/): only the process entry is hand-written ARM64 in [`entry.s`](entry.s). The server logic lives in C++ (`asm_bridge.cpp`, httplib, repositories).

## Requirements

- **macOS Apple Silicon** — Intel Macs skip `api_crud_asm`.
- **Rosetta (x86_64 CMake)** on Apple Silicon: the main tree is often `cpp/build/` without `api_crud_asm`. This repo then configures **`cpp/build-arm64/`** under **`arch -arm64`** via [`../scripts/build_asm_arm64.sh`](../scripts/build_asm_arm64.sh) (also run automatically from `make build` here, `compare_all.sh`, and `make build-all`). The binary may be **`cpp/build-arm64/api_crud_asm`**.
- If linking fails, install **arm64 Homebrew** deps under **`/opt/homebrew`** (the script prepends it to `CMAKE_PREFIX_PATH`). Pure **`/usr/local`** x86_64 OpenSSL will not link into an arm64 executable.
- Alternative: native arm64 shell only — `arch -arm64 zsh`, then `rm -rf ../cpp/build && make -C ../cpp build` so `api_crud_asm` lands in `cpp/build/`.
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

The binary is **`../cpp/build/api_crud_asm`** when CMake ran as arm64, or **`../cpp/build-arm64/api_crud_asm`** after the Rosetta workaround (same sources).

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
