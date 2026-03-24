# REST CRUD API + SQLite — C++ vs Rust

Monorepo with **C++**, **Rust**, and **`asm/`** (ARM64 assembly entry) linking the **same C++ HTTP + SQLite stack** as `api_crud_server` (for fair apples-to-apples load tests).

| Variant | Stack | Output binary |
|---------|--------|----------------|
| C++ | C++17 `main`, cpp-httplib, nlohmann/json, system SQLite | `cpp/build/api_crud_server` |
| ASM + C++ libs | ARM64 `_main` in [`asm/entry.s`](asm/entry.s) → `extern "C"` → same routes/DB as above | **`cpp/build/api_crud_asm`** (arm64 on Apple Silicon; see `cpp/CMakeLists.txt`) |
| Rust | Axum, rusqlite **bundled** SQLite | `…/release/api_crud_rust` ([Rust binary path](#rust-binary-path)) |

The ASM binary only replaces the process entry and `PORT` / `DB_PATH` handling via libc (`getenv` / `atoi`); **all routes and SQLite access are still the C++ library code**. Benchmarks vs `api_crud_server` should be nearly identical.

## Prerequisites

- **macOS** (Apple Silicon or Intel) with developer tools  
  - **C++**: Xcode Command Line Tools (`clang`, `cmake`)  
  - **Rust**: [rustup](https://rustup.rs/) stable toolchain  
- **Network** on first C++ configure: CMake **FetchContent** clones cpp-httplib and nlohmann/json into `cpp/build/_deps/`.
- **Optional**: `ab` (ApacheBench) for `make bench-*`, `curl` for manual tests, `jq` for nicer script output, **Python 3** for `scripts/compare_load.sh` / `rust/bench.sh` (resolves the Rust binary path).

## Quick start — build and run

From the repository root (`api_test/`):

```bash
# Build both servers
make build-all

# C++ (default: http://0.0.0.0:18080, DB at cpp/data/app.db)
make run-cpp

# Same API, assembly entry + C++ stack (arm64 Mac only)
make run-asm
# (alias: make run-cpp-asm)

# In another terminal — Rust
make run-rust
```

Stop whatever is listening on the default port:

```bash
make stop          # kills listeners on PORT (default 18080)
make status        # show listener on PORT
```

### Environment variables (both servers)

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `18080` | TCP port |
| `DB_PATH` | `data/app.db` (relative to **current working directory** when you start the server) | SQLite file path |
| `BIND_ADDRESS` | `0.0.0.0` | Bind address |

**Important:** Start each server from its project directory (`cpp/` or `rust/`) if you rely on the default `DB_PATH`, or set `DB_PATH` to an absolute path.

Example:

```bash
cd cpp && PORT=18080 DB_PATH="$PWD/data/app.db" ./build/api_crud_server
cd rust && PORT=18081 DB_PATH="$PWD/data/app.db" cargo run --release
```

## HTTP API (shared contract)

- `GET /health` → `{"status":"ok"}`
- `GET /api/items?limit=50&offset=0` → `{ "items": [...], "total": N }` (`limit` capped at 500)
- `GET /api/items/:id` → item JSON or `404`
- `POST /api/items` → `201` — JSON body: `name` (required string), `description`, `quantity` (≥ 0)
- `PUT /api/items/:id` → `200` or `404`
- `DELETE /api/items/:id` → `{"deleted":true,"id":...}` or `404`

### Manual smoke test (`curl`)

With the C++ server on port 18080:

```bash
curl -s http://127.0.0.1:18080/health
curl -s http://127.0.0.1:18080/api/items
curl -s -X POST http://127.0.0.1:18080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"alpha","description":"test","quantity":3}'
curl -s http://127.0.0.1:18080/api/items/1
curl -s -X PUT http://127.0.0.1:18080/api/items/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"alpha","description":"updated","quantity":10}'
curl -s -X DELETE http://127.0.0.1:18080/api/items/1
```

## Testing and benchmarks

Full step-by-step guide: **[docs/BUILD_AND_TEST.md](docs/BUILD_AND_TEST.md)**.

**Un solo comando** (compilar todo y ejecutar la comparación de carga + informe de tiempos/tamaños):

```bash
chmod +x scripts/build_and_test.sh
./scripts/build_and_test.sh              # igual que make test: C++ + ASM (si existe) + Rust
./scripts/build_and_test.sh --quick      # menos inserciones (más rápido)
./scripts/build_and_test.sh --cpp-rust   # solo C++ vs Rust (sin fila ASM en el informe)
./scripts/build_and_test.sh --smoke      # solo build + curl a /health (C++)
./scripts/build_and_test.sh --help
```

### Makefile shortcuts

| Target | Action |
|--------|--------|
| `make` / `make build` | Same as `make build-all` |
| `make clean` | `cpp` CMake `distclean` + `cargo clean` for Rust |
| `make build-cpp` | Configure + build C++ with CMake |
| `make build-rust` | `cargo build --release` for Rust |
| `make build-asm` | C++ CMake (checks `api_crud_asm` on arm64) |
| `make build-all` | C++, Rust, and asm check |
| `make run-cpp` / `make run-asm` / `make run-cpp-asm` / `make run-rust` | Run the chosen server |
| `make bench-cpp` | ApacheBench → `benchmarks/bench_cpp_*.txt` |
| `make bench-asm` / `make bench-cpp-asm` | ApacheBench → `benchmarks/bench_asm_*.txt` (ASM entry binary) |
| `make bench-rust` | ApacheBench → `benchmarks/bench_rust_*.txt` |
| `make test` | **Build + pruebas**: `scripts/build_and_test.sh` (C++ + **ASM si está compilado** + Rust + informe) |
| `make compare` | C++ vs Rust: `scripts/compare_load.sh` |
| `make compare-all` | C++ + ASM entry + Rust: `scripts/compare_all.sh` |

### Load scripts (with a server already running)

Run each line separately (do not paste `# …` comment lines into zsh — they are not comments in every paste context). Use **`./scripts/…`** so **bash** runs the shebang; with **zsh**, URLs that contain `?` must be **quoted** if you type `curl` yourself.

```bash
chmod +x scripts/bulk_insert.sh scripts/bulk_query.sh scripts/compare_load.sh scripts/compare_all.sh

BASE_URL=http://127.0.0.1:18080 COUNT=5000 PARALLEL=32 ./scripts/bulk_insert.sh
ROUNDS=800 PAGE_SIZE=100 PARALLEL=32 ./scripts/bulk_query.sh
```

Optional second phase (needs **jq**):

```bash
SAMPLE_IDS=50 ./scripts/bulk_query.sh
```

### Head-to-head insert load

```bash
COUNT=10000 PARALLEL=32 ./scripts/compare_load.sh
```

Produces `cpp/data/compare_load.db` and `rust/data/compare_load.db`, prints wall-clock time for each stack, then a **summary** (fastest/slowest insert, relative %, and **binary sizes** via `scripts/emit_compare_report.py`). A **Markdown** report is also saved under **`benchmarks/reports/compare_load_*.md`** (tracked in git) for uploads.

Three-way insert comparison (C++ binary, ASM entry binary, Rust):

```bash
./scripts/compare_all.sh
```

Same style of **timing + binary size** report at the end (two or three variants depending on whether `api_crud_asm` was built), plus **`benchmarks/reports/compare_all_*.md`**.

### Sample `compare_all` result (checked in)

Full Markdown report: **[`benchmarks/reports/compare_all_20260324_140824.md`](benchmarks/reports/compare_all_20260324_140824.md)**  
Generated `2026-03-24` (UTC in file). Workload: **`COUNT=5000`**, **`PARALLEL=32`**, **`PORT=18080`** (`bulk_insert`).

**Machine resources (that run)**

| Resource | Value |
|----------|--------|
| SoC | Apple **M1 Max** |
| RAM | **32 GiB** |
| CPU cores | **10** (physical / logical) |
| Architecture | **arm64** (Apple Silicon) |
| OS | **macOS 26.3.1** (build 25D771280a) |
| Hostname | `MacBook-Pro-de-Marvin.local` (from report) |

**Outcome (wall time bulk insert, seconds; binary on disk)**

| Variant | Time (s) | Binary size |
|---------|----------|-------------|
| C++ | 10.7 | 2.93 MiB |
| ASM + C++ libs | 11.2 | 2.91 MiB |
| Rust | 11.1 | 4.52 MiB |

C++ was fastest for this sample; ASM vs C++ differs only by entry/bootstrap — numbers within run-to-run variance. See the linked `.md` for timing % and size ratios.

## Rust binary path

If `CARGO_TARGET_DIR` is set globally, the release binary may **not** live under `rust/target/release/`. The scripts `scripts/compare_load.sh` and `rust/bench.sh` locate it via:

```bash
cargo metadata --format-version 1 --no-deps  # field: target_directory
```

Python 3 is required for that one-liner in those scripts.

## Fair comparison notes

- Bottlenecks are usually **SQLite + disk + concurrent HTTP**, not the language.
- Rust links **bundled** SQLite; C++ uses the **system** library on macOS. For identical engine versions, align SQLite or switch rusqlite to system linking (advanced).
- For very large ingests, **batch APIs / transactions** often beat micro-optimizing the language.

## Repository layout

```
api_test/
  Makefile
  README.md
  docs/BUILD_AND_TEST.md
  cpp/                 # CMake: api_crud_server + api_crud_asm (links ../asm/entry.s)
  asm/                 # ARM64 entry.s + Makefile / bench (binary still under cpp/build/)
  rust/                # Cargo project
  scripts/             # bulk_insert, bulk_query, compare_load, compare_all
  benchmarks/          # ab logs (ignored); reports/compare_*.md from compare scripts (tracked)
```

Language-specific notes: [`cpp/README.md`](cpp/README.md), [`asm/README.md`](asm/README.md), [`rust/README.md`](rust/README.md).
