# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional proposed acceptance targets; never run during private preparation.
# Native overlap is tested at dispatch width1 with both fetch widths. Existing
# dual/manual gates separately cover dispatch width2 policies.
.PHONY: test-core-false-hazards test-core-false-hazards-fault test-core-ctr-retained-hazard

test-core-false-hazards:
	python3 tools/false_hazard_program.py --tools-dir tools --output $(BUILD_DIR)/false-hazards/program
	$(VERILATOR) --binary --timing --assert -Wall -j 1 -GFETCH_WIDTH=1 --top-module tb_core_false_hazards --Mdir $(BUILD_DIR)/false-hazards/w1 $(RTL) ../tb/tb_core_false_hazards.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/w1/Vtb_core_false_hazards +PROGRAM_DIR=$(BUILD_DIR)/false-hazards/program $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall -j 1 -GFETCH_WIDTH=2 --top-module tb_core_false_hazards --Mdir $(BUILD_DIR)/false-hazards/w2 $(RTL) ../tb/tb_core_false_hazards.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/w2/Vtb_core_false_hazards +PROGRAM_DIR=$(BUILD_DIR)/false-hazards/program $(SIM_ARGS)

test-core-false-hazards-fault:
	$(VERILATOR) --binary --timing --assert -Wall -j 1 --top-module tb_core_false_hazards_fault --Mdir $(BUILD_DIR)/false-hazards/fault $(RTL) ../tb/tb_core_false_hazards_fault.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/fault/Vtb_core_false_hazards_fault $(SIM_ARGS)

test-core-ctr-retained-hazard:
	python3 tools/ctr_capture_retained_program.py --tools-dir tools --output $(BUILD_DIR)/false-hazards/ctr-retained
	$(VERILATOR) --binary --timing --assert -Wall -j 1 -GFETCH_WIDTH=1 --top-module tb_core_ctr_retained_hazard --Mdir $(BUILD_DIR)/false-hazards/ctr-w1 $(RTL) ../tb/tb_core_ctr_retained_hazard.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/ctr-w1/Vtb_core_ctr_retained_hazard $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/false-hazards/ctr-retained +REQUIRE_CTR_CAPTURE_MATRIX=1
	PPC_VERILATOR_FLAGS='$(filter-out +define+PPC_DISPATCH_WIDTH=%,$(PPC_VERILATOR_FLAGS))' $(VERILATOR) --binary --timing --assert -Wall -j 1 +define+PPC_DISPATCH_WIDTH=2 -GFETCH_WIDTH=2 --top-module tb_core_ctr_retained_hazard --Mdir $(BUILD_DIR)/false-hazards/ctr-w2 $(RTL) ../tb/tb_core_ctr_retained_hazard.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/ctr-w2/Vtb_core_ctr_retained_hazard $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/false-hazards/ctr-retained +REQUIRE_CTR_CAPTURE_MATRIX=1 +REQUIRE_CTR_RELEASE_BOTH=1

.PHONY: test-core-false-hazards-branch
test-core-false-hazards-branch:
	$(VERILATOR) --binary --timing --assert -Wall -j 1 "-GBRANCH_REMOVAL=1'b0" --top-module tb_core_false_hazards_branch --Mdir $(BUILD_DIR)/false-hazards/branch-r0 $(RTL) ../tb/tb_core_false_hazards_branch.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/branch-r0/Vtb_core_false_hazards_branch $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall -j 1 "-GBRANCH_REMOVAL=1'b1" --top-module tb_core_false_hazards_branch --Mdir $(BUILD_DIR)/false-hazards/branch-r1 $(RTL) ../tb/tb_core_false_hazards_branch.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/branch-r1/Vtb_core_false_hazards_branch $(SIM_ARGS)

.PHONY: test-core-shadow-exception-boundary
test-core-shadow-exception-boundary:
	$(VERILATOR) --binary --timing --assert -Wall -j 1 --top-module tb_core_shadow_exception_boundary --Mdir $(BUILD_DIR)/false-hazards/shadow-exception $(RTL) ../tb/tb_core_shadow_exception_boundary.sv
	timeout 90s $(abspath $(BUILD_DIR))/false-hazards/shadow-exception/Vtb_core_shadow_exception_boundary $(SIM_ARGS)
