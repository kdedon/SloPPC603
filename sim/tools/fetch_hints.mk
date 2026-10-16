# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Optional acceptance. Parent/caller coordinates the simulator lock.
FETCH_HINTS_PROFILE ?= focused
FETCH_HINTS_VALUE ?= 1
FETCH_HINTS_DIR ?= $(BUILD_DIR)/fetch-hints
FETCH_HINTS_TIMEOUT ?= 3600
.PHONY: test-fetch-hints test-fetch-hints-cached test-fetch-hints-package check-fetch-hint-config

test-fetch-hints: check-fetch-hint-config
	python3 tools/run_fetch_hints.py --profile $(FETCH_HINTS_PROFILE) --hints $(FETCH_HINTS_VALUE) --build-dir $(FETCH_HINTS_DIR) --timeout $(FETCH_HINTS_TIMEOUT)

test-fetch-hints-cached: check-fetch-hint-config
	python3 tools/run_fetch_hints.py --profile cached-all --hints $(FETCH_HINTS_VALUE) --build-dir $(FETCH_HINTS_DIR) --timeout $(FETCH_HINTS_TIMEOUT)

test-fetch-hints-package: check-fetch-hint-config
	python3 tools/run_fetch_hints.py --profile package --hints $(FETCH_HINTS_VALUE) --build-dir $(FETCH_HINTS_DIR) --timeout $(FETCH_HINTS_TIMEOUT)

check-fetch-hint-config:
	python3 tools/check_fetch_hint_config.py

# Optional four-model same-source identity gate; no firmware build/default cost.
FETCH_HINTS_BENCH_DIR ?= $(BUILD_DIR)/fetch-hints-benchmark
FETCH_HINTS_BENCH_QUIET ?= 0
FETCH_HINTS_BENCH_TIMEOUT ?= 7200
.PHONY: benchmark-fetch-hints
benchmark-fetch-hints: check-fetch-hint-config
	python3 tools/benchmark_fetch_hints.py --image $(INTEGER_PAIR_IMAGE) --dump $(INTEGER_PAIR_DUMP) --output $(FETCH_HINTS_BENCH_DIR) --quiet-observe $(FETCH_HINTS_BENCH_QUIET) --timeout $(FETCH_HINTS_BENCH_TIMEOUT)
