# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional, serialized matched benchmark; no firmware rebuild or dependency.
INTEGER_PAIR_HINTS ?= 0
ifneq ($(filter $(INTEGER_PAIR_HINTS),0 1),$(INTEGER_PAIR_HINTS))
$(error INTEGER_PAIR_HINTS must be 0 or 1)
endif
ifneq ($(words $(INTEGER_PAIR_HINTS)),1)
$(error INTEGER_PAIR_HINTS must be 0 or 1)
endif
INTEGER_PAIR_DIR ?= $(BUILD_DIR)/integer-fpu-pair-hints$(INTEGER_PAIR_HINTS)
INTEGER_PAIR_DIGEST_ARGS ?=
INTEGER_PAIR_IMAGE ?= ../toolchain/build/demo/dhrystone.hex
INTEGER_PAIR_DUMP ?= ../toolchain/build/demo/dhrystone.dump
INTEGER_PAIR_DEFINES := +define+PPC_DISPATCH_WIDTH=2 +define+PPC_LSU_PIPE=1 +define+PPC_BRANCH_REMOVAL=0 +define+PPC_FETCH_DECODE_REG=0 +define+PPC_MISPREDICT_FETCH_NOW=1
INTEGER_PAIR_PARAMETERS := "-GENABLE_FETCH_HINTS=1'b$(INTEGER_PAIR_HINTS)" -GFPU_IMPL=0 "-GENABLE_DCACHE=1'b0" -GDISPATCH_WIDTH=2 "-GENABLE_LSU_PIPE=1'b1"
INTEGER_PAIR_ARGS := +INTEGER_PAIR_ZERO_RAM +INTEGER_BRANCH_PROFILE +LOOP_START_PC=fff03ecc +LOOP_START_WORD=80810058 +LOOP_STOP_PC=fff03ff8 +LOOP_STOP_WORD=48000c55 +MAX_CYCLES=400000000
.PHONY: benchmark-integer-fpu-pair
benchmark-integer-fpu-pair:
	python3 tools/integer_branch_pair.py prepare --image $(INTEGER_PAIR_IMAGE) --dump $(INTEGER_PAIR_DUMP) --out $(INTEGER_PAIR_DIR)
	PPC_VERILATOR_FLAGS='$(INTEGER_PAIR_DEFINES)' $(VERILATOR) --binary --timing --assert -Wall -O3 -j 1 --top-module tb_demo_soc "-GENABLE_FPU=1'b0" $(INTEGER_PAIR_PARAMETERS) --Mdir $(INTEGER_PAIR_DIR)/fpu0 $(DEMO_FPU_RTL) -I../tb ../tb/soc/tb_demo_soc.sv
	timeout 600s $(abspath $(INTEGER_PAIR_DIR))/fpu0/Vtb_demo_soc $(SIM_ARGS) +IMAGE=$(abspath $(INTEGER_PAIR_DIR))/frozen.hex +NAME=dhrystone-fpu0 $(INTEGER_PAIR_ARGS) +INTEGER_RETIRE_TUPLES=$(abspath $(INTEGER_PAIR_DIR))/fpu0.tuples > $(INTEGER_PAIR_DIR)/fpu0.log
	python3 tools/integer_branch_pair.py digest --out $(INTEGER_PAIR_DIR) --profile 0 $(INTEGER_PAIR_DIGEST_ARGS)
	PPC_VERILATOR_FLAGS='$(INTEGER_PAIR_DEFINES)' $(VERILATOR) --binary --timing --assert -Wall -O3 -j 1 --top-module tb_demo_soc "-GENABLE_FPU=1'b1" $(INTEGER_PAIR_PARAMETERS) --Mdir $(INTEGER_PAIR_DIR)/fpu1 $(DEMO_FPU_RTL) -I../tb ../tb/soc/tb_demo_soc.sv
	timeout 600s $(abspath $(INTEGER_PAIR_DIR))/fpu1/Vtb_demo_soc $(SIM_ARGS) +IMAGE=$(abspath $(INTEGER_PAIR_DIR))/frozen.hex +NAME=dhrystone-fpu1 $(INTEGER_PAIR_ARGS) +INTEGER_RETIRE_TUPLES=$(abspath $(INTEGER_PAIR_DIR))/fpu1.tuples > $(INTEGER_PAIR_DIR)/fpu1.log
	python3 tools/integer_branch_pair.py digest --out $(INTEGER_PAIR_DIR) --profile 1 $(INTEGER_PAIR_DIGEST_ARGS)
	python3 tools/integer_branch_pair.py compare --out $(INTEGER_PAIR_DIR)
