# Fortran tools: api demo + JSON lines for bulk_insert (PAYLOAD_FILE).
# Default compiler is gfortran; override: make FC=flang

FC := gfortran
FFLAGS := -std=f2008 -Wall -Wextra -O2
BUILD_DIR := build

TARGETS := $(BUILD_DIR)/api_example $(BUILD_DIR)/gen_bulk_payloads

.PHONY: all build-optional clean

all: $(TARGETS)

# Used from repo root when gfortran may be absent (CI / minimal setups).
build-optional:
	@if ! command -v $(FC) >/dev/null 2>&1; then \
		echo "SKIP fortran build: $(FC) not found"; \
		exit 0; \
	fi
	$(MAKE) all

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/api_example: api_example.f90 | $(BUILD_DIR)
	$(FC) $(FFLAGS) -o $@ $<

$(BUILD_DIR)/gen_bulk_payloads: gen_bulk_payloads.f90 | $(BUILD_DIR)
	$(FC) $(FFLAGS) -o $@ $<

clean:
	rm -rf $(BUILD_DIR)
