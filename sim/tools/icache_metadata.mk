# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional independent word/opaque-metadata acceptance. All24profiles serialize
# in one recipe and reuse one owned Mdir; no parallel builds or RTL snapshots.
.PHONY: test-icache-metadata

test-icache-metadata:
	python3 tools/check_icache_metadata.py --output $(BUILD_DIR)/icache-metadata/source
	@set -eu; proof_dir='$(abspath $(BUILD_DIR))/icache-metadata'; \
	mkdir -p "$$proof_dir"; owned_build=$$(mktemp -d "$$proof_dir/model.XXXXXX"); \
	trap 'rm -rf -- "$$owned_build"' EXIT; \
	for bits in 2 3; do for geometry in 128x4 128x2 64x2; do \
	  sets=$${geometry%x*}; ways=$${geometry#*x}; \
	  for width in 1 2; do for metadata in 0 1; do \
	    echo "cache metadata $$geometry FW=$$width metadata=$$metadata bits=$$bits"; \
	    PPC_VERILATOR_FLAGS= OBJCACHE= timeout 900s $(VERILATOR_TOOL) --binary --timing --assert -Wall -j 1 \
	      --top-module tb_icache -GSETS=$$sets -GWAYS=$$ways -GFETCH_WIDTH=$$width \
	      "-GMETADATA=1'b$$metadata" -GWORD_META_BITS=$$bits --Mdir "$$owned_build" \
	      -MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0' \
	      $(ICACHE_RTL) ../tb/tb_icache.sv; \
	    timeout 90s "$$owned_build/Vtb_icache" $(SIM_ARGS); \
	  done; done; \
	done; done
