# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional Icarus proof; does not extend the default test or coverage targets.
.PHONY: test-d1-alignment-admission-equivalence
test-d1-alignment-admission-equivalence:
	python3 tools/check_d1_alignment_admission.py --output "$(BUILD_DIR)/d1-alignment-admission-proof"
