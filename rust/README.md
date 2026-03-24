# Rust CRUD server (Axum + SQLite)

Same HTTP API as [`../cpp/`](../cpp/) for performance comparison.

## Requirements

- Rust stable ([rustup](https://rustup.rs/))

## Build and run

```bash
cd rust
cargo build --release
cargo run --release
```

From the monorepo root:

```bash
make run-rust
```

Environment: `PORT`, `DB_PATH`, `BIND_ADDRESS`. Defaults behave like the C++ server; start from `rust/` or set an absolute `DB_PATH`.

## Benchmarks

```bash
./bench.sh
```

Output: `../benchmarks/bench_rust_*.txt`.

`bench.sh` and `../scripts/compare_load.sh` locate the release binary using `cargo metadata` (needed when `CARGO_TARGET_DIR` is not `rust/target/`). **Python 3** is required for that helper.

## Compare with C++ (bulk insert)

From the repo root:

```bash
./scripts/compare_load.sh
```

## SQLite note

This crate enables rusqlite’s **`bundled`** feature (SQLite compiled with the dependency). The C++ server links the **system** SQLite on macOS. Throughput numbers are comparable in magnitude; for identical engine builds, align SQLite versions or switch rusqlite to system linking (advanced).

More detail: **[../README.md](../README.md)** and **[../docs/BUILD_AND_TEST.md](../docs/BUILD_AND_TEST.md)**.
