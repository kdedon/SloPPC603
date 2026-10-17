# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional precise-exception capacity witness.
D1_CAPACITY_TB ?= ../tb/tb_core_d1_capacity_boundary.sv
D1_CAPACITY_ARGS ?=
.PHONY: test-core-d1-capacity-boundary
test-core-d1-capacity-boundary:
	mkdir -p $(BUILD_DIR)/core-d1-capacity-boundary
	OBJCACHE= timeout 300s $(VERILATOR) --binary --timing --assert -Wall -j 1 \
	  --top-module tb_core_d1_capacity_boundary \
	  --Mdir $(abspath $(BUILD_DIR))/core-d1-capacity-boundary \
	  -MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0' \
	  $(RTL) $(D1_CAPACITY_TB)
	timeout 120s $(abspath $(BUILD_DIR))/core-d1-capacity-boundary/Vtb_core_d1_capacity_boundary $(SIM_ARGS) $(D1_CAPACITY_ARGS)
