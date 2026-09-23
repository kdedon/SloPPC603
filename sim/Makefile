VERILATOR ?= verilator
BUILD_DIR ?= build
RTL := $(shell cat ../rtl/files.f)
BUS_RTL := $(shell cat ../rtl/bus_files.f)
SYSTEM_RTL := $(shell cat ../rtl/system_files.f)
LINE_RTL := $(shell cat ../rtl/line_read_files.f)
ICACHE_RTL := $(shell cat ../rtl/icache_files.f)
CACHED_SYSTEM_RTL := $(shell cat ../rtl/cached_system_files.f)
BAT_RTL := $(shell cat ../rtl/bat_files.f)
BAT_SERVICE_RTL := $(shell cat ../rtl/bat_service_files.f)
CORE_BAT_RTL := $(shell cat ../rtl/core_bat_files.f)
TLB_SERVICE_RTL := $(shell cat ../rtl/tlb_service_files.f)
SEGMENT_REGISTER_RTL := $(shell cat ../rtl/segment_register_files.f)
CACHE_CONTROL_RTL := $(shell cat ../rtl/cache_control_files.f)
EXCEPTION_RTL := $(shell cat ../rtl/exception_files.f)
.PHONY: all lint test test-core test-completion test-execution test-stage check-spec test-recovery test-recovery-select test-recovery-execution test-recovery-state test-core-recovery test-fetch-recovery test-core-logical test-flags test-completion-flags test-record-execution test-core-record-logical test-core-record-edges test-core-add-flags test-core-add-recovery test-add-execution test-core-adde test-core-adde-recovery test-adde-execution test-core-add-unary test-add-unary-execution test-addme-recovery test-addze-recovery test-core-rotate test-rotate-execution test-core-control-memory test-core-memory-edges test-core-shifts test-shift-execution test-slw-recovery test-srw-recovery clean
# Shared Verilator output directories have a single build owner per invocation.
# These phony prerequisites keep source/configuration checking in Verilator while
# allowing each read-only simulation to run concurrently on its own program files.
.PHONY: regression build-control-memory build-core-bus60x build-core-bus60x-unified
all: regression
regression: lint check-spec test-recovery test-recovery-select test

build-control-memory:
	mkdir -p $(BUILD_DIR)/control-memory/obj
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_control_memory --Mdir $(BUILD_DIR)/control-memory/obj $(RTL) ../tb/tb_core_control_memory.sv

build-core-bus60x:
	mkdir -p $(BUILD_DIR)/core-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x --Mdir $(BUILD_DIR)/core-bus60x $(RTL) $(BUS_RTL) ../tb/tb_core_bus60x.sv

build-core-bus60x-unified:
	mkdir -p $(BUILD_DIR)/core-bus60x-unified
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_unified --Mdir $(BUILD_DIR)/core-bus60x-unified $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/tb_core_bus60x_unified.sv

lint:
	cd ../quartus/timer-bat && $(VERILATOR) --lint-only -Wall --top-module ppc_timer_bat_measure -f files.f
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_segment_registers $(SEGMENT_REGISTER_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_tlb_service $(TLB_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_service $(BAT_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x_managed $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x_managed "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_translate $(BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_exception_state $(EXCEPTION_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_cached_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_icache $(ICACHE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bus60x_line_read $(LINE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bus60x $(BUS_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bus60x $(RTL) $(BUS_RTL) $(SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(RTL) $(BUS_RTL) $(SYSTEM_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_measure $(RTL) ../quartus/ppc_core_measure.sv
test: test-iterative-divider test-bus60x-line-read test-reference-memory test-line-read-independent test-core-divider-timing test-core-divider-timing-pid6 test-bus60x-arbiter test-core-bus60x-ifetch-error test-divider-timing test-core-bus60x-unified test-core-bus60x-unified-update test-lsu-update-decode test-completion-update test-lsu-update-edges test-core-lsu-update test-bus60x test-core-bus60x test-core-bus60x-update test-reference test-divw-decode test-divw-execution test-core-divide-signed test-divw-recovery test-divw-zero-recovery test-divw-overflow-recovery test-divwu-decode test-divwu-execution test-core-divide-unsigned test-divwu-recovery test-divwu-zero-recovery test-multiply-high-decode test-multiply-high-execution test-core-multiply-high test-mulhw-recovery test-mulhwu-recovery test-multiply-decode test-multiply-execution test-core-multiply test-multiply-recovery test-multiply-overflow-recovery test-crstate-execution test-crstate-decode test-core-crstate test-crstate-edges test-crlogical-decode test-completion-cr-bits test-crlogical-edges test-core-crlogical test-crtransfer-decode test-completion-cr-fields test-crtransfer-edges test-core-crtransfer test-unarylogical-decode test-core-unarylogical test-unarylogical-execution test-cntlzw-recovery test-extsb-recovery test-extsh-recovery test-core-andimmediate test-andi-recovery test-andis-recovery test-core-addimmediate test-addic-recovery test-addic-record-recovery test-core-subimmediate test-subfic-recovery test-subfic-negative-recovery test-core-subunary test-subunary-execution test-subfme-recovery test-subfze-recovery test-core-subextend test-subextend-execution test-subfe-recovery test-subfe-zero-recovery test-core-subcarry test-subcarry-execution test-subfc-recovery test-core-subtract test-subtract-execution test-subf-recovery test-neg-recovery test-core-insert test-insert-execution test-insert-recovery test-core-arithmetic-shifts test-arithmetic-shift-execution test-sraw-recovery test-srawi-recovery test-core test-completion test-execution test-stage test-recovery-execution test-recovery-state test-core-recovery test-fetch-recovery test-core-logical test-flags test-completion-flags test-record-execution test-core-record-logical test-core-record-edges test-core-add-flags test-core-add-recovery test-add-execution test-core-adde test-core-adde-recovery test-adde-execution test-core-add-unary test-add-unary-execution test-addme-recovery test-addze-recovery test-core-rotate test-rotate-execution test-core-control-memory test-core-memory-edges test-core-shifts test-shift-execution test-slw-recovery test-srw-recovery
test-core:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core --Mdir $(BUILD_DIR) $(RTL) ../tb/tb_core.sv
	./$(BUILD_DIR)/Vtb_core
test-completion:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion --Mdir $(BUILD_DIR)/completion ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion.sv
	./$(BUILD_DIR)/completion/Vtb_completion
test-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_execution --Mdir $(BUILD_DIR)/execution ../rtl/ppc_pkg.sv ../rtl/ppc_rename.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_execution.sv
	./$(BUILD_DIR)/execution/Vtb_execution
test-stage:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_stage_timing --Mdir $(BUILD_DIR)/stage $(RTL) ../tb/tb_stage_timing.sv
	./$(BUILD_DIR)/stage/Vtb_stage_timing +TRACE=$(BUILD_DIR)/stage/trace.jsonl
	python3 tools/check_stage_timing.py $(BUILD_DIR)/stage/trace.jsonl
check-spec:
	python3 spec/check_timing.py
	python3 spec/check_bus.py
	python3 tools/bus_address.py validate
	python3 tools/isa_generate.py --check
	python3 tools/check_stage_timing.py
	python3 -m unittest discover -s tools -p 'test_*.py'
	python3 -m unittest discover -s cosim -p 'test_*.py'
test-recovery:
	python3 -m unittest discover -s recovery -p 'test_*.py'
test-recovery-select:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_select --Mdir $(BUILD_DIR)/recovery-select ../rtl/ppc_pkg.sv recovery/rtl/ppc_recovery_select.sv ../tb/tb_recovery_select.sv
	./$(BUILD_DIR)/recovery-select/Vtb_recovery_select
test-recovery-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_execution --Mdir $(BUILD_DIR)/recovery-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_recovery_execution.sv
	./$(BUILD_DIR)/recovery-execution/Vtb_recovery_execution
test-recovery-state:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_state --Mdir $(BUILD_DIR)/recovery-state ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_rename.sv ../tb/tb_recovery_state.sv
	./$(BUILD_DIR)/recovery-state/Vtb_recovery_state
test-core-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_recovery --Mdir $(BUILD_DIR)/core-recovery $(RTL) ../tb/tb_core_recovery.sv
	./$(BUILD_DIR)/core-recovery/Vtb_core_recovery
test-fetch-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_fetch_recovery --Mdir $(BUILD_DIR)/fetch-recovery ../rtl/ppc_pkg.sv ../rtl/ppc_fetch.sv ../tb/tb_fetch_recovery.sv
	./$(BUILD_DIR)/fetch-recovery/Vtb_fetch_recovery
test-core-logical:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_logical --Mdir $(BUILD_DIR)/core-logical $(RTL) ../tb/tb_core_logical.sv
	./$(BUILD_DIR)/core-logical/Vtb_core_logical
test-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_flags --Mdir $(BUILD_DIR)/flags ../rtl/ppc_pkg.sv ../rtl/ppc_flags.sv ../tb/tb_flags.sv
	./$(BUILD_DIR)/flags/Vtb_flags
test-completion-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_flags --Mdir $(BUILD_DIR)/completion-flags ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_flags.sv
	./$(BUILD_DIR)/completion-flags/Vtb_completion_flags
test-record-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_record_execution --Mdir $(BUILD_DIR)/record-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_record_execution.sv
	./$(BUILD_DIR)/record-execution/Vtb_record_execution
test-core-record-logical:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_record_logical --Mdir $(BUILD_DIR)/core-record-logical $(RTL) ../tb/tb_core_record_logical.sv
	./$(BUILD_DIR)/core-record-logical/Vtb_core_record_logical
test-core-record-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_record_edges --Mdir $(BUILD_DIR)/core-record-edges $(RTL) ../tb/tb_core_record_edges.sv
	./$(BUILD_DIR)/core-record-edges/Vtb_core_record_edges
test-core-add-flags:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_flags --Mdir $(BUILD_DIR)/core-add-flags $(RTL) ../tb/tb_core_add_flags.sv
	./$(BUILD_DIR)/core-add-flags/Vtb_core_add_flags
test-core-add-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery --Mdir $(BUILD_DIR)/core-add-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/core-add-recovery/Vtb_core_add_recovery
test-add-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_add_execution --Mdir $(BUILD_DIR)/add-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_add_execution.sv
	./$(BUILD_DIR)/add-execution/Vtb_add_execution
test-core-adde:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_adde --Mdir $(BUILD_DIR)/core-adde $(RTL) ../tb/tb_core_adde.sv
	./$(BUILD_DIR)/core-adde/Vtb_core_adde
test-core-adde-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ADDE=1 --Mdir $(BUILD_DIR)/core-adde-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/core-adde-recovery/Vtb_core_add_recovery
test-adde-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_adde_execution --Mdir $(BUILD_DIR)/adde-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_adde_execution.sv
	./$(BUILD_DIR)/adde-execution/Vtb_adde_execution
test-core-add-unary:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_unary --Mdir $(BUILD_DIR)/core-add-unary $(RTL) ../tb/tb_core_add_unary.sv
	./$(BUILD_DIR)/core-add-unary/Vtb_core_add_unary
test-add-unary-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_add_unary_execution --Mdir $(BUILD_DIR)/add-unary-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_add_unary_execution.sv
	./$(BUILD_DIR)/add-unary-execution/Vtb_add_unary_execution
test-addme-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_UNARY=1 --Mdir $(BUILD_DIR)/addme-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/addme-recovery/Vtb_core_add_recovery
test-addze-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_UNARY=2 --Mdir $(BUILD_DIR)/addze-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/addze-recovery/Vtb_core_add_recovery
clean:
	rm -rf $(BUILD_DIR)

# Run only after builds finish; subsequent compilation regenerates these caches.
.PHONY: clean-cache
clean-cache:
	python3 tools/clean_cache.py --build-dir "$(BUILD_DIR)"

test-core-rotate:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_rotate --Mdir $(BUILD_DIR)/core-rotate $(RTL) ../tb/tb_core_rotate.sv
	./$(BUILD_DIR)/core-rotate/Vtb_core_rotate

test-rotate-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_rotate_execution --Mdir $(BUILD_DIR)/rotate-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_rotate_execution.sv
	./$(BUILD_DIR)/rotate-execution/Vtb_rotate_execution

test-core-control-memory: build-control-memory
	python3 tools/control_memory_program.py --output $(BUILD_DIR)/control-memory
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/control-memory

test-core-memory-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_memory_edges --Mdir $(BUILD_DIR)/memory-edges $(RTL) ../tb/tb_core_memory_edges.sv
	./$(BUILD_DIR)/memory-edges/Vtb_core_memory_edges

test-core-shifts: build-control-memory
	python3 tools/control_memory_program.py --shifts --output $(BUILD_DIR)/logical-shifts
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/logical-shifts

test-shift-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_shift_execution --Mdir $(BUILD_DIR)/shift-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_shift_execution.sv
	./$(BUILD_DIR)/shift-execution/Vtb_shift_execution

test-slw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SHIFT=1 --Mdir $(BUILD_DIR)/slw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/slw-recovery/Vtb_core_add_recovery

test-srw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SHIFT=2 --Mdir $(BUILD_DIR)/srw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/srw-recovery/Vtb_core_add_recovery

.PHONY: test-core-arithmetic-shifts test-arithmetic-shift-execution test-sraw-recovery test-srawi-recovery
test-core-arithmetic-shifts: build-control-memory
	python3 tools/control_memory_program.py --arithmetic-shifts --output $(BUILD_DIR)/arithmetic-shifts
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/arithmetic-shifts

test-arithmetic-shift-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_arithmetic_shift_execution --Mdir $(BUILD_DIR)/arithmetic-shift-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_arithmetic_shift_execution.sv
	./$(BUILD_DIR)/arithmetic-shift-execution/Vtb_arithmetic_shift_execution

test-sraw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ARITH_SHIFT=1 --Mdir $(BUILD_DIR)/sraw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/sraw-recovery/Vtb_core_add_recovery

test-srawi-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ARITH_SHIFT=2 --Mdir $(BUILD_DIR)/srawi-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/srawi-recovery/Vtb_core_add_recovery

.PHONY: test-core-insert test-insert-execution test-insert-recovery
test-core-insert: build-control-memory
	python3 tools/control_memory_program.py --insert --output $(BUILD_DIR)/insert
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/insert

test-insert-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_insert_execution --Mdir $(BUILD_DIR)/insert-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_insert_execution.sv
	./$(BUILD_DIR)/insert-execution/Vtb_insert_execution

test-insert-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_INSERT=1 --Mdir $(BUILD_DIR)/insert-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/insert-recovery/Vtb_core_add_recovery

.PHONY: test-core-subtract test-subtract-execution test-subf-recovery test-neg-recovery
test-core-subtract: build-control-memory
	python3 tools/control_memory_program.py --subtract --output $(BUILD_DIR)/subtract
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/subtract

test-subtract-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subtract_execution --Mdir $(BUILD_DIR)/subtract-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subtract_execution.sv
	./$(BUILD_DIR)/subtract-execution/Vtb_subtract_execution

test-subf-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUB=1 --Mdir $(BUILD_DIR)/subf-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subf-recovery/Vtb_core_add_recovery

test-neg-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUB=2 --Mdir $(BUILD_DIR)/neg-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/neg-recovery/Vtb_core_add_recovery

.PHONY: test-core-subcarry test-subcarry-execution test-subfc-recovery
test-core-subcarry: build-control-memory
	python3 tools/control_memory_program.py --subcarry --output $(BUILD_DIR)/subcarry
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/subcarry

test-subcarry-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subcarry_execution --Mdir $(BUILD_DIR)/subcarry-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subcarry_execution.sv
	./$(BUILD_DIR)/subcarry-execution/Vtb_subcarry_execution

test-subfc-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBFC=1 --Mdir $(BUILD_DIR)/subfc-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfc-recovery/Vtb_core_add_recovery

.PHONY: test-core-subextend test-subextend-execution test-subfe-recovery test-subfe-zero-recovery
test-core-subextend: build-control-memory
	python3 tools/control_memory_program.py --subextend --output $(BUILD_DIR)/subextend
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/subextend

test-subextend-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subextend_execution --Mdir $(BUILD_DIR)/subextend-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subextend_execution.sv
	./$(BUILD_DIR)/subextend-execution/Vtb_subextend_execution

test-subfe-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBFE=1 --Mdir $(BUILD_DIR)/subfe-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfe-recovery/Vtb_core_add_recovery

test-subfe-zero-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBFE=2 --Mdir $(BUILD_DIR)/subfe-zero-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfe-zero-recovery/Vtb_core_add_recovery

.PHONY: test-core-subunary test-subunary-execution test-subfme-recovery test-subfze-recovery
test-core-subunary: build-control-memory
	python3 tools/control_memory_program.py --subunary --output $(BUILD_DIR)/subunary
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/subunary

test-subunary-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_subunary_execution --Mdir $(BUILD_DIR)/subunary-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_subunary_execution.sv
	./$(BUILD_DIR)/subunary-execution/Vtb_subunary_execution

test-subfme-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBUNARY=1 --Mdir $(BUILD_DIR)/subfme-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfme-recovery/Vtb_core_add_recovery

test-subfze-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBUNARY=2 --Mdir $(BUILD_DIR)/subfze-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfze-recovery/Vtb_core_add_recovery

.PHONY: test-core-subimmediate test-subfic-recovery test-subfic-negative-recovery
test-core-subimmediate: build-control-memory
	python3 tools/control_memory_program.py --subimmediate --output $(BUILD_DIR)/subimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/subimmediate

test-subfic-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBFIC=1 --Mdir $(BUILD_DIR)/subfic-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfic-recovery/Vtb_core_add_recovery

test-subfic-negative-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SUBFIC=2 --Mdir $(BUILD_DIR)/subfic-negative-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/subfic-negative-recovery/Vtb_core_add_recovery

.PHONY: test-core-addimmediate test-addic-recovery test-addic-record-recovery
test-core-addimmediate: build-control-memory
	python3 tools/control_memory_program.py --addimmediate --output $(BUILD_DIR)/addimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/addimmediate

test-addic-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ADDIC=1 --Mdir $(BUILD_DIR)/addic-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/addic-recovery/Vtb_core_add_recovery

test-addic-record-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ADDIC=2 --Mdir $(BUILD_DIR)/addic-record-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/addic-record-recovery/Vtb_core_add_recovery

.PHONY: test-core-andimmediate test-andi-recovery test-andis-recovery
test-core-andimmediate: build-control-memory
	python3 tools/control_memory_program.py --andimmediate --output $(BUILD_DIR)/andimmediate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/andimmediate

test-andi-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ANDIMM=1 --Mdir $(BUILD_DIR)/andi-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/andi-recovery/Vtb_core_add_recovery

test-andis-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ANDIMM=2 --Mdir $(BUILD_DIR)/andis-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/andis-recovery/Vtb_core_add_recovery

.PHONY: test-core-unarylogical test-unarylogical-execution test-cntlzw-recovery test-extsb-recovery test-extsh-recovery
test-core-unarylogical: build-control-memory
	python3 tools/control_memory_program.py --unarylogical --output $(BUILD_DIR)/unarylogical
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/unarylogical

test-unarylogical-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_unarylogical_execution --Mdir $(BUILD_DIR)/unarylogical-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_unarylogical_execution.sv
	./$(BUILD_DIR)/unarylogical-execution/Vtb_unarylogical_execution

test-cntlzw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ULOGIC=1 --Mdir $(BUILD_DIR)/cntlzw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/cntlzw-recovery/Vtb_core_add_recovery

test-extsb-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ULOGIC=2 --Mdir $(BUILD_DIR)/extsb-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/extsb-recovery/Vtb_core_add_recovery

test-extsh-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_ULOGIC=3 --Mdir $(BUILD_DIR)/extsh-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/extsh-recovery/Vtb_core_add_recovery

.PHONY: test-unarylogical-decode
test-unarylogical-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_unarylogical_decode --Mdir $(BUILD_DIR)/unarylogical-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_unarylogical_decode.sv
	./$(BUILD_DIR)/unarylogical-decode/Vtb_unarylogical_decode

.PHONY: test-core-crtransfer
test-core-crtransfer: build-control-memory
	python3 tools/control_memory_program.py --crtransfer --output $(BUILD_DIR)/crtransfer
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/crtransfer

.PHONY: test-crtransfer-edges
test-crtransfer-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crtransfer_edges --Mdir $(BUILD_DIR)/crtransfer-edges $(RTL) ../tb/tb_core_crtransfer_edges.sv
	./$(BUILD_DIR)/crtransfer-edges/Vtb_core_crtransfer_edges

.PHONY: test-completion-cr-fields
test-completion-cr-fields:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_cr_fields --Mdir $(BUILD_DIR)/completion-cr-fields ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_cr_fields.sv
	./$(BUILD_DIR)/completion-cr-fields/Vtb_completion_cr_fields

.PHONY: test-crtransfer-decode
test-crtransfer-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crtransfer_decode --Mdir $(BUILD_DIR)/crtransfer-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crtransfer_decode.sv
	./$(BUILD_DIR)/crtransfer-decode/Vtb_crtransfer_decode

.PHONY: test-core-crlogical
test-core-crlogical: build-control-memory
	python3 tools/control_memory_program.py --crlogical --output $(BUILD_DIR)/crlogical
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/crlogical

.PHONY: test-crlogical-edges
test-crlogical-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crlogical_edges --Mdir $(BUILD_DIR)/crlogical-edges $(RTL) ../tb/tb_core_crlogical_edges.sv
	./$(BUILD_DIR)/crlogical-edges/Vtb_core_crlogical_edges

.PHONY: test-completion-cr-bits
test-completion-cr-bits:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_cr_bits --Mdir $(BUILD_DIR)/completion-cr-bits ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../rtl/ppc_flags.sv ../tb/tb_completion_cr_bits.sv
	./$(BUILD_DIR)/completion-cr-bits/Vtb_completion_cr_bits

.PHONY: test-crlogical-decode
test-crlogical-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crlogical_decode --Mdir $(BUILD_DIR)/crlogical-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crlogical_decode.sv
	./$(BUILD_DIR)/crlogical-decode/Vtb_crlogical_decode

.PHONY: test-core-crstate test-crstate-edges
test-core-crstate: build-control-memory
	python3 tools/control_memory_program.py --crstate --output $(BUILD_DIR)/crstate
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/crstate

test-crstate-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_crstate_edges --Mdir $(BUILD_DIR)/crstate-edges $(RTL) ../tb/tb_core_crstate_edges.sv
	./$(BUILD_DIR)/crstate-edges/Vtb_core_crstate_edges

.PHONY: test-crstate-decode
test-crstate-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crstate_decode --Mdir $(BUILD_DIR)/crstate-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_crstate_decode.sv
	./$(BUILD_DIR)/crstate-decode/Vtb_crstate_decode

.PHONY: test-crstate-execution
test-crstate-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_crstate_execution --Mdir $(BUILD_DIR)/crstate-execution ../rtl/ppc_pkg.sv $(EXCEPTION_RTL) ../rtl/ppc_timer.sv ../rtl/ppc_miss_derive.sv ../rtl/ppc_special.sv ../tb/tb_crstate_execution.sv
	./$(BUILD_DIR)/crstate-execution/Vtb_crstate_execution

.PHONY: test-core-multiply test-multiply-recovery test-multiply-overflow-recovery
test-core-multiply: build-control-memory
	python3 tools/control_memory_program.py --multiply --output $(BUILD_DIR)/multiply
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/multiply

test-multiply-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_MUL=1 --Mdir $(BUILD_DIR)/multiply-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/multiply-recovery/Vtb_core_add_recovery

test-multiply-overflow-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_MUL=2 --Mdir $(BUILD_DIR)/multiply-overflow-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/multiply-overflow-recovery/Vtb_core_add_recovery

.PHONY: test-multiply-decode
test-multiply-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_decode --Mdir $(BUILD_DIR)/multiply-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_multiply_decode.sv
	./$(BUILD_DIR)/multiply-decode/Vtb_multiply_decode

.PHONY: test-multiply-execution
test-multiply-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_execution --Mdir $(BUILD_DIR)/multiply-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_multiply_execution.sv
	./$(BUILD_DIR)/multiply-execution/Vtb_multiply_execution

.PHONY: test-core-multiply-high test-mulhw-recovery test-mulhwu-recovery
test-core-multiply-high: build-control-memory
	python3 tools/control_memory_program.py --multiply-high --output $(BUILD_DIR)/multiply-high
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/multiply-high

test-mulhw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_MULHIGH=1 --Mdir $(BUILD_DIR)/mulhw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/mulhw-recovery/Vtb_core_add_recovery

test-mulhwu-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_MULHIGH=2 --Mdir $(BUILD_DIR)/mulhwu-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/mulhwu-recovery/Vtb_core_add_recovery

.PHONY: test-multiply-high-decode
test-multiply-high-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_high_decode --Mdir $(BUILD_DIR)/multiply-high-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_multiply_high_decode.sv
	./$(BUILD_DIR)/multiply-high-decode/Vtb_multiply_high_decode

.PHONY: test-multiply-high-execution
test-multiply-high-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_high_execution --Mdir $(BUILD_DIR)/multiply-high-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_multiply_high_execution.sv
	./$(BUILD_DIR)/multiply-high-execution/Vtb_multiply_high_execution

.PHONY: test-core-divide-unsigned test-divwu-recovery test-divwu-zero-recovery
test-core-divide-unsigned: build-control-memory
	python3 tools/control_memory_program.py --divide-unsigned --output $(BUILD_DIR)/divide-unsigned
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/divide-unsigned

test-divwu-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_DIV=1 --Mdir $(BUILD_DIR)/divwu-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/divwu-recovery/Vtb_core_add_recovery

test-divwu-zero-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_DIV=2 --Mdir $(BUILD_DIR)/divwu-zero-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/divwu-zero-recovery/Vtb_core_add_recovery

.PHONY: test-divwu-decode
test-divwu-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divwu_decode --Mdir $(BUILD_DIR)/divwu-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_divwu_decode.sv
	./$(BUILD_DIR)/divwu-decode/Vtb_divwu_decode

.PHONY: test-divwu-execution
test-divwu-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divwu_execution --Mdir $(BUILD_DIR)/divwu-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divwu_execution.sv
	./$(BUILD_DIR)/divwu-execution/Vtb_divwu_execution

.PHONY: test-core-divide-signed test-divw-recovery test-divw-zero-recovery test-divw-overflow-recovery
test-core-divide-signed: build-control-memory
	python3 tools/control_memory_program.py --divide-signed --output $(BUILD_DIR)/divide-signed
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/divide-signed

test-divw-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SDIV=1 --Mdir $(BUILD_DIR)/divw-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/divw-recovery/Vtb_core_add_recovery

test-divw-zero-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SDIV=2 --Mdir $(BUILD_DIR)/divw-zero-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/divw-zero-recovery/Vtb_core_add_recovery

test-divw-overflow-recovery:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_add_recovery -GUSE_SDIV=3 --Mdir $(BUILD_DIR)/divw-overflow-recovery $(RTL) ../tb/tb_core_add_recovery.sv
	./$(BUILD_DIR)/divw-overflow-recovery/Vtb_core_add_recovery

.PHONY: test-divw-decode
test-divw-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divw_decode --Mdir $(BUILD_DIR)/divw-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_divw_decode.sv
	./$(BUILD_DIR)/divw-decode/Vtb_divw_decode

.PHONY: test-divw-execution
test-divw-execution:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divw_execution --Mdir $(BUILD_DIR)/divw-execution ../rtl/ppc_pkg.sv ../rtl/ppc_dispatch.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divw_execution.sv
	./$(BUILD_DIR)/divw-execution/Vtb_divw_execution

.PHONY: test-core-lsu-update test-core-bus60x test-core-bus60x-update
test-core-lsu-update: build-control-memory
	python3 tools/control_memory_program.py --lsu-update --output $(BUILD_DIR)/lsu-update
	./$(BUILD_DIR)/control-memory/obj/Vtb_core_control_memory +PROGRAM_DIR=$(BUILD_DIR)/lsu-update
test-core-bus60x: build-core-bus60x
	python3 tools/control_memory_program.py --output $(BUILD_DIR)/bus60x-program
	./$(BUILD_DIR)/core-bus60x/Vtb_core_bus60x +PROGRAM_DIR=$(BUILD_DIR)/bus60x-program
test-core-bus60x-update: build-core-bus60x
	python3 tools/control_memory_program.py --lsu-update --output $(BUILD_DIR)/bus60x-update-program
	./$(BUILD_DIR)/core-bus60x/Vtb_core_bus60x +PROGRAM_DIR=$(BUILD_DIR)/bus60x-update-program

.PHONY: test-reference
test-reference:
	python3 cosim/run_reference.py --build-dir $(BUILD_DIR)/reference

.PHONY: test-lsu-update-decode test-completion-update test-lsu-update-edges test-bus60x
test-lsu-update-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_lsu_update_decode --Mdir $(BUILD_DIR)/lsu-update-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_lsu_update_decode.sv
	./$(BUILD_DIR)/lsu-update-decode/Vtb_lsu_update_decode
test-completion-update:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_update --Mdir $(BUILD_DIR)/completion-update ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion_update.sv
	./$(BUILD_DIR)/completion-update/Vtb_completion_update
test-lsu-update-edges:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_lsu_update_edges --Mdir $(BUILD_DIR)/lsu-update-edges $(RTL) ../tb/tb_lsu_update_edges.sv
	./$(BUILD_DIR)/lsu-update-edges/Vtb_lsu_update_edges
test-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x --Mdir $(BUILD_DIR)/bus60x $(BUS_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_bus60x.sv
	./$(BUILD_DIR)/bus60x/Vtb_bus60x

.PHONY: test-core-bus60x-unified test-core-bus60x-unified-update
test-core-bus60x-unified: build-core-bus60x-unified
	python3 tools/control_memory_program.py --memory-base 0x6000 --output $(BUILD_DIR)/bus60x-unified-program
	./$(BUILD_DIR)/core-bus60x-unified/Vtb_core_bus60x_unified +PROGRAM_DIR=$(BUILD_DIR)/bus60x-unified-program
test-core-bus60x-unified-update: build-core-bus60x-unified
	python3 tools/control_memory_program.py --lsu-update --memory-base 0x6000 --output $(BUILD_DIR)/bus60x-unified-update-program
	./$(BUILD_DIR)/core-bus60x-unified/Vtb_core_bus60x_unified +PROGRAM_DIR=$(BUILD_DIR)/bus60x-unified-update-program

.PHONY: test-bus60x-arbiter test-core-bus60x-ifetch-error test-divider-timing
test-bus60x-arbiter:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_arbiter --Mdir $(BUILD_DIR)/bus60x-arbiter ../rtl/ppc_bus60x_arbiter.sv ../tb/tb_bus60x_arbiter.sv
	./$(BUILD_DIR)/bus60x-arbiter/Vtb_bus60x_arbiter
test-core-bus60x-ifetch-error:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_ifetch_error --Mdir $(BUILD_DIR)/core-bus60x-ifetch-error $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_ifetch_error.sv
	./$(BUILD_DIR)/core-bus60x-ifetch-error/Vtb_core_bus60x_ifetch_error
test-divider-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_divider_timing --Mdir $(BUILD_DIR)/divider-timing ../rtl/ppc_pkg.sv ../rtl/ppc_divider.sv ../rtl/ppc_iu.sv ../tb/tb_divider_timing.sv
	./$(BUILD_DIR)/divider-timing/Vtb_divider_timing

.PHONY: test-core-divider-timing test-core-divider-timing-pid6
test-core-divider-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_divider_timing --Mdir $(BUILD_DIR)/core-divider-timing $(RTL) ../tb/tb_core_divider_timing.sv
	./$(BUILD_DIR)/core-divider-timing/Vtb_core_divider_timing
test-core-divider-timing-pid6:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_divider_timing -GDIV_LATENCY=37 --Mdir $(BUILD_DIR)/core-divider-timing-pid6 $(RTL) ../tb/tb_core_divider_timing.sv
	./$(BUILD_DIR)/core-divider-timing-pid6/Vtb_core_divider_timing

.PHONY: test-line-read-independent
test-line-read-independent:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_line_read_independent --Mdir $(BUILD_DIR)/line-read-independent $(LINE_RTL) ../tb/tb_line_read_independent.sv
	./$(BUILD_DIR)/line-read-independent/Vtb_line_read_independent

.PHONY: test-iterative-divider test-bus60x-line-read test-reference-memory
test-iterative-divider:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_iterative_divider --Mdir $(BUILD_DIR)/iterative-divider ../rtl/ppc_divider.sv ../tb/tb_iterative_divider.sv
	./$(BUILD_DIR)/iterative-divider/Vtb_iterative_divider
test-bus60x-line-read:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_line_read --Mdir $(BUILD_DIR)/bus60x-line-read $(LINE_RTL) ../tb/bfm/bus60x_line_target_bfm.sv ../tb/tb_bus60x_line_read.sv
	./$(BUILD_DIR)/bus60x-line-read/Vtb_bus60x_line_read
test-reference-memory:
	python3 cosim/run_memory_reference.py --build-dir $(BUILD_DIR)/reference-memory

.PHONY: test-multiply-timing test-core-multiply-timing test-icache test-icache-bus60x test-reference-stress
test: test-multiply-timing test-core-multiply-timing test-icache test-icache-bus60x test-reference-stress

test-multiply-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_multiply_timing --Mdir $(BUILD_DIR)/multiply-timing $(RTL) ../tb/tb_multiply_timing.sv
	./$(BUILD_DIR)/multiply-timing/Vtb_multiply_timing

test-core-multiply-timing:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_multiply_timing --Mdir $(BUILD_DIR)/core-multiply-timing $(RTL) ../tb/tb_core_multiply_timing.sv
	./$(BUILD_DIR)/core-multiply-timing/Vtb_core_multiply_timing

test-icache:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache --Mdir $(BUILD_DIR)/icache $(ICACHE_RTL) ../tb/tb_icache.sv
	./$(BUILD_DIR)/icache/Vtb_icache

test-icache-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache_bus60x --Mdir $(BUILD_DIR)/icache-bus60x $(ICACHE_RTL) $(LINE_RTL) ../tb/tb_icache_bus60x.sv
	./$(BUILD_DIR)/icache-bus60x/Vtb_icache_bus60x

test-reference-stress:
	python3 cosim/run_reference_stress.py --build-dir $(BUILD_DIR)/reference-stress

.PHONY: test-bat test-bat-independent test-exception-state test-bus60x-master-select test-core-cached-bus60x test-reference-cached
test: test-bat test-bat-independent test-exception-state test-bus60x-master-select test-core-cached-bus60x test-reference-cached

test-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_translate --Mdir $(BUILD_DIR)/bat $(BAT_RTL) ../tb/tb_bat_translate.sv
	./$(BUILD_DIR)/bat/Vtb_bat_translate

test-bat-independent: test-bat
	python3 tools/bat_vectors.py --output $(BUILD_DIR)/bat/vectors.txt
	./$(BUILD_DIR)/bat/Vtb_bat_translate +VECTORS=$(BUILD_DIR)/bat/vectors.txt

test-exception-state:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_state --Mdir $(BUILD_DIR)/exception-state $(EXCEPTION_RTL) ../tb/tb_exception_state.sv
	./$(BUILD_DIR)/exception-state/Vtb_exception_state

test-bus60x-master-select:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bus60x_master_select --Mdir $(BUILD_DIR)/bus60x-master-select ../rtl/ppc_bus60x_master_select.sv ../tb/tb_bus60x_master_select.sv
	./$(BUILD_DIR)/bus60x-master-select/Vtb_bus60x_master_select

test-core-cached-bus60x:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cached_bus60x --Mdir $(BUILD_DIR)/core-cached-bus60x $(RTL) $(BUS_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) ../tb/tb_core_cached_bus60x.sv
	./$(BUILD_DIR)/core-cached-bus60x/Vtb_core_cached_bus60x

test-reference-cached:
	python3 cosim/run_cached_reference.py --build-dir $(BUILD_DIR)/reference-cached

# Round38 independent BAT transactions and managed transport reference profiles.
.PHONY: test-bat-service test-bat-service-independent test-reference-managed test-reference-cache-disabled
test: test-bat-service test-bat-service-independent test-reference-managed test-reference-cache-disabled

test-bat-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_service --Mdir $(BUILD_DIR)/bat-service $(BAT_SERVICE_RTL) ../tb/tb_bat_service.sv
	./$(BUILD_DIR)/bat-service/Vtb_bat_service

test-bat-service-independent: test-bat-service
	python3 tools/bat_service_vectors.py --output $(BUILD_DIR)/bat-service/vectors.txt
	./$(BUILD_DIR)/bat-service/Vtb_bat_service +VECTORS=$(BUILD_DIR)/bat-service/vectors.txt

test-reference-managed:
	python3 cosim/run_cached_reference.py --cache-profile managed --build-dir $(BUILD_DIR)/reference-managed

test-reference-cache-disabled:
	python3 cosim/run_cached_reference.py --cache-profile disabled --build-dir $(BUILD_DIR)/reference-cache-disabled

.PHONY: test-icache-managed test-core-cached-managed test-supervisor-decode test-core-supervisor
test: test-icache-managed test-core-cached-managed test-supervisor-decode test-core-supervisor

test-icache-managed:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_icache_managed --Mdir $(BUILD_DIR)/icache-managed $(ICACHE_RTL) ../rtl/ppc_icache_managed.sv ../tb/tb_icache_managed.sv
	./$(BUILD_DIR)/icache-managed/Vtb_icache_managed

test-core-cached-managed:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_cached_bus60x_managed --Mdir $(BUILD_DIR)/core-cached-managed $(RTL) $(BUS_RTL) $(SYSTEM_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL) ../tb/tb_core_cached_bus60x_managed.sv
	./$(BUILD_DIR)/core-cached-managed/Vtb_core_cached_bus60x_managed

test-supervisor-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_supervisor_decode --Mdir $(BUILD_DIR)/supervisor-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_supervisor_decode.sv
	./$(BUILD_DIR)/supervisor-decode/Vtb_supervisor_decode

test-core-supervisor:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_supervisor --Mdir $(BUILD_DIR)/core-supervisor $(RTL) ../tb/tb_core_supervisor.sv
	./$(BUILD_DIR)/core-supervisor/Vtb_core_supervisor

# Round39: serialized architectural barriers and translated CPU reference.
.PHONY: test-serialization-decode test-core-serialization test-reference-bat
test: test-serialization-decode test-core-serialization test-reference-bat
test-serialization-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_serialization_decode --Mdir $(BUILD_DIR)/serialization-decode $(RTL) ../tb/tb_serialization_decode.sv
	./$(BUILD_DIR)/serialization-decode/Vtb_serialization_decode
test-core-serialization:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_serialization --Mdir $(BUILD_DIR)/core-serialization $(RTL) ../tb/tb_core_serialization.sv
	./$(BUILD_DIR)/core-serialization/Vtb_core_serialization
test-reference-bat:
	python3 cosim/run_bat_reference.py --build-dir $(BUILD_DIR)/reference-bat

.PHONY: test-tlb-service test-tlb-independent
test: test-tlb-service test-tlb-independent
test-tlb-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_service --Mdir $(BUILD_DIR)/tlb-service $(TLB_SERVICE_RTL) ../tb/tb_tlb_service.sv
	./$(BUILD_DIR)/tlb-service/Vtb_tlb_service
test-tlb-independent: test-tlb-service
	python3 tools/tlb_vectors.py --output $(BUILD_DIR)/tlb-service/vectors.txt
	./$(BUILD_DIR)/tlb-service/Vtb_tlb_service +VECTORS=$(BUILD_DIR)/tlb-service/vectors.txt

.PHONY: test-bat-memory-router test-core-bat
test: test-bat-memory-router test-core-bat
test-bat-memory-router:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_memory_router --Mdir $(BUILD_DIR)/bat-memory-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_memory_router.sv
	./$(BUILD_DIR)/bat-memory-router/Vtb_bat_memory_router
test-core-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat --Mdir $(BUILD_DIR)/core-bat $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_bat.sv
	./$(BUILD_DIR)/core-bat/Vtb_core_bat

# Round40: bounded supervisor scratch-register access.
.PHONY: test-sprg-decode test-core-sprg
test: test-sprg-decode test-core-sprg
test-sprg-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_sprg_decode --Mdir $(BUILD_DIR)/sprg-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_sprg_decode.sv
	./$(BUILD_DIR)/sprg-decode/Vtb_sprg_decode
test-core-sprg:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sprg --Mdir $(BUILD_DIR)/core-sprg $(RTL) ../tb/tb_core_sprg.sv
	./$(BUILD_DIR)/core-sprg/Vtb_core_sprg

.PHONY: test-segment-registers
test: test-segment-registers
test-segment-registers:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_registers --Mdir $(BUILD_DIR)/segment-registers $(SEGMENT_REGISTER_RTL) ../tb/tb_segment_registers.sv
	./$(BUILD_DIR)/segment-registers/Vtb_segment_registers

# Supervisor-enabled and default-disabled CPU profiles through physical bus pins.
.PHONY: test-core-bus60x-supervisor test-core-bus60x-supervisor-disabled
test: test-core-bus60x-supervisor test-core-bus60x-supervisor-disabled

test-core-bus60x-supervisor:
	mkdir -p $(BUILD_DIR)/core-bus60x-supervisor
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_supervisor --Mdir $(BUILD_DIR)/core-bus60x-supervisor $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_supervisor.sv
	./$(BUILD_DIR)/core-bus60x-supervisor/Vtb_core_bus60x_supervisor

test-core-bus60x-supervisor-disabled:
	mkdir -p $(BUILD_DIR)/core-bus60x-supervisor-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bus60x_supervisor "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-bus60x-supervisor-disabled $(RTL) $(BUS_RTL) $(SYSTEM_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bus60x_supervisor.sv
	./$(BUILD_DIR)/core-bus60x-supervisor-disabled/Vtb_core_bus60x_supervisor

# Precise resumable alignment routing and legacy disabled-profile diagnostics.
.PHONY: test-core-alignment test-core-alignment-disabled
test: test-core-alignment test-core-alignment-disabled
test-core-alignment:
	mkdir -p $(BUILD_DIR)/core-alignment
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment --Mdir $(BUILD_DIR)/core-alignment $(RTL) ../tb/tb_core_alignment.sv
	./$(BUILD_DIR)/core-alignment/Vtb_core_alignment

test-core-alignment-disabled:
	mkdir -p $(BUILD_DIR)/core-alignment-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-alignment-disabled $(RTL) ../tb/tb_core_alignment.sv
	./$(BUILD_DIR)/core-alignment-disabled/Vtb_core_alignment

# Typed synchronous fetch faults: architectural ISI and explicit diagnostics.
.PHONY: test-core-fetch-fault test-core-fetch-fault-disabled
test: test-core-fetch-fault test-core-fetch-fault-disabled
test-core-fetch-fault:
	mkdir -p $(BUILD_DIR)/core-fetch-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch_fault --Mdir $(BUILD_DIR)/core-fetch-fault $(RTL) ../tb/tb_core_fetch_fault.sv
	./$(BUILD_DIR)/core-fetch-fault/Vtb_core_fetch_fault

test-core-fetch-fault-disabled:
	mkdir -p $(BUILD_DIR)/core-fetch-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_fetch_fault "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-fetch-fault-disabled $(RTL) ../tb/tb_core_fetch_fault.sv
	./$(BUILD_DIR)/core-fetch-fault-disabled/Vtb_core_fetch_fault

.PHONY: test-recovery-storage
test: test-recovery-storage
test-recovery-storage:
	mkdir -p $(BUILD_DIR)/recovery-storage
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_recovery_storage --Mdir $(BUILD_DIR)/recovery-storage ../rtl/ppc_pkg.sv ../rtl/ppc_fifo.sv ../rtl/ppc_rename.sv ../tb/tb_recovery_storage.sv
	./$(BUILD_DIR)/recovery-storage/Vtb_recovery_storage

.PHONY: test-bat-memory-router-live
test: test-bat-memory-router-live
test-bat-memory-router-live:
	mkdir -p $(BUILD_DIR)/bat-memory-router-live
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" --Mdir $(BUILD_DIR)/bat-memory-router-live $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_memory_router.sv
	./$(BUILD_DIR)/bat-memory-router-live/Vtb_bat_memory_router

.PHONY: test-completion-ring
test: test-completion-ring
test-completion-ring:
	mkdir -p $(BUILD_DIR)/completion-ring
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_completion_ring --Mdir $(BUILD_DIR)/completion-ring ../rtl/ppc_pkg.sv ../rtl/ppc_completion.sv ../tb/tb_completion_ring.sv
	./$(BUILD_DIR)/completion-ring/Vtb_completion_ring

.PHONY: test-core-live-context test-core-live-context-disabled test-core-bat-live-context
test: test-core-live-context test-core-live-context-disabled test-core-bat-live-context
test-core-live-context:
	mkdir -p $(BUILD_DIR)/core-live-context
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context --Mdir $(BUILD_DIR)/core-live-context $(RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-live-context/Vtb_core_live_context

test-core-live-context-disabled:
	mkdir -p $(BUILD_DIR)/core-live-context-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context "-GENABLE_LIVE_CONTEXT=1'b0" --Mdir $(BUILD_DIR)/core-live-context-disabled $(RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-live-context-disabled/Vtb_core_live_context

test-core-bat-live-context:
	mkdir -p $(BUILD_DIR)/core-bat-live-context
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_live_context "-GUSE_BAT=1'b1" --Mdir $(BUILD_DIR)/core-bat-live-context $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_live_context.sv
	./$(BUILD_DIR)/core-bat-live-context/Vtb_core_live_context

.PHONY: test-live-context-decode
test: test-live-context-decode
test-live-context-decode:
	mkdir -p $(BUILD_DIR)/live-context-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_live_context_decode --Mdir $(BUILD_DIR)/live-context-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_live_context_decode.sv
	./$(BUILD_DIR)/live-context-decode/Vtb_live_context_decode

.PHONY: test-core-interrupt test-core-interrupt-disabled
test: test-core-interrupt test-core-interrupt-disabled
test-core-interrupt:
	mkdir -p $(BUILD_DIR)/core-interrupt
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_interrupt --Mdir $(BUILD_DIR)/core-interrupt $(RTL) ../tb/tb_core_interrupt.sv
	./$(BUILD_DIR)/core-interrupt/Vtb_core_interrupt

test-core-interrupt-disabled:
	mkdir -p $(BUILD_DIR)/core-interrupt-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_interrupt "-GENABLE_EXTERNAL_INTERRUPTS=1'b0" --Mdir $(BUILD_DIR)/core-interrupt-disabled $(RTL) ../tb/tb_core_interrupt.sv
	./$(BUILD_DIR)/core-interrupt-disabled/Vtb_core_interrupt

.PHONY: test-core-alignment-dependencies
test: test-core-alignment-dependencies
test-core-alignment-dependencies:
	mkdir -p $(BUILD_DIR)/core-alignment-dependencies
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_alignment_dependencies --Mdir $(BUILD_DIR)/core-alignment-dependencies $(RTL) ../tb/tb_core_alignment_dependencies.sv
	./$(BUILD_DIR)/core-alignment-dependencies/Vtb_core_alignment_dependencies

.PHONY: test-timer-decode
test: test-timer-decode
test-timer-decode:
	mkdir -p $(BUILD_DIR)/timer-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_timer_decode --Mdir $(BUILD_DIR)/timer-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_timer_decode.sv
	./$(BUILD_DIR)/timer-decode/Vtb_timer_decode

.PHONY: test-timer test-core-timer-registers
test: test-timer test-core-timer-registers
test-timer:
	mkdir -p $(BUILD_DIR)/timer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_timer --Mdir $(BUILD_DIR)/timer ../rtl/ppc_timer.sv ../tb/tb_timer.sv
	./$(BUILD_DIR)/timer/Vtb_timer

test-core-timer-registers:
	mkdir -p $(BUILD_DIR)/core-timer-registers
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_timer_registers --Mdir $(BUILD_DIR)/core-timer-registers $(RTL) ../tb/tb_core_timer_registers.sv
	./$(BUILD_DIR)/core-timer-registers/Vtb_core_timer_registers

.PHONY: test-core-timer-events
test: test-core-timer-events
test-core-timer-events:
	mkdir -p $(BUILD_DIR)/core-timer-events
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_timer_events --Mdir $(BUILD_DIR)/core-timer-events $(RTL) ../tb/tb_core_timer_events.sv
	./$(BUILD_DIR)/core-timer-events/Vtb_core_timer_events

.PHONY: test-core-xer
test: test-core-xer
test-core-xer:
	mkdir -p $(BUILD_DIR)/core-xer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_xer --Mdir $(BUILD_DIR)/core-xer $(RTL) ../tb/tb_core_xer.sv
	./$(BUILD_DIR)/core-xer/Vtb_core_xer

.PHONY: test-core-event-reset
test: test-core-event-reset
test-core-event-reset:
	mkdir -p $(BUILD_DIR)/core-event-reset
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_event_reset --Mdir $(BUILD_DIR)/core-event-reset $(RTL) ../tb/tb_core_event_reset.sv
	./$(BUILD_DIR)/core-event-reset/Vtb_core_event_reset

.PHONY: lint-runtime-bat test-bat-runtime-service test-bat-runtime-router test-core-runtime-bat test-core-runtime-bat-privilege test-runtime-bat-decode
lint: lint-runtime-bat
test: test-bat-runtime-service test-bat-runtime-router test-core-runtime-bat test-core-runtime-bat-privilege test-runtime-bat-decode

lint-runtime-bat:
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_service "-GENABLE_RUNTIME_BAT=1'b1" $(BAT_SERVICE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-bat-runtime-service:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_runtime_service --Mdir $(BUILD_DIR)/bat-runtime-service $(BAT_SERVICE_RTL) ../tb/tb_bat_runtime_service.sv
	./$(BUILD_DIR)/bat-runtime-service/Vtb_bat_runtime_service

test-bat-runtime-router:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_runtime_router --Mdir $(BUILD_DIR)/bat-runtime-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_runtime_router.sv
	./$(BUILD_DIR)/bat-runtime-router/Vtb_bat_runtime_router

test-core-runtime-bat:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_runtime_bat --Mdir $(BUILD_DIR)/core-runtime-bat $(RTL) ../tb/tb_core_runtime_bat.sv
	./$(BUILD_DIR)/core-runtime-bat/Vtb_core_runtime_bat

test-core-runtime-bat-privilege:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_runtime_bat_privilege --Mdir $(BUILD_DIR)/core-runtime-bat-privilege $(RTL) ../tb/tb_core_runtime_bat_privilege.sv
	./$(BUILD_DIR)/core-runtime-bat-privilege/Vtb_core_runtime_bat_privilege

test-runtime-bat-decode:
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_runtime_bat_decode --Mdir $(BUILD_DIR)/runtime-bat-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_runtime_bat_decode.sv
	./$(BUILD_DIR)/runtime-bat-decode/Vtb_runtime_bat_decode

# Typed synchronous data-protection responses and BAT producer classification.
.PHONY: test-core-data-fault test-core-data-fault-disabled test-bat-data-fault test-bat-data-fault-disabled lint-data-exceptions
test: test-core-data-fault test-core-data-fault-disabled test-bat-data-fault test-bat-data-fault-disabled
lint: lint-data-exceptions
lint-data-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_DATA_EXCEPTIONS=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv

test-core-data-fault:
	mkdir -p $(BUILD_DIR)/core-data-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault --Mdir $(BUILD_DIR)/core-data-fault $(RTL) ../tb/tb_core_data_fault.sv
	./$(BUILD_DIR)/core-data-fault/Vtb_core_data_fault

test-core-data-fault-disabled:
	mkdir -p $(BUILD_DIR)/core-data-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/core-data-fault-disabled $(RTL) ../tb/tb_core_data_fault.sv
	./$(BUILD_DIR)/core-data-fault-disabled/Vtb_core_data_fault

test-bat-data-fault:
	mkdir -p $(BUILD_DIR)/bat-data-fault
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_data_fault --Mdir $(BUILD_DIR)/bat-data-fault $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_data_fault.sv
	./$(BUILD_DIR)/bat-data-fault/Vtb_bat_data_fault

test-bat-data-fault-disabled:
	mkdir -p $(BUILD_DIR)/bat-data-fault-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_bat_data_fault "-GENABLE_DATA_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/bat-data-fault-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_bat_data_fault.sv
	./$(BUILD_DIR)/bat-data-fault-disabled/Vtb_bat_data_fault

.PHONY: test-core-data-fault-cancel
test: test-core-data-fault-cancel
test-core-data-fault-cancel:
	mkdir -p $(BUILD_DIR)/core-data-fault-cancel
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_data_fault_cancel --Mdir $(BUILD_DIR)/core-data-fault-cancel $(RTL) ../tb/tb_core_data_fault_cancel.sv
	./$(BUILD_DIR)/core-data-fault-cancel/Vtb_core_data_fault_cancel

# Optional CPU-programmed segment register instructions and prepared service path.
.PHONY: lint-segment-integration test-segment-cpu-decode test-core-segment-csr test-core-segment-privilege test-segment-runtime-service test-segment-runtime-router
lint: lint-segment-integration
test: test-segment-cpu-decode test-core-segment-csr test-core-segment-privilege test-segment-runtime-service test-segment-runtime-router
lint-segment-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_bat_memory_router "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv

test-segment-cpu-decode:
	mkdir -p $(BUILD_DIR)/segment-cpu-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_cpu_decode --Mdir $(BUILD_DIR)/segment-cpu-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_segment_cpu_decode.sv
	./$(BUILD_DIR)/segment-cpu-decode/Vtb_segment_cpu_decode

test-core-segment-csr:
	mkdir -p $(BUILD_DIR)/core-segment-csr
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_segment_csr --Mdir $(BUILD_DIR)/core-segment-csr $(RTL) ../tb/tb_core_segment_csr.sv
	./$(BUILD_DIR)/core-segment-csr/Vtb_core_segment_csr

test-core-segment-privilege:
	mkdir -p $(BUILD_DIR)/core-segment-privilege
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_segment_privilege --Mdir $(BUILD_DIR)/core-segment-privilege $(RTL) ../tb/tb_core_segment_privilege.sv
	./$(BUILD_DIR)/core-segment-privilege/Vtb_core_segment_privilege

test-segment-runtime-service:
	mkdir -p $(BUILD_DIR)/segment-runtime-service
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_runtime_service --Mdir $(BUILD_DIR)/segment-runtime-service $(SEGMENT_REGISTER_RTL) ../tb/tb_segment_runtime_service.sv
	./$(BUILD_DIR)/segment-runtime-service/Vtb_segment_runtime_service

test-segment-runtime-router:
	mkdir -p $(BUILD_DIR)/segment-runtime-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_segment_runtime_router --Mdir $(BUILD_DIR)/segment-runtime-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_segment_runtime_router.sv
	./$(BUILD_DIR)/segment-runtime-router/Vtb_segment_runtime_router

# Opt-in BAT-miss -> committed SR snapshot -> prefilled page-TLB lookup.
.PHONY: lint-page-path test-core-page-translation test-page-memory-router
lint: lint-page-path
test: test-core-page-translation test-page-memory-router
lint-page-path:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-core-page-translation:
	mkdir -p $(BUILD_DIR)/core-page-translation
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_translation --Mdir $(BUILD_DIR)/core-page-translation $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_translation.sv
	./$(BUILD_DIR)/core-page-translation/Vtb_core_page_translation

test-page-memory-router:
	mkdir -p $(BUILD_DIR)/page-memory-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_memory_router --Mdir $(BUILD_DIR)/page-memory-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_memory_router.sv
	./$(BUILD_DIR)/page-memory-router/Vtb_page_memory_router

# Opt-in supervisor tlbie with retirement-committed four-entry set invalidation.
.PHONY: lint-tlbie-integration test-tlbie-decode test-core-tlbie test-core-tlbie-privilege test-tlb-runtime-invalidate-service test-tlb-runtime-invalidate-router
lint: lint-tlbie-integration
test: test-tlbie-decode test-core-tlbie test-core-tlbie-privilege test-tlb-runtime-invalidate-service test-tlb-runtime-invalidate-router
lint-tlbie-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlbie-decode:
	mkdir -p $(BUILD_DIR)/tlbie-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlbie_decode --Mdir $(BUILD_DIR)/tlbie-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlbie_decode.sv
	./$(BUILD_DIR)/tlbie-decode/Vtb_tlbie_decode

test-core-tlbie:
	mkdir -p $(BUILD_DIR)/core-tlbie
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie --Mdir $(BUILD_DIR)/core-tlbie $(RTL) ../tb/tb_core_tlbie.sv
	./$(BUILD_DIR)/core-tlbie/Vtb_core_tlbie

test-core-tlbie-privilege:
	mkdir -p $(BUILD_DIR)/core-tlbie-privilege
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie_privilege --Mdir $(BUILD_DIR)/core-tlbie-privilege $(RTL) ../tb/tb_core_tlbie_privilege.sv
	./$(BUILD_DIR)/core-tlbie-privilege/Vtb_core_tlbie_privilege
	mkdir -p $(BUILD_DIR)/core-tlbie-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlbie_privilege -GFEATURE=0 --Mdir $(BUILD_DIR)/core-tlbie-disabled $(RTL) ../tb/tb_core_tlbie_privilege.sv
	./$(BUILD_DIR)/core-tlbie-disabled/Vtb_core_tlbie_privilege

test-tlb-runtime-invalidate-service:
	mkdir -p $(BUILD_DIR)/tlb-runtime-invalidate-service
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_invalidate_service --Mdir $(BUILD_DIR)/tlb-runtime-invalidate-service $(TLB_SERVICE_RTL) ../tb/tb_tlb_runtime_invalidate_service.sv
	./$(BUILD_DIR)/tlb-runtime-invalidate-service/Vtb_tlb_runtime_invalidate_service

test-tlb-runtime-invalidate-router:
	mkdir -p $(BUILD_DIR)/tlb-runtime-invalidate-router
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_invalidate_router --Mdir $(BUILD_DIR)/tlb-runtime-invalidate-router $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_invalidate_router.sv
	./$(BUILD_DIR)/tlb-runtime-invalidate-router/Vtb_tlb_runtime_invalidate_router

# Prepared TLB refill, independently checked in all invalidate/refill options.
.PHONY: test-tlb-prepared-refill
test: test-tlb-prepared-refill
test-tlb-prepared-refill:
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-00
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b0" "-GRUNTIME_REFILL=1'b0" --Mdir $(BUILD_DIR)/tlb-prepared-refill-00 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-00/Vtb_tlb_prepared_refill
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-01
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b0" "-GRUNTIME_REFILL=1'b1" --Mdir $(BUILD_DIR)/tlb-prepared-refill-01 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-01/Vtb_tlb_prepared_refill
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-10
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b1" "-GRUNTIME_REFILL=1'b0" --Mdir $(BUILD_DIR)/tlb-prepared-refill-10 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-10/Vtb_tlb_prepared_refill
	mkdir -p $(BUILD_DIR)/tlb-prepared-refill-11
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_prepared_refill "-GRUNTIME_INVALIDATE=1'b1" "-GRUNTIME_REFILL=1'b1" --Mdir $(BUILD_DIR)/tlb-prepared-refill-11 $(TLB_SERVICE_RTL) ../tb/tb_tlb_prepared_refill.sv
	./$(BUILD_DIR)/tlb-prepared-refill-11/Vtb_tlb_prepared_refill

# Opt-in committed DCMP, ICMP and RPA seed SPRs, before TLB load instructions.
.PHONY: lint-tlb-seed test-tlb-seed-decode test-core-tlb-seed
lint: lint-tlb-seed
test: test-tlb-seed-decode test-core-tlb-seed
lint-tlb-seed:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlb-seed-decode:
	mkdir -p $(BUILD_DIR)/tlb-seed-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_seed_decode --Mdir $(BUILD_DIR)/tlb-seed-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlb_seed_decode.sv
	./$(BUILD_DIR)/tlb-seed-decode/Vtb_tlb_seed_decode

test-core-tlb-seed:
	mkdir -p $(BUILD_DIR)/core-tlb-seed-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_seed --Mdir $(BUILD_DIR)/core-tlb-seed-enabled $(RTL) ../tb/tb_core_tlb_seed.sv
	./$(BUILD_DIR)/core-tlb-seed-enabled/Vtb_core_tlb_seed
	mkdir -p $(BUILD_DIR)/core-tlb-seed-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_seed "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-seed-disabled $(RTL) ../tb/tb_core_tlb_seed.sv
	./$(BUILD_DIR)/core-tlb-seed-disabled/Vtb_core_tlb_seed

# Router transaction ownership for retirement-prepared TLB fills.
.PHONY: test-tlb-runtime-fill-router
test: test-tlb-runtime-fill-router
test-tlb-runtime-fill-router:
	mkdir -p $(BUILD_DIR)/tlb-runtime-fill-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_fill_router --Mdir $(BUILD_DIR)/tlb-runtime-fill-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_fill_router.sv
	./$(BUILD_DIR)/tlb-runtime-fill-router-enabled/Vtb_tlb_runtime_fill_router
	mkdir -p $(BUILD_DIR)/tlb-runtime-fill-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_runtime_fill_router "-GENABLE_FILL=1'b0" --Mdir $(BUILD_DIR)/tlb-runtime-fill-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_tlb_runtime_fill_router.sv
	./$(BUILD_DIR)/tlb-runtime-fill-router-disabled/Vtb_tlb_runtime_fill_router

# CPU tlbld/tlbli decode and retirement-owned prepared-refill transport.
.PHONY: lint-tlb-load-integration test-tlb-load-decode test-core-tlb-load
lint: lint-tlb-load-integration
test: test-tlb-load-decode test-core-tlb-load
lint-tlb-load-integration:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL)
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-tlb-load-decode:
	mkdir -p $(BUILD_DIR)/tlb-load-decode
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_tlb_load_decode --Mdir $(BUILD_DIR)/tlb-load-decode ../rtl/ppc_pkg.sv ../rtl/ppc_decode.sv ../tb/tb_tlb_load_decode.sv
	./$(BUILD_DIR)/tlb-load-decode/Vtb_tlb_load_decode

test-core-tlb-load:
	mkdir -p $(BUILD_DIR)/core-tlb-load-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_load --Mdir $(BUILD_DIR)/core-tlb-load-enabled $(RTL) ../tb/tb_core_tlb_load.sv
	./$(BUILD_DIR)/core-tlb-load-enabled/Vtb_core_tlb_load
	mkdir -p $(BUILD_DIR)/core-tlb-load-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_load "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-load-disabled $(RTL) ../tb/tb_core_tlb_load.sv
	./$(BUILD_DIR)/core-tlb-load-disabled/Vtb_core_tlb_load

# Opt-in page-hit PP denial delivered through the existing precise data DSI.
.PHONY: lint-page-data-exceptions test-page-data-exception-router test-core-page-data-exception
lint: lint-page-data-exceptions
test: test-page-data-exception-router test-core-page-data-exception
lint-page-data-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-data-exception-router:
	mkdir -p $(BUILD_DIR)/page-data-exception-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_data_exception_router --Mdir $(BUILD_DIR)/page-data-exception-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_data_exception_router.sv
	./$(BUILD_DIR)/page-data-exception-router-enabled/Vtb_page_data_exception_router
	mkdir -p $(BUILD_DIR)/page-data-exception-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_data_exception_router "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/page-data-exception-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_data_exception_router.sv
	./$(BUILD_DIR)/page-data-exception-router-disabled/Vtb_page_data_exception_router

test-core-page-data-exception:
	mkdir -p $(BUILD_DIR)/core-page-data-exception
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_data_exception --Mdir $(BUILD_DIR)/core-page-data-exception $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_data_exception.sv
	./$(BUILD_DIR)/core-page-data-exception/Vtb_core_page_data_exception

# Opt-in page instruction PP, no-execute and guarded ISI delivery.
.PHONY: lint-page-instruction-exceptions test-page-instruction-exception-router test-core-page-instruction-exception
lint: lint-page-instruction-exceptions
test: test-page-instruction-exception-router test-core-page-instruction-exception
lint-page-instruction-exceptions:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-instruction-exception-router:
	mkdir -p $(BUILD_DIR)/page-instruction-exception-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_instruction_exception_router --Mdir $(BUILD_DIR)/page-instruction-exception-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_instruction_exception_router.sv
	./$(BUILD_DIR)/page-instruction-exception-router-enabled/Vtb_page_instruction_exception_router
	mkdir -p $(BUILD_DIR)/page-instruction-exception-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_instruction_exception_router "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/page-instruction-exception-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_instruction_exception_router.sv
	./$(BUILD_DIR)/page-instruction-exception-router-disabled/Vtb_page_instruction_exception_router

test-core-page-instruction-exception:
	mkdir -p $(BUILD_DIR)/core-page-instruction-exception
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_instruction_exception --Mdir $(BUILD_DIR)/core-page-instruction-exception $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../tb/tb_core_page_instruction_exception.sv
	./$(BUILD_DIR)/core-page-instruction-exception/Vtb_core_page_instruction_exception

# Response-bound page miss/changed diagnostic capsules; no architectural miss entry.
.PHONY: lint-page-miss-results test-page-miss-result-router test-core-page-miss-result
lint: lint-page-miss-results
test: test-page-miss-result-router test-core-page-miss-result
lint-page-miss-results:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core_bat "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL)

test-page-miss-result-router:
	mkdir -p $(BUILD_DIR)/page-miss-result-router-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_miss_result_router --Mdir $(BUILD_DIR)/page-miss-result-router-enabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_miss_result_router.sv
	./$(BUILD_DIR)/page-miss-result-router-enabled/Vtb_page_miss_result_router
	mkdir -p $(BUILD_DIR)/page-miss-result-router-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_page_miss_result_router "-GENABLE_PAGE_MISS_RESULTS=1'b0" --Mdir $(BUILD_DIR)/page-miss-result-router-disabled $(BAT_SERVICE_RTL) ../rtl/ppc_bat_memory_router.sv ../tb/tb_page_miss_result_router.sv
	./$(BUILD_DIR)/page-miss-result-router-disabled/Vtb_page_miss_result_router

test-core-page-miss-result:
	mkdir -p $(BUILD_DIR)/core-page-miss-result-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_miss_result --Mdir $(BUILD_DIR)/core-page-miss-result-enabled $(RTL) ../tb/tb_core_page_miss_result.sv
	./$(BUILD_DIR)/core-page-miss-result-enabled/Vtb_core_page_miss_result
	mkdir -p $(BUILD_DIR)/core-page-miss-result-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_page_miss_result "-GENABLE_PAGE_MISS_RESULTS=1'b0" --Mdir $(BUILD_DIR)/core-page-miss-result-disabled $(RTL) ../tb/tb_core_page_miss_result.sv
	./$(BUILD_DIR)/core-page-miss-result-disabled/Vtb_core_page_miss_result

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
	./$(BUILD_DIR)/sdr1-decode/Vtb_sdr1_decode

test-core-sdr1:
	mkdir -p $(BUILD_DIR)/core-sdr1-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sdr1 --Mdir $(BUILD_DIR)/core-sdr1-enabled $(RTL) ../tb/tb_core_sdr1.sv
	./$(BUILD_DIR)/core-sdr1-enabled/Vtb_core_sdr1
	mkdir -p $(BUILD_DIR)/core-sdr1-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_sdr1 "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-sdr1-disabled $(RTL) ../tb/tb_core_sdr1.sv
	./$(BUILD_DIR)/core-sdr1-disabled/Vtb_core_sdr1

test-miss-derive:
	mkdir -p $(BUILD_DIR)/miss-derive
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_miss_derive --Mdir $(BUILD_DIR)/miss-derive ../rtl/ppc_miss_derive.sv ../tb/tb_miss_derive.sv
	./$(BUILD_DIR)/miss-derive/Vtb_miss_derive

# Temporary GPR0–GPR3 overlay under opt-in MSR.TGPR context control.
.PHONY: lint-tgpr test-regfile-tgpr test-core-tgpr
lint: lint-tgpr
test: test-regfile-tgpr test-core-tgpr
lint-tgpr:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TGPR=1'b1" $(RTL)

test-regfile-tgpr:
	mkdir -p $(BUILD_DIR)/regfile-tgpr-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_tgpr --Mdir $(BUILD_DIR)/regfile-tgpr-enabled ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_tgpr.sv
	./$(BUILD_DIR)/regfile-tgpr-enabled/Vtb_regfile_tgpr
	mkdir -p $(BUILD_DIR)/regfile-tgpr-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_regfile_tgpr "-GENABLE_TGPR=1'b0" --Mdir $(BUILD_DIR)/regfile-tgpr-disabled ../rtl/ppc_regfile_gpr.sv ../tb/tb_regfile_tgpr.sv
	./$(BUILD_DIR)/regfile-tgpr-disabled/Vtb_regfile_tgpr

test-core-tgpr:
	mkdir -p $(BUILD_DIR)/core-tgpr-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tgpr --Mdir $(BUILD_DIR)/core-tgpr-enabled $(RTL) ../tb/tb_core_tgpr.sv
	./$(BUILD_DIR)/core-tgpr-enabled/Vtb_core_tgpr
	mkdir -p $(BUILD_DIR)/core-tgpr-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tgpr "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tgpr-disabled $(RTL) ../tb/tb_core_tgpr.sv
	./$(BUILD_DIR)/core-tgpr-disabled/Vtb_core_tgpr

# Architectural opt-in 603e TLB miss event and actual-core retirement boundaries.
.PHONY: lint-tlb-miss test-exception-tlb-miss test-core-tlb-miss
lint: lint-tlb-miss
test: test-exception-tlb-miss test-core-tlb-miss
lint-tlb-miss:
	$(VERILATOR) --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TLB_LOAD=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" $(RTL)

test-exception-tlb-miss:
	mkdir -p $(BUILD_DIR)/exception-tlb-miss-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_tlb_miss --Mdir $(BUILD_DIR)/exception-tlb-miss-enabled ../rtl/ppc_exception_state.sv ../tb/tb_exception_tlb_miss.sv
	./$(BUILD_DIR)/exception-tlb-miss-enabled/Vtb_exception_tlb_miss
	mkdir -p $(BUILD_DIR)/exception-tlb-miss-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_exception_tlb_miss "-GENABLE_TLB_MISS_EXCEPTIONS=1'b0" --Mdir $(BUILD_DIR)/exception-tlb-miss-disabled ../rtl/ppc_exception_state.sv ../tb/tb_exception_tlb_miss.sv
	./$(BUILD_DIR)/exception-tlb-miss-disabled/Vtb_exception_tlb_miss

test-core-tlb-miss:
	mkdir -p $(BUILD_DIR)/core-tlb-miss-enabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_miss --Mdir $(BUILD_DIR)/core-tlb-miss-enabled $(RTL) ../tb/tb_core_tlb_miss.sv
	./$(BUILD_DIR)/core-tlb-miss-enabled/Vtb_core_tlb_miss
	mkdir -p $(BUILD_DIR)/core-tlb-miss-disabled
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_tlb_miss "-GFEATURE=1'b0" --Mdir $(BUILD_DIR)/core-tlb-miss-disabled $(RTL) ../tb/tb_core_tlb_miss.sv
	./$(BUILD_DIR)/core-tlb-miss-disabled/Vtb_core_tlb_miss

# Translated core with the existing cache-inhibited scalar 60x transport.
CORE_BAT_BUS60X_RTL := $(RTL) $(BAT_SERVICE_RTL) $(CORE_BAT_RTL) ../rtl/ppc_bus60x.sv ../rtl/ppc_bus60x_arbiter.sv $(shell cat ../rtl/core_bat_bus60x_files.f)
.PHONY: test-core-bat-bus60x
test: test-core-bat-bus60x
test-core-bat-bus60x:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x --Mdir $(BUILD_DIR)/core-bat-bus60x $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x.sv
	./$(BUILD_DIR)/core-bat-bus60x/Vtb_core_bat_bus60x

.PHONY: lint-core-bat-bus60x
lint: lint-core-bat-bus60x
lint-core-bat-bus60x:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_bus60x $(CORE_BAT_BUS60X_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(CORE_BAT_BUS60X_RTL)

.PHONY: test-core-bat-bus60x-retry
test: test-core-bat-bus60x-retry
test-core-bat-bus60x-retry:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x-retry
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x_retry --Mdir $(BUILD_DIR)/core-bat-bus60x-retry $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x_retry.sv
	./$(BUILD_DIR)/core-bat-bus60x-retry/Vtb_core_bat_bus60x_retry

.PHONY: test-core-bat-bus60x-errors
test: test-core-bat-bus60x-errors
test-core-bat-bus60x-errors:
	mkdir -p $(BUILD_DIR)/core-bat-bus60x-errors
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_bus60x_errors --Mdir $(BUILD_DIR)/core-bat-bus60x-errors $(CORE_BAT_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_bus60x_errors.sv
	./$(BUILD_DIR)/core-bat-bus60x-errors/Vtb_core_bat_bus60x_errors

# Physical instruction cache after CPU-owned translation and permissions.
CORE_BAT_CACHED_BUS60X_RTL := $(CORE_BAT_BUS60X_RTL) $(LINE_RTL) $(ICACHE_RTL) $(CACHED_SYSTEM_RTL) $(CACHE_CONTROL_RTL) $(shell cat ../rtl/core_bat_cached_bus60x_files.f)
.PHONY: test-core-bat-cached-bus60x lint-core-bat-cached-bus60x
test: test-core-bat-cached-bus60x
test-core-bat-cached-bus60x:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x --Mdir $(BUILD_DIR)/core-bat-cached-bus60x $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x/Vtb_core_bat_cached_bus60x
lint: lint-core-bat-cached-bus60x
lint-core-bat-cached-bus60x:
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_cached_bus60x $(CORE_BAT_CACHED_BUS60X_RTL)
	$(VERILATOR) --lint-only --assert -Wall --top-module ppc_core_bat_cached_bus60x "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" "-GENABLE_LIVE_CONTEXT=1'b1" "-GENABLE_RUNTIME_BAT=1'b1" "-GENABLE_EXTERNAL_INTERRUPTS=1'b1" "-GENABLE_TIMERS=1'b1" "-GENABLE_SEGMENT_REGISTERS=1'b1" "-GENABLE_SDR1=1'b1" "-GENABLE_TGPR=1'b1" "-GENABLE_TLB_MISS_EXCEPTIONS=1'b1" "-GENABLE_PAGE_TRANSLATION=1'b1" "-GENABLE_PAGE_MISS_RESULTS=1'b1" "-GENABLE_PAGE_DATA_EXCEPTIONS=1'b1" "-GENABLE_PAGE_INSTRUCTION_EXCEPTIONS=1'b1" "-GENABLE_TLB_INVALIDATE=1'b1" "-GENABLE_TLB_LOAD=1'b1" $(CORE_BAT_CACHED_BUS60X_RTL)

.PHONY: test-core-bat-cached-bus60x-drain
test: test-core-bat-cached-bus60x-drain
test-core-bat-cached-bus60x-drain:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-drain
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_drain --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-drain $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_drain.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-drain/Vtb_core_bat_cached_bus60x_drain

.PHONY: test-core-bat-cached-bus60x-coherence
test: test-core-bat-cached-bus60x-coherence
test-core-bat-cached-bus60x-coherence:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-coherence
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_coherence --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-coherence $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_coherence.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-coherence/Vtb_core_bat_cached_bus60x_coherence

# Precise external interrupt while a translated cache refill is outstanding.
.PHONY: test-core-bat-cached-bus60x-irq
test: test-core-bat-cached-bus60x-irq
test-core-bat-cached-bus60x-irq:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-irq
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_irq --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-irq $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_irq.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-irq/Vtb_core_bat_cached_bus60x_irq

# DEC-to-EXT promotion while a translated cache refill drains.
.PHONY: test-core-bat-cached-bus60x-timer
test: test-core-bat-cached-bus60x-timer
test-core-bat-cached-bus60x-timer:
	mkdir -p $(BUILD_DIR)/core-bat-cached-bus60x-timer
	$(VERILATOR) --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_timer --Mdir $(BUILD_DIR)/core-bat-cached-bus60x-timer $(CORE_BAT_CACHED_BUS60X_RTL) ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_timer.sv
	./$(BUILD_DIR)/core-bat-cached-bus60x-timer/Vtb_core_bat_cached_bus60x_timer
