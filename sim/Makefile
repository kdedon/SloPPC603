# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
VERILATOR ?= $(CURDIR)/tools/verilate
# The cosim drivers take one executable path; they add the X flags from --xrand-seed.
VERILATOR_TOOL := $(VERILATOR)
# Randomize uninitialized state with a fixed seed so a missing reset fails reproducibly.
XRAND ?= 1
XRAND_SEED ?= 1
ifeq ($(XRAND),1)
override VERILATOR += --x-assign unique --x-initial unique
SIM_ARGS ?= +verilator+seed+$(XRAND_SEED) +verilator+rand+reset+2
XRAND_REFERENCE_ARGS := --xrand-seed $(XRAND_SEED)
endif
# DISPATCH_WIDTH=2 builds every core and wrapper whose width is not set
# explicitly at that width, in its own build directory.
ifdef DISPATCH_WIDTH
export PPC_VERILATOR_FLAGS := +define+PPC_DISPATCH_WIDTH=$(DISPATCH_WIDTH)
BUILD_DIR ?= build-w$(DISPATCH_WIDTH)
endif
BUILD_DIR ?= build
RTL := $(shell cat ../rtl/files.f)
BUS_RTL := $(shell cat ../rtl/bus_files.f)
SYSTEM_RTL := $(shell cat ../rtl/system_files.f)
LINE_RTL := $(shell cat ../rtl/line_read_files.f)
ICACHE_RTL := $(shell cat ../rtl/icache_files.f)
DCACHE_RTL := $(shell cat ../rtl/dcache_files.f)
CACHED_SYSTEM_RTL := $(shell cat ../rtl/cached_system_files.f)
BAT_RTL := $(shell cat ../rtl/bat_files.f)
BAT_SERVICE_RTL := $(shell cat ../rtl/bat_service_files.f)
# Core builds already list the package through RTL.
CORE_BAT_SERVICE_RTL := $(filter-out ../rtl/ppc_pkg.sv,$(BAT_SERVICE_RTL))
CORE_BAT_RTL := $(shell cat ../rtl/core_bat_files.f)
TLB_SERVICE_RTL := $(shell cat ../rtl/tlb_service_files.f)
SEGMENT_REGISTER_RTL := $(shell cat ../rtl/segment_register_files.f)
CACHE_CONTROL_RTL := $(shell cat ../rtl/cache_control_files.f)
EXCEPTION_RTL := $(shell cat ../rtl/exception_files.f)
# The core with ENABLE_FPU; other profiles carry only the FPU package.
FPU_CORE_RTL := $(RTL) ../rtl/ppc_ram_lut.sv $(shell cat ../rtl/fpu_files.f)
.PHONY: all lint test test-core test-completion test-execution test-stage check-spec test-recovery test-recovery-select test-recovery-execution test-recovery-state test-core-recovery test-fetch-recovery test-core-logical test-flags test-completion-flags test-record-execution test-core-record-logical test-core-record-edges test-core-add-flags test-core-add-recovery test-add-execution test-core-adde test-core-adde-recovery test-adde-execution test-core-add-unary test-add-unary-execution test-addme-recovery test-addze-recovery test-core-rotate test-rotate-execution test-core-control-memory test-core-memory-edges test-core-shifts test-shift-execution test-slw-recovery test-srw-recovery clean
# Shared Verilator output directories have a single build owner per invocation.
# These phony prerequisites keep source/configuration checking in Verilator while
# allowing each read-only simulation to run concurrently on its own program files.
.PHONY: regression build-control-memory build-core-bus60x build-core-bus60x-unified build-core-add-recovery
all: regression
regression: reference-checkout lint check-spec test-recovery test-recovery-select test

build-control-memory:
	mkdir -p $(BUILD_DIR)/control-memory/obj
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_control_memory --Mdir $(BUILD_DIR)/control-memory/obj $(RTL) ../tb/tb_core_control_memory.sv

build-core-bus60x:
	mkdir -p $(BUILD_DIR)/core-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x --Mdir $(BUILD_DIR)/core-bus60x $(RTL) $(BUS_RTL) ../tb/bfm/bus60x_delay_target_bfm.sv ../tb/tb_core_bus60x.sv

build-core-add-recovery:
	mkdir -p $(BUILD_DIR)/core-add-recovery
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery --Mdir $(BUILD_DIR)/core-add-recovery $(RTL) ../tb/tb_core_add_recovery.sv

build-core-bus60x-unified:
	mkdir -p $(BUILD_DIR)/core-bus60x-unified
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_unified --Mdir $(BUILD_DIR)/core-bus60x-unified $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_delay_target_bfm.sv ../tb/tb_core_bus60x_unified.sv

lint:
	cd ../quartus/timer-bat && $(VERILATOR) --lint-only -Wall --top-module ppc_timer_bat_measure -f files.f
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" "-GENABLE_DEBUG_EXCEPTIONS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" "-GENABLE_BYTE_REVERSE=1'b1" "-GENABLE_MULTIPLE_STRING=1'b1" "-GENABLE_RESERVATION=1'b1" "-GENABLE_MISALIGNED_ACCESS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_FULL_DECODE=1'b1" "-GENABLE_RESERVATION=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_FULL_DECODE=1'b1" "-GENABLE_FPU=1'b1" "-GENABLE_TEST_REDIRECT=1'b0" "-GENABLE_RESERVATION=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" $(FPU_CORE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_FULL_DECODE=1'b1" "-GENABLE_FPU=1'b1" -GDMEM_BITS=64 "-GENABLE_TEST_REDIRECT=1'b0" "-GENABLE_RESERVATION=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" $(FPU_CORE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc603e "-GENABLE_FPU=1'b1" $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f)
	$(VERILATOR) --lint-only -Wall --top-module tb_fpu_impl_lint -GFPU_IMPL=1 $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f) ../tb/tb_fpu_impl_lint.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_MULTIPLE_STRING=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_segment_registers $(SEGMENT_REGISTER_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_tlb_service $(TLB_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_service $(BAT_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_MICRO_TLB=1'b0" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_DATA_EXCEPTIONS=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x_managed $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x_managed "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_translate $(BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_exception_state $(EXCEPTION_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_icache $(ICACHE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_dcache $(DCACHE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bus60x_line_read $(LINE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bus60x $(BUS_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bus60x $(RTL) $(BUS_RTL) $(SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(SYSTEM_RTL)
	cd ../quartus && $(VERILATOR) --lint-only -Wall --top-module ppc_core_measure -f files.f
	cd ../quartus/integrated && $(VERILATOR) --lint-only -Wall --top-module ppc_integrated_measure -f files.f
	cd ../quartus/translated && $(VERILATOR) --lint-only -Wall --top-module ppc_translated_measure -f files.f
	cd ../quartus/icache && $(VERILATOR) --lint-only -Wall --top-module ppc_icache -f files.f
	cd ../quartus/dcache && $(VERILATOR) --lint-only -Wall --top-module ppc_dcache_measure -f files.f
test: test-compare-execution test-core-compare test-iterative-divider test-bus60x-line-read test-reference-memory test-line-read-independent test-core-divider-timing test-core-divider-timing-pid6 test-bus60x-arbiter test-core-bus60x-ifetch-error test-divider-timing test-core-bus60x-unified test-core-bus60x-unified-update test-lsu-update-decode test-completion-update test-lsu-update-edges test-core-lsu-update test-bus60x test-core-bus60x test-core-bus60x-update test-reference test-divw-decode test-divw-execution test-core-divide-signed test-divw-recovery test-divw-zero-recovery test-divw-overflow-recovery test-divwu-decode test-divwu-execution test-core-divide-unsigned test-divwu-recovery test-divwu-zero-recovery test-multiply-high-decode test-multiply-high-execution test-core-multiply-high test-mulhw-recovery test-mulhwu-recovery test-multiply-decode test-multiply-execution test-core-multiply test-multiply-recovery test-multiply-overflow-recovery test-crstate-execution test-crstate-decode test-core-crstate test-crstate-edges test-crlogical-decode test-completion-cr-bits test-crlogical-edges test-core-crlogical test-crtransfer-decode test-completion-cr-fields test-crtransfer-edges test-core-crtransfer test-unarylogical-decode test-core-unarylogical test-unarylogical-execution test-cntlzw-recovery test-extsb-recovery test-extsh-recovery test-core-andimmediate test-andi-recovery test-andis-recovery test-core-addimmediate test-addic-recovery test-addic-record-recovery test-core-subimmediate test-subfic-recovery test-subfic-negative-recovery test-core-subunary test-subunary-execution test-subfme-recovery test-subfze-recovery test-core-subextend test-subextend-execution test-subfe-recovery test-subfe-zero-recovery test-core-subcarry test-subcarry-execution test-subfc-recovery test-core-subtract test-subtract-execution test-subf-recovery test-neg-recovery test-core-insert test-insert-execution test-insert-recovery test-core-arithmetic-shifts test-arithmetic-shift-execution test-sraw-recovery test-srawi-recovery test-core test-completion test-execution test-stage test-recovery-execution test-recovery-state test-core-recovery test-fetch-recovery test-core-logical test-flags test-completion-flags test-record-execution test-core-record-logical test-core-record-edges test-core-add-flags test-core-add-recovery test-add-execution test-core-adde test-core-adde-recovery test-adde-execution test-core-add-unary test-add-unary-execution test-addme-recovery test-addze-recovery test-core-rotate test-rotate-execution test-core-control-memory test-core-memory-edges test-core-shifts test-shift-execution test-slw-recovery test-srw-recovery

# Python reference-model unit tests for the FPU oracle.
.PHONY: test-fpu-reference
test-fpu-reference:
	python3 -m unittest discover -s fpu -p 'test_*.py'

.PHONY: test-fpu-arith-initial test-fpu-arith test-fpu-arith-602
PPC_FPU_ARITH_RTL := ../rtl/ppc_pkg.sv ../rtl/fpu/ppc_fpu_pkg.sv ../rtl/fpu/ppc_fpu_arith_pkg.sv \
  ../rtl/fpu/ppc_fpu_unpack.sv ../rtl/fpu/ppc_fpu_multiplier.sv ../rtl/fpu/ppc_fpu_align_plan.sv ../rtl/fpu/ppc_fpu_aligner.sv ../rtl/fpu/ppc_fpu_adder.sv ../rtl/fpu/ppc_fpu_convert.sv ../rtl/fpu/ppc_fpu_rounder.sv ../rtl/fpu/ppc_fpu_divider.sv \
  ../rtl/fpu/ppc_fpu_arith.sv
PPC_FPU_SHELL_RTL := ../rtl/fpu/ppc_fpu_shell_pkg.sv ../rtl/ppc_ram_lut.sv ../rtl/fpu/ppc_fpu_fprs.sv ../rtl/fpu/ppc_fpu.sv
PPC_FPU_ARITH_BUILD := $(BUILD_DIR)/ppc-fpu-arith
PPC_FPU_ARITH_602_BUILD := $(BUILD_DIR)/ppc-fpu-arith-602
PPC_FPU_ARITH_INITIAL := $(BUILD_DIR)/fpu/production-initial.txt
PPC_FPU_ARITH_ALL := $(BUILD_DIR)/fpu/production-all.txt
PPC_FPU_ARITH_602_VECTORS := $(BUILD_DIR)/fpu/production-602.txt

$(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_ppc_fpu_arith --Mdir $(PPC_FPU_ARITH_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv

$(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_arith --Mdir $(PPC_FPU_ARITH_602_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv

$(PPC_FPU_ARITH_INITIAL): fpu/production_vectors.py fpu/ppc_reference.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/production_vectors.py --vectors $@ --random 32 --ops add sub mul madd msub nmadd nmsub frsp fctiw fctiwz cmpu cmpo

$(PPC_FPU_ARITH_ALL): fpu/production_vectors.py fpu/ppc_reference.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/production_vectors.py --vectors $@ --random 128

$(PPC_FPU_ARITH_602_VECTORS): fpu/production_vectors_602.py fpu/production_vectors.py fpu/ppc_reference.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/production_vectors_602.py --vectors $@ --random 128

test-fpu-arith-initial: test-fpu-reference $(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith $(PPC_FPU_ARITH_INITIAL)
	./$(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_ARITH_INITIAL)

test-fpu-arith: test-fpu-reference $(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith $(PPC_FPU_ARITH_ALL)
	./$(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_ARITH_ALL)

test-fpu-arith-602: test-fpu-reference $(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith $(PPC_FPU_ARITH_602_VECTORS)
	./$(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_ARITH_602_VECTORS)

# Exponent-clustered operands with random RN and VE/OE/UE/ZE/NI enables.
.PHONY: test-fpu-arith-cluster test-fpu-arith-cluster-602
PPC_FPU_CLUSTER_603 := $(BUILD_DIR)/fpu/cluster-603.txt
PPC_FPU_CLUSTER_602 := $(BUILD_DIR)/fpu/cluster-602.txt
$(PPC_FPU_CLUSTER_603): fpu/cluster_vectors.py fpu/production_vectors.py fpu/production_vectors_602.py fpu/ppc_reference.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/cluster_vectors.py --personality 603e --vectors $@ --count 2000 --seed 0xc105e603
$(PPC_FPU_CLUSTER_602): fpu/cluster_vectors.py fpu/production_vectors.py fpu/production_vectors_602.py fpu/ppc_reference.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/cluster_vectors.py --personality 602 --vectors $@ --count 2000 --seed 0xc105e602
test-fpu-arith-cluster: $(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith $(PPC_FPU_CLUSTER_603)
	./$(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_CLUSTER_603)
test-fpu-arith-cluster-602: $(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith $(PPC_FPU_CLUSTER_602)
	./$(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_CLUSTER_602)

# Arithmetic under FPSCR enables with MSR FE0/FE1, through the shell.
.PHONY: test-fpu-enabled-603 test-fpu-enabled-602
PPC_FPU_ENABLED_603_BUILD := $(BUILD_DIR)/ppc-fpu-enabled-603
PPC_FPU_ENABLED_602_BUILD := $(BUILD_DIR)/ppc-fpu-enabled-602
PPC_FPU_ENABLED_603 := $(BUILD_DIR)/fpu/enabled-603.txt
PPC_FPU_ENABLED_602 := $(BUILD_DIR)/fpu/enabled-602.txt
PPC_FPU_ENABLED_PY := fpu/enabled_vectors.py fpu/cluster_vectors.py fpu/production_vectors.py fpu/production_vectors_602.py fpu/ppc_reference.py fpu/reference.py
$(PPC_FPU_ENABLED_603): $(PPC_FPU_ENABLED_PY)
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/enabled_vectors.py --personality 603e --vectors $@ --count 3000 --seed 0xe7ab1ed
$(PPC_FPU_ENABLED_602): $(PPC_FPU_ENABLED_PY)
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/enabled_vectors.py --personality 602 --vectors $@ --count 3000 --seed 0xe7ab602
$(PPC_FPU_ENABLED_603_BUILD)/Vtb_ppc_fpu_enabled: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_enabled.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b0" --top-module tb_ppc_fpu_enabled --Mdir $(PPC_FPU_ENABLED_603_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_enabled.sv
$(PPC_FPU_ENABLED_602_BUILD)/Vtb_ppc_fpu_enabled: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_enabled.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_enabled --Mdir $(PPC_FPU_ENABLED_602_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_enabled.sv
test-fpu-enabled-603: $(PPC_FPU_ENABLED_603_BUILD)/Vtb_ppc_fpu_enabled $(PPC_FPU_ENABLED_603)
	./$(PPC_FPU_ENABLED_603_BUILD)/Vtb_ppc_fpu_enabled +VECTORS=$(PPC_FPU_ENABLED_603)
test-fpu-enabled-602: $(PPC_FPU_ENABLED_602_BUILD)/Vtb_ppc_fpu_enabled $(PPC_FPU_ENABLED_602)
	./$(PPC_FPU_ENABLED_602_BUILD)/Vtb_ppc_fpu_enabled +VECTORS=$(PPC_FPU_ENABLED_602)

# The exact-rational oracle against host IEEE arithmetic in all four modes.
.PHONY: test-fpu-oracle-host
test-fpu-oracle-host:
	cd fpu && python3 host_check.py --count 20000 --seed 0x1eee754

# Berkeley TestFloat level-1 cases through the model and the arithmetic
# bench. Fetches pinned third-party sources into $(BUILD_DIR)/testfloat.
.PHONY: test-fpu-testfloat test-fpu-testfloat-603 test-fpu-testfloat-602
TESTFLOAT_GEN := $(BUILD_DIR)/testfloat/testfloat_gen
TESTFLOAT_FUSED_STRIDE ?= 613
$(TESTFLOAT_GEN): fpu/fetch-softfloat.sh
	fpu/fetch-softfloat.sh $(BUILD_DIR)/testfloat
test-fpu-testfloat-603: $(TESTFLOAT_GEN) $(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith
	python3 fpu/testfloat_vectors.py --gen $(TESTFLOAT_GEN) --personality 603e --fused-stride $(TESTFLOAT_FUSED_STRIDE) --vectors $(BUILD_DIR)/fpu/testfloat-603.txt
	./$(PPC_FPU_ARITH_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(BUILD_DIR)/fpu/testfloat-603.txt
	rm -f $(BUILD_DIR)/fpu/testfloat-603.txt
test-fpu-testfloat-602: $(TESTFLOAT_GEN) $(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith
	python3 fpu/testfloat_vectors.py --gen $(TESTFLOAT_GEN) --personality 602 --fused-stride $(TESTFLOAT_FUSED_STRIDE) --vectors $(BUILD_DIR)/fpu/testfloat-602.txt
	./$(PPC_FPU_ARITH_602_BUILD)/Vtb_ppc_fpu_arith +VECTORS=$(BUILD_DIR)/fpu/testfloat-602.txt
	rm -f $(BUILD_DIR)/fpu/testfloat-602.txt
test-fpu-testfloat: test-fpu-testfloat-603 test-fpu-testfloat-602

.PHONY: test-fpu-timing-603 test-fpu-timing-602 lint-fpu-timing
PPC_FPU_TIMING_603_BUILD := $(BUILD_DIR)/ppc-fpu-timing-603
PPC_FPU_TIMING_602_BUILD := $(BUILD_DIR)/ppc-fpu-timing-602
$(PPC_FPU_TIMING_603_BUILD)/Vtb_ppc_fpu_timing: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b0" --top-module tb_ppc_fpu_timing --Mdir $(PPC_FPU_TIMING_603_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv

$(PPC_FPU_TIMING_602_BUILD)/Vtb_ppc_fpu_timing: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_timing --Mdir $(PPC_FPU_TIMING_602_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv

test-fpu-timing-603: $(PPC_FPU_TIMING_603_BUILD)/Vtb_ppc_fpu_timing
	./$(PPC_FPU_TIMING_603_BUILD)/Vtb_ppc_fpu_timing

test-fpu-timing-602: $(PPC_FPU_TIMING_602_BUILD)/Vtb_ppc_fpu_timing
	./$(PPC_FPU_TIMING_602_BUILD)/Vtb_ppc_fpu_timing

lint-fpu-timing:
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b0" --top-module tb_ppc_fpu_timing $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b1" --top-module tb_ppc_fpu_timing $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_timing.sv

lint: lint-fpu-timing

.PHONY: test-fpu-shell
PPC_FPU_SHELL_BUILD := $(BUILD_DIR)/ppc-fpu-shell
$(PPC_FPU_SHELL_BUILD)/Vtb_ppc_fpu_shell: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_shell.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_ppc_fpu_shell --Mdir $(PPC_FPU_SHELL_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_shell.sv

test-fpu-shell: $(PPC_FPU_SHELL_BUILD)/Vtb_ppc_fpu_shell
	./$(PPC_FPU_SHELL_BUILD)/Vtb_ppc_fpu_shell

.PHONY: test-fpu-602
PPC_FPU_602_BUILD := $(BUILD_DIR)/ppc-fpu-602
$(PPC_FPU_602_BUILD)/Vtb_ppc_fpu_602: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_602.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_ppc_fpu_602 --Mdir $(PPC_FPU_602_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_602.sv

test-fpu-602: $(PPC_FPU_602_BUILD)/Vtb_ppc_fpu_602
	./$(PPC_FPU_602_BUILD)/Vtb_ppc_fpu_602

.PHONY: test-fpu-stream-603 test-fpu-stream-602 lint-fpu-stream
PPC_FPU_STREAM_603_BUILD := $(BUILD_DIR)/ppc-fpu-stream-603
PPC_FPU_STREAM_602_BUILD := $(BUILD_DIR)/ppc-fpu-stream-602
$(PPC_FPU_STREAM_603_BUILD)/Vtb_ppc_fpu_stream: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b0" --top-module tb_ppc_fpu_stream --Mdir $(PPC_FPU_STREAM_603_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv

$(PPC_FPU_STREAM_602_BUILD)/Vtb_ppc_fpu_stream: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_stream --Mdir $(PPC_FPU_STREAM_602_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv

test-fpu-stream-603: $(PPC_FPU_STREAM_603_BUILD)/Vtb_ppc_fpu_stream
	./$(PPC_FPU_STREAM_603_BUILD)/Vtb_ppc_fpu_stream

test-fpu-stream-602: $(PPC_FPU_STREAM_602_BUILD)/Vtb_ppc_fpu_stream
	./$(PPC_FPU_STREAM_602_BUILD)/Vtb_ppc_fpu_stream

lint-fpu-stream:
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b0" --top-module tb_ppc_fpu_stream $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b1" --top-module tb_ppc_fpu_stream $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_stream.sv

lint: lint-fpu-stream

.PHONY: test-fpu-dual-603 test-fpu-dual-602 lint-fpu-dual
PPC_FPU_DUAL_603_BUILD := $(BUILD_DIR)/ppc-fpu-dual-603
PPC_FPU_DUAL_602_BUILD := $(BUILD_DIR)/ppc-fpu-dual-602
$(PPC_FPU_DUAL_603_BUILD)/Vtb_ppc_fpu_dual: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b0" --top-module tb_ppc_fpu_dual --Mdir $(PPC_FPU_DUAL_603_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv

$(PPC_FPU_DUAL_602_BUILD)/Vtb_ppc_fpu_dual: $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_dual --Mdir $(PPC_FPU_DUAL_602_BUILD) $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv

test-fpu-dual-603: $(PPC_FPU_DUAL_603_BUILD)/Vtb_ppc_fpu_dual
	./$(PPC_FPU_DUAL_603_BUILD)/Vtb_ppc_fpu_dual

test-fpu-dual-602: $(PPC_FPU_DUAL_602_BUILD)/Vtb_ppc_fpu_dual
	./$(PPC_FPU_DUAL_602_BUILD)/Vtb_ppc_fpu_dual

lint-fpu-dual:
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b0" --top-module tb_ppc_fpu_dual $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b1" --top-module tb_ppc_fpu_dual $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL) fpu/tb_ppc_fpu_dual.sv

lint: lint-fpu-dual

.PHONY: test-fpu-estimates
PPC_FPU_ESTIMATE_BUILD := $(BUILD_DIR)/ppc-fpu-estimates
PPC_FPU_ESTIMATE_VECTORS := $(BUILD_DIR)/fpu/estimate-vectors.txt
PPC_FPU_ESTIMATE_RESULTS := $(BUILD_DIR)/fpu/estimate-results.txt
$(PPC_FPU_ESTIMATE_BUILD)/Vtb_ppc_fpu_estimates: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_ppc_fpu_estimates --Mdir $(PPC_FPU_ESTIMATE_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv

$(PPC_FPU_ESTIMATE_VECTORS): fpu/estimate_vectors.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/estimate_vectors.py generate --vectors $@ --random 512

test-fpu-estimates: $(PPC_FPU_ESTIMATE_BUILD)/Vtb_ppc_fpu_estimates $(PPC_FPU_ESTIMATE_VECTORS)
	./$(PPC_FPU_ESTIMATE_BUILD)/Vtb_ppc_fpu_estimates +VECTORS=$(PPC_FPU_ESTIMATE_VECTORS) +OUTPUT=$(PPC_FPU_ESTIMATE_RESULTS)
	python3 fpu/estimate_vectors.py compare --vectors $(PPC_FPU_ESTIMATE_VECTORS) --results $(PPC_FPU_ESTIMATE_RESULTS)

.PHONY: test-fpu-estimates-602 lint-fpu-estimates-602
PPC_FPU_ESTIMATE_602_BUILD := $(BUILD_DIR)/ppc-fpu-estimates-602
PPC_FPU_ESTIMATE_602_VECTORS := $(BUILD_DIR)/fpu/estimate-602-vectors.txt
PPC_FPU_ESTIMATE_602_RESULTS := $(BUILD_DIR)/fpu/estimate-602-results.txt
$(PPC_FPU_ESTIMATE_602_BUILD)/Vtb_ppc_fpu_estimates: $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
	$(VERILATOR) --binary --timing --assert -Wall -j 2 "-GCPU_602=1'b1" --top-module tb_ppc_fpu_estimates --Mdir $(PPC_FPU_ESTIMATE_602_BUILD) $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv

$(PPC_FPU_ESTIMATE_602_VECTORS): fpu/estimate_vectors_602.py fpu/production_vectors_602.py fpu/estimate_vectors.py fpu/reference.py
	mkdir -p $(BUILD_DIR)/fpu
	python3 fpu/estimate_vectors_602.py generate --vectors $@ --random 512

test-fpu-estimates-602: $(PPC_FPU_ESTIMATE_602_BUILD)/Vtb_ppc_fpu_estimates $(PPC_FPU_ESTIMATE_602_VECTORS)
	./$(PPC_FPU_ESTIMATE_602_BUILD)/Vtb_ppc_fpu_estimates +VECTORS=$(PPC_FPU_ESTIMATE_602_VECTORS) +OUTPUT=$(PPC_FPU_ESTIMATE_602_RESULTS)
	python3 fpu/estimate_vectors_602.py compare --vectors $(PPC_FPU_ESTIMATE_602_VECTORS) --results $(PPC_FPU_ESTIMATE_602_RESULTS)

lint-fpu-estimates-602:
	$(VERILATOR) --lint-only --timing -Wall "-GCPU_602=1'b1" --top-module tb_ppc_fpu_estimates $(PPC_FPU_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv

lint: lint-fpu-estimates-602

.PHONY: test-fpu-rsqrt-table test-fpu
test-fpu-rsqrt-table:
	python3 ../rtl/fpu/ppc_fpu_arith_rsqrt_table.py

test-fpu: test-fpu-rsqrt-table test-fpu-arith test-fpu-estimates test-fpu-shell

.PHONY: test-fpu-all
test-fpu-all: test-fpu test-fpu-arith-602 test-fpu-estimates-602 \
	test-fpu-arith-cluster test-fpu-arith-cluster-602 \
	test-fpu-enabled-603 test-fpu-enabled-602 test-fpu-oracle-host \
	test-fpu-602 test-fpu-timing-603 test-fpu-timing-602 \
	test-fpu-stream-603 test-fpu-stream-602 \
	test-fpu-dual-603 test-fpu-dual-602

.PHONY: lint-fpu-production
lint-fpu-production:
	$(VERILATOR) --lint-only -Wall --top-module ppc_fpu $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL)
	$(VERILATOR) --lint-only -Wall "-GCPU_602=1'b1" --top-module ppc_fpu $(PPC_FPU_ARITH_RTL) $(PPC_FPU_SHELL_RTL)

lint: lint-fpu-production

# FPU_IMPL=COMPACT: the same numerical and architectural benches against
# ppc_fpu_compact and ppc_fpu_arith_compact (+define+FPU_COMPACT). Benches that
# need overlapped instructions or Table 6-5 cycle counts stay FULL only.
.PHONY: test-fpu-compact lint-fpu-compact test-fpu-testfloat-compact
.PHONY: test-fpu-compact-arith test-fpu-compact-arith-602
.PHONY: test-fpu-compact-cluster test-fpu-compact-cluster-602
.PHONY: test-fpu-compact-estimates test-fpu-compact-estimates-602
.PHONY: test-fpu-compact-shell test-fpu-compact-602
.PHONY: test-fpu-compact-enabled-603 test-fpu-compact-enabled-602
.PHONY: test-fpu-testfloat-compact-603 test-fpu-testfloat-compact-602
PPC_FPU_COMPACT_ARITH_RTL := $(PPC_FPU_ARITH_RTL) ../rtl/fpu/ppc_fpu_arith_compact.sv
PPC_FPU_COMPACT_RTL := $(PPC_FPU_COMPACT_ARITH_RTL) ../rtl/fpu/ppc_fpu_shell_pkg.sv ../rtl/ppc_ram_lut.sv ../rtl/fpu/ppc_fpu_compact.sv
PPC_FPU_COMPACT_BUILD := $(BUILD_DIR)/ppc-fpu-compact
COMPACT_VERILATE := $(VERILATOR) --binary --timing --assert -Wall -j 2 +define+FPU_COMPACT
$(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith: $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b0" --top-module tb_ppc_fpu_arith --Mdir $(@D) $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
$(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith: $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b1" --top-module tb_ppc_fpu_arith --Mdir $(@D) $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_arith.sv
$(PPC_FPU_COMPACT_BUILD)-estimates-603/Vtb_ppc_fpu_estimates: $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b0" --top-module tb_ppc_fpu_estimates --Mdir $(@D) $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
$(PPC_FPU_COMPACT_BUILD)-estimates-602/Vtb_ppc_fpu_estimates: $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b1" --top-module tb_ppc_fpu_estimates --Mdir $(@D) $(PPC_FPU_COMPACT_ARITH_RTL) fpu/tb_ppc_fpu_estimates.sv
$(PPC_FPU_COMPACT_BUILD)-shell/Vtb_ppc_fpu_shell: $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_shell.sv
	$(COMPACT_VERILATE) --top-module tb_ppc_fpu_shell --Mdir $(@D) $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_shell.sv
$(PPC_FPU_COMPACT_BUILD)-602/Vtb_ppc_fpu_602: $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_602.sv
	$(COMPACT_VERILATE) --top-module tb_ppc_fpu_602 --Mdir $(@D) $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_602.sv
$(PPC_FPU_COMPACT_BUILD)-enabled-603/Vtb_ppc_fpu_enabled: $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_enabled.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b0" --top-module tb_ppc_fpu_enabled --Mdir $(@D) $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_enabled.sv
$(PPC_FPU_COMPACT_BUILD)-enabled-602/Vtb_ppc_fpu_enabled: $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_enabled.sv
	$(COMPACT_VERILATE) "-GCPU_602=1'b1" --top-module tb_ppc_fpu_enabled --Mdir $(@D) $(PPC_FPU_COMPACT_RTL) fpu/tb_ppc_fpu_enabled.sv
test-fpu-compact-arith: test-fpu-reference $(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith $(PPC_FPU_ARITH_ALL)
	./$(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_ARITH_ALL)
test-fpu-compact-arith-602: test-fpu-reference $(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith $(PPC_FPU_ARITH_602_VECTORS)
	./$(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_ARITH_602_VECTORS)
test-fpu-compact-cluster: $(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith $(PPC_FPU_CLUSTER_603)
	./$(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_CLUSTER_603)
test-fpu-compact-cluster-602: $(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith $(PPC_FPU_CLUSTER_602)
	./$(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith +VECTORS=$(PPC_FPU_CLUSTER_602)
test-fpu-compact-estimates: $(PPC_FPU_COMPACT_BUILD)-estimates-603/Vtb_ppc_fpu_estimates $(PPC_FPU_ESTIMATE_VECTORS)
	./$(PPC_FPU_COMPACT_BUILD)-estimates-603/Vtb_ppc_fpu_estimates +VECTORS=$(PPC_FPU_ESTIMATE_VECTORS) +OUTPUT=$(BUILD_DIR)/fpu/estimate-compact-results.txt
	python3 fpu/estimate_vectors.py compare --vectors $(PPC_FPU_ESTIMATE_VECTORS) --results $(BUILD_DIR)/fpu/estimate-compact-results.txt
test-fpu-compact-estimates-602: $(PPC_FPU_COMPACT_BUILD)-estimates-602/Vtb_ppc_fpu_estimates $(PPC_FPU_ESTIMATE_602_VECTORS)
	./$(PPC_FPU_COMPACT_BUILD)-estimates-602/Vtb_ppc_fpu_estimates +VECTORS=$(PPC_FPU_ESTIMATE_602_VECTORS) +OUTPUT=$(BUILD_DIR)/fpu/estimate-compact-602-results.txt
	python3 fpu/estimate_vectors_602.py compare --vectors $(PPC_FPU_ESTIMATE_602_VECTORS) --results $(BUILD_DIR)/fpu/estimate-compact-602-results.txt
test-fpu-compact-shell: $(PPC_FPU_COMPACT_BUILD)-shell/Vtb_ppc_fpu_shell
	./$(PPC_FPU_COMPACT_BUILD)-shell/Vtb_ppc_fpu_shell
test-fpu-compact-602: $(PPC_FPU_COMPACT_BUILD)-602/Vtb_ppc_fpu_602
	./$(PPC_FPU_COMPACT_BUILD)-602/Vtb_ppc_fpu_602
test-fpu-compact-enabled-603: $(PPC_FPU_COMPACT_BUILD)-enabled-603/Vtb_ppc_fpu_enabled $(PPC_FPU_ENABLED_603)
	./$(PPC_FPU_COMPACT_BUILD)-enabled-603/Vtb_ppc_fpu_enabled +VECTORS=$(PPC_FPU_ENABLED_603)
test-fpu-compact-enabled-602: $(PPC_FPU_COMPACT_BUILD)-enabled-602/Vtb_ppc_fpu_enabled $(PPC_FPU_ENABLED_602)
	./$(PPC_FPU_COMPACT_BUILD)-enabled-602/Vtb_ppc_fpu_enabled +VECTORS=$(PPC_FPU_ENABLED_602)
test-fpu-compact: test-fpu-compact-arith test-fpu-compact-arith-602 \
	test-fpu-compact-cluster test-fpu-compact-cluster-602 \
	test-fpu-compact-estimates test-fpu-compact-estimates-602 \
	test-fpu-compact-shell test-fpu-compact-602 \
	test-fpu-compact-enabled-603 test-fpu-compact-enabled-602
test-fpu-all: test-fpu-compact
test-fpu-testfloat-compact-603: $(TESTFLOAT_GEN) $(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith
	python3 fpu/testfloat_vectors.py --gen $(TESTFLOAT_GEN) --personality 603e --fused-stride $(TESTFLOAT_FUSED_STRIDE) --vectors $(BUILD_DIR)/fpu/testfloat-compact-603.txt
	./$(PPC_FPU_COMPACT_BUILD)-arith-603/Vtb_ppc_fpu_arith +VECTORS=$(BUILD_DIR)/fpu/testfloat-compact-603.txt
	rm -f $(BUILD_DIR)/fpu/testfloat-compact-603.txt
test-fpu-testfloat-compact-602: $(TESTFLOAT_GEN) $(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith
	python3 fpu/testfloat_vectors.py --gen $(TESTFLOAT_GEN) --personality 602 --fused-stride $(TESTFLOAT_FUSED_STRIDE) --vectors $(BUILD_DIR)/fpu/testfloat-compact-602.txt
	./$(PPC_FPU_COMPACT_BUILD)-arith-602/Vtb_ppc_fpu_arith +VECTORS=$(BUILD_DIR)/fpu/testfloat-compact-602.txt
	rm -f $(BUILD_DIR)/fpu/testfloat-compact-602.txt
test-fpu-testfloat-compact: test-fpu-testfloat-compact-603 test-fpu-testfloat-compact-602
test-fpu-testfloat: test-fpu-testfloat-compact
lint-fpu-compact:
	$(VERILATOR) --lint-only -Wall --top-module ppc_fpu_compact $(PPC_FPU_COMPACT_RTL)
	$(VERILATOR) --lint-only -Wall "-GCPU_602=1'b1" --top-module ppc_fpu_compact $(PPC_FPU_COMPACT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_fpu_arith_compact $(PPC_FPU_COMPACT_ARITH_RTL)
	$(VERILATOR) --lint-only -Wall "-GCPU_602=1'b1" --top-module ppc_fpu_arith_compact $(PPC_FPU_COMPACT_ARITH_RTL)
lint: lint-fpu-compact

test-core:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core --Mdir $(BUILD_DIR) $(RTL) ../tb/tb_core.sv
	./$(BUILD_DIR)/Vtb_core $(SIM_ARGS)
test-completion:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion --Mdir $(BUILD_DIR)/completion ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion.sv
	./$(BUILD_DIR)/completion/Vtb_completion $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_pair --Mdir $(BUILD_DIR)/completion-pair ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion_pair.sv
	./$(BUILD_DIR)/completion-pair/Vtb_completion_pair $(SIM_ARGS)
test-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_execution --Mdir $(BUILD_DIR)/execution ../rtl/ppc_pkg.sv ../rtl/ppc_rename.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_execution.sv
	./$(BUILD_DIR)/execution/Vtb_execution $(SIM_ARGS)
test-stage:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_stage_timing --Mdir $(BUILD_DIR)/stage $(RTL) ../tb/tb_stage_timing.sv
	./$(BUILD_DIR)/stage/Vtb_stage_timing $(SIM_ARGS) +TRACE=$(BUILD_DIR)/stage/trace.jsonl +DISPATCH_TRACE=$(BUILD_DIR)/stage/events.txt
	python3 tools/check_stage_timing.py $(BUILD_DIR)/stage/trace.jsonl
	python3 tools/check_dispatch_trace.py $(BUILD_DIR)/stage/events.txt spec/schedules/stage.txt --stage $(BUILD_DIR)/stage/trace.jsonl
check-spec:
	python3 tools/check_licence.py
	python3 spec/check_timing.py
	python3 spec/check_bus.py
	python3 tools/bus_address.py validate
	python3 tools/isa_generate.py --check
	python3 tools/check_stage_timing.py
	python3 -m unittest discover -s tools -p 'test_*.py'
	python3 -m unittest discover -s cosim -p 'test_*.py'
	python3 ../quartus/qsf_sources.py --check ../quartus ../quartus/integrated ../quartus/timer-bat ../quartus/translated ../quartus/icache ../quartus/dcache ../quartus/chip ../quartus/chip602 ../quartus/demo
test-recovery:
	python3 -m unittest discover -s recovery -p 'test_*.py'
test-recovery-select:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_select --Mdir $(BUILD_DIR)/recovery-select ../rtl/ppc_pkg.sv recovery/rtl/ppc_recovery_select.sv ../tb/tb_recovery_select.sv
	./$(BUILD_DIR)/recovery-select/Vtb_recovery_select $(SIM_ARGS)
test-recovery-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_execution --Mdir $(BUILD_DIR)/recovery-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_recovery_execution.sv
	./$(BUILD_DIR)/recovery-execution/Vtb_recovery_execution $(SIM_ARGS)
test-recovery-state:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_state --Mdir $(BUILD_DIR)/recovery-state ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_rename.sv ../tb/tb_recovery_state.sv
	./$(BUILD_DIR)/recovery-state/Vtb_recovery_state $(SIM_ARGS)
test-core-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_recovery --Mdir $(BUILD_DIR)/core-recovery $(RTL) ../tb/tb_core_recovery.sv
	./$(BUILD_DIR)/core-recovery/Vtb_core_recovery $(SIM_ARGS)
# Two-word fetch into the shifting IQ; both widths must retire the same stream.
.PHONY: test-core-dual
test: test-core-dual
# One program at dispatch widths 1 and 2: the pair rules at width 2 and the
# same retirement stream at both.
test-core-dual:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_dual -GDISPATCH_WIDTH=1 --Mdir $(BUILD_DIR)/core-dual-w1 $(RTL) ../tb/tb_core_dual.sv
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_dual -GDISPATCH_WIDTH=2 --Mdir $(BUILD_DIR)/core-dual-w2 $(RTL) ../tb/tb_core_dual.sv
	./$(BUILD_DIR)/core-dual-w1/Vtb_core_dual $(SIM_ARGS) +RETIRE_LOG=$(BUILD_DIR)/core-dual-w1/retire.txt
	./$(BUILD_DIR)/core-dual-w2/Vtb_core_dual $(SIM_ARGS) +RETIRE_LOG=$(BUILD_DIR)/core-dual-w2/retire.txt
	cmp $(BUILD_DIR)/core-dual-w1/retire.txt $(BUILD_DIR)/core-dual-w2/retire.txt
	@echo "PASS: widths 1 and 2 retire $$(wc -l < $(BUILD_DIR)/core-dual-w1/retire.txt) identical packets"
.PHONY: test-core-fetch2
test: test-core-fetch2
test-core-fetch2:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch2 -GFETCH_WIDTH=1 --Mdir $(BUILD_DIR)/core-fetch2-w1 $(RTL) ../tb/tb_core_fetch2.sv
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch2 -GFETCH_WIDTH=2 --Mdir $(BUILD_DIR)/core-fetch2-w2 $(RTL) ../tb/tb_core_fetch2.sv
	./$(BUILD_DIR)/core-fetch2-w1/Vtb_core_fetch2 $(SIM_ARGS) +RETIRE_LOG=$(BUILD_DIR)/core-fetch2-w1/retire.txt
	./$(BUILD_DIR)/core-fetch2-w2/Vtb_core_fetch2 $(SIM_ARGS) +RETIRE_LOG=$(BUILD_DIR)/core-fetch2-w2/retire.txt
	cmp $(BUILD_DIR)/core-fetch2-w1/retire.txt $(BUILD_DIR)/core-fetch2-w2/retire.txt
	@echo "PASS: widths 1 and 2 retire $$(wc -l < $(BUILD_DIR)/core-fetch2-w1/retire.txt) identical packets"
test-fetch-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_fetch_recovery --Mdir $(BUILD_DIR)/fetch-recovery ../rtl/ppc_pkg.sv ../rtl/ppc_fetch.sv ../tb/tb_fetch_recovery.sv
	./$(BUILD_DIR)/fetch-recovery/Vtb_fetch_recovery $(SIM_ARGS)
test-core-logical:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_logical --Mdir $(BUILD_DIR)/core-logical $(RTL) ../tb/tb_core_logical.sv
	./$(BUILD_DIR)/core-logical/Vtb_core_logical $(SIM_ARGS)
test-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_flags --Mdir $(BUILD_DIR)/flags ../rtl/ppc_pkg.sv ../rtl/ppc_flags.sv ../tb/tb_flags.sv
	./$(BUILD_DIR)/flags/Vtb_flags $(SIM_ARGS)
test-completion-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_flags --Mdir $(BUILD_DIR)/completion-flags ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_flags.sv
	./$(BUILD_DIR)/completion-flags/Vtb_completion_flags $(SIM_ARGS)
test-record-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_record_execution --Mdir $(BUILD_DIR)/record-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_record_execution.sv
	./$(BUILD_DIR)/record-execution/Vtb_record_execution $(SIM_ARGS)
test-core-record-logical:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_record_logical --Mdir $(BUILD_DIR)/core-record-logical $(RTL) ../tb/tb_core_record_logical.sv
	./$(BUILD_DIR)/core-record-logical/Vtb_core_record_logical $(SIM_ARGS)
test-core-record-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_record_edges --Mdir $(BUILD_DIR)/core-record-edges $(RTL) ../tb/tb_core_record_edges.sv
	./$(BUILD_DIR)/core-record-edges/Vtb_core_record_edges $(SIM_ARGS)
test-core-add-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_flags --Mdir $(BUILD_DIR)/core-add-flags $(RTL) ../tb/tb_core_add_flags.sv
	./$(BUILD_DIR)/core-add-flags/Vtb_core_add_flags $(SIM_ARGS)
test-core-add-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=add $(SIM_ARGS)
test-add-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_add_execution --Mdir $(BUILD_DIR)/add-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_add_execution.sv
	./$(BUILD_DIR)/add-execution/Vtb_add_execution $(SIM_ARGS)
test-core-adde:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_adde --Mdir $(BUILD_DIR)/core-adde $(RTL) ../tb/tb_core_adde.sv
	./$(BUILD_DIR)/core-adde/Vtb_core_adde $(SIM_ARGS)
test-core-adde-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=adde $(SIM_ARGS)
test-adde-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_adde_execution --Mdir $(BUILD_DIR)/adde-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_adde_execution.sv
	./$(BUILD_DIR)/adde-execution/Vtb_adde_execution $(SIM_ARGS)
test-core-add-unary:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_unary --Mdir $(BUILD_DIR)/core-add-unary $(RTL) ../tb/tb_core_add_unary.sv
	./$(BUILD_DIR)/core-add-unary/Vtb_core_add_unary $(SIM_ARGS)
test-add-unary-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_add_unary_execution --Mdir $(BUILD_DIR)/add-unary-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_add_unary_execution.sv
	./$(BUILD_DIR)/add-unary-execution/Vtb_add_unary_execution $(SIM_ARGS)
test-addme-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=addme $(SIM_ARGS)
test-addze-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=addze $(SIM_ARGS)
clean:
	rm -rf $(BUILD_DIR)

# Run only after builds finish; subsequent compilation regenerates these caches.
.PHONY: clean-cache
clean-cache:
	python3 tools/clean_cache.py --build-dir "$(BUILD_DIR)"

test-core-rotate:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_rotate --Mdir $(BUILD_DIR)/core-rotate $(RTL) ../tb/tb_core_rotate.sv
	./$(BUILD_DIR)/core-rotate/Vtb_core_rotate $(SIM_ARGS)

test-rotate-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_rotate_execution --Mdir $(BUILD_DIR)/rotate-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_rotate_execution.sv
	python3 tools/rotate_vectors.py --output $(BUILD_DIR)/rotate-execution/vectors.txt
	./$(BUILD_DIR)/rotate-execution/Vtb_rotate_execution $(SIM_ARGS) +VECTORS=$(BUILD_DIR)/rotate-execution/vectors.txt

test-core-control-memory: build-control-memory
	python3 tools/control_memory_program.py --output $(BUILD_DIR)/control-memory
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/control-memory

test-core-memory-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_memory_edges --Mdir $(BUILD_DIR)/memory-edges $(RTL) ../tb/tb_core_memory_edges.sv
	./$(BUILD_DIR)/memory-edges/Vtb_core_memory_edges $(SIM_ARGS)

test-core-shifts: build-control-memory
	python3 tools/control_memory_program.py --shifts --output $(BUILD_DIR)/logical-shifts
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/logical-shifts

test-shift-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_shift_execution --Mdir $(BUILD_DIR)/shift-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_shift_execution.sv
	./$(BUILD_DIR)/shift-execution/Vtb_shift_execution $(SIM_ARGS)

test-slw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=slw $(SIM_ARGS)

test-srw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=srw $(SIM_ARGS)

.PHONY: test-core-arithmetic-shifts test-arithmetic-shift-execution test-sraw-recovery test-srawi-recovery
test-core-arithmetic-shifts: build-control-memory
	python3 tools/control_memory_program.py --arithmetic-shifts --output $(BUILD_DIR)/arithmetic-shifts
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/arithmetic-shifts

test-arithmetic-shift-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_arithmetic_shift_execution --Mdir $(BUILD_DIR)/arithmetic-shift-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_arithmetic_shift_execution.sv
	./$(BUILD_DIR)/arithmetic-shift-execution/Vtb_arithmetic_shift_execution $(SIM_ARGS)

test-sraw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=sraw $(SIM_ARGS)

test-srawi-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=srawi $(SIM_ARGS)

.PHONY: test-core-insert test-insert-execution test-insert-recovery
test-core-insert: build-control-memory
	python3 tools/control_memory_program.py --insert --output $(BUILD_DIR)/insert
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/insert

test-insert-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_insert_execution --Mdir $(BUILD_DIR)/insert-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_insert_execution.sv
	./$(BUILD_DIR)/insert-execution/Vtb_insert_execution $(SIM_ARGS)

test-insert-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=insert $(SIM_ARGS)

.PHONY: test-core-branch-recovery
# Mispredicted loop exits with a divide in flight and a dependent chain behind.
test-core-branch-recovery: build-control-memory
	python3 tools/control_memory_program.py --branch-recovery --output $(BUILD_DIR)/branch-recovery
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/branch-recovery

# Folded bclr and bcctr: LR/CTR hazards, mispredictions both ways, linking
# forms; again with two-word fetch and dispatch, where folded branches pair
# from DQ1.
.PHONY: test-core-branch-fold
test: test-core-branch-fold
test-core-branch-fold: build-control-memory
	python3 tools/control_memory_program.py --branch-fold --output $(BUILD_DIR)/branch-fold
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/branch-fold
	mkdir -p $(BUILD_DIR)/control-memory-w2
	$(VERILATOR) --binary --timing --assert -Wall +define+PPC_DISPATCH_WIDTH=2 -GFETCH_WIDTH=2 --top-module tb_core_control_memory --Mdir $(BUILD_DIR)/control-memory-w2 $(RTL) ../tb/tb_core_control_memory.sv
	./$(BUILD_DIR)/control-memory-w2/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/branch-fold

.PHONY: test-core-compare test-compare-execution
test-core-compare: build-control-memory
	python3 tools/control_memory_program.py --compare --output $(BUILD_DIR)/compare
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/compare

test-compare-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_compare_execution --Mdir $(BUILD_DIR)/compare-execution ../rtl/ppc_pkg.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_compare_execution.sv
	./$(BUILD_DIR)/compare-execution/Vtb_compare_execution $(SIM_ARGS)

.PHONY: test-core-subtract test-subtract-execution test-subf-recovery test-neg-recovery
test-core-subtract: build-control-memory
	python3 tools/control_memory_program.py --subtract --output $(BUILD_DIR)/subtract
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/subtract

test-subtract-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subtract_execution --Mdir $(BUILD_DIR)/subtract-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subtract_execution.sv
	./$(BUILD_DIR)/subtract-execution/Vtb_subtract_execution $(SIM_ARGS)

test-subf-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subf $(SIM_ARGS)

test-neg-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=neg $(SIM_ARGS)

.PHONY: test-core-subcarry test-subcarry-execution test-subfc-recovery
test-core-subcarry: build-control-memory
	python3 tools/control_memory_program.py --subcarry --output $(BUILD_DIR)/subcarry
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/subcarry

test-subcarry-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subcarry_execution --Mdir $(BUILD_DIR)/subcarry-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subcarry_execution.sv
	./$(BUILD_DIR)/subcarry-execution/Vtb_subcarry_execution $(SIM_ARGS)

test-subfc-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfc $(SIM_ARGS)

.PHONY: test-core-subextend test-subextend-execution test-subfe-recovery test-subfe-zero-recovery
test-core-subextend: build-control-memory
	python3 tools/control_memory_program.py --subextend --output $(BUILD_DIR)/subextend
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/subextend

test-subextend-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subextend_execution --Mdir $(BUILD_DIR)/subextend-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subextend_execution.sv
	./$(BUILD_DIR)/subextend-execution/Vtb_subextend_execution $(SIM_ARGS)

test-subfe-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfe $(SIM_ARGS)

test-subfe-zero-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfe-zero $(SIM_ARGS)

.PHONY: test-core-subunary test-subunary-execution test-subfme-recovery test-subfze-recovery
test-core-subunary: build-control-memory
	python3 tools/control_memory_program.py --subunary --output $(BUILD_DIR)/subunary
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/subunary

test-subunary-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subunary_execution --Mdir $(BUILD_DIR)/subunary-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subunary_execution.sv
	./$(BUILD_DIR)/subunary-execution/Vtb_subunary_execution $(SIM_ARGS)

test-subfme-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfme $(SIM_ARGS)

test-subfze-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfze $(SIM_ARGS)

.PHONY: test-core-subimmediate test-subfic-recovery test-subfic-negative-recovery
test-core-subimmediate: build-control-memory
	python3 tools/control_memory_program.py --subimmediate --output $(BUILD_DIR)/subimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/subimmediate

test-subfic-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfic $(SIM_ARGS)

test-subfic-negative-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=subfic-negative $(SIM_ARGS)

.PHONY: test-core-addimmediate test-addic-recovery test-addic-record-recovery
test-core-addimmediate: build-control-memory
	python3 tools/control_memory_program.py --addimmediate --output $(BUILD_DIR)/addimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/addimmediate

test-addic-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=addic $(SIM_ARGS)

test-addic-record-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=addic-record $(SIM_ARGS)

.PHONY: test-core-andimmediate test-andi-recovery test-andis-recovery
test-core-andimmediate: build-control-memory
	python3 tools/control_memory_program.py --andimmediate --output $(BUILD_DIR)/andimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/andimmediate

test-andi-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=andi $(SIM_ARGS)

test-andis-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=andis $(SIM_ARGS)

.PHONY: test-core-unarylogical test-unarylogical-execution test-cntlzw-recovery test-extsb-recovery test-extsh-recovery
test-core-unarylogical: build-control-memory
	python3 tools/control_memory_program.py --unarylogical --output $(BUILD_DIR)/unarylogical
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/unarylogical

test-unarylogical-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_unarylogical_execution --Mdir $(BUILD_DIR)/unarylogical-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_unarylogical_execution.sv
	./$(BUILD_DIR)/unarylogical-execution/Vtb_unarylogical_execution $(SIM_ARGS)

test-cntlzw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=cntlzw $(SIM_ARGS)

test-extsb-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=extsb $(SIM_ARGS)

test-extsh-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=extsh $(SIM_ARGS)

.PHONY: test-unarylogical-decode
test-unarylogical-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_unarylogical_decode --Mdir $(BUILD_DIR)/unarylogical-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_unarylogical_decode.sv
	./$(BUILD_DIR)/unarylogical-decode/Vtb_unarylogical_decode $(SIM_ARGS)

.PHONY: test-core-crtransfer
test-core-crtransfer: build-control-memory
	python3 tools/control_memory_program.py --crtransfer --output $(BUILD_DIR)/crtransfer
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/crtransfer

.PHONY: test-crtransfer-edges
test-crtransfer-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crtransfer_edges --Mdir $(BUILD_DIR)/crtransfer-edges $(RTL) ../tb/tb_core_crtransfer_edges.sv
	./$(BUILD_DIR)/crtransfer-edges/Vtb_core_crtransfer_edges $(SIM_ARGS)

.PHONY: test-completion-cr-fields
test-completion-cr-fields:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_cr_fields --Mdir $(BUILD_DIR)/completion-cr-fields ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_cr_fields.sv
	./$(BUILD_DIR)/completion-cr-fields/Vtb_completion_cr_fields $(SIM_ARGS)

.PHONY: test-crtransfer-decode
test-crtransfer-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crtransfer_decode --Mdir $(BUILD_DIR)/crtransfer-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crtransfer_decode.sv
	./$(BUILD_DIR)/crtransfer-decode/Vtb_crtransfer_decode $(SIM_ARGS)

.PHONY: test-core-crlogical
test-core-crlogical: build-control-memory
	python3 tools/control_memory_program.py --crlogical --output $(BUILD_DIR)/crlogical
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/crlogical

.PHONY: test-crlogical-edges
test-crlogical-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crlogical_edges --Mdir $(BUILD_DIR)/crlogical-edges $(RTL) ../tb/tb_core_crlogical_edges.sv
	./$(BUILD_DIR)/crlogical-edges/Vtb_core_crlogical_edges $(SIM_ARGS)

.PHONY: test-completion-cr-bits
test-completion-cr-bits:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_cr_bits --Mdir $(BUILD_DIR)/completion-cr-bits ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_cr_bits.sv
	./$(BUILD_DIR)/completion-cr-bits/Vtb_completion_cr_bits $(SIM_ARGS)

.PHONY: test-crlogical-decode
test-crlogical-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crlogical_decode --Mdir $(BUILD_DIR)/crlogical-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crlogical_decode.sv
	./$(BUILD_DIR)/crlogical-decode/Vtb_crlogical_decode $(SIM_ARGS)

.PHONY: test-core-crstate test-crstate-edges
test-core-crstate: build-control-memory
	python3 tools/control_memory_program.py --crstate --output $(BUILD_DIR)/crstate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/crstate

test-crstate-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crstate_edges --Mdir $(BUILD_DIR)/crstate-edges $(RTL) ../tb/tb_core_crstate_edges.sv
	./$(BUILD_DIR)/crstate-edges/Vtb_core_crstate_edges $(SIM_ARGS)

.PHONY: test-crstate-decode
test-crstate-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crstate_decode --Mdir $(BUILD_DIR)/crstate-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crstate_decode.sv
	./$(BUILD_DIR)/crstate-decode/Vtb_crstate_decode $(SIM_ARGS)

.PHONY: test-crstate-execution
test-crstate-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crstate_execution --Mdir $(BUILD_DIR)/crstate-execution $(EXCEPTION_RTL) ../rtl/fpu/ppc_fpu_pkg.sv ../rtl/ppc_timer.sv ../rtl/ppc_miss_derive.sv ../rtl/ppc_watchdog.sv ../rtl/ppc_special.sv ../tb/tb_crstate_execution.sv
	./$(BUILD_DIR)/crstate-execution/Vtb_crstate_execution $(SIM_ARGS)

.PHONY: test-core-multiply test-multiply-recovery test-multiply-overflow-recovery
test-core-multiply: build-control-memory
	python3 tools/control_memory_program.py --multiply --output $(BUILD_DIR)/multiply
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/multiply

test-multiply-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=multiply $(SIM_ARGS)

test-multiply-overflow-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=multiply-overflow $(SIM_ARGS)

.PHONY: test-multiply-decode
test-multiply-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_decode --Mdir $(BUILD_DIR)/multiply-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_multiply_decode.sv
	./$(BUILD_DIR)/multiply-decode/Vtb_multiply_decode $(SIM_ARGS)

.PHONY: test-multiply-execution
test-multiply-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_execution --Mdir $(BUILD_DIR)/multiply-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_multiply_execution.sv
	./$(BUILD_DIR)/multiply-execution/Vtb_multiply_execution $(SIM_ARGS)

.PHONY: test-core-multiply-high test-mulhw-recovery test-mulhwu-recovery
test-core-multiply-high: build-control-memory
	python3 tools/control_memory_program.py --multiply-high --output $(BUILD_DIR)/multiply-high
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/multiply-high

test-mulhw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=mulhw $(SIM_ARGS)

test-mulhwu-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=mulhwu $(SIM_ARGS)

.PHONY: test-multiply-high-decode
test-multiply-high-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_high_decode --Mdir $(BUILD_DIR)/multiply-high-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_multiply_high_decode.sv
	./$(BUILD_DIR)/multiply-high-decode/Vtb_multiply_high_decode $(SIM_ARGS)

.PHONY: test-multiply-high-execution
test-multiply-high-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_high_execution --Mdir $(BUILD_DIR)/multiply-high-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_multiply_high_execution.sv
	./$(BUILD_DIR)/multiply-high-execution/Vtb_multiply_high_execution $(SIM_ARGS)

.PHONY: test-core-divide-unsigned test-divwu-recovery test-divwu-zero-recovery
test-core-divide-unsigned: build-control-memory
	python3 tools/control_memory_program.py --divide-unsigned --output $(BUILD_DIR)/divide-unsigned
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/divide-unsigned

test-divwu-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=divwu $(SIM_ARGS)

test-divwu-zero-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=divwu-zero $(SIM_ARGS)

.PHONY: test-divwu-decode
test-divwu-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divwu_decode --Mdir $(BUILD_DIR)/divwu-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_divwu_decode.sv
	./$(BUILD_DIR)/divwu-decode/Vtb_divwu_decode $(SIM_ARGS)

.PHONY: test-divwu-execution
test-divwu-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divwu_execution --Mdir $(BUILD_DIR)/divwu-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divwu_execution.sv
	./$(BUILD_DIR)/divwu-execution/Vtb_divwu_execution $(SIM_ARGS)

.PHONY: test-core-divide-signed test-divw-recovery test-divw-zero-recovery test-divw-overflow-recovery
test-core-divide-signed: build-control-memory
	python3 tools/control_memory_program.py --divide-signed --output $(BUILD_DIR)/divide-signed
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/divide-signed

test-divw-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=divw $(SIM_ARGS)

test-divw-zero-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=divw-zero $(SIM_ARGS)

test-divw-overflow-recovery: build-core-add-recovery
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery +case=divw-overflow $(SIM_ARGS)

.PHONY: test-divw-decode
test-divw-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divw_decode --Mdir $(BUILD_DIR)/divw-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_divw_decode.sv
	./$(BUILD_DIR)/divw-decode/Vtb_divw_decode $(SIM_ARGS)

.PHONY: test-divw-execution
test-divw-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divw_execution --Mdir $(BUILD_DIR)/divw-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divw_execution.sv
	./$(BUILD_DIR)/divw-execution/Vtb_divw_execution $(SIM_ARGS)

.PHONY: test-core-lsu-update test-core-bus60x test-core-bus60x-update
test-core-lsu-update: build-control-memory
	python3 tools/control_memory_program.py --lsu-update --output $(BUILD_DIR)/lsu-update
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/lsu-update
test-core-bus60x: build-core-bus60x
	python3 tools/control_memory_program.py --output $(BUILD_DIR)/bus60x-program
	./$(BUILD_DIR)/core-bus60x/Vtb_core_bus60x $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/bus60x-program
test-core-bus60x-update: build-core-bus60x
	python3 tools/control_memory_program.py --lsu-update --output $(BUILD_DIR)/bus60x-update-program
	./$(BUILD_DIR)/core-bus60x/Vtb_core_bus60x $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/bus60x-update-program

.PHONY: test-reference reference-checkout reference-runner-flat reference-update
# Reference targets need a DingusPPC checkout beside this repository; track its latest commit.
REFERENCE_DIR := ../../dingusppc
REFERENCE_ARGS = --verilator $(VERILATOR_TOOL) $(XRAND_REFERENCE_ARGS)
FLAT_REFERENCE_ARGS = $(REFERENCE_ARGS) --reference-runner-dir $(BUILD_DIR)/reference-runner-flat
reference-checkout:
	@test -f $(REFERENCE_DIR)/cpu/ppc/ppcopcodes.cpp || { \
		echo "ERROR: reference targets (and regression) need a DingusPPC checkout at $(abspath $(REFERENCE_DIR)); see docs/REFERENCE_RUNNER.md" >&2; exit 2; }
# Fast-forward the DingusPPC checkout and print the range it moved over.
reference-update: reference-checkout
	@old=$$(git -C $(REFERENCE_DIR) rev-parse --short HEAD); git -C $(REFERENCE_DIR) pull --ff-only && \
		new=$$(git -C $(REFERENCE_DIR) rev-parse --short HEAD) && echo "DingusPPC $$old..$$new" && \
		git -C $(REFERENCE_DIR) log --oneline $$old..$$new
# One flat-RAM runner build shared by every memory reference target.
reference-runner-flat: reference-checkout
	python3 cosim/build_reference_runner.py --build-dir $(BUILD_DIR)/reference-runner-flat
test-reference: reference-checkout
	python3 cosim/run_reference.py --build-dir $(BUILD_DIR)/reference $(REFERENCE_ARGS)

.PHONY: test-lsu-update-decode test-completion-update test-lsu-update-edges test-bus60x
.PHONY: test-lsu-extensions-decode
test: test-lsu-extensions-decode
test-lsu-extensions-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_lsu_extensions_decode --Mdir $(BUILD_DIR)/lsu-extensions-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_lsu_extensions_decode.sv
	./$(BUILD_DIR)/lsu-extensions-decode/Vtb_lsu_extensions_decode $(SIM_ARGS)
test-lsu-update-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_lsu_update_decode --Mdir $(BUILD_DIR)/lsu-update-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_lsu_update_decode.sv
	./$(BUILD_DIR)/lsu-update-decode/Vtb_lsu_update_decode $(SIM_ARGS)
test-completion-update:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_update --Mdir $(BUILD_DIR)/completion-update ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion_update.sv
	./$(BUILD_DIR)/completion-update/Vtb_completion_update $(SIM_ARGS)
test-lsu-update-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_lsu_update_edges --Mdir $(BUILD_DIR)/lsu-update-edges $(RTL) ../tb/tb_lsu_update_edges.sv
	./$(BUILD_DIR)/lsu-update-edges/Vtb_lsu_update_edges $(SIM_ARGS)
test-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x --Mdir $(BUILD_DIR)/bus60x $(BUS_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_bus60x.sv
	./$(BUILD_DIR)/bus60x/Vtb_bus60x $(SIM_ARGS)

.PHONY: test-core-bus60x-unified test-core-bus60x-unified-update
test-core-bus60x-unified: build-core-bus60x-unified
	python3 tools/control_memory_program.py --memory-base 0x6000 --output $(BUILD_DIR)/bus60x-unified-program
	./$(BUILD_DIR)/core-bus60x-unified/Vtb_core_bus60x_unified $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/bus60x-unified-program
test-core-bus60x-unified-update: build-core-bus60x-unified
	python3 tools/control_memory_program.py --lsu-update --memory-base 0x6000 --output $(BUILD_DIR)/bus60x-unified-update-program
	./$(BUILD_DIR)/core-bus60x-unified/Vtb_core_bus60x_unified $(SIM_ARGS) +PROGRAM_DIR=$(BUILD_DIR)/bus60x-unified-update-program

.PHONY: test-bus60x-arbiter test-core-bus60x-ifetch-error test-divider-timing
test-bus60x-arbiter:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_arbiter --Mdir $(BUILD_DIR)/bus60x-arbiter ../rtl/ppc_bus60x_arbiter.sv ../tb/tb_bus60x_arbiter.sv
	./$(BUILD_DIR)/bus60x-arbiter/Vtb_bus60x_arbiter $(SIM_ARGS)
test-core-bus60x-ifetch-error:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_ifetch_error --Mdir $(BUILD_DIR)/core-bus60x-ifetch-error $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_ifetch_error.sv
	./$(BUILD_DIR)/core-bus60x-ifetch-error/Vtb_core_bus60x_ifetch_error $(SIM_ARGS)
test-divider-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divider_timing --Mdir $(BUILD_DIR)/divider-timing ../rtl/ppc_pkg.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divider_timing.sv
	./$(BUILD_DIR)/divider-timing/Vtb_divider_timing $(SIM_ARGS)

.PHONY: test-core-divider-timing test-core-divider-timing-pid6
test-core-divider-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_divider_timing --Mdir $(BUILD_DIR)/core-divider-timing $(RTL) ../tb/tb_core_divider_timing.sv
	./$(BUILD_DIR)/core-divider-timing/Vtb_core_divider_timing $(SIM_ARGS)
test-core-divider-timing-pid6:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_divider_timing -GVARIANT=1 --Mdir $(BUILD_DIR)/core-divider-timing-pid6 $(RTL) ../tb/tb_core_divider_timing.sv
	./$(BUILD_DIR)/core-divider-timing-pid6/Vtb_core_divider_timing $(SIM_ARGS)

.PHONY: test-line-read-independent
test-line-read-independent:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_line_read_independent --Mdir $(BUILD_DIR)/line-read-independent $(LINE_RTL) ../tb/tb_line_read_independent.sv
	./$(BUILD_DIR)/line-read-independent/Vtb_line_read_independent $(SIM_ARGS)

.PHONY: test-iterative-divider test-bus60x-line-read test-reference-memory
test-iterative-divider:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_iterative_divider --Mdir $(BUILD_DIR)/iterative-divider ../rtl/ppc_divider.sv ../tb/tb_iterative_divider.sv
	./$(BUILD_DIR)/iterative-divider/Vtb_iterative_divider $(SIM_ARGS)
test-bus60x-line-read:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_line_read --Mdir $(BUILD_DIR)/bus60x-line-read $(LINE_RTL) ../tb/bfm/bus60x_line_target_bfm.sv ../tb/tb_bus60x_line_read.sv
	./$(BUILD_DIR)/bus60x-line-read/Vtb_bus60x_line_read $(SIM_ARGS)
test-reference-memory: reference-runner-flat
	python3 cosim/run_memory_reference.py --build-dir $(BUILD_DIR)/reference-memory $(FLAT_REFERENCE_ARGS)
.PHONY: test-reference-lsu
test: test-reference-lsu
test-reference-lsu: reference-checkout
	python3 cosim/run_lsu_reference.py --build-dir $(BUILD_DIR)/reference-lsu $(REFERENCE_ARGS)

.PHONY: test-multiply-timing test-core-multiply-timing test-icache test-icache-bus60x test-reference-stress
test: test-multiply-timing test-core-multiply-timing test-icache test-icache-bus60x test-reference-stress

test-multiply-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_timing --Mdir $(BUILD_DIR)/multiply-timing $(RTL) ../tb/tb_multiply_timing.sv
	./$(BUILD_DIR)/multiply-timing/Vtb_multiply_timing $(SIM_ARGS)

test-core-multiply-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_multiply_timing --Mdir $(BUILD_DIR)/core-multiply-timing $(RTL) ../tb/tb_core_multiply_timing.sv
	./$(BUILD_DIR)/core-multiply-timing/Vtb_core_multiply_timing $(SIM_ARGS)

test-icache:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache --Mdir $(BUILD_DIR)/icache $(ICACHE_RTL) ../tb/tb_icache.sv
	./$(BUILD_DIR)/icache/Vtb_icache $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache -GFETCH_WIDTH=2 --Mdir $(BUILD_DIR)/icache-pair $(ICACHE_RTL) ../tb/tb_icache.sv
	./$(BUILD_DIR)/icache-pair/Vtb_icache $(SIM_ARGS)

test-icache-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache_bus60x --Mdir $(BUILD_DIR)/icache-bus60x $(ICACHE_RTL) $(LINE_RTL) ../tb/tb_icache_bus60x.sv
	./$(BUILD_DIR)/icache-bus60x/Vtb_icache_bus60x $(SIM_ARGS)

test-reference-stress: reference-runner-flat
	python3 cosim/run_reference_stress.py --build-dir $(BUILD_DIR)/reference-stress $(FLAT_REFERENCE_ARGS)

.PHONY: test-bat test-bat-independent test-exception-state test-bus60x-master-select test-core-cached-bus60x test-reference-cached
test: test-bat test-bat-independent test-exception-state test-bus60x-master-select test-core-cached-bus60x test-reference-cached

test-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_translate --Mdir $(BUILD_DIR)/bat $(BAT_RTL) ../tb/tb_bat_translate.sv
	./$(BUILD_DIR)/bat/Vtb_bat_translate $(SIM_ARGS)

test-bat-independent: test-bat
	python3 tools/bat_vectors.py --output $(BUILD_DIR)/bat/vectors.txt
	./$(BUILD_DIR)/bat/Vtb_bat_translate $(SIM_ARGS) +VECTORS=$(BUILD_DIR)/bat/vectors.txt

test-exception-state:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_state --Mdir $(BUILD_DIR)/exception-state $(EXCEPTION_RTL) ../tb/tb_exception_state.sv
	./$(BUILD_DIR)/exception-state/Vtb_exception_state $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_state "-GFULL_DECODE=1'b1" --Mdir $(BUILD_DIR)/exception-state-full-decode $(EXCEPTION_RTL) ../tb/tb_exception_state.sv
	./$(BUILD_DIR)/exception-state-full-decode/Vtb_exception_state $(SIM_ARGS)

test-bus60x-master-select:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_master_select --Mdir $(BUILD_DIR)/bus60x-master-select ../rtl/ppc_bus60x_master_select.sv ../tb/tb_bus60x_master_select.sv
	./$(BUILD_DIR)/bus60x-master-select/Vtb_bus60x_master_select $(SIM_ARGS)

test-core-cached-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cached_bus60x --Mdir $(BUILD_DIR)/core-cached-bus60x $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) ../tb/bfm/bus60x_negedge_target_bfm.sv ../tb/tb_core_cached_bus60x.sv
	./$(BUILD_DIR)/core-cached-bus60x/Vtb_core_cached_bus60x $(SIM_ARGS)

test-reference-cached: reference-runner-flat
	python3 cosim/run_cached_reference.py --build-dir $(BUILD_DIR)/reference-cached $(FLAT_REFERENCE_ARGS)

# Round38 independent BAT transactions and managed transport reference profiles.
.PHONY: test-bat-service test-bat-service-independent test-reference-managed test-reference-cache-disabled
test: test-bat-service test-bat-service-independent test-reference-managed test-reference-cache-disabled

test-bat-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_service --Mdir $(BUILD_DIR)/bat-service $(BAT_SERVICE_RTL) ../tb/tb_bat_service.sv
	./$(BUILD_DIR)/bat-service/Vtb_bat_service $(SIM_ARGS)

test-bat-service-independent: test-bat-service
	python3 tools/bat_service_vectors.py --output $(BUILD_DIR)/bat-service/vectors.txt
	./$(BUILD_DIR)/bat-service/Vtb_bat_service $(SIM_ARGS) +VECTORS=$(BUILD_DIR)/bat-service/vectors.txt

test-reference-managed: reference-runner-flat
	python3 cosim/run_cached_reference.py --cache-profile managed --build-dir $(BUILD_DIR)/reference-managed $(FLAT_REFERENCE_ARGS)

test-reference-cache-disabled: reference-runner-flat
	python3 cosim/run_cached_reference.py --cache-profile disabled --build-dir $(BUILD_DIR)/reference-cache-disabled $(FLAT_REFERENCE_ARGS)

.PHONY: test-icache-managed test-core-cached-managed test-supervisor-decode test-core-supervisor
test: test-icache-managed test-core-cached-managed test-supervisor-decode test-core-supervisor

test-icache-managed:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache_managed --Mdir $(BUILD_DIR)/icache-managed $(ICACHE_RTL) ../rtl/ppc_icache_managed.sv ../tb/tb_icache_managed.sv
	./$(BUILD_DIR)/icache-managed/Vtb_icache_managed $(SIM_ARGS)

test-core-cached-managed:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cached_bus60x_managed --Mdir $(BUILD_DIR)/core-cached-managed $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL) ../tb/bfm/bus60x_negedge_target_bfm.sv ../tb/tb_core_cached_bus60x_managed.sv
	./$(BUILD_DIR)/core-cached-managed/Vtb_core_cached_bus60x_managed $(SIM_ARGS)

test-supervisor-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_supervisor_decode --Mdir $(BUILD_DIR)/supervisor-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_supervisor_decode.sv
	./$(BUILD_DIR)/supervisor-decode/Vtb_supervisor_decode $(SIM_ARGS)

test-core-supervisor:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_supervisor --Mdir $(BUILD_DIR)/core-supervisor $(RTL) ../tb/tb_core_supervisor.sv
	./$(BUILD_DIR)/core-supervisor/Vtb_core_supervisor $(SIM_ARGS)

# Round39: serialized architectural barriers and translated CPU reference.
.PHONY: test-serialization-decode test-core-serialization test-reference-bat
test: test-serialization-decode test-core-serialization test-reference-bat
test-serialization-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_serialization_decode --Mdir $(BUILD_DIR)/serialization-decode $(RTL) ../tb/tb_serialization_decode.sv
	./$(BUILD_DIR)/serialization-decode/Vtb_serialization_decode $(SIM_ARGS)
test-core-serialization:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_serialization --Mdir $(BUILD_DIR)/core-serialization $(RTL) ../tb/tb_core_serialization.sv
	./$(BUILD_DIR)/core-serialization/Vtb_core_serialization $(SIM_ARGS)
test-reference-bat: reference-runner-flat
	python3 cosim/run_bat_reference.py --build-dir $(BUILD_DIR)/reference-bat $(FLAT_REFERENCE_ARGS)

.PHONY: test-tlb-service test-tlb-independent
test: test-tlb-service test-tlb-independent
test-tlb-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_service --Mdir $(BUILD_DIR)/tlb-service $(TLB_SERVICE_RTL) ../tb/tb_tlb_service.sv
	./$(BUILD_DIR)/tlb-service/Vtb_tlb_service $(SIM_ARGS)
test-tlb-independent: test-tlb-service
	python3 tools/tlb_vectors.py --output $(BUILD_DIR)/tlb-service/vectors.txt
	./$(BUILD_DIR)/tlb-service/Vtb_tlb_service $(SIM_ARGS) +VECTORS=$(BUILD_DIR)/tlb-service/vectors.txt

.PHONY: test-bat-memory-router test-core-bat
test: test-bat-memory-router test-core-bat
test-bat-memory-router:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_memory_router --Mdir $(BUILD_DIR)/bat-memory-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_memory_router.sv
	./$(BUILD_DIR)/bat-memory-router/Vtb_bat_memory_router $(SIM_ARGS)
test-core-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat --Mdir $(BUILD_DIR)/core-bat $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_bat.sv
	./$(BUILD_DIR)/core-bat/Vtb_core_bat $(SIM_ARGS)

# Round40: bounded supervisor scratch-register access.
.PHONY: test-sprg-decode test-core-sprg
test: test-sprg-decode test-core-sprg
test-sprg-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_sprg_decode --Mdir $(BUILD_DIR)/sprg-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_sprg_decode.sv
	./$(BUILD_DIR)/sprg-decode/Vtb_sprg_decode $(SIM_ARGS)
test-core-sprg:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sprg --Mdir $(BUILD_DIR)/core-sprg $(RTL) ../tb/tb_core_sprg.sv
	./$(BUILD_DIR)/core-sprg/Vtb_core_sprg $(SIM_ARGS)

.PHONY: test-segment-registers
test: test-segment-registers
test-segment-registers:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_registers --Mdir $(BUILD_DIR)/segment-registers $(SEGMENT_REGISTER_RTL) ../tb/tb_segment_registers.sv
	./$(BUILD_DIR)/segment-registers/Vtb_segment_registers $(SIM_ARGS)

# Supervisor-enabled and default-disabled CPU profiles through physical bus pins.
.PHONY: test-core-bus60x-supervisor test-core-bus60x-supervisor-disabled
test: test-core-bus60x-supervisor test-core-bus60x-supervisor-disabled

test-core-bus60x-supervisor:
	mkdir -p $(BUILD_DIR)/core-bus60x-supervisor
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_supervisor --Mdir $(BUILD_DIR)/core-bus60x-supervisor $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_supervisor.sv
	./$(BUILD_DIR)/core-bus60x-supervisor/Vtb_core_bus60x_supervisor $(SIM_ARGS)

test-core-bus60x-supervisor-disabled:
	mkdir -p $(BUILD_DIR)/core-bus60x-supervisor-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_supervisor "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-bus60x-supervisor-disabled $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_supervisor.sv
	./$(BUILD_DIR)/core-bus60x-supervisor-disabled/Vtb_core_bus60x_supervisor $(SIM_ARGS)

# Precise resumable alignment routing and legacy disabled-profile diagnostics.
.PHONY: test-core-alignment test-core-alignment-disabled
test: test-core-alignment test-core-alignment-disabled
test-core-alignment:
	mkdir -p $(BUILD_DIR)/core-alignment
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment --Mdir $(BUILD_DIR)/core-alignment $(RTL) ../tb/tb_core_alignment.sv
	./$(BUILD_DIR)/core-alignment/Vtb_core_alignment $(SIM_ARGS)

test-core-alignment-disabled:
	mkdir -p $(BUILD_DIR)/core-alignment-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-alignment-disabled $(RTL) ../tb/tb_core_alignment.sv
	./$(BUILD_DIR)/core-alignment-disabled/Vtb_core_alignment $(SIM_ARGS)

# Typed synchronous fetch faults: architectural ISI and explicit diagnostics.
.PHONY: test-core-fetch-fault test-core-fetch-fault-disabled
test: test-core-fetch-fault test-core-fetch-fault-disabled
test-core-fetch-fault:
	mkdir -p $(BUILD_DIR)/core-fetch-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch_fault --Mdir $(BUILD_DIR)/core-fetch-fault $(RTL) ../tb/tb_core_fetch_fault.sv
	./$(BUILD_DIR)/core-fetch-fault/Vtb_core_fetch_fault $(SIM_ARGS)

test-core-fetch-fault-disabled:
	mkdir -p $(BUILD_DIR)/core-fetch-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch_fault "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-fetch-fault-disabled $(RTL) ../tb/tb_core_fetch_fault.sv
	./$(BUILD_DIR)/core-fetch-fault-disabled/Vtb_core_fetch_fault $(SIM_ARGS)

.PHONY: test-recovery-storage
test: test-recovery-storage
test-recovery-storage:
	mkdir -p $(BUILD_DIR)/recovery-storage
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_storage --Mdir $(BUILD_DIR)/recovery-storage ../rtl/ppc_pkg.sv ../rtl/ppc_fifo.sv ../rtl/ppc_rename.sv ../tb/tb_recovery_storage.sv
	./$(BUILD_DIR)/recovery-storage/Vtb_recovery_storage $(SIM_ARGS)

.PHONY: test-bat-memory-router-live
test: test-bat-memory-router-live
test-bat-memory-router-live:
	mkdir -p $(BUILD_DIR)/bat-memory-router-live
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" --Mdir $(BUILD_DIR)/bat-memory-router-live $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_memory_router.sv
	./$(BUILD_DIR)/bat-memory-router-live/Vtb_bat_memory_router $(SIM_ARGS)

.PHONY: test-completion-ring
test: test-completion-ring
test-completion-ring:
	mkdir -p $(BUILD_DIR)/completion-ring
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_ring --Mdir $(BUILD_DIR)/completion-ring ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion_ring.sv
	./$(BUILD_DIR)/completion-ring/Vtb_completion_ring $(SIM_ARGS)

.PHONY: test-core-live-context test-core-live-context-disabled test-core-bat-live-context
test: test-core-live-context test-core-live-context-disabled test-core-bat-live-context
test-core-live-context:
	mkdir -p $(BUILD_DIR)/core-live-context
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context --Mdir $(BUILD_DIR)/core-live-context $(RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-live-context/Vtb_core_live_context $(SIM_ARGS)

test-core-live-context-disabled:
	mkdir -p $(BUILD_DIR)/core-live-context-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context "-GENABLE_LIVE_CONTEXT=1'b0" --Mdir $(BUILD_DIR)/core-live-context-disabled $(RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-live-context-disabled/Vtb_core_live_context $(SIM_ARGS)

test-core-bat-live-context:
	mkdir -p $(BUILD_DIR)/core-bat-live-context
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context "-GUSE_BAT=1'b1" --Mdir $(BUILD_DIR)/core-bat-live-context $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-bat-live-context/Vtb_core_live_context $(SIM_ARGS)

.PHONY: test-live-context-decode
test: test-live-context-decode
test-live-context-decode:
	mkdir -p $(BUILD_DIR)/live-context-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_live_context_decode --Mdir $(BUILD_DIR)/live-context-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_live_context_decode.sv
	./$(BUILD_DIR)/live-context-decode/Vtb_live_context_decode $(SIM_ARGS)

.PHONY: test-core-interrupt test-core-interrupt-disabled
test: test-core-interrupt test-core-interrupt-disabled
test-core-interrupt:
	mkdir -p $(BUILD_DIR)/core-interrupt
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_interrupt --Mdir $(BUILD_DIR)/core-interrupt $(RTL) ../tb/tb_core_interrupt.sv
	./$(BUILD_DIR)/core-interrupt/Vtb_core_interrupt $(SIM_ARGS)

test-core-interrupt-disabled:
	mkdir -p $(BUILD_DIR)/core-interrupt-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_interrupt "-GENABLE_EXTERNAL_INTERRUPTS=1'b0" --Mdir $(BUILD_DIR)/core-interrupt-disabled $(RTL) ../tb/tb_core_interrupt.sv
	./$(BUILD_DIR)/core-interrupt-disabled/Vtb_core_interrupt $(SIM_ARGS)

.PHONY: test-core-alignment-dependencies
test: test-core-alignment-dependencies
test-core-alignment-dependencies:
	mkdir -p $(BUILD_DIR)/core-alignment-dependencies
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment_dependencies --Mdir $(BUILD_DIR)/core-alignment-dependencies $(RTL) ../tb/tb_core_alignment_dependencies.sv
	./$(BUILD_DIR)/core-alignment-dependencies/Vtb_core_alignment_dependencies $(SIM_ARGS)

.PHONY: test-timer-decode
test: test-timer-decode
test-timer-decode:
	mkdir -p $(BUILD_DIR)/timer-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_timer_decode --Mdir $(BUILD_DIR)/timer-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_timer_decode.sv
	./$(BUILD_DIR)/timer-decode/Vtb_timer_decode $(SIM_ARGS)

.PHONY: test-timer test-core-timer-registers
test: test-timer test-core-timer-registers
test-timer:
	mkdir -p $(BUILD_DIR)/timer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_timer --Mdir $(BUILD_DIR)/timer ../rtl/ppc_timer.sv ../tb/tb_timer.sv
	./$(BUILD_DIR)/timer/Vtb_timer $(SIM_ARGS)

test-core-timer-registers:
	mkdir -p $(BUILD_DIR)/core-timer-registers
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_timer_registers --Mdir $(BUILD_DIR)/core-timer-registers $(RTL) ../tb/tb_core_timer_registers.sv
	./$(BUILD_DIR)/core-timer-registers/Vtb_core_timer_registers $(SIM_ARGS)

.PHONY: test-core-timer-events
test: test-core-timer-events
test-core-timer-events:
	mkdir -p $(BUILD_DIR)/core-timer-events
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_timer_events --Mdir $(BUILD_DIR)/core-timer-events $(RTL) ../tb/tb_core_timer_events.sv
	./$(BUILD_DIR)/core-timer-events/Vtb_core_timer_events $(SIM_ARGS)

.PHONY: test-core-xer
test: test-core-xer
test-core-xer:
	mkdir -p $(BUILD_DIR)/core-xer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_xer --Mdir $(BUILD_DIR)/core-xer $(RTL) ../tb/tb_core_xer.sv
	./$(BUILD_DIR)/core-xer/Vtb_core_xer $(SIM_ARGS)

.PHONY: test-core-event-reset
test: test-core-event-reset
test-core-event-reset:
	mkdir -p $(BUILD_DIR)/core-event-reset
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_event_reset --Mdir $(BUILD_DIR)/core-event-reset $(RTL) ../tb/tb_core_event_reset.sv
	./$(BUILD_DIR)/core-event-reset/Vtb_core_event_reset $(SIM_ARGS)

.PHONY: lint-runtime-bat test-bat-runtime-service test-bat-runtime-router test-core-runtime-bat test-core-runtime-bat-privilege test-runtime-bat-decode
lint: lint-runtime-bat
test: test-bat-runtime-service test-bat-runtime-router test-core-runtime-bat test-core-runtime-bat-privilege test-runtime-bat-decode

lint-runtime-bat:
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_service "-GENABLE_RUNTIME_BAT=1'b1" $(BAT_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-bat-runtime-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_runtime_service --Mdir $(BUILD_DIR)/bat-runtime-service $(BAT_SERVICE_RTL) ../tb/tb_bat_runtime_service.sv
	./$(BUILD_DIR)/bat-runtime-service/Vtb_bat_runtime_service $(SIM_ARGS)

test-bat-runtime-router:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_runtime_router --Mdir $(BUILD_DIR)/bat-runtime-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_runtime_router.sv
	./$(BUILD_DIR)/bat-runtime-router/Vtb_bat_runtime_router $(SIM_ARGS)

test-core-runtime-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_runtime_bat --Mdir $(BUILD_DIR)/core-runtime-bat $(RTL) ../tb/tb_core_runtime_bat.sv
	./$(BUILD_DIR)/core-runtime-bat/Vtb_core_runtime_bat $(SIM_ARGS)

test-core-runtime-bat-privilege:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_runtime_bat_privilege --Mdir $(BUILD_DIR)/core-runtime-bat-privilege $(RTL) ../tb/tb_core_runtime_bat_privilege.sv
	./$(BUILD_DIR)/core-runtime-bat-privilege/Vtb_core_runtime_bat_privilege $(SIM_ARGS)

test-runtime-bat-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_runtime_bat_decode --Mdir $(BUILD_DIR)/runtime-bat-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_runtime_bat_decode.sv
	./$(BUILD_DIR)/runtime-bat-decode/Vtb_runtime_bat_decode $(SIM_ARGS)

# Typed synchronous data-protection responses and BAT producer classification.
.PHONY: test-core-data-fault test-core-data-fault-disabled test-bat-data-fault test-bat-data-fault-disabled lint-data-exceptions
test: test-core-data-fault test-core-data-fault-disabled test-bat-data-fault test-bat-data-fault-disabled
lint: lint-data-exceptions
lint-data-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_DATA_EXCEPTIONS=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv

test-core-data-fault:
	mkdir -p $(BUILD_DIR)/core-data-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault --Mdir $(BUILD_DIR)/core-data-fault $(RTL) ../tb/tb_core_data_fault.sv
	./$(BUILD_DIR)/core-data-fault/Vtb_core_data_fault $(SIM_ARGS)

test-core-data-fault-disabled:
	mkdir -p $(BUILD_DIR)/core-data-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-data-fault-disabled $(RTL) ../tb/tb_core_data_fault.sv
	./$(BUILD_DIR)/core-data-fault-disabled/Vtb_core_data_fault $(SIM_ARGS)

test-bat-data-fault:
	mkdir -p $(BUILD_DIR)/bat-data-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_data_fault --Mdir $(BUILD_DIR)/bat-data-fault $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_data_fault.sv
	./$(BUILD_DIR)/bat-data-fault/Vtb_bat_data_fault $(SIM_ARGS)

test-bat-data-fault-disabled:
	mkdir -p $(BUILD_DIR)/bat-data-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_data_fault "-GENABLE_DATA_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/bat-data-fault-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_data_fault.sv
	./$(BUILD_DIR)/bat-data-fault-disabled/Vtb_bat_data_fault $(SIM_ARGS)

.PHONY: test-core-data-fault-cancel
test: test-core-data-fault-cancel
test-core-data-fault-cancel:
	mkdir -p $(BUILD_DIR)/core-data-fault-cancel
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault_cancel --Mdir $(BUILD_DIR)/core-data-fault-cancel $(RTL) ../tb/tb_core_data_fault_cancel.sv
	./$(BUILD_DIR)/core-data-fault-cancel/Vtb_core_data_fault_cancel $(SIM_ARGS)

# Optional CPU-programmed segment register instructions and prepared service path.
.PHONY: lint-segment-integration test-segment-cpu-decode test-core-segment-csr test-core-segment-privilege test-segment-runtime-service test-segment-runtime-router
lint: lint-segment-integration
test: test-segment-cpu-decode test-core-segment-csr test-core-segment-privilege test-segment-runtime-service test-segment-runtime-router
lint-segment-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv

test-segment-cpu-decode:
	mkdir -p $(BUILD_DIR)/segment-cpu-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_cpu_decode --Mdir $(BUILD_DIR)/segment-cpu-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_segment_cpu_decode.sv
	./$(BUILD_DIR)/segment-cpu-decode/Vtb_segment_cpu_decode $(SIM_ARGS)

test-core-segment-csr:
	mkdir -p $(BUILD_DIR)/core-segment-csr
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_segment_csr --Mdir $(BUILD_DIR)/core-segment-csr $(RTL) ../tb/tb_core_segment_csr.sv
	./$(BUILD_DIR)/core-segment-csr/Vtb_core_segment_csr $(SIM_ARGS)

test-core-segment-privilege:
	mkdir -p $(BUILD_DIR)/core-segment-privilege
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_segment_privilege --Mdir $(BUILD_DIR)/core-segment-privilege $(RTL) ../tb/tb_core_segment_privilege.sv
	./$(BUILD_DIR)/core-segment-privilege/Vtb_core_segment_privilege $(SIM_ARGS)

test-segment-runtime-service:
	mkdir -p $(BUILD_DIR)/segment-runtime-service
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_runtime_service --Mdir $(BUILD_DIR)/segment-runtime-service $(SEGMENT_REGISTER_RTL) ../tb/tb_segment_runtime_service.sv
	./$(BUILD_DIR)/segment-runtime-service/Vtb_segment_runtime_service $(SIM_ARGS)

test-segment-runtime-router:
	mkdir -p $(BUILD_DIR)/segment-runtime-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_runtime_router --Mdir $(BUILD_DIR)/segment-runtime-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_segment_runtime_router.sv
	./$(BUILD_DIR)/segment-runtime-router/Vtb_segment_runtime_router $(SIM_ARGS)

# Opt-in BAT-miss -> committed SR snapshot -> prefilled page-TLB lookup.
.PHONY: lint-page-path test-core-page-translation test-page-memory-router
lint: lint-page-path
test: test-core-page-translation test-page-memory-router
lint-page-path:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-core-page-translation:
	mkdir -p $(BUILD_DIR)/core-page-translation
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_translation --Mdir $(BUILD_DIR)/core-page-translation $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_translation.sv
	./$(BUILD_DIR)/core-page-translation/Vtb_core_page_translation $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-page-translation-no-micro-tlb
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_translation "-GENABLE_MICRO_TLB=1'b0" --Mdir $(BUILD_DIR)/core-page-translation-no-micro-tlb $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_translation.sv
	./$(BUILD_DIR)/core-page-translation-no-micro-tlb/Vtb_core_page_translation $(SIM_ARGS)

test-page-memory-router:
	mkdir -p $(BUILD_DIR)/page-memory-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_memory_router --Mdir $(BUILD_DIR)/page-memory-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_memory_router.sv
	./$(BUILD_DIR)/page-memory-router/Vtb_page_memory_router $(SIM_ARGS)

MICRO_TLB_TB := ../tb/tb_micro_tlb_pkg.sv ../tb/tb_micro_tlb_harness.sv ../tb/tb_micro_tlb_router.sv
test: test-micro-tlb-router
test-micro-tlb-router:
	mkdir -p $(BUILD_DIR)/micro-tlb-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_micro_tlb_router --Mdir $(BUILD_DIR)/micro-tlb-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv $(MICRO_TLB_TB)
	./$(BUILD_DIR)/micro-tlb-router/Vtb_micro_tlb_router $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/micro-tlb-router-seed2
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_micro_tlb_router -GSEED=2 -GRANDOM_OPS=900 --Mdir $(BUILD_DIR)/micro-tlb-router-seed2 $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv $(MICRO_TLB_TB)
	./$(BUILD_DIR)/micro-tlb-router-seed2/Vtb_micro_tlb_router $(SIM_ARGS)

# 16-set TLB geometry (602UM 5.4.4: EA16..19 index): service direct tests and
# independent vectors, prepared refill, runtime fill, micro-TLB differential
# and the translated core. The 32-set runs are the targets above.
.PHONY: test-tlb-geometry-16
test: test-tlb-geometry-16
test-tlb-geometry-16:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_service -GTLB_SETS=16 --Mdir $(BUILD_DIR)/tlb-service-16 $(TLB_SERVICE_RTL) ../tb/tb_tlb_service.sv
	./$(BUILD_DIR)/tlb-service-16/Vtb_tlb_service $(SIM_ARGS)
	python3 tools/tlb_vectors.py --sets 16 --output $(BUILD_DIR)/tlb-service-16/vectors.txt
	./$(BUILD_DIR)/tlb-service-16/Vtb_tlb_service $(SIM_ARGS) +VECTORS=$(BUILD_DIR)/tlb-service-16/vectors.txt
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b1" "-GRUNTIME_REFILL=1'b1" -GTLB_SETS=16 --Mdir $(BUILD_DIR)/tlb-prepared-refill-16 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-16/Vtb_tlb_prepared_refill $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_fill_router -GTLB_SETS=16 --Mdir $(BUILD_DIR)/tlb-runtime-fill-router-16 $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_fill_router.sv
	./$(BUILD_DIR)/tlb-runtime-fill-router-16/Vtb_tlb_runtime_fill_router $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_micro_tlb_router -GSEED=2 -GRANDOM_OPS=900 -GTLB_SETS=16 --Mdir $(BUILD_DIR)/micro-tlb-router-16 $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv $(MICRO_TLB_TB)
	./$(BUILD_DIR)/micro-tlb-router-16/Vtb_micro_tlb_router $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_micro_tlb_router -GSEED=3 -GRANDOM_OPS=900 -GTLB_SETS=16 "-GHAS_602=1'b1" --Mdir $(BUILD_DIR)/micro-tlb-router-602 $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv $(MICRO_TLB_TB)
	./$(BUILD_DIR)/micro-tlb-router-602/Vtb_micro_tlb_router $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_translation -GTLB_SETS=16 --Mdir $(BUILD_DIR)/core-page-translation-16 $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_translation.sv
	./$(BUILD_DIR)/core-page-translation-16/Vtb_core_page_translation $(SIM_ARGS)
	if $(VERILATOR) --lint-only -Wall --top-module ppc_tlb_service -GTLB_SETS=64 $(TLB_SERVICE_RTL) > $(BUILD_DIR)/tlb-service-16/reject.log 2>&1; then echo "FAIL: TLB_SETS=64 elaborated"; exit 1; fi
	grep -q "is not a 603e (32) or 602 (16) geometry" $(BUILD_DIR)/tlb-service-16/reject.log
	@echo "PASS: 16-set TLB geometry; TLB_SETS=64 rejected"

# Opt-in supervisor tlbie with retirement-committed four-entry set invalidation.
.PHONY: lint-tlbie-integration test-tlbie-decode test-core-tlbie test-core-tlbie-privilege test-tlb-runtime-invalidate-service test-tlb-runtime-invalidate-router
lint: lint-tlbie-integration
test: test-tlbie-decode test-core-tlbie test-core-tlbie-privilege test-tlb-runtime-invalidate-service test-tlb-runtime-invalidate-router
lint-tlbie-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlbie-decode:
	mkdir -p $(BUILD_DIR)/tlbie-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlbie_decode --Mdir $(BUILD_DIR)/tlbie-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlbie_decode.sv
	./$(BUILD_DIR)/tlbie-decode/Vtb_tlbie_decode $(SIM_ARGS)

test-core-tlbie:
	mkdir -p $(BUILD_DIR)/core-tlbie
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie --Mdir $(BUILD_DIR)/core-tlbie $(RTL) ../tb/tb_core_tlbie.sv
	./$(BUILD_DIR)/core-tlbie/Vtb_core_tlbie $(SIM_ARGS)

test-core-tlbie-privilege:
	mkdir -p $(BUILD_DIR)/core-tlbie-privilege
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie_privilege --Mdir $(BUILD_DIR)/core-tlbie-privilege $(RTL) ../tb/tb_core_tlbie_privilege.sv
	./$(BUILD_DIR)/core-tlbie-privilege/Vtb_core_tlbie_privilege $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-tlbie-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie_privilege -GFEATURE=0 --Mdir $(BUILD_DIR)/core-tlbie-disabled $(RTL) ../tb/tb_core_tlbie_privilege.sv
	./$(BUILD_DIR)/core-tlbie-disabled/Vtb_core_tlbie_privilege $(SIM_ARGS)

test-tlb-runtime-invalidate-service:
	mkdir -p $(BUILD_DIR)/tlb-runtime-invalidate-service
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_invalidate_service --Mdir $(BUILD_DIR)/tlb-runtime-invalidate-service $(TLB_SERVICE_RTL) ../tb/tb_tlb_runtime_invalidate_service.sv
	./$(BUILD_DIR)/tlb-runtime-invalidate-service/Vtb_tlb_runtime_invalidate_service $(SIM_ARGS)

test-tlb-runtime-invalidate-router:
	mkdir -p $(BUILD_DIR)/tlb-runtime-invalidate-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_invalidate_router --Mdir $(BUILD_DIR)/tlb-runtime-invalidate-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_invalidate_router.sv
	./$(BUILD_DIR)/tlb-runtime-invalidate-router/Vtb_tlb_runtime_invalidate_router $(SIM_ARGS)

# Prepared TLB refill, independently checked in all invalidate/refill options.
.PHONY: test-tlb-prepared-refill
test: test-tlb-prepared-refill
test-tlb-prepared-refill:
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-00
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b0" "-GRUNTIME_REFILL=1'b0" --Mdir $(BUILD_DIR)/tlb-prepared-refill-00 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-00/Vtb_tlb_prepared_refill $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-01
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b0" "-GRUNTIME_REFILL=1'b1" --Mdir $(BUILD_DIR)/tlb-prepared-refill-01 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-01/Vtb_tlb_prepared_refill $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-10
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b1" "-GRUNTIME_REFILL=1'b0" --Mdir $(BUILD_DIR)/tlb-prepared-refill-10 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-10/Vtb_tlb_prepared_refill $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-11
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b1" "-GRUNTIME_REFILL=1'b1" --Mdir $(BUILD_DIR)/tlb-prepared-refill-11 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-11/Vtb_tlb_prepared_refill $(SIM_ARGS)

# Opt-in committed DCMP, ICMP and RPA seed SPRs, before TLB load instructions.
.PHONY: lint-tlb-seed test-tlb-seed-decode test-core-tlb-seed
lint: lint-tlb-seed
test: test-tlb-seed-decode test-core-tlb-seed
lint-tlb-seed:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlb-seed-decode:
	mkdir -p $(BUILD_DIR)/tlb-seed-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_seed_decode --Mdir $(BUILD_DIR)/tlb-seed-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlb_seed_decode.sv
	./$(BUILD_DIR)/tlb-seed-decode/Vtb_tlb_seed_decode $(SIM_ARGS)

test-core-tlb-seed:
	mkdir -p $(BUILD_DIR)/core-tlb-seed-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_seed --Mdir $(BUILD_DIR)/core-tlb-seed-enabled $(RTL) ../tb/tb_core_tlb_seed.sv
	./$(BUILD_DIR)/core-tlb-seed-enabled/Vtb_core_tlb_seed $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-tlb-seed-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_seed "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-seed-disabled $(RTL) ../tb/tb_core_tlb_seed.sv
	./$(BUILD_DIR)/core-tlb-seed-disabled/Vtb_core_tlb_seed $(SIM_ARGS)

# Router transaction ownership for retirement-prepared TLB fills.
.PHONY: test-tlb-runtime-fill-router
test: test-tlb-runtime-fill-router
test-tlb-runtime-fill-router:
	mkdir -p $(BUILD_DIR)/tlb-runtime-fill-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_fill_router --Mdir $(BUILD_DIR)/tlb-runtime-fill-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_fill_router.sv
	./$(BUILD_DIR)/tlb-runtime-fill-router-enabled/Vtb_tlb_runtime_fill_router $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/tlb-runtime-fill-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_fill_router "-GENABLE_FILL=1'b0" --Mdir $(BUILD_DIR)/tlb-runtime-fill-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_fill_router.sv
	./$(BUILD_DIR)/tlb-runtime-fill-router-disabled/Vtb_tlb_runtime_fill_router $(SIM_ARGS)

# CPU tlbld/tlbli decode and retirement-owned prepared-refill transport.
.PHONY: lint-tlb-load-integration test-tlb-load-decode test-core-tlb-load
lint: lint-tlb-load-integration
test: test-tlb-load-decode test-core-tlb-load
lint-tlb-load-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlb-load-decode:
	mkdir -p $(BUILD_DIR)/tlb-load-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_load_decode --Mdir $(BUILD_DIR)/tlb-load-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlb_load_decode.sv
	./$(BUILD_DIR)/tlb-load-decode/Vtb_tlb_load_decode $(SIM_ARGS)

test-core-tlb-load:
	mkdir -p $(BUILD_DIR)/core-tlb-load-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_load --Mdir $(BUILD_DIR)/core-tlb-load-enabled $(RTL) ../tb/tb_core_tlb_load.sv
	./$(BUILD_DIR)/core-tlb-load-enabled/Vtb_core_tlb_load $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-tlb-load-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_load "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-load-disabled $(RTL) ../tb/tb_core_tlb_load.sv
	./$(BUILD_DIR)/core-tlb-load-disabled/Vtb_core_tlb_load $(SIM_ARGS)

# Opt-in page-hit PP denial delivered through the existing precise data DSI.
.PHONY: lint-page-data-exceptions test-page-data-exception-router test-core-page-data-exception
lint: lint-page-data-exceptions
test: test-page-data-exception-router test-core-page-data-exception
lint-page-data-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-data-exception-router:
	mkdir -p $(BUILD_DIR)/page-data-exception-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_data_exception_router --Mdir $(BUILD_DIR)/page-data-exception-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_data_exception_router.sv
	./$(BUILD_DIR)/page-data-exception-router-enabled/Vtb_page_data_exception_router $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/page-data-exception-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_data_exception_router "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/page-data-exception-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_data_exception_router.sv
	./$(BUILD_DIR)/page-data-exception-router-disabled/Vtb_page_data_exception_router $(SIM_ARGS)

test-core-page-data-exception:
	mkdir -p $(BUILD_DIR)/core-page-data-exception
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_data_exception --Mdir $(BUILD_DIR)/core-page-data-exception $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_data_exception.sv
	./$(BUILD_DIR)/core-page-data-exception/Vtb_core_page_data_exception $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-page-data-exception-no-micro-tlb
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_data_exception "-GENABLE_MICRO_TLB=1'b0" --Mdir $(BUILD_DIR)/core-page-data-exception-no-micro-tlb $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_data_exception.sv
	./$(BUILD_DIR)/core-page-data-exception-no-micro-tlb/Vtb_core_page_data_exception $(SIM_ARGS)

# Opt-in page instruction PP, no-execute and guarded ISI delivery.
.PHONY: lint-page-instruction-exceptions test-page-instruction-exception-router test-core-page-instruction-exception
lint: lint-page-instruction-exceptions
test: test-page-instruction-exception-router test-core-page-instruction-exception
lint-page-instruction-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-instruction-exception-router:
	mkdir -p $(BUILD_DIR)/page-instruction-exception-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_instruction_exception_router --Mdir $(BUILD_DIR)/page-instruction-exception-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_instruction_exception_router.sv
	./$(BUILD_DIR)/page-instruction-exception-router-enabled/Vtb_page_instruction_exception_router $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/page-instruction-exception-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_instruction_exception_router "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/page-instruction-exception-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_instruction_exception_router.sv
	./$(BUILD_DIR)/page-instruction-exception-router-disabled/Vtb_page_instruction_exception_router $(SIM_ARGS)

test-core-page-instruction-exception:
	mkdir -p $(BUILD_DIR)/core-page-instruction-exception
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_instruction_exception --Mdir $(BUILD_DIR)/core-page-instruction-exception $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_instruction_exception.sv
	./$(BUILD_DIR)/core-page-instruction-exception/Vtb_core_page_instruction_exception $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-page-instruction-exception-no-micro-tlb
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_instruction_exception "-GENABLE_MICRO_TLB=1'b0" --Mdir $(BUILD_DIR)/core-page-instruction-exception-no-micro-tlb $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_instruction_exception.sv
	./$(BUILD_DIR)/core-page-instruction-exception-no-micro-tlb/Vtb_core_page_instruction_exception $(SIM_ARGS)

# Response-bound page miss/changed diagnostic capsules; no architectural miss entry.
.PHONY: lint-page-miss-results test-page-miss-result-router test-core-page-miss-result
lint: lint-page-miss-results
test: test-page-miss-result-router test-core-page-miss-result
lint-page-miss-results:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-miss-result-router:
	mkdir -p $(BUILD_DIR)/page-miss-result-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_miss_result_router --Mdir $(BUILD_DIR)/page-miss-result-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_miss_result_router.sv
	./$(BUILD_DIR)/page-miss-result-router-enabled/Vtb_page_miss_result_router $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/page-miss-result-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_miss_result_router "-GENABLE_PAGE_MISS_RESULTS=1'b0" --Mdir $(BUILD_DIR)/page-miss-result-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_miss_result_router.sv
	./$(BUILD_DIR)/page-miss-result-router-disabled/Vtb_page_miss_result_router $(SIM_ARGS)

test-core-page-miss-result:
	mkdir -p $(BUILD_DIR)/core-page-miss-result-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_miss_result --Mdir $(BUILD_DIR)/core-page-miss-result-enabled $(RTL) ../tb/tb_core_page_miss_result.sv
	./$(BUILD_DIR)/core-page-miss-result-enabled/Vtb_core_page_miss_result $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-page-miss-result-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_miss_result "-GENABLE_PAGE_MISS_RESULTS=1'b0" --Mdir $(BUILD_DIR)/core-page-miss-result-disabled $(RTL) ../tb/tb_core_page_miss_result.sv
	./$(BUILD_DIR)/core-page-miss-result-disabled/Vtb_core_page_miss_result $(SIM_ARGS)

# CPU SDR1 state and pure 32-bit page-miss derivation.
.PHONY: lint-sdr1 test-sdr1-decode test-core-sdr1 test-miss-derive
lint: lint-sdr1
test: test-sdr1-decode test-core-sdr1 test-miss-derive
lint-sdr1:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SDR1=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_miss_derive ../rtl/ppc_miss_derive.sv

test-sdr1-decode:
	mkdir -p $(BUILD_DIR)/sdr1-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_sdr1_decode --Mdir $(BUILD_DIR)/sdr1-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_sdr1_decode.sv
	./$(BUILD_DIR)/sdr1-decode/Vtb_sdr1_decode $(SIM_ARGS)

test-core-sdr1:
	mkdir -p $(BUILD_DIR)/core-sdr1-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sdr1 --Mdir $(BUILD_DIR)/core-sdr1-enabled $(RTL) ../tb/tb_core_sdr1.sv
	./$(BUILD_DIR)/core-sdr1-enabled/Vtb_core_sdr1 $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-sdr1-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sdr1 "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-sdr1-disabled $(RTL) ../tb/tb_core_sdr1.sv
	./$(BUILD_DIR)/core-sdr1-disabled/Vtb_core_sdr1 $(SIM_ARGS)

test-miss-derive:
	mkdir -p $(BUILD_DIR)/miss-derive
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_miss_derive --Mdir $(BUILD_DIR)/miss-derive ../rtl/ppc_miss_derive.sv ../tb/tb_miss_derive.sv
	./$(BUILD_DIR)/miss-derive/Vtb_miss_derive $(SIM_ARGS)

# Temporary GPR0–GPR3 overlay under opt-in MSR.TGPR context control.
.PHONY: lint-tgpr test-regfile-tgpr test-core-tgpr
lint: lint-tgpr
test: test-regfile-tgpr test-core-tgpr
lint-tgpr:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TGPR=1'b1" $(RTL)

test-regfile-tgpr:
	mkdir -p $(BUILD_DIR)/regfile-tgpr-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_tgpr --Mdir $(BUILD_DIR)/regfile-tgpr-enabled ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_tgpr.sv
	./$(BUILD_DIR)/regfile-tgpr-enabled/Vtb_regfile_tgpr $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/regfile-tgpr-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_tgpr "-GENABLE_TGPR=1'b0" --Mdir $(BUILD_DIR)/regfile-tgpr-disabled ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_tgpr.sv
	./$(BUILD_DIR)/regfile-tgpr-disabled/Vtb_regfile_tgpr $(SIM_ARGS)

# Rename with two allocations and releases per cycle against a model.
.PHONY: test-rename-pair
test: test-rename-pair
test-rename-pair:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_rename_pair --Mdir $(BUILD_DIR)/rename-pair ../rtl/ppc_pkg.sv ../rtl/ppc_rename.sv ../tb/tb_rename_pair.sv
	./$(BUILD_DIR)/rename-pair/Vtb_rename_pair $(SIM_ARGS)

# Six-read, two-write GPR file (live-value table) against a model.
.PHONY: test-regfile-gpr-ports
test: test-regfile-gpr-ports
test-regfile-gpr-ports:
	mkdir -p $(BUILD_DIR)/regfile-gpr-ports-tgpr
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_gpr_ports --Mdir $(BUILD_DIR)/regfile-gpr-ports-tgpr ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_gpr_ports.sv
	./$(BUILD_DIR)/regfile-gpr-ports-tgpr/Vtb_regfile_gpr_ports $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/regfile-gpr-ports
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_gpr_ports "-GENABLE_TGPR=1'b0" --Mdir $(BUILD_DIR)/regfile-gpr-ports ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_gpr_ports.sv
	./$(BUILD_DIR)/regfile-gpr-ports/Vtb_regfile_gpr_ports $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/regfile-gpr-ports-single
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_gpr_ports "-GDUAL_WRITE=1'b0" --Mdir $(BUILD_DIR)/regfile-gpr-ports-single ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_gpr_ports.sv
	./$(BUILD_DIR)/regfile-gpr-ports-single/Vtb_regfile_gpr_ports $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/regfile-gpr-ports-single-plain
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_gpr_ports "-GENABLE_TGPR=1'b0" "-GDUAL_WRITE=1'b0" --Mdir $(BUILD_DIR)/regfile-gpr-ports-single-plain ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_gpr_ports.sv
	./$(BUILD_DIR)/regfile-gpr-ports-single-plain/Vtb_regfile_gpr_ports $(SIM_ARGS)

test-core-tgpr:
	mkdir -p $(BUILD_DIR)/core-tgpr-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tgpr --Mdir $(BUILD_DIR)/core-tgpr-enabled $(RTL) ../tb/tb_core_tgpr.sv
	./$(BUILD_DIR)/core-tgpr-enabled/Vtb_core_tgpr $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-tgpr-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tgpr "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tgpr-disabled $(RTL) ../tb/tb_core_tgpr.sv
	./$(BUILD_DIR)/core-tgpr-disabled/Vtb_core_tgpr $(SIM_ARGS)

# Architectural opt-in 603e TLB miss event and actual-core retirement boundaries.
.PHONY: lint-tlb-miss test-exception-tlb-miss test-core-tlb-miss
lint: lint-tlb-miss
test: test-exception-tlb-miss test-core-tlb-miss
lint-tlb-miss:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" $(RTL)

test-exception-tlb-miss:
	mkdir -p $(BUILD_DIR)/exception-tlb-miss-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_tlb_miss --Mdir $(BUILD_DIR)/exception-tlb-miss-enabled $(EXCEPTION_RTL) ../tb/tb_exception_tlb_miss.sv
	./$(BUILD_DIR)/exception-tlb-miss-enabled/Vtb_exception_tlb_miss $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/exception-tlb-miss-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_tlb_miss "-GENABLE_TLB_MISS_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/exception-tlb-miss-disabled $(EXCEPTION_RTL) ../tb/tb_exception_tlb_miss.sv
	./$(BUILD_DIR)/exception-tlb-miss-disabled/Vtb_exception_tlb_miss $(SIM_ARGS)

test-core-tlb-miss:
	mkdir -p $(BUILD_DIR)/core-tlb-miss-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_miss --Mdir $(BUILD_DIR)/core-tlb-miss-enabled $(RTL) ../tb/tb_core_tlb_miss.sv
	./$(BUILD_DIR)/core-tlb-miss-enabled/Vtb_core_tlb_miss $(SIM_ARGS)
	mkdir -p $(BUILD_DIR)/core-tlb-miss-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_miss "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-miss-disabled $(RTL) ../tb/tb_core_tlb_miss.sv
	./$(BUILD_DIR)/core-tlb-miss-disabled/Vtb_core_tlb_miss $(SIM_ARGS)

# Translated core with the existing cache-inhibited scalar 60x transport.
CORE_BAT_BUS60X_RTL := $(RTL) $(CORE_BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../rtl/ppc_bus60x.sv ../rtl/ppc_bus60x_arbiter.sv $(shell cat ../rtl/core_bat_bus60x_files.f)
.PHONY: test-core-bat-bus60x
test: test-core-bat-bus60x
test-core-bat-bus60x:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x --Mdir $(BUILD_DIR)/core-bat-bus60x $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x.sv
	./$(BUILD_DIR)/core-bat-bus60x/Vtb_core_bat_bus60x $(SIM_ARGS)

.PHONY: lint-core-bat-bus60x
lint: lint-core-bat-bus60x
lint-core-bat-bus60x:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_bus60x $(CORE_BAT_BUS60X_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" "-GENABLE_DEBUG_EXCEPTIONS=1'b1" $(CORE_BAT_BUS60X_RTL)

.PHONY: test-core-bat-bus60x-retry
test: test-core-bat-bus60x-retry
test-core-bat-bus60x-retry:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x-retry
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x_retry --Mdir $(BUILD_DIR)/core-bat-bus60x-retry $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x_retry.sv
	./$(BUILD_DIR)/core-bat-bus60x-retry/Vtb_core_bat_bus60x_retry $(SIM_ARGS)

.PHONY: test-core-bat-bus60x-errors
test: test-core-bat-bus60x-errors
test-core-bat-bus60x-errors:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x-errors
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x_errors --Mdir $(BUILD_DIR)/core-bat-bus60x-errors $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x_errors.sv
	./$(BUILD_DIR)/core-bat-bus60x-errors/Vtb_core_bat_bus60x_errors $(SIM_ARGS)

# Physical instruction cache after CPU-owned translation and permissions.
CORE_BAT_CACHED_BUS60X_RTL := $(CORE_BAT_BUS60X_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL) $(shell cat ../rtl/core_bat_cached_bus60x_files.f)
.PHONY: test-core-bat-cached-bus60x lint-core-bat-cached-bus60x
test: test-core-bat-cached-bus60x
test-core-bat-cached-bus60x:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x --Mdir $(BUILD_DIR)/core-bat-cached-bus60x $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x/Vtb_core_bat_cached_bus60x $(SIM_ARGS)
# The same bench with the bus at 1.5:1, 2:1, 2.5:1, 3:1, 3.5:1 and 4:1
# (processor clocks per SYSCLK, doubled).
CORE_RATIO2S ?= 3 4 5 6 7 8
.PHONY: test-core-bat-cached-bus60x-ratios
test: test-core-bat-cached-bus60x-ratios
test-core-bat-cached-bus60x-ratios:
	for r in $(CORE_RATIO2S); do \
	  mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-r$$r; \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x -GBUS_RATIO2=$$r --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-r$$r $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x.sv || exit 1; \
	  ./$(BUILD_DIR)/core-bat-cached-bus60x-r$$r/Vtb_core_bat_cached_bus60x $(SIM_ARGS) || exit 1; \
	  rm -rf $(BUILD_DIR)/core-bat-cached-bus60x-r$$r; \
	done
	@echo "PASS: translated cached top at ratio x2 $(CORE_RATIO2S)"
# Translated cached top with the data cache in its slot.
DCACHE_CORE_PARAMS := "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" "-GENABLE_BYTE_REVERSE=1'b1" "-GENABLE_MULTIPLE_STRING=1'b1" "-GENABLE_RESERVATION=1'b1" "-GENABLE_MISALIGNED_ACCESS=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" "-GENABLE_PIN_INTERRUPTS=1'b1" "-GENABLE_FULL_DECODE=1'b1" "-GENABLE_DCACHE=1'b1"
# Data cache in the translated cached top on the bench BIU; the mutations
# must fail.
.PHONY: test-core-dcache test-core-dcache-negative
test: test-core-dcache test-core-dcache-negative
DCACHE_CORE_TB := -I../tb $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_core_dcache.sv
test-core-dcache:
	mkdir -p $(BUILD_DIR)/core-dcache
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_dcache --Mdir $(BUILD_DIR)/core-dcache $(DCACHE_CORE_TB)
	./$(BUILD_DIR)/core-dcache/Vtb_core_dcache $(SIM_ARGS)
# The same program with the pipelined load/store unit: load hits one per cycle.
.PHONY: test-core-dcache-lsu-pipe
test: test-core-dcache-lsu-pipe
test-core-dcache-lsu-pipe:
	mkdir -p $(BUILD_DIR)/core-dcache-lsu-pipe
	$(VERILATOR) --binary --timing --assert -Wall +define+PPC_LSU_PIPE=1 --top-module tb_core_dcache --Mdir $(BUILD_DIR)/core-dcache-lsu-pipe $(DCACHE_CORE_TB)
	./$(BUILD_DIR)/core-dcache-lsu-pipe/Vtb_core_dcache $(SIM_ARGS)
test-core-dcache-negative:
	mkdir -p $(BUILD_DIR)/core-dcache-negative
	for m in 1 2 3 4 5 7 101 102 103; do \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_dcache -GMUTATION=$$m --Mdir $(BUILD_DIR)/core-dcache-negative/m$$m $(DCACHE_CORE_TB) > $(BUILD_DIR)/core-dcache-negative/build$$m.log 2>&1 || exit 1; \
	  if ./$(BUILD_DIR)/core-dcache-negative/m$$m/Vtb_core_dcache > $(BUILD_DIR)/core-dcache-negative/run$$m.log 2>&1; then \
	    echo "FAIL: mutation $$m passed"; exit 1; fi; \
	  echo "mutation $$m rejected: $$(grep -m1 -o '%Fatal.*\|%Error.*' $(BUILD_DIR)/core-dcache-negative/run$$m.log | cut -c1-120)"; \
	  rm -rf $(BUILD_DIR)/core-dcache-negative/m$$m; \
	done
	@echo "PASS: data cache core mutations rejected"
lint: lint-core-bat-cached-bus60x
lint-core-bat-cached-bus60x:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_cached_bus60x $(CORE_BAT_CACHED_BUS60X_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_cached_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_CACHE_INSTRUCTIONS=1'b1" "-GENABLE_MACHINE_CHECK=1'b1" "-GENABLE_DEBUG_EXCEPTIONS=1'b1" $(CORE_BAT_CACHED_BUS60X_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_cached_bus60x $(DCACHE_CORE_PARAMS) $(CORE_BAT_CACHED_BUS60X_RTL)

.PHONY: test-core-bat-cached-bus60x-drain
test: test-core-bat-cached-bus60x-drain
test-core-bat-cached-bus60x-drain:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-drain
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_drain --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-drain $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_drain.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-drain/Vtb_core_bat_cached_bus60x_drain $(SIM_ARGS)

.PHONY: test-core-bat-cached-bus60x-coherence
test: test-core-bat-cached-bus60x-coherence
test-core-bat-cached-bus60x-coherence:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-coherence
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_coherence --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-coherence $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_coherence.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-coherence/Vtb_core_bat_cached_bus60x_coherence $(SIM_ARGS)

# Precise external interrupt while a translated cache refill is outstanding.
.PHONY: test-core-bat-cached-bus60x-irq
test: test-core-bat-cached-bus60x-irq
test-core-bat-cached-bus60x-irq:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-irq
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_irq --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-irq $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_irq.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-irq/Vtb_core_bat_cached_bus60x_irq $(SIM_ARGS)

# DEC-to-EXT promotion while a translated cache refill drains.
.PHONY: test-core-cache-control
test: test-core-cache-control
test-core-cache-control:
	mkdir -p $(BUILD_DIR)/core-cache-control
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cache_control --Mdir $(BUILD_DIR)/core-cache-control -I../tb $(RTL) ../tb/tb_core_cache_control.sv
	./$(BUILD_DIR)/core-cache-control/Vtb_core_cache_control $(SIM_ARGS)

.PHONY: test-core-lsu-extensions
test: test-core-lsu-extensions
test-core-lsu-extensions:
	mkdir -p $(BUILD_DIR)/core-lsu-extensions
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_lsu_extensions --Mdir $(BUILD_DIR)/core-lsu-extensions -I../tb $(RTL) ../tb/tb_core_lsu_extensions.sv
	./$(BUILD_DIR)/core-lsu-extensions/Vtb_core_lsu_extensions $(SIM_ARGS)

.PHONY: test-core-cache-probe-miss
test: test-core-cache-probe-miss
test-core-cache-probe-miss:
	mkdir -p $(BUILD_DIR)/core-cache-probe-miss
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cache_probe_miss --Mdir $(BUILD_DIR)/core-cache-probe-miss -I../tb $(RTL) ../tb/tb_core_cache_probe_miss.sv
	./$(BUILD_DIR)/core-cache-probe-miss/Vtb_core_cache_probe_miss $(SIM_ARGS)

.PHONY: test-core-bat-cached-bus60x-cacheops
test: test-core-bat-cached-bus60x-cacheops
test-core-bat-cached-bus60x-cacheops:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-cacheops
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_cacheops --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-cacheops -I../tb $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_scripted_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_cacheops.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-cacheops/Vtb_core_bat_cached_bus60x_cacheops $(SIM_ARGS)

.PHONY: test-core-bat-cached-bus60x-stress
test: test-core-bat-cached-bus60x-stress
STRESS_SEEDS ?= 1 2 3 4
test-core-bat-cached-bus60x-stress:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-stress
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_stress --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-stress -I../tb $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_scripted_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_stress.sv
	for seed in $(STRESS_SEEDS); do ./$(BUILD_DIR)/core-bat-cached-bus60x-stress/Vtb_core_bat_cached_bus60x_stress $(SIM_ARGS) +seed=$$seed || exit 1; done

.PHONY: test-core-bat-cached-bus60x-timer
test: test-core-bat-cached-bus60x-timer
test-core-bat-cached-bus60x-timer:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-timer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_timer --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-timer $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_timer.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-timer/Vtb_core_bat_cached_bus60x_timer $(SIM_ARGS)

# Machine check, trace and IABR: causes, saved state, recovery and priority.
.PHONY: test-core-machine-check-trace
test: test-core-machine-check-trace
test-core-machine-check-trace:
	mkdir -p $(BUILD_DIR)/core-machine-check-trace
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_machine_check_trace --Mdir $(BUILD_DIR)/core-machine-check-trace -I../tb $(RTL) ../tb/tb_core_machine_check_trace.sv
	for seed in 1 2 4 7; do ./$(BUILD_DIR)/core-machine-check-trace/Vtb_core_machine_check_trace $(SIM_ARGS) +seed=$$seed || exit 1; done

# Machine check from 60x TEA on the translated cached top (line fill and
# bypass) and the translated scalar top, with the ME=0 checkstop control.
.PHONY: test-core-bat-machine-check
test: test-core-bat-machine-check
test-core-bat-machine-check:
	mkdir -p $(BUILD_DIR)/core-bat-mc-fill $(BUILD_DIR)/core-bat-mc-bypass $(BUILD_DIR)/core-bat-mc-scalar
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_machine_check --Mdir $(BUILD_DIR)/core-bat-mc-fill -I../tb $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_scripted_target_bfm.sv ../tb/tb_core_bat_machine_check.sv
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_machine_check --Mdir $(BUILD_DIR)/core-bat-mc-bypass -I../tb "-GCACHE_ENABLE=1'b0" $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_scripted_target_bfm.sv ../tb/tb_core_bat_machine_check.sv
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_machine_check --Mdir $(BUILD_DIR)/core-bat-mc-scalar -I../tb "-GCACHED=1'b0" $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_scripted_target_bfm.sv ../tb/tb_core_bat_machine_check.sv
	for dir in fill bypass scalar; do for mode in 0 1; do ./$(BUILD_DIR)/core-bat-mc-$$dir/Vtb_core_bat_machine_check $(SIM_ARGS) +MODE=$$mode || exit 1; done; done

# The ppc603e package top: directed system-pin checks at the pins, and lint
# of the top and its Quartus measurement wrapper.
CHIP_RTL := $(shell cat ../rtl/chip_files.f)
.PHONY: test-chip-dcache-coherence test-chip-dcache-coherence-negative
test: test-chip-dcache-coherence test-chip-dcache-coherence-negative
CHIP_COHERENCE_TB := -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_dcache_coherence.sv
test-chip-dcache-coherence:
	mkdir -p $(BUILD_DIR)/chip-dcache-coherence
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_dcache_coherence --Mdir $(BUILD_DIR)/chip-dcache-coherence $(CHIP_COHERENCE_TB)
	for s in 1 2 3; do ./$(BUILD_DIR)/chip-dcache-coherence/Vtb_chip_dcache_coherence +SEED=$$s $(SIM_ARGS) || exit 1; done
test-chip-dcache-coherence-negative:
	mkdir -p $(BUILD_DIR)/chip-dcache-coherence-negative
	for m in 1 2; do \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_dcache_coherence -GMUTATION=$$m --Mdir $(BUILD_DIR)/chip-dcache-coherence-negative/m$$m $(CHIP_COHERENCE_TB) > $(BUILD_DIR)/chip-dcache-coherence-negative/build$$m.log 2>&1 || exit 1; \
	  if ./$(BUILD_DIR)/chip-dcache-coherence-negative/m$$m/Vtb_chip_dcache_coherence > $(BUILD_DIR)/chip-dcache-coherence-negative/run$$m.log 2>&1; then \
	    echo "FAIL: mutation $$m passed"; exit 1; fi; \
	  echo "mutation $$m rejected: $$(grep -m1 -o '%Fatal.*\|%Error.*' $(BUILD_DIR)/chip-dcache-coherence-negative/run$$m.log | cut -c1-120)"; \
	  rm -rf $(BUILD_DIR)/chip-dcache-coherence-negative/m$$m; \
	done
	@echo "PASS: chip coherence negative controls rejected"
# The core FPU program, self-checking, on the package top with the data cache
# enabled (FP accesses through the D-cache and 60x bus).
.PHONY: test-chip-mp
test: test-chip-mp
test-chip-mp:
	mkdir -p $(BUILD_DIR)/chip-mp
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_mp --Mdir $(BUILD_DIR)/chip-mp -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_mp_bfm.sv ../tb/tb_chip_mp.sv
	for s in 1 2 3; do ./$(BUILD_DIR)/chip-mp/Vtb_chip_mp +SEED=$$s $(SIM_ARGS) || exit 1; done

.PHONY: test-chip-fpu
FPU_CHIP_IMAGE := $(BUILD_DIR)/chip-fpu/program.hex
FPU_CHIP_RANDOM ?= 40
test-chip-fpu:
	mkdir -p $(BUILD_DIR)/chip-fpu
	$(VERILATOR) --binary --timing --assert -Wall -j 2 +define+CHIP_ENABLE_FPU=1 --top-module tb_chip_firmware --Mdir $(BUILD_DIR)/chip-fpu -I../tb $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_firmware.sv
	python3 tools/fpu_core_program.py --chip-image $(FPU_CHIP_IMAGE) --seed $(FPU_CORE_SEED) --random $(FPU_CHIP_RANDOM)
	./$(BUILD_DIR)/chip-fpu/Vtb_chip_firmware +IMAGE=$(FPU_CHIP_IMAGE) +TOHOST=fff3ff00 +MIN_DWORDS=1 $(SIM_ARGS)

.PHONY: test-chip-pins test-chip-power lint-chip
test: test-chip-pins test-chip-power
# 603 at its pins: PVR, CSE, direct-store segments on XATS (UM Appendix C).
test-chip-603:
	mkdir -p $(BUILD_DIR)/chip-603
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_603 +define+CHIP_VARIANT=3 +define+CHIP_DS_PID=10 --Mdir $(BUILD_DIR)/chip-603 -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_603.sv
	./$(BUILD_DIR)/chip-603/Vtb_chip_603 $(SIM_ARGS)
# The same with the FPU: FP loads and stores to T=1 take alignment.
test-chip-603-fpu:
	mkdir -p $(BUILD_DIR)/chip-603-fpu
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_chip_603 +define+CHIP_VARIANT=3 +define+CHIP_DS_PID=5 +define+CHIP_ENABLE_FPU=1 --Mdir $(BUILD_DIR)/chip-603-fpu -I../tb $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_603.sv
	./$(BUILD_DIR)/chip-603-fpu/Vtb_chip_603 $(SIM_ARGS)
test-chip-pins:
	mkdir -p $(BUILD_DIR)/chip-pins
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_pins --Mdir $(BUILD_DIR)/chip-pins -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_pins.sv
	./$(BUILD_DIR)/chip-pins/Vtb_chip_pins $(SIM_ARGS)
test-chip-power:
	mkdir -p $(BUILD_DIR)/chip-power
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_power --Mdir $(BUILD_DIR)/chip-power -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_power.sv
	./$(BUILD_DIR)/chip-power/Vtb_chip_power $(SIM_ARGS)
# The pin and coherence benches at processor:bus ratios other than 1:1,
# as PID7v PLL_CFG codes: 2:1, 2.5:1, 3:1, 3.5:1 and 4:1. RATIO_PLLS
# selects a subset.
RATIO_PLLS ?= 4 6 8 14 10
.PHONY: test-chip-ratios
test: test-chip-ratios
test-chip-ratios:
	for p in $(RATIO_PLLS); do \
	  mkdir -p $(BUILD_DIR)/chip-pins-pll$$p $(BUILD_DIR)/chip-coherence-pll$$p; \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_pins -GPLL=$$p --Mdir $(BUILD_DIR)/chip-pins-pll$$p -I../tb $(CHIP_RTL) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_pins.sv || exit 1; \
	  ./$(BUILD_DIR)/chip-pins-pll$$p/Vtb_chip_pins $(SIM_ARGS) || exit 1; \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip_dcache_coherence -GPLL=$$p --Mdir $(BUILD_DIR)/chip-coherence-pll$$p $(CHIP_COHERENCE_TB) || exit 1; \
	  for s in 1 2; do ./$(BUILD_DIR)/chip-coherence-pll$$p/Vtb_chip_dcache_coherence +SEED=$$s $(SIM_ARGS) || exit 1; done; \
	  rm -rf $(BUILD_DIR)/chip-pins-pll$$p $(BUILD_DIR)/chip-coherence-pll$$p; \
	done
	@echo "PASS: chip pins and coherence at PLL_CFG $(RATIO_PLLS)"
lint: lint-chip
lint-chip:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e $(CHIP_RTL)
	$(VERILATOR) --lint-only --assert -Wall +define+PPC_LSU_PIPE=1 --top-module ppc603e "-GENABLE_FPU=1'b1" $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f)
	cd ../quartus/chip && $(VERILATOR) --lint-only -Wall --top-module ppc603e_measure -f files.f

# The ppc602 package top: 602 bus BFM with directed pin checks and a program
# boot in 64- and 32-bit data modes, and lint of the top and its Quartus
# measurement wrapper, without and with the FPU.
CHIP602_RTL := $(shell cat ../rtl/chip602_files.f)
.PHONY: test-chip602-pins lint-chip602
test: test-chip602-pins
test-chip602-pins:
	mkdir -p $(BUILD_DIR)/chip602-pins
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_chip602_pins --Mdir $(BUILD_DIR)/chip602-pins -I../tb $(CHIP602_RTL) ../tb/bfm/bus602_bfm.sv ../tb/tb_chip602_pins.sv
	./$(BUILD_DIR)/chip602-pins/Vtb_chip602_pins $(SIM_ARGS)
lint: lint-chip602
lint-chip602:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc602 $(CHIP602_RTL)
	cd ../quartus/chip602 && $(VERILATOR) --lint-only -Wall --top-module ppc602_measure -f files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc602 "-GENABLE_FPU=1'b1" $(CHIP602_RTL) $(shell cat ../rtl/fpu_files.f)
	cd ../quartus/chip602 && $(VERILATOR) --lint-only -Wall --top-module ppc602_measure "-GENABLE_FPU=1'b1" "-GFPU_COMPACT=1'b1" -f files.f $(patsubst ../%,../../%,$(shell cat ../rtl/fpu_files.f))

# Line coverage of the translated cached 60x top from the compiled MMU stress
# (all retry and TEA modes) and cache-operation firmware, and of the data
# cache, its bus master and snooper from the LSU image and the chip MMU stress. Needs their ELFs (see
# toolchain/README.md). The summary gates total rtl/ coverage and every case
# arm of the control modules against coverage_waivers.txt.
COVERAGE_DIR := $(BUILD_DIR)/coverage
COVERAGE_MIN ?= 72
FIRMWARE_DIR := ../toolchain/build
.PHONY: coverage coverage-summary
coverage:
	rm -f $(COVERAGE_DIR)/*/cov-*.dat
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile mmu-stress-retry --elf $(FIRMWARE_DIR)/mmu-stress/smoke.elf --build-dir $(COVERAGE_DIR)/mmu-stress-retry
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile mmu-stress-tea --elf $(FIRMWARE_DIR)/mmu-stress/smoke.elf --build-dir $(COVERAGE_DIR)/mmu-stress-tea
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile cacheops --elf $(FIRMWARE_DIR)/cacheops/smoke.elf --build-dir $(COVERAGE_DIR)/cacheops
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile lsu --elf $(FIRMWARE_DIR)/lsu/smoke.elf --build-dir $(COVERAGE_DIR)/lsu
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile full-decode --elf $(FIRMWARE_DIR)/full-decode/smoke.elf --build-dir $(COVERAGE_DIR)/full-decode
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile lsu-dcache --elf $(FIRMWARE_DIR)/lsu/smoke.elf --build-dir $(COVERAGE_DIR)/lsu-dcache
	python3 ../toolchain/run-rtl-smoke.py --coverage --profile chip-mmu-stress --elf $(FIRMWARE_DIR)/chip-mmu-stress/smoke.elf --build-dir $(COVERAGE_DIR)/chip-mmu-stress
	$(MAKE) coverage-summary
coverage-summary:
	python3 tools/coverage_summary.py --waivers coverage_waivers.txt --min-total $(COVERAGE_MIN) $(COVERAGE_DIR)/*/cov-*.dat

# The continuous gate: regression, every compiled-firmware profile and the
# coverage summary. Builds the firmware with the host cross-compiler, or in
# the pinned container when the compiler is absent.
CROSS_GCC := powerpc-linux-gnu-gcc
.PHONY: ci ci-firmware
ci:
	$(MAKE) regression
	$(MAKE) ci-firmware
	$(MAKE) -C ../toolchain rtl-all
	$(MAKE) coverage
	@echo "PASS: ci (regression, compiled firmware, coverage)"
ci-firmware:
	if command -v $(CROSS_GCC) >/dev/null 2>&1; then $(MAKE) -C ../toolchain firmware-all; \
	else ../toolchain/build-in-container.sh firmware-all; fi

# Release gates in one command: ci, reference acceptance and the four fits.
# RELEASE_ARGS passes --skip-quartus, --allow-dirty, --dry-run or -j N.
.PHONY: release-check release-archive
release-check:
	tools/release-check $(RELEASE_ARGS)
# Source tarball and tool manifest in $(BUILD_DIR)/release.
release-archive:
	tools/release-archive --out $(abspath $(BUILD_DIR))/release $(RELEASE_ARGS)

# Compiled firmware on DingusPPC and the RTL: retirement lockstep and final RAM.
.PHONY: test-reference-firmware
test-reference-firmware: reference-checkout ci-firmware
	python3 cosim/run_firmware_reference.py --build-dir $(BUILD_DIR)/reference-firmware --reference $(REFERENCE_DIR) --verilator $(VERILATOR_TOOL)

# Long DingusPPC comparison, outside regression: every reference profile
# plus 64 stress seeds at the generator's 512-block maximum.
REFERENCE_SEEDS_A := 1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,10,11,12,13,14,15,16,17,18,19,1a,1b,1c,1d,1e,1f,20
REFERENCE_SEEDS_B := 603e,deadbeef,21,22,23,24,25,26,27,28,29,2a,2b,2c,2d,2e,2f,30,31,32,33,34,35,36,37,38,39,3a,3b,3c,3d,3e
.PHONY: reference-acceptance
reference-acceptance: reference-runner-flat
	$(MAKE) test-reference test-reference-memory test-reference-bat test-reference-cached test-reference-managed test-reference-cache-disabled test-reference-firmware
	python3 cosim/run_reference_stress.py --build-dir $(BUILD_DIR)/reference-acceptance-a --seeds $(REFERENCE_SEEDS_A) --blocks 512 $(FLAT_REFERENCE_ARGS)
	python3 cosim/run_reference_stress.py --build-dir $(BUILD_DIR)/reference-acceptance-b --seeds $(REFERENCE_SEEDS_B) --blocks 512 $(FLAT_REFERENCE_ARGS)
	@echo "PASS: reference acceptance"

# Complete decode: illegal/invalid forms, traps, FP unavailable, HID0/EAR.
# FPU attached to the core: directed, random enabled-exception and latency
# program; runs with and without retirement stalls.
.PHONY: test-core-fpu test-core-fpu-split
FPU_CORE_IMAGE := $(BUILD_DIR)/core-fpu/program.txt
FPU_CORE_SEED ?= 0x603e
FPU_CORE_RANDOM ?= 200
# Latency probes follow the load/store path the Verilator command selects.
FPU_CORE_LSU := $(if $(or $(findstring lsu-pipe,$(VERILATOR)),$(findstring PPC_LSU_PIPE=1,$(VERILATOR))),--lsu-pipe)
test-core-fpu:
	mkdir -p $(BUILD_DIR)/core-fpu
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_core_fpu --Mdir $(BUILD_DIR)/core-fpu $(FPU_CORE_RTL) ../tb/tb_core_fpu.sv
	python3 tools/fpu_core_program.py --image $(FPU_CORE_IMAGE) --seed $(FPU_CORE_SEED) --random $(FPU_CORE_RANDOM) $(FPU_CORE_LSU)
	./$(BUILD_DIR)/core-fpu/Vtb_core_fpu +IMAGE=$(FPU_CORE_IMAGE) +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-fpu/Vtb_core_fpu +IMAGE=$(FPU_CORE_IMAGE) +STALL=0 $(SIM_ARGS)

# Little-endian mode (LITTLE_ENDIAN.md). Each run: variant, CPU_VARIANT,
# DMEM_BITS, FETCH_WIDTH, DISPATCH_WIDTH, LSU_PIPE, FPU_IMPL.
LE_CORE_RUNS := pid7v pid7v-w2 pid6 pid6-w2 pid6-compact 603 602
LE_pid7v := pid7v 0 64 2 1 0 0
LE_pid7v-w2 := pid7v 0 32 1 2 1 0
LE_pid6 := pid6 1 32 1 1 0 0
LE_pid6-w2 := pid6 1 64 2 2 1 0
LE_pid6-compact := pid6 1 64 1 1 0 1
LE_603 := 603 3 32 1 1 0 0
LE_602 := 602 4 32 1 1 0 0
.PHONY: test-core-le $(addprefix test-core-le-,$(LE_CORE_RUNS))
test: test-core-le
test-core-le: $(addprefix test-core-le-,$(LE_CORE_RUNS))
$(addprefix test-core-le-,$(LE_CORE_RUNS)): test-core-le-%:
	mkdir -p $(BUILD_DIR)/core-le-$*
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_core_le -GCPU_VARIANT=$(word 2,$(LE_$*)) -GDMEM_BITS=$(word 3,$(LE_$*)) -GFETCH_WIDTH=$(word 4,$(LE_$*)) -GDISPATCH_WIDTH=$(word 5,$(LE_$*)) -GLSU_PIPE=$(word 6,$(LE_$*)) -GFPU_IMPL=$(word 7,$(LE_$*)) --Mdir $(BUILD_DIR)/core-le-$* $(FPU_CORE_RTL) ../tb/tb_core_le.sv
	python3 tools/le_core_program.py --image $(BUILD_DIR)/core-le-$*/program.txt --variant $(word 1,$(LE_$*))
	./$(BUILD_DIR)/core-le-$*/Vtb_core_le +IMAGE=$(BUILD_DIR)/core-le-$*/program.txt +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-le-$*/Vtb_core_le +IMAGE=$(BUILD_DIR)/core-le-$*/program.txt +STALL=0 $(SIM_ARGS)

# The little-endian program, self-checking, on the package top with both
# caches enabled.
.PHONY: test-chip-le
test-chip-le:
	mkdir -p $(BUILD_DIR)/chip-le
	$(VERILATOR) --binary --timing --assert -Wall -j 2 +define+CHIP_ENABLE_FPU=1 --top-module tb_chip_firmware --Mdir $(BUILD_DIR)/chip-le -I../tb $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f) ../tb/bfm/bus60x_coherent_bfm.sv ../tb/tb_chip_firmware.sv
	python3 tools/le_core_program.py --chip-image $(BUILD_DIR)/chip-le/program.hex
	./$(BUILD_DIR)/chip-le/Vtb_chip_firmware +IMAGE=$(BUILD_DIR)/chip-le/program.hex +TOHOST=fff3ff00 $(SIM_ARGS)

# The same program with the pipelined LSU over a memory taking one access per
# cycle; adds the Table 6-6 integer load/store rows.
.PHONY: test-core-lsu-timing
test-core-lsu-timing:
	mkdir -p $(BUILD_DIR)/core-lsu-timing
	$(VERILATOR) --binary --timing --assert -Wall -j 2 +define+PPC_LSU_PIPE=1 -GPIPE_MEM=1 --top-module tb_core_fpu --Mdir $(BUILD_DIR)/core-lsu-timing $(FPU_CORE_RTL) ../tb/tb_core_fpu.sv
	python3 tools/fpu_core_program.py --image $(BUILD_DIR)/core-lsu-timing/program.txt --seed $(FPU_CORE_SEED) --random $(FPU_CORE_RANDOM) --lsu-pipe --pipe-mem
	./$(BUILD_DIR)/core-lsu-timing/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-lsu-timing/program.txt +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-lsu-timing/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-lsu-timing/program.txt +STALL=0 $(SIM_ARGS)

# The same program over a 32-bit data path: doublewords split into two words.
FPU_CORE_SPLIT_IMAGE := $(BUILD_DIR)/core-fpu-split/program.txt
test-core-fpu-split:
	mkdir -p $(BUILD_DIR)/core-fpu-split
	$(VERILATOR) --binary --timing --assert -Wall -j 2 --top-module tb_core_fpu -GDMEM_BITS=32 --Mdir $(BUILD_DIR)/core-fpu-split $(FPU_CORE_RTL) ../tb/tb_core_fpu.sv
	python3 tools/fpu_core_program.py --image $(FPU_CORE_SPLIT_IMAGE) --seed $(FPU_CORE_SEED) --random $(FPU_CORE_RANDOM) --dmem-bits 32 $(FPU_CORE_LSU)
	./$(BUILD_DIR)/core-fpu-split/Vtb_core_fpu +IMAGE=$(FPU_CORE_SPLIT_IMAGE) +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-fpu-split/Vtb_core_fpu +IMAGE=$(FPU_CORE_SPLIT_IMAGE) +STALL=0 $(SIM_ARGS)

# The same program with FPU_IMPL=COMPACT; latencies are printed, not checked.
.PHONY: test-core-fpu-compact
test-core-fpu-compact:
	mkdir -p $(BUILD_DIR)/core-fpu-compact
	$(VERILATOR) --binary --timing --assert -Wall -j 2 -GFPU_IMPL=1 --top-module tb_core_fpu --Mdir $(BUILD_DIR)/core-fpu-compact $(FPU_CORE_RTL) ../tb/tb_core_fpu.sv
	python3 tools/fpu_core_program.py --image $(BUILD_DIR)/core-fpu-compact/program.txt --seed $(FPU_CORE_SEED) --random $(FPU_CORE_RANDOM)
	./$(BUILD_DIR)/core-fpu-compact/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-fpu-compact/program.txt +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-fpu-compact/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-fpu-compact/program.txt +STALL=0 $(SIM_ARGS)

# The 602 core with its FPU, FULL and COMPACT: SP/LT tags, emulation traps,
# unaligned loads and the sticky-bit completion stall.
FPU_CORE_602_SEED ?= 0x602
.PHONY: test-core-fpu-602 test-core-fpu-602-compact
test-core-fpu-602 test-core-fpu-602-compact: test-core-fpu-602%:
	mkdir -p $(BUILD_DIR)/core-fpu-602$*
	$(VERILATOR) --binary --timing --assert -Wall -j 2 -GCPU_VARIANT=4 $(if $*,-GFPU_IMPL=1) --top-module tb_core_fpu --Mdir $(BUILD_DIR)/core-fpu-602$* $(FPU_CORE_RTL) ../tb/tb_core_fpu.sv
	python3 tools/fpu_core_602_program.py --image $(BUILD_DIR)/core-fpu-602$*/program.txt --seed $(FPU_CORE_602_SEED) --random $(FPU_CORE_RANDOM)
	./$(BUILD_DIR)/core-fpu-602$*/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-fpu-602$*/program.txt +STALL=1 +SEED=1 $(SIM_ARGS)
	./$(BUILD_DIR)/core-fpu-602$*/Vtb_core_fpu +IMAGE=$(BUILD_DIR)/core-fpu-602$*/program.txt +STALL=0 $(SIM_ARGS)

.PHONY: test-decode-sweep test-core-full-decode
test: test-decode-sweep test-core-full-decode
test-decode-sweep:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_decode_sweep --Mdir $(BUILD_DIR)/decode-sweep ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_decode_sweep.sv
	./$(BUILD_DIR)/decode-sweep/Vtb_decode_sweep $(SIM_ARGS)
test-core-full-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_full_decode --Mdir $(BUILD_DIR)/core-full-decode -I../tb $(RTL) ../tb/tb_core_full_decode.sv
	./$(BUILD_DIR)/core-full-decode/Vtb_core_full_decode $(SIM_ARGS)

# CPU variants (cpu_variant_e encoding): chip lint, divide latency,
# PVR/HID0/HID1 read-back and SRR1[KEY] on each implemented variant; the
# 603e pin top must refuse CPU_602. cpu_cfg() flags, PLL_CFG codes and SPR
# decode are checked on every variant. The PID6 reference run compares
# against DingusPPC MPC603E.
VARIANT_IDS := 0 1 2 3
VARIANT_REJECTED := 4
# Variants the core builds; the 603e pin top still rejects the 602.
VARIANT_CORE_IDS := 0 1 2 3 4
VARIANT_ALL := 0 1 2 3 4
# Strap codes a build must refuse, as VARIANT-PLL-message: PID7v has no 1:1
# ratio; a PID6 2:1 code is legal but not 1:1; 0111 is no PID6 code.
VARIANT_PLL_REJECTS := 0-0 0-12 1-7
.PHONY: variant-matrix test-reference-pid6 test-reference-603
regression: variant-matrix
variant-matrix: $(addprefix variant-lint-,$(VARIANT_IDS)) $(addprefix variant-reject-,$(VARIANT_REJECTED)) \
                $(addprefix variant-divider-,$(VARIANT_CORE_IDS)) $(addprefix variant-full-decode-,$(VARIANT_CORE_IDS)) \
                variant-multiply-timing-0 variant-multiply-timing-4 variant-icache-602 \
                $(addprefix variant-config-,$(VARIANT_ALL)) $(addprefix variant-tlb-miss-,$(VARIANT_ALL)) \
                $(addprefix variant-pll-reject-,$(VARIANT_PLL_REJECTS)) variant-pll-accept test-reference-pid6 test-reference-603 \
                $(addprefix variant-decode-sweep-,$(filter-out 0,$(VARIANT_ALL))) $(addprefix variant-exception-602-,$(VARIANT_ALL)) \
                $(addprefix variant-mmu-602-,$(VARIANT_ALL)) \
                variant-special-lint-602 variant-watchdog-602 test-chip-603
	@echo "PASS: variant-matrix (chip variants $(VARIANT_IDS), core variants $(VARIANT_CORE_IDS) built and checked; chip $(VARIANT_REJECTED) rejected)"
# 602 decode, SPR and ESA/MSR checks below the rejected core: the decode
# sweep and exception state at each variant, and the SRU lane linted with
# the 602 personality.
variant-decode-sweep-%:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_decode_sweep -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-decode-sweep-$* ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_decode_sweep.sv
	./$(BUILD_DIR)/variant-decode-sweep-$*/Vtb_decode_sweep $(SIM_ARGS)
# 602 MMU protection at module level (BAT translate, TLB service, esa).
variant-mmu-602-%:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_mmu_602 -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-mmu-602-$* ../rtl/ppc_pkg.sv ../rtl/ppc_bat_translate.sv ../rtl/ppc_tlb_ram.sv ../rtl/ppc_tlb_service.sv ../tb/tb_mmu_602.sv
	./$(BUILD_DIR)/variant-mmu-602-$*/Vtb_mmu_602 $(SIM_ARGS)
variant-exception-602-%:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_602 -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-exception-602-$* $(EXCEPTION_RTL) ../tb/tb_exception_602.sv
	./$(BUILD_DIR)/variant-exception-602-$*/Vtb_exception_602 $(SIM_ARGS)
variant-watchdog-602:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_watchdog --Mdir $(BUILD_DIR)/variant-watchdog-602 ../rtl/ppc_pkg.sv ../rtl/ppc_watchdog.sv ../tb/tb_watchdog.sv
	./$(BUILD_DIR)/variant-watchdog-602/Vtb_watchdog $(SIM_ARGS)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_special_watchdog --Mdir $(BUILD_DIR)/variant-special-watchdog-602 $(RTL) ../tb/tb_special_watchdog.sv
	./$(BUILD_DIR)/variant-special-watchdog-602/Vtb_special_watchdog $(SIM_ARGS)
variant-special-lint-602:
	$(VERILATOR) --lint-only -Wall --top-module tb_special_lint -GVARIANT=4 $(RTL) ../tb/tb_special_lint.sv
	@echo "PASS: ppc_special linted at CPU_602"
variant-config-%:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_variant_config -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-config-$* ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_variant_config.sv
	./$(BUILD_DIR)/variant-config-$*/Vtb_variant_config $(SIM_ARGS)
variant-tlb-miss-%:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_tlb_miss -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-tlb-miss-$* $(EXCEPTION_RTL) ../tb/tb_exception_tlb_miss.sv
	./$(BUILD_DIR)/variant-tlb-miss-$*/Vtb_exception_tlb_miss $(SIM_ARGS)
variant-pll-reject-%:
	mkdir -p $(BUILD_DIR)/variant-pll
	v=$(word 1,$(subst -, ,$*)); p=$(word 2,$(subst -, ,$*)); \
	if $(VERILATOR) --lint-only -Wall --top-module tb_variant_lint -GVARIANT=$$v -GPLL=$$p $(CHIP_RTL) ../tb/tb_variant_lint.sv \
	   > $(BUILD_DIR)/variant-pll/$*.log 2>&1; then echo "FAIL: variant $$v PLL_CFG $$p elaborated"; exit 1; fi
	grep -q "is not a code of" $(BUILD_DIR)/variant-pll/$*.log
	@echo "PASS: variant $(word 1,$(subst -, ,$*)) PLL_CFG $(word 2,$(subst -, ,$*)) rejected"
# PLL bypass on PID6, and non-1:1 ratios: PID7v 2:1 and 3.5:1, PID6 1.5:1.
VARIANT_PLL_ACCEPTS := 1-3 0-4 0-14 1-12
variant-pll-accept:
	for vp in $(VARIANT_PLL_ACCEPTS); do \
	  $(VERILATOR) --lint-only -Wall --top-module tb_variant_lint -GVARIANT=$${vp%-*} -GPLL=$${vp#*-} $(CHIP_RTL) ../tb/tb_variant_lint.sv || exit 1; \
	done
	@echo "PASS: PLL_CFG accepted: $(VARIANT_PLL_ACCEPTS)"
test-reference-pid6: reference-checkout
	python3 cosim/run_reference.py --build-dir $(BUILD_DIR)/reference-pid6 --model MPC603E $(REFERENCE_ARGS)
test-reference-603: reference-checkout
	python3 cosim/run_reference.py --build-dir $(BUILD_DIR)/reference-603 --model MPC603 $(REFERENCE_ARGS)
variant-lint-%:
	$(VERILATOR) --lint-only -Wall --top-module tb_variant_lint -GVARIANT=$* $(CHIP_RTL) ../tb/tb_variant_lint.sv
variant-reject-%:
	mkdir -p $(BUILD_DIR)/variant-reject
	if $(VERILATOR) --lint-only -Wall --top-module tb_variant_lint -GVARIANT=$* $(CHIP_RTL) ../tb/tb_variant_lint.sv \
	   > $(BUILD_DIR)/variant-reject/$*.log 2>&1; then echo "FAIL: variant $* elaborated"; exit 1; fi
	grep -q "is not implemented" $(BUILD_DIR)/variant-reject/$*.log
	@echo "PASS: variant $* rejected at elaboration"
variant-divider-%:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_divider_timing -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-divider-$* $(RTL) ../tb/tb_core_divider_timing.sv
	./$(BUILD_DIR)/variant-divider-$*/Vtb_core_divider_timing $(SIM_ARGS)
# 602 core on the cached 60x wrapper: I-cache without ICE, ICFI, PVR, multiply.
variant-icache-602:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_602 --Mdir $(BUILD_DIR)/variant-icache-602 $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_602.sv
	./$(BUILD_DIR)/variant-icache-602/Vtb_core_602 $(SIM_ARGS)
variant-multiply-timing-%:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_timing -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-multiply-timing-$* $(RTL) ../tb/tb_multiply_timing.sv
	./$(BUILD_DIR)/variant-multiply-timing-$*/Vtb_multiply_timing $(SIM_ARGS)
variant-full-decode-%:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_full_decode -GVARIANT=$* --Mdir $(BUILD_DIR)/variant-full-decode-$* -I../tb $(RTL) ../tb/tb_core_full_decode.sv
	./$(BUILD_DIR)/variant-full-decode-$*/Vtb_core_full_decode $(SIM_ARGS)

# Standalone data cache: directed MEI checks plus seeded random traffic, and
# injected defects the bench must reject.
DCACHE_MUTATIONS := 1 2 3 4 5 6 7
DCACHE_SEEDS := 2 3
.PHONY: test-dcache test-dcache-mutations
test: test-dcache test-dcache-mutations

test-dcache:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_dcache --Mdir $(BUILD_DIR)/dcache $(DCACHE_RTL) ../tb/tb_dcache.sv
	./$(BUILD_DIR)/dcache/Vtb_dcache $(SIM_ARGS) +seed=1
	for seed in $(DCACHE_SEEDS); do ./$(BUILD_DIR)/dcache/Vtb_dcache $(SIM_ARGS) +seed=$$seed || exit 1; done

# Load hits answered in their lookup cycle (the pipelined load/store unit).
.PHONY: test-dcache-fast
test: test-dcache-fast
test-dcache-fast:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_dcache "-GFAST_LOAD_HIT=1'b1" --Mdir $(BUILD_DIR)/dcache-fast $(DCACHE_RTL) ../tb/tb_dcache.sv
	for seed in 1 $(DCACHE_SEEDS); do ./$(BUILD_DIR)/dcache-fast/Vtb_dcache $(SIM_ARGS) +seed=$$seed || exit 1; done

test-dcache-mutations:
	mkdir -p $(BUILD_DIR)
	for m in $(DCACHE_MUTATIONS); do \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_dcache -GMUTATION=$$m --Mdir $(BUILD_DIR)/dcache-m$$m $(DCACHE_RTL) ../tb/tb_dcache.sv > $(BUILD_DIR)/dcache-m$$m.build.log 2>&1 || { cat $(BUILD_DIR)/dcache-m$$m.build.log; exit 1; }; \
	  if ./$(BUILD_DIR)/dcache-m$$m/Vtb_dcache $(SIM_ARGS) +seed=1 > $(BUILD_DIR)/dcache-m$$m.log 2>&1; then \
	    echo "FAIL: mutation $$m was not detected"; exit 1; \
	  fi; \
	  echo "mutation $$m detected: $$(grep -m1 -o 'FAIL: .*' $(BUILD_DIR)/dcache-m$$m.log)"; \
	done

# Data cache BIU master and 60x snooping: the standalone cache behind the BIU
# with a second bus master, seeded bus timing and a coherent image, plus
# injected defects the bench must reject (BIU mutations, and the cache
# answering a modified snoop hit without a push).
BIU_DCACHE_RTL := ../rtl/ppc_pkg.sv ../rtl/ppc_bus60x.sv ../rtl/ppc_bus60x_arbiter.sv ../rtl/ppc_bus60x_line_read.sv ../rtl/ppc_bus60x_master_select.sv ../rtl/ppc_bus60x_two_master.sv ../rtl/ppc_bus60x_cache_master.sv ../rtl/ppc_bus60x_snoop.sv ../rtl/ppc_bus60x_direct_store.sv ../rtl/ppc_biu.sv $(DCACHE_RTL)
BIU_DCACHE_SEEDS := 2 3 4 5
BIU_DCACHE_MUTATIONS := BIU_MUTATION=1 BIU_MUTATION=2 BIU_MUTATION=3 BIU_MUTATION=4 DC_MUTATION=2
.PHONY: test-biu-dcache-snoop test-biu-dcache-snoop-mutations lint-biu-dcache
test: test-biu-dcache-snoop test-biu-dcache-snoop-mutations
lint: lint-biu-dcache
lint-biu-dcache:
	$(VERILATOR) --lint-only -Wall --top-module ppc_biu "-GENABLE_DCACHE=1'b1" $(BIU_DCACHE_RTL)
test-biu-dcache-snoop:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_biu_dcache_snoop --Mdir $(BUILD_DIR)/biu-dcache-snoop $(BIU_DCACHE_RTL) ../tb/tb_biu_dcache_snoop.sv
	./$(BUILD_DIR)/biu-dcache-snoop/Vtb_biu_dcache_snoop $(SIM_ARGS) +seed=1
	for seed in $(BIU_DCACHE_SEEDS); do ./$(BUILD_DIR)/biu-dcache-snoop/Vtb_biu_dcache_snoop $(SIM_ARGS) +seed=$$seed || exit 1; done
test-biu-dcache-snoop-mutations:
	mkdir -p $(BUILD_DIR)
	for m in $(BIU_DCACHE_MUTATIONS); do \
	  $(VERILATOR) --binary --timing --assert -Wall --top-module tb_biu_dcache_snoop -G$$m --Mdir $(BUILD_DIR)/biu-dcache-$$m $(BIU_DCACHE_RTL) ../tb/tb_biu_dcache_snoop.sv > $(BUILD_DIR)/biu-dcache-$$m.build.log 2>&1 || { cat $(BUILD_DIR)/biu-dcache-$$m.build.log; exit 1; }; \
	  if ./$(BUILD_DIR)/biu-dcache-$$m/Vtb_biu_dcache_snoop $(SIM_ARGS) +seed=1 > $(BUILD_DIR)/biu-dcache-$$m.log 2>&1; then \
	    echo "FAIL: mutation $$m was not detected"; exit 1; \
	  fi; \
	  echo "mutation $$m detected: $$(grep -m1 -o 'FAIL: .*' $(BUILD_DIR)/biu-dcache-$$m.log)"; \
	done

# Demonstration system (rtl/soc, docs/DEMO_SOC.md): firmware from toolchain/demo on the
# processor package with block RAM and a framebuffer. demo-<name> runs one image and
# writes the scanned-out frame to $(BUILD_DIR)/demo/<name>.png. Firmware builds in the
# pinned container unless DEMO_FW_MAKE is overridden; benchmark sources are fetched first.
DEMO_RTL := $(CHIP_RTL) $(shell cat ../rtl/soc/files.f)
DEMO_FPU_RTL := $(CHIP_RTL) $(shell cat ../rtl/fpu_files.f) $(shell cat ../rtl/soc/files.f)
DEMO_FW_DIR ?= ../toolchain/build/demo
DEMO_FW_MAKE ?= ../toolchain/build-in-container.sh -f demo/Makefile
DEMO_NAMES := hello dhrystone coremark
.PHONY: lint-demo-soc demo-soc-model demo-firmware demo-all $(addprefix demo-,$(DEMO_NAMES))
lint: lint-demo-soc
lint-demo-soc:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e_demo_soc $(DEMO_RTL)
	$(VERILATOR) --lint-only --timing -Wall --top-module tb_demo_soc $(DEMO_RTL) ../tb/soc/tb_demo_soc.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e_demo_soc "-GENABLE_FPU=1'b1" $(DEMO_FPU_RTL)
# The demo SoC's 60x target requests no memory beat under reset.
.PHONY: test-soc-target-reset
test: test-soc-target-reset
test-soc-target-reset:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_soc_target_reset --Mdir $(BUILD_DIR)/soc-target-reset ../rtl/soc/soc_bus60x_target.sv ../tb/soc/tb_soc_target_reset.sv
	./$(BUILD_DIR)/soc-target-reset/Vtb_soc_target_reset $(SIM_ARGS)
demo-soc-model:
	mkdir -p $(BUILD_DIR)/demo
	$(VERILATOR) --binary --timing --assert -Wall -O3 --top-module tb_demo_soc --Mdir $(BUILD_DIR)/demo/model $(DEMO_RTL) ../tb/soc/tb_demo_soc.sv
# The demo SoC with ENABLE_FPU.
.PHONY: demo-soc-fpu-model
demo-soc-fpu-model:
	mkdir -p $(BUILD_DIR)/demo
	$(VERILATOR) --binary --timing --assert -Wall -O3 -j 2 --top-module tb_demo_soc "-GENABLE_FPU=1'b1" --Mdir $(BUILD_DIR)/demo/model-fpu $(DEMO_FPU_RTL) ../tb/soc/tb_demo_soc.sv
# The same SoC with FPU_IMPL=COMPACT.
.PHONY: demo-soc-fpu-compact-model
demo-soc-fpu-compact-model:
	mkdir -p $(BUILD_DIR)/demo
	$(VERILATOR) --binary --timing --assert -Wall -O3 -j 2 --top-module tb_demo_soc "-GENABLE_FPU=1'b1" -GFPU_IMPL=1 --Mdir $(BUILD_DIR)/demo/model-fpu-compact $(DEMO_FPU_RTL) ../tb/soc/tb_demo_soc.sv
demo-firmware:
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) all
$(addprefix demo-,$(DEMO_NAMES)): demo-%: demo-soc-model demo-firmware
	./$(BUILD_DIR)/demo/model/Vtb_demo_soc $(SIM_ARGS) +IMAGE=$(DEMO_FW_DIR)/$*.hex +NAME=$* +PPM=$(BUILD_DIR)/demo/$*.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/$*.ppm $(BUILD_DIR)/demo/$*.png
demo-all: $(addprefix demo-,$(DEMO_NAMES))
# nbench, Embench-IoT and Whetstone (docs/BENCHMARKS.md): short fixed sizes;
# the -full images, built alongside, are for hardware.
BENCH_NAMES := nbench embench whetstone
.PHONY: demo-bench-firmware $(addprefix demo-,$(BENCH_NAMES))
demo-bench-firmware:
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) benchmarks
$(addprefix demo-,$(BENCH_NAMES)): demo-%: demo-soc-model demo-bench-firmware
	timeout 7200 ./$(BUILD_DIR)/demo/model/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=2000000000 +IMAGE=$(DEMO_FW_DIR)/$*.hex +NAME=$* +PPM=$(BUILD_DIR)/demo/$*.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/$*.ppm $(BUILD_DIR)/demo/$*.png
# Opcode self-test (docs/SELFTEST.md): the 603e image on the demo SoC, which
# exits with the number of failed cases.
.PHONY: test-selftest
test-selftest: demo-soc-model
	$(DEMO_FW_MAKE) selftest
	timeout 3600 ./$(BUILD_DIR)/demo/model/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=400000000 +IMAGE=$(DEMO_FW_DIR)/selftest.hex +NAME=selftest +PPM=$(BUILD_DIR)/demo/selftest.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/selftest.ppm $(BUILD_DIR)/demo/selftest.png
# The same image on the SoC with the FPU runs the floating-point cases.
.PHONY: test-selftest-fpu
test-selftest-fpu: demo-soc-fpu-model
	$(DEMO_FW_MAKE) selftest
	timeout 3600 ./$(BUILD_DIR)/demo/model-fpu/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=400000000 +IMAGE=$(DEMO_FW_DIR)/selftest.hex +NAME=selftest-fpu +PPM=$(BUILD_DIR)/demo/selftest-fpu.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/selftest-fpu.ppm $(BUILD_DIR)/demo/selftest-fpu.png
.PHONY: test-selftest-fpu-compact
test-selftest-fpu-compact: demo-soc-fpu-compact-model
	$(DEMO_FW_MAKE) selftest
	timeout 3600 ./$(BUILD_DIR)/demo/model-fpu-compact/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=400000000 +IMAGE=$(DEMO_FW_DIR)/selftest.hex +NAME=selftest-fpu-compact +PPM=$(BUILD_DIR)/demo/selftest-fpu-compact.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/selftest-fpu-compact.ppm $(BUILD_DIR)/demo/selftest-fpu-compact.png
# Whetstone built hard-float, on the SoC with the FPU; the MiSTer layout too.
.PHONY: demo-whetstone-hf demo-mister-whetstone-hf
demo-whetstone-hf: demo-soc-fpu-model demo-bench-firmware
	timeout 7200 ./$(BUILD_DIR)/demo/model-fpu/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=2000000000 +IMAGE=$(DEMO_FW_DIR)/whetstone-hf.hex +NAME=whetstone-hf +PPM=$(BUILD_DIR)/demo/whetstone-hf.ppm
	python3 tools/ppm_to_png.py $(BUILD_DIR)/demo/whetstone-hf.ppm $(BUILD_DIR)/demo/whetstone-hf.png
demo-mister-whetstone-hf: demo-soc-fpu-model
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-whetstone-hf
	timeout 7200 ./$(BUILD_DIR)/demo/model-fpu/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=2000000000 +IMAGE=$(DEMO_FW_DIR)/mister-whetstone-hf-smoke.hex +NAME=mister-whetstone-hf +PPM=$(BUILD_DIR)/demo/mister-whetstone-hf.ppm
# The MiSTer suite images' layout (mister/build.sh --suite), at simulation size.
.PHONY: $(addprefix demo-mister-,$(BENCH_NAMES))
$(addprefix demo-mister-,$(BENCH_NAMES)): demo-mister-%: demo-soc-model
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-$*
	timeout 7200 ./$(BUILD_DIR)/demo/model/Vtb_demo_soc $(SIM_ARGS) +MAX_CYCLES=2000000000 +IMAGE=$(DEMO_FW_DIR)/mister-$*-smoke.hex +NAME=mister-$* +PPM=$(BUILD_DIR)/demo/mister-$*.ppm

# MiSTer core body (mister/, docs/MISTER_CORE.md) with a DDRAM model. mister-smoke
# runs the MiSTer image; MISTER_MODE is the MODE register byte (bits 1:0 program:
# 0 hello, 1 Dhrystone, 2 CoreMark, 3 all; bit 2 full length, off by default).
# MISTER_FB=0 selects the native-video build instead of the DDR3 framebuffer.
MISTER_MODE ?= 03
MISTER_FB ?= 1
# MISTER_FPU=1 and MISTER_BENCH=1 match mister/build.sh --fpu and --suite: the
# FPU, and 256 KiB of program RAM.
MISTER_FPU ?= 0
MISTER_BENCH ?= 0
MISTER_RTL := $(if $(filter 1,$(MISTER_FPU)),$(DEMO_FPU_RTL),$(DEMO_RTL)) ../mister/rtl/ppc603e_mister.sv
# MISTER_FB_BASE (hex) moves the framebuffer; MISTER_BUSY_SEED (hex) changes the
# DDRAM busy pattern. Each option gives the model its own directory.
MISTER_GFLAGS := $(if $(MISTER_FB_BASE),-GFB_BASE="32'h$(MISTER_FB_BASE)") \
                 $(if $(MISTER_BUSY_SEED),-GBUSY_SEED="16'h$(MISTER_BUSY_SEED)") \
                 $(if $(filter 1,$(MISTER_FPU)),"-GENABLE_FPU=1'b1") \
                 $(if $(filter 1,$(MISTER_BENCH)),-GRAM_BYTES=262144)
MISTER_OUT := $(BUILD_DIR)/mister/fb$(MISTER_FB)$(if $(MISTER_FB_BASE),-$(MISTER_FB_BASE))$(if $(MISTER_BUSY_SEED),-s$(MISTER_BUSY_SEED))$(if $(filter 1,$(MISTER_FPU)),-fpu)$(if $(filter 1,$(MISTER_BENCH)),-bench)
.PHONY: lint-mister mister-model mister-firmware mister-smoke mister-smoke-fpu
lint: lint-mister
lint-mister:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e_mister $(MISTER_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e_mister -GFB_EXTERNAL="1'b0" $(MISTER_RTL)
	$(VERILATOR) --lint-only --timing -Wall --top-module tb_mister $(MISTER_RTL) ../tb/mister/tb_mister.sv
	$(VERILATOR) --lint-only --timing -Wall --top-module tb_mister -GFB_EXTERNAL="1'b0" $(MISTER_RTL) ../tb/mister/tb_mister.sv
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc603e_mister "-GENABLE_FPU=1'b1" $(DEMO_FPU_RTL) ../mister/rtl/ppc603e_mister.sv
mister-model:
	mkdir -p $(MISTER_OUT)
	$(VERILATOR) --binary --timing --assert -Wall -O3 --top-module tb_mister -GFB_EXTERNAL="1'b$(MISTER_FB)" $(MISTER_GFLAGS) --Mdir $(MISTER_OUT)/model $(MISTER_RTL) ../tb/mister/tb_mister.sv
mister-firmware:
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister GIT_SHORT=$$(git rev-parse --short HEAD)
mister-smoke: mister-model mister-firmware
	timeout 3600 ./$(MISTER_OUT)/model/Vtb_mister $(SIM_ARGS) +IMAGE=$(DEMO_FW_DIR)/mister.hex +MODE=$(MISTER_MODE) +PPM=$(MISTER_OUT)/mister-$(MISTER_MODE).ppm +SAVE=$(MISTER_OUT)/screen-$(MISTER_MODE).pfb
	python3 tools/ppm_to_png.py $(MISTER_OUT)/mister-$(MISTER_MODE).ppm $(MISTER_OUT)/mister-$(MISTER_MODE).png
	if [ "$(MISTER_FB)" = 1 ]; then python3 ../mister/fb2png.py $(MISTER_OUT)/screen-$(MISTER_MODE).pfb $(MISTER_OUT)/screen-$(MISTER_MODE).png; fi
# The --fpu --suite whetstone core: hard-float Whetstone at simulation size,
# MODE as the suite core drives it (no menu).
mister-smoke-fpu:
	$(MAKE) mister-model MISTER_FPU=1 MISTER_BENCH=1
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-whetstone-hf
	timeout 3600 ./$(BUILD_DIR)/mister/fb1-fpu-bench/model/Vtb_mister $(SIM_ARGS) +MAX_CYCLES=1000000000 +IMAGE=$(DEMO_FW_DIR)/mister-whetstone-hf-smoke.hex +MODE=04 +PPM=$(BUILD_DIR)/mister/fb1-fpu-bench/whetstone-hf.ppm +SAVE=$(BUILD_DIR)/mister/fb1-fpu-bench/screen.pfb
	python3 ../mister/fb2png.py $(BUILD_DIR)/mister/fb1-fpu-bench/screen.pfb $(BUILD_DIR)/mister/fb1-fpu-bench/screen.png
# The --fpu core: the FPU image (the MiSTer programs plus Whetstone and the
# double-precision Mandelbrot set). MISTER_FPU_MODE is the MODE byte, with
# program bit 2 in bit 3: 09 is Run all at smoke-test length.
MISTER_FPU_MODE ?= 09
.PHONY: mister-smoke-fpu-all
mister-smoke-fpu-all:
	$(MAKE) mister-model MISTER_FPU=1
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-fpu GIT_SHORT=$$(git rev-parse --short HEAD)
	timeout 3600 ./$(BUILD_DIR)/mister/fb1-fpu/model/Vtb_mister $(SIM_ARGS) +MAX_CYCLES=1000000000 +IMAGE=$(DEMO_FW_DIR)/mister-fpu.hex +MODE=$(MISTER_FPU_MODE) +PPM=$(BUILD_DIR)/mister/fb1-fpu/mister-fpu-$(MISTER_FPU_MODE).ppm +SAVE=$(BUILD_DIR)/mister/fb1-fpu/screen-$(MISTER_FPU_MODE).pfb
	python3 ../mister/fb2png.py $(BUILD_DIR)/mister/fb1-fpu/screen-$(MISTER_FPU_MODE).pfb $(BUILD_DIR)/mister/fb1-fpu/screen-$(MISTER_FPU_MODE).png
# Program images from DDR3 on the test core's configuration (COMPACT FPU, dual
# dispatch, pipelined LSU): each image of MISTER_LOAD_IMAGES, at simulation
# size, goes through the ioctl loader into a DDR3 model and runs from there;
# after the first, the core restarts without it into the on-chip FPU menu
# image (hello).
MISTER_LOAD_OUT := $(BUILD_DIR)/mister/load
MISTER_LOAD_IMAGES ?= selftest whetstone-hf
MISTER_LOAD_GFLAGS := "-GENABLE_FPU=1'b1" -GFPU_IMPL=1 -GDISPATCH_WIDTH=2 "-GENABLE_LSU_PIPE=1'b1"
MISTER_LOAD_RTL := $(DEMO_FPU_RTL) ../mister/rtl/ppc603e_mister.sv ../tb/mister/tb_mister_load.sv
.PHONY: mister-load-model test-mister-load
lint-mister: lint-mister-load
lint-mister-load:
	$(VERILATOR) --lint-only --timing -Wall --top-module tb_mister_load $(MISTER_LOAD_GFLAGS) $(MISTER_LOAD_RTL)
mister-load-model:
	mkdir -p $(MISTER_LOAD_OUT)
	$(VERILATOR) --binary --timing --assert -Wall -O3 -j 2 --top-module tb_mister_load $(MISTER_LOAD_GFLAGS) --Mdir $(MISTER_LOAD_OUT)/model $(MISTER_LOAD_RTL)
test-mister-load: mister-load-model
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-images-smoke mister-fpu GIT_SHORT=$$(git rev-parse --short HEAD)
	menu=+MENU=$(DEMO_FW_DIR)/mister-fpu.hex; for i in $(MISTER_LOAD_IMAGES); do \
	  timeout 3600 ./$(MISTER_LOAD_OUT)/model/Vtb_mister_load $(SIM_ARGS) +MAX_CYCLES=1000000000 \
	    +IMAGE=$(DEMO_FW_DIR)/images/ppc603e-$$i-smoke.bin $$menu +PPM=$(MISTER_LOAD_OUT)/$$i.ppm || exit 1; \
	  python3 tools/ppm_to_png.py $(MISTER_LOAD_OUT)/$$i.ppm $(MISTER_LOAD_OUT)/$$i.png; menu=; done
# Uninitialized-state sweep: core, chip, demo SoC and MiSTer benches rerun
# with several random initial values (XRAND builds) plus all-zero and all-one
# state, so a register or memory that is used or written before reset
# fails on some seed. Each model builds once; runs are separate targets, so
# `make -j2 xrand-sweep` runs two at a time. Logs go to $(BUILD_DIR)/xrand.
XRAND_SWEEP_SEEDS ?= 1 2 3 4 5 6 7 8 zero ones
XRAND_SWEEP_BENCHES := soc-target-reset core-full-decode chip-pins demo-hello mister-fb1 mister-fb0 \
                       mister-fpu
xrand_args = $(if $(filter zero,$1),+verilator+rand+reset+0,$(if $(filter ones,$1),+verilator+rand+reset+1,+verilator+seed+$1 +verilator+rand+reset+2))
XRAND_CMD_soc-target-reset := ./$(BUILD_DIR)/soc-target-reset/Vtb_soc_target_reset
XRAND_CMD_core-full-decode := ./$(BUILD_DIR)/core-full-decode/Vtb_core_full_decode
XRAND_CMD_chip-pins := ./$(BUILD_DIR)/chip-pins/Vtb_chip_pins
XRAND_CMD_demo-hello := ./$(BUILD_DIR)/demo/model/Vtb_demo_soc +IMAGE=$(DEMO_FW_DIR)/hello.hex +NAME=hello
XRAND_CMD_mister-fb1 := ./$(BUILD_DIR)/mister/fb1/model/Vtb_mister +IMAGE=$(DEMO_FW_DIR)/mister.hex +MODE=00
XRAND_CMD_mister-fb0 := ./$(BUILD_DIR)/mister/fb0/model/Vtb_mister +IMAGE=$(DEMO_FW_DIR)/mister.hex +MODE=00
XRAND_CMD_mister-fpu := ./$(BUILD_DIR)/mister/fb1-fpu-bench/model/Vtb_mister +IMAGE=$(DEMO_FW_DIR)/mister-whetstone-hf-smoke.hex +MODE=04
XRAND_SWEEP_RUNS := $(foreach b,$(XRAND_SWEEP_BENCHES),$(foreach s,$(XRAND_SWEEP_SEEDS),xrand-run-$b-$s))
.PHONY: xrand-sweep xrand-models $(XRAND_SWEEP_RUNS)
xrand-models:
	$(MAKE) XRAND=1 test-soc-target-reset test-core-full-decode test-chip-pins demo-soc-model demo-firmware mister-firmware
	$(MAKE) XRAND=1 mister-model MISTER_FB=1
	$(MAKE) XRAND=1 mister-model MISTER_FB=0
	$(MAKE) XRAND=1 mister-model MISTER_FPU=1 MISTER_BENCH=1
	../toolchain/demo/fetch-benchmarks.sh
	$(DEMO_FW_MAKE) mister-whetstone-hf
	mkdir -p $(BUILD_DIR)/xrand
xrand_seed = $(lastword $(subst -, ,$1))
xrand_bench = $(patsubst xrand-run-%-$(call xrand_seed,$1),%,$1)
$(XRAND_SWEEP_RUNS): xrand-models
	@if timeout 1800 $(XRAND_CMD_$(call xrand_bench,$@)) $(call xrand_args,$(call xrand_seed,$@)) \
	    > $(BUILD_DIR)/xrand/$(patsubst xrand-run-%,%,$@).log 2>&1; then \
	  echo "PASS $@"; \
	else echo "FAIL $@"; grep -a -m3 'FAIL\|%Fatal\|%Error' $(BUILD_DIR)/xrand/$(patsubst xrand-run-%,%,$@).log; exit 1; fi
xrand-sweep: $(XRAND_SWEEP_RUNS)
	@echo "PASS: xrand sweep, $(words $(XRAND_SWEEP_RUNS)) runs ($(XRAND_SWEEP_BENCHES)) x ($(XRAND_SWEEP_SEEDS))"
# Cache geometry as a bench parameter: the 603 (128 sets x 2 ways) and 602
# (64 x 2) geometries on the standalone and integrated cache benches, which
# the default targets run at 128 x 4. A target is cache-geo-<bench>-<sets>x<ways>.
CACHE_GEOMETRIES := 128x2 64x2
CACHE_GEO_BENCHES := icache icache-bus60x icache-managed dcache biu-dcache-snoop \
                     core-dcache core-bat-cached-bus60x-coherence chip-dcache-coherence
CACHE_GEO_TOP_icache := tb_icache
CACHE_GEO_SRC_icache := $(ICACHE_RTL) ../tb/tb_icache.sv
CACHE_GEO_RUNS_icache := +geometry
CACHE_GEO_TOP_icache-bus60x := tb_icache_bus60x
CACHE_GEO_SRC_icache-bus60x := $(ICACHE_RTL) $(LINE_RTL) ../tb/tb_icache_bus60x.sv
CACHE_GEO_RUNS_icache-bus60x := +geometry
CACHE_GEO_TOP_icache-managed := tb_icache_managed
CACHE_GEO_SRC_icache-managed := $(ICACHE_RTL) ../rtl/ppc_icache_managed.sv ../tb/tb_icache_managed.sv
CACHE_GEO_RUNS_icache-managed := +geometry
CACHE_GEO_TOP_dcache := tb_dcache
CACHE_GEO_SRC_dcache := $(DCACHE_RTL) ../tb/tb_dcache.sv
CACHE_GEO_RUNS_dcache := +seed=1 $(addprefix +seed=,$(DCACHE_SEEDS))
CACHE_GEO_TOP_biu-dcache-snoop := tb_biu_dcache_snoop
CACHE_GEO_SRC_biu-dcache-snoop := $(BIU_DCACHE_RTL) ../tb/tb_biu_dcache_snoop.sv
CACHE_GEO_RUNS_biu-dcache-snoop := +seed=1 $(addprefix +seed=,$(BIU_DCACHE_SEEDS))
CACHE_GEO_TOP_core-dcache := tb_core_dcache
CACHE_GEO_SRC_core-dcache := $(DCACHE_CORE_TB)
CACHE_GEO_RUNS_core-dcache := +geometry
CACHE_GEO_TOP_core-bat-cached-bus60x-coherence := tb_core_bat_cached_bus60x_coherence
CACHE_GEO_SRC_core-bat-cached-bus60x-coherence := $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_coherence.sv
CACHE_GEO_RUNS_core-bat-cached-bus60x-coherence := +geometry
CACHE_GEO_TOP_chip-dcache-coherence := tb_chip_dcache_coherence
CACHE_GEO_SRC_chip-dcache-coherence := $(CHIP_COHERENCE_TB)
CACHE_GEO_RUNS_chip-dcache-coherence := +SEED=1 +SEED=2 +SEED=3
geo_tag = $(lastword $(subst -, ,$1))
geo_bench = $(patsubst %-$(call geo_tag,$1),%,$1)
geo_sets = $(word 1,$(subst x, ,$(call geo_tag,$1)))
geo_ways = $(word 2,$(subst x, ,$(call geo_tag,$1)))
.PHONY: cache-geometry
regression: cache-geometry
cache-geometry: $(foreach b,$(CACHE_GEO_BENCHES),$(addprefix cache-geo-$(b)-,$(CACHE_GEOMETRIES))) \
                cache-geo-reject
	@echo "PASS: cache-geometry ($(CACHE_GEO_BENCHES) at $(CACHE_GEOMETRIES))"
# Any other geometry fails elaboration.
.PHONY: cache-geo-reject
cache-geo-reject:
	mkdir -p $(BUILD_DIR)/cache-geo-reject
	for g in 128x8 32x2 256x4; do s=$${g%x*}; w=$${g#*x}; \
	  for m in "ppc_icache $(ICACHE_RTL)" "ppc_dcache $(DCACHE_RTL)"; do set -- $$m; top=$$1; shift; \
	    if $(VERILATOR) --lint-only -Wall --top-module $$top -GSET_COUNT=$$s -GWAY_COUNT=$$w $$@ \
	       > $(BUILD_DIR)/cache-geo-reject/$$top-$$g.log 2>&1; then echo "FAIL: $$top $$g elaborated"; exit 1; fi; \
	    grep -q "unsupported geometry" $(BUILD_DIR)/cache-geo-reject/$$top-$$g.log || exit 1; \
	  done; done
	@echo "PASS: cache geometries 128x8, 32x2 and 256x4 rejected"
cache-geo-%:
	mkdir -p $(BUILD_DIR)/cache-geo-$*
	$(VERILATOR) --binary --timing --assert -Wall --top-module $(CACHE_GEO_TOP_$(call geo_bench,$*)) \
	  -GSETS=$(call geo_sets,$*) -GWAYS=$(call geo_ways,$*) --Mdir $(BUILD_DIR)/cache-geo-$* \
	  -I../tb $(CACHE_GEO_SRC_$(call geo_bench,$*))
	for r in $(CACHE_GEO_RUNS_$(call geo_bench,$*)); do \
	  ./$(BUILD_DIR)/cache-geo-$*/V$(CACHE_GEO_TOP_$(call geo_bench,$*)) $(SIM_ARGS) $$r || exit 1; done
	rm -rf $(BUILD_DIR)/cache-geo-$*
