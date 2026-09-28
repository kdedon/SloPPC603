#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail

for tool in quartus_sh quartus_map quartus_fit quartus_sta; do
  if command -v "${tool}" >/dev/null 2>&1; then
    printf 'FOUND   %-16s %s\n' "${tool}" "$(command -v "${tool}")"
  else
    printf 'MISSING %-16s\n' "${tool}"
  fi
done

if command -v quartus_sh >/dev/null 2>&1; then
  quartus_sh --version | sed -n '1,5p'
fi
