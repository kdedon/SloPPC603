# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional standalone Icarus selector proof; no default suite dependency.
.PHONY: test-iu-record-flags-proof
test-iu-record-flags-proof:
	python3 tools/check_iu_record_flags.py --output "$(BUILD_DIR)/iu-record-flags-proof"
