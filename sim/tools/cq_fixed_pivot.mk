# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional four-state expression proof; deliberately not a default regression dependency.
.PHONY: test-cq-fixed-pivot-source-equivalence
test-cq-fixed-pivot-source-equivalence:
	python3 tools/check_cq_fixed_pivot_projection.py --output $(BUILD_DIR)/cq-fixed-pivot-source
