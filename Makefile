# Convenience targets from the monorepo root (api_test/)

.PHONY: build build-cpp build-rust build-asm build-fortran build-all clean clean-cpp clean-rust clean-fortran test test-fortran-example run-cpp run-cpp-asm run-asm run-rust bench-cpp bench-cpp-asm bench-asm bench-rust compare compare-all stop status

# Default target — same as build-all
build: build-all

clean: clean-cpp clean-rust clean-fortran

clean-cpp:
	$(MAKE) -C cpp distclean

clean-rust:
	cargo clean --manifest-path rust/Cargo.toml

clean-fortran:
	$(MAKE) -C fortran clean

build-cpp:
	$(MAKE) -C cpp build

build-rust:
	cargo build --release --manifest-path rust/Cargo.toml

build-asm:
	$(MAKE) -C asm build

build-fortran:
	$(MAKE) -C fortran build-optional

build-all: build-cpp build-rust build-asm build-fortran

run-cpp:
	$(MAKE) -C cpp run

run-cpp-asm:
	$(MAKE) -C asm run

run-asm:
	$(MAKE) -C asm run

run-rust:
	cd rust && cargo run --release

bench-cpp:
	$(MAKE) -C cpp bench

bench-cpp-asm:
	chmod +x asm/bench.sh
	cd asm && ./bench.sh

bench-asm: bench-cpp-asm

bench-rust:
	chmod +x rust/bench.sh
	cd rust && ./bench.sh

compare:
	chmod +x scripts/compare_load.sh
	./scripts/compare_load.sh

compare-all:
	chmod +x scripts/compare_all.sh
	./scripts/compare_all.sh

test:
	chmod +x scripts/build_and_test.sh
	./scripts/build_and_test.sh

test-fortran-example:
	chmod +x scripts/test_fortran_example.sh
	./scripts/test_fortran_example.sh

stop:
	@lsof -ti tcp:$${PORT:-18080} | xargs kill -9 2>/dev/null || true

status:
	@lsof -nP -iTCP:$${PORT:-18080} -sTCP:LISTEN || echo "Nothing listening on $${PORT:-18080}."
