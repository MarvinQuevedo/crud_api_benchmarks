# Assembly entry project: builds api_crud_asm via the C++ CMake tree (same link as before).
CPP_DIR := ../cpp
BUILD_DIR := $(CPP_DIR)/build
BIN := $(BUILD_DIR)/api_crud_asm

.PHONY: all build run bench stop status clean

all: build

build:
	$(MAKE) -C $(CPP_DIR) build
	chmod +x ../scripts/build_asm_arm64.sh && ../scripts/build_asm_arm64.sh
	@if [ -x $(BUILD_DIR)/api_crud_asm ]; then echo "asm: api_crud_asm at $(BUILD_DIR)/api_crud_asm."; \
	elif [ -x $(CPP_DIR)/build-arm64/api_crud_asm ]; then echo "asm: api_crud_asm at $(CPP_DIR)/build-arm64/api_crud_asm (Rosetta workaround)."; \
	else echo "asm: api_crud_asm not available (need Apple Silicon + arm64 link; see asm/README.md)."; fi

run: build
	cd $(CPP_DIR) && \
	  ASM_BIN=./build/api_crud_asm; \
	  if [ ! -x "$$ASM_BIN" ]; then ASM_BIN=./build-arm64/api_crud_asm; fi; \
	  test -x "$$ASM_BIN" || (echo "No api_crud_asm in build/ or build-arm64/."; exit 1); \
	  PORT=$${PORT:-18080} DB_PATH=$${DB_PATH:-data/app.db} exec "$$ASM_BIN"

bench:
	chmod +x ./bench.sh
	./bench.sh

stop:
	@lsof -ti tcp:$${PORT:-18080} | xargs kill -9 2>/dev/null || true

status:
	@lsof -nP -iTCP:$${PORT:-18080} -sTCP:LISTEN || echo "Nothing listening on $${PORT:-18080}."

clean:
	$(MAKE) -C $(CPP_DIR) clean
