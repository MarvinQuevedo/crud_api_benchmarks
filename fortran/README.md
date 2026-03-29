# Fortran tooling (optional)

Requires **`gfortran`** (e.g. `brew install gcc`). From repo root:

```bash
make build-fortran
# or
make -C fortran all
```

## Binaries (`fortran/build/`)

| Program | Role |
|---------|------|
| **`api_example`** | In-memory simulation of the shared HTTP CRUD contract (prints pseudo responses). |
| **`gen_bulk_payloads`** | Writes **one JSON POST body per line** to stdout, same shape as `scripts/bulk_insert.sh` uses: `{"name":"PREFIX-i","description":"auto bulk","quantity":…}` with `quantity = mod(i, 200)` (same rule as the bash path). |

Usage:

```bash
./build/gen_bulk_payloads 5000 bulk > data/last_bulk.ndjson
```

Arguments: `COUNT` and optional `PREFIX` (default `bulk`).

## Hooking into the HTTP API

With a server running on `BASE_URL`, point `bulk_insert` at the file:

```bash
cd /path/to/api_test
./fortran/build/gen_bulk_payloads 2000 bulk > /tmp/payloads.ndjson
PAYLOAD_FILE=/tmp/payloads.ndjson COUNT=2000 ./scripts/bulk_insert.sh
```

`compare_all.sh`, `compare_load.sh`, and `make test` / `./scripts/build_and_test.sh` regenerate **`fortran/data/last_bulk.ndjson`** automatically when `gen_bulk_payloads` is built.

## Tests

```bash
make test-fortran-example
```
