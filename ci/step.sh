#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Runs one workflow step and, on failure, repeats the last 40 lines of its
# output as an error annotation, which the public run page shows without login.
set -uo pipefail
log="$(mktemp)"
"$@" 2>&1 | tee "${log}"
rc=${PIPESTATUS[0]}
if ((rc != 0)); then
  tail -n 40 "${log}" | python3 -c 'import sys; t=sys.stdin.read(); print("::error title=" + sys.argv[1] + " failed::" + t.replace("%", "%25").replace("\r", "").replace("\n", "%0A"))' "$1"
fi
rm -f "${log}"
exit "${rc}"
