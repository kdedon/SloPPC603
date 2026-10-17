# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional temporal acceptance extension to the existing core dual-dispatch bench.
.PHONY: test-core-special-port1-temporal
test-core-special-port1-temporal:
	$(VERILATOR) --binary --timing --assert -Wall -j 1 -CFLAGS -O0 +define+PPC_LSU_PIPE=1 --top-module tb_core_dual -GDISPATCH_WIDTH=2 "-GPORT1_STRESS=1'b1" --Mdir $(BUILD_DIR)/core-special-port1 $(RTL) ../tb/tb_core_dual.sv
	timeout 90s ./$(BUILD_DIR)/core-special-port1/Vtb_core_dual $(SIM_ARGS)
