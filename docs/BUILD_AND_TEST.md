# Build and test guide

This document explains how to compile both servers, run them, and exercise the API with manual checks, load scripts, and ApacheBench.

## 1. Prerequisites

### All platforms used in this repo

- **Git** (to clone)
- **curl** (smoke tests and load scripts)

### C++ server (`cpp/`)

- **CMake** ≥ 3.16
- **C++17 compiler** (Apple Clang with Xcode Command Line Tools is enough on macOS)
- **SQLite 3** development package — on macOS, CMake’s `FindSQLite3` typically uses the SDK
- **Internet** on the **first** CMake configure: dependencies are fetched with `FetchContent` (cpp-httplib, nlohmann/json)

### Rust server (`rust/`)

- **Rust stable** via [rustup](https://rustup.rs/)
- First `cargo build` downloads crates from crates.io (network)

### Optional tools

| Tool | Used for |
|------|-----------|
| `ab` (ApacheBench) | `make bench-cpp`, `make bench-asm`, `make bench-rust`, `cpp/bench.sh`, `asm/bench.sh`, `rust/bench.sh` |
| `jq` | Extra summaries in `scripts/bulk_insert.sh`; ID sampling in `scripts/bulk_query.sh` |
| `lsof` | `make stop` / `make status` (also used inside scripts) |
| **Python 3** | `scripts/compare_load.sh`, `scripts/compare_all.sh`, and `rust/bench.sh` (read `target_directory` from `cargo metadata`) |

---

## 2. Build

### Build and run integration tests in one step

```bash
chmod +x scripts/build_and_test.sh
./scripts/build_and_test.sh              # make build-all, then compare_all (C++ / ASM if built / Rust + report)
./scripts/build_and_test.sh --quick      # smaller COUNT/PARALLEL
./scripts/build_and_test.sh --cpp-rust   # compare_load only (two variants in the report)
./scripts/build_and_test.sh --smoke      # build + curl smoke test only
```

Equivalent: **`make test`** (same as `./scripts/build_and_test.sh` without flags).

**Assembly:** On Apple Silicon, CMake enables **`api_crud_asm`** using **`sysctl hw.optional.arm64`**, so Rosetta (x86_64) CMake still builds an **arm64** `api_crud_asm` in **`cpp/build/`** (see `cpp/CMakeLists.txt`). [`build_asm_arm64.sh`](../scripts/build_asm_arm64.sh) ensures a build if missing; it may fall back to **`cpp/build-arm64/`** only if needed.

### From repository root

```bash
make build-cpp    # cmake -B cpp/build -S cpp && cmake --build cpp/build
make build-rust   # cargo build --release --manifest-path rust/Cargo.toml
make build-asm    # same C++ build + checks api_crud_asm on Apple arm64
make build-all    # cpp + rust + asm check
```

### C++ only (inside `cpp/`)

```bash
cd cpp
make build
# Binaries:
#   cpp/build/api_crud_server   — always (on macOS with SQLite)
#   cpp/build/api_crud_asm      — only when `uname -m` is arm64 (Apple Silicon)
```

**First-time CMake** may take several minutes while dependencies clone.

### Assembly entry + C++ libraries (`api_crud_asm`)

On **Apple arm64**, CMake also builds `api_crud_asm`:

- [`asm/entry.s`](../../asm/entry.s) provides `_main`, reads `PORT` and `DB_PATH` via `_getenv` / `_atoi`, then calls `asm_crud_run` from [`cpp/src/asm/asm_bridge.cpp`](../../cpp/src/asm/asm_bridge.cpp).
- That C++ bridge forwards to the same `http_api::run()` as `api_crud_server` (httplib + SQLite + JSON).

Intel Macs skip this target (the `.s` file is ARM64-only).

```bash
cd asm
make build
make run              # from cpp cwd + default DB_PATH
./bench.sh            # ApacheBench against api_crud_asm
```

From the repo root: `make build-asm`, `make run-asm`, `make bench-asm` (or `make bench-cpp-asm`).

### Rust only (inside `rust/`)

```bash
cd rust
cargo build --release
# Default binary path: rust/target/release/api_crud_rust
# If CARGO_TARGET_DIR is set, use: cargo metadata --format-version 1 --no-deps | jq -r .target_directory
```

---

## 3. Run the servers

### Port already in use

```bash
make stop      # default PORT=18080
PORT=18081 make stop
make status
```

### C++

```bash
cd cpp
./build/api_crud_server
```

Or:

```bash
make -C cpp run
```

Defaults: `PORT=18080`, `DB_PATH=data/app.db` (relative to **current working directory**), `BIND_ADDRESS=0.0.0.0`.

### ASM entry (`api_crud_asm`, arm64 Mac only)

```bash
cd cpp
./build/api_crud_asm
```

`PORT` and `DB_PATH` are read from the environment inside [`asm/entry.s`](../../asm/entry.s). The bind address is fixed to `0.0.0.0` in assembly (override in C++ by changing `asm_bridge.cpp` if needed).

### Rust

```bash
cd rust
cargo run --release
```

Or from root:

```bash
make run-rust
```

You should see log lines similar to:

```text
Listening on http://0.0.0.0:18080
Database: data/app.db
```

---

## 4. Verify the API (manual)

Replace the port if you changed `PORT`.

```bash
curl -sS http://127.0.0.1:18080/health
curl -sS http://127.0.0.1:18080/api/items
```

Create and delete an item:

```bash
curl -sS -X POST http://127.0.0.1:18080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"doc-test","description":"","quantity":1}'
curl -sS -X DELETE http://127.0.0.1:18080/api/items/1
```

Expected failures (sanity):

- Missing `name` on POST → `400`
- Unknown id on GET → `404`

---

## 5. Load testing

### 5.1 Bulk insert (many `POST /api/items`)

Requires a **running** server.

```bash
chmod +x scripts/bulk_insert.sh
BASE_URL=http://127.0.0.1:18080 COUNT=2000 PARALLEL=16 ./scripts/bulk_insert.sh
```

Environment variables:

| Variable | Default | Meaning |
|----------|---------|---------|
| `BASE_URL` | `http://127.0.0.1:18080` | Server origin |
| `COUNT` | `2000` | Number of POSTs |
| `PARALLEL` | `16` | Parallel workers (`xargs -P`) |
| `PREFIX` | `bulk` | Name prefix for generated items |
| `VERBOSE` | `0` | Set to `1` to print per-request HTTP codes |

### 5.2 Bulk read (many `GET /api/items`)

```bash
chmod +x scripts/bulk_query.sh
BASE_URL=http://127.0.0.1:18080 ROUNDS=400 PAGE_SIZE=50 PARALLEL=24 ./scripts/bulk_query.sh
```

Optional (needs `jq`):

```bash
SAMPLE_IDS=50 ./scripts/bulk_query.sh
```

**Shell note:** run with `bash ./scripts/bulk_query.sh` or `./scripts/bulk_query.sh` (bash shebang). Running under `zsh` with bash-specific snippets can cause obscure errors.

### 5.3 Compare C++ vs Rust insert throughput

Builds both, starts each server in turn on the same `PORT`, runs `bulk_insert` with the same `COUNT` / `PARALLEL`, writes separate SQLite files:

- `cpp/data/compare_load.db`
- `rust/data/compare_load.db`

```bash
chmod +x scripts/compare_load.sh
./scripts/compare_load.sh
# Tune:
COUNT=10000 PARALLEL=32 PORT=18080 ./scripts/compare_load.sh
```

Requires **Python 3** for `cargo metadata` and for **`scripts/emit_compare_report.py`**, which prints a short **timing + executable size** summary after the run.

### 5.4 Compare C++ + ASM entry + Rust

Runs the same `bulk_insert` workload against `api_crud_server`, then `api_crud_asm` (if built), then Rust:

```bash
chmod +x scripts/compare_all.sh
./scripts/compare_all.sh
```

SQLite outputs: `cpp/data/compare_pure.db`, `cpp/data/compare_asm.db`, `rust/data/compare_rust.db`. The ASM phase is skipped on machines where `api_crud_asm` was not built. At the end, **`emit_compare_report.py`** summarizes wall times (bulk insert) and on-disk sizes of each server binary.

### 5.5 ApacheBench (`ab`)

```bash
make bench-cpp         # from repo root
make bench-asm         # ASM entry binary (arm64 only); same as make bench-cpp-asm
make bench-rust
```

Reports land under `benchmarks/` (`bench_cpp_*.txt`, `bench_asm_*.txt`, `bench_rust_*.txt`).

Tune from `cpp/` or `rust/`:

```bash
cd cpp && N=20000 C=100 ./bench.sh
cd asm && N=20000 C=100 ./bench.sh
```

---

## 6. Troubleshooting

| Symptom | Likely cause | What to do |
|---------|----------------|------------|
| `make run` / server exits immediately | Port in use | `make stop` or change `PORT` |
| CMake fails cloning deps | Network / proxy / partial `cpp/build` | `rm -rf cpp/build` and re-run `make build-cpp` |
| Rust script: binary not found | Custom `CARGO_TARGET_DIR` | Use provided scripts; ensure `python3` is on `PATH` |
| `ab: command not found` | Apache not installed | Install Apache or use only `curl` / load scripts |
| `api_crud_asm` missing | Not Apple arm64 | Expected on Intel Mac; use `api_crud_server` only |
| Empty DB after “success” | Wrong `DB_PATH` cwd | Use absolute `DB_PATH` or start server from `cpp/` / `rust/` |

---

## 7. Cleaning artifacts

```bash
make -C cpp distclean    # removes cpp/build
rm -rf rust/target       # Rust build cache (also gitignored)
rm -f cpp/data/*.db rust/data/*.db
```

Do **not** delete `rust/Cargo.lock` if you want reproducible dependency versions for the Rust binary.
