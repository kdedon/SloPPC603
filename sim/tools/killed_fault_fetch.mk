# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional directed ownership acceptance; existing symbolic prefix is unchanged.
.PHONY: test-core-killed-fault-fetch
test-core-killed-fault-fetch:
	python3 tools/killed_fault_fetch_program.py --output $(BUILD_DIR)/killed-fault-fetch/program
	$(VERILATOR) --binary --timing --assert -Wall -j 1 -GFETCH_WIDTH=2 --top-module tb_core_killed_fault_fetch --Mdir $(BUILD_DIR)/killed-fault-fetch/model $(RTL) ../tb/tb_core_killed_fault_fetch.sv
	timeout 90s $(abspath $(BUILD_DIR))/killed-fault-fetch/model/Vtb_core_killed_fault_fetch +PROGRAM_DIR=$(BUILD_DIR)/killed-fault-fetch/program $(SIM_ARGS)
