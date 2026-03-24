BUILD_DIR := build
TARGET := $(BUILD_DIR)/api_crud_server
ASM_BIN := $(BUILD_DIR)/api_crud_asm

.PHONY: all configure build run run-asm bench bench-asm clean distclean stop status

all: build

configure:
	cmake -B $(BUILD_DIR) -S .

$(TARGET): CMakeLists.txt
	cmake -B $(BUILD_DIR) -S .
	cmake --build $(BUILD_DIR) -j 8

build: $(TARGET)

run: $(TARGET)
	./$(TARGET)

run-asm: $(TARGET)
	@test -x $(ASM_BIN) || (echo "api_crud_asm not found. Build requires Apple arm64 (uname -m = arm64)."; exit 1)
	./$(ASM_BIN)

bench:
	chmod +x ./bench.sh
	./bench.sh

bench-asm:
	chmod +x ./bench_asm.sh
	./bench_asm.sh

clean:
	cmake --build $(BUILD_DIR) --target clean 2>/dev/null || true

distclean:
	rm -rf $(BUILD_DIR)

stop:
	@lsof -ti tcp:$${PORT:-18080} | xargs kill -9 2>/dev/null || true
	@echo "Stopped listeners on port $${PORT:-18080} (if any)."

status:
	@lsof -nP -iTCP:$${PORT:-18080} -sTCP:LISTEN || echo "Nothing listening on $${PORT:-18080}."
