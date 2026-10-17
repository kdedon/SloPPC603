# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional Icarus control-product proof; no default test dependency.
.PHONY: test-special-port1-offer-proof
test-special-port1-offer-proof:
	python3 tools/check_special_port1_offer.py --output $(BUILD_DIR)/special-port1-offer-proof
	@set -eu; proof_output='$(abspath $(BUILD_DIR))/special-port1-offer-proof/proof.vvp'; \
	trap 'rm -f -- "$$proof_output"' EXIT; \
	timeout 30s iverilog -g2012 -s tb_special_port1_projection -o "$$proof_output" $(BUILD_DIR)/special-port1-offer-proof/tb_special_port1_projection.sv; \
	timeout 90s vvp "$$proof_output"
