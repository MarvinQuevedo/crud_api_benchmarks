# C++ CRUD server (C++17 + SQLite)

Same HTTP API as [`../rust/`](../rust/) for side-by-side benchmarks.

## `api_crud_asm` (assembly entry, same C++ stack)

On **Apple Silicon** (`uname -m` = `arm64`), CMake also builds **`build/api_crud_asm`**:

- [`../asm/entry.s`](../asm/entry.s) — ARM64 `_main`, reads `PORT` / `DB_PATH` from the environment (`getenv`, `atoi`), then calls into C++.
- [`src/asm/asm_bridge.cpp`](src/asm/asm_bridge.cpp) — `extern "C" int asm_crud_run(...)` forwards to `http_api::run()` (identical behavior to `api_crud_server`).

Run: `make -C ../asm run` or `make run-asm` from repo root · Bench: [`../asm/bench.sh`](../asm/bench.sh) · `./bench_asm.sh` here delegates to that script.

Performance vs `api_crud_server` should be effectively the same; the assembly is only the bootstrap.

## Build and run

```bash
cd cpp
make build
make run
```

From the monorepo root:

```bash
make -C cpp build
make -C cpp run
```

Environment variables: `PORT`, `DB_PATH`, `BIND_ADDRESS` (see `include/app/config.hpp`).  
Default `DB_PATH` is relative to the **current working directory** when you launch the binary—prefer running from `cpp/` or set an absolute path.

## Utilities

- `make stop` / `make status` — free or inspect the default port (`PORT`, default `18080`)
- `./bench.sh` — ApacheBench; writes `../benchmarks/bench_cpp_*.txt`

## Dependencies

CMake **FetchContent** downloads [cpp-httplib](https://github.com/yhirose/cpp-httplib) and [nlohmann/json](https://github.com/nlohmann/json) into `build/_deps/` on first configure (network required). SQLite is resolved via CMake’s `FindSQLite3` (system SDK on macOS).

## Legacy

[`legacy_asm/server.s`](legacy_asm/server.s) is a standalone ARM64 HTTP demo and is **not** part of the main CMake target.

Full API, testing, and comparison notes: **[../README.md](../README.md)** and **[../docs/BUILD_AND_TEST.md](../docs/BUILD_AND_TEST.md)**.
