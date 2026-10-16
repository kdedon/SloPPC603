# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
.PHONY: test-icache-abort-install-602 test-icache-abort-install-603e test-icache-abort-control-proof
test: test-icache-abort-install-602 test-icache-abort-install-603e

define ICACHE_ABORT_TEST
	mkdir -p $(BUILD_DIR)/icache-abort-$(1)-$(2)
	OBJCACHE= timeout 300s $(VERILATOR) --binary --timing --assert -Wall -j 1 \
	  --x-assign unique --x-initial unique --top-module tb_icache_abort_install \
	  -GSETS=$(1) -GWAYS=$(2) --Mdir $(BUILD_DIR)/icache-abort-$(1)-$(2) \
	  -MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0' \
	  $(ICACHE_RTL) ../tb/tb_icache_abort_install.sv
	timeout 30s $(abspath $(BUILD_DIR))/icache-abort-$(1)-$(2)/Vtb_icache_abort_install +verilator+seed+1 +verilator+rand+reset+2
endef

test-icache-abort-install-602:
	$(call ICACHE_ABORT_TEST,64,2)

test-icache-abort-install-603e:
	$(call ICACHE_ABORT_TEST,128,4)

# Icarus remains optional; this target is not part of default test.
test-icache-abort-control-proof:
	python3 tools/check_icache_abort_control.py --output $(BUILD_DIR)/icache-abort-control
	@set -eu; proof_output='$(abspath $(BUILD_DIR))/icache-abort-control/proof.vvp'; \
	trap 'rm -f -- "$$proof_output"' EXIT; \
	timeout 30s iverilog -g2012 -s tb_icache_abort_control -o "$$proof_output" $(BUILD_DIR)/icache-abort-control/tb_icache_abort_control.sv; \
	timeout 30s vvp "$$proof_output"

# Standalone leaf coverage is also called by coverage before its summary.
# The two public-oracle geometries run serially; no ELF is required.
.PHONY: coverage-icache-abort
coverage-icache-abort:
	python3 tools/run_icache_abort_coverage.py --coverage-dir "$(abspath $(COVERAGE_DIR))/icache-abort"
