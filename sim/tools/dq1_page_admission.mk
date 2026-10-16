# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional bounded four-state check; Icarus is not a default dependency.
.PHONY: test-dq1-page-admission-proof
test-dq1-page-admission-proof:
	python3 tools/check_dq1_page_admission.py --output $(BUILD_DIR)/dq1-page-admission/generated
	@set -eu; proof_output='$(abspath $(BUILD_DIR))/dq1-page-admission/proof.vvp'; \
	trap 'rm -f -- "$$proof_output"' EXIT; \
	timeout 30s iverilog -g2012 -s tb_dq1_page_admission_proof \
	  -o "$$proof_output" $(BUILD_DIR)/dq1-page-admission/generated/dq1_page_predicates.sv \
	  ../tb/tb_dq1_page_admission_proof.sv; \
	timeout 120s vvp "$$proof_output"
