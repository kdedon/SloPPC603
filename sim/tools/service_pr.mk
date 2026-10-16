# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Bounded four-state and actual-router temporal projection checks.
# Icarus remains optional; the actual-router pair joins normal regression.
.PHONY: test-service-pr-input-proof test-service-pr-router-pair
test: test-service-pr-router-pair

test-service-pr-input-proof:
	python3 tools/check_service_pr_projection.py --output $(BUILD_DIR)/service-pr-input/generated
	@set -eu; proof_output='$(abspath $(BUILD_DIR))/service-pr-input/proof.vvp'; \
	trap 'rm -f -- "$$proof_output"' EXIT; \
	for runtime_bat in 0 1; do \
	  timeout 30s iverilog -g2012 -s tb_service_pr_payload \
	    -Ptb_service_pr_payload.ENABLE_RUNTIME_BAT=$$runtime_bat \
	    -o "$$proof_output" $(BUILD_DIR)/service-pr-input/generated/ppc_pkg.sv \
	    ../tb/tb_service_pr_payload.sv; \
	  timeout 90s vvp "$$proof_output"; \
	done

test-service-pr-router-pair:
	python3 tools/check_service_pr_projection.py --output $(BUILD_DIR)/service-pr-router/generated
	OBJCACHE= timeout 300s $(VERILATOR) --binary --timing --assert -Wall -j 1 \
	  --top-module tb_service_pr_router_pair --Mdir $(BUILD_DIR)/service-pr-router/obj \
	  $(BAT_SERVICE_RTL) $(BUILD_DIR)/service-pr-router/generated/ppc_bat_memory_router_original.sv \
	  ../rtl/ppc_bat_memory_router.sv ../tb/tb_service_pr_router_pair.sv
	timeout 90s $(abspath $(BUILD_DIR))/service-pr-router/obj/Vtb_service_pr_router_pair $(SIM_ARGS)
