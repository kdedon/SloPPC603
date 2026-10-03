#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Runs one workflow step and, on failure, repeats the end of its output (the
# last 3500 characters, under GitHub's annotation limit) as an error
# annotation, which the public run page shows without login.
set -uo pipefail
log="$(mktemp)"
"$@" 2>&1 | tee "${log}"
rc=${PIPESTATUS[0]}
if ((rc != 0)); then
  python3 -c 'import sys; t=open(sys.argv[2], errors="replace").read()[-3500:]; print("::error title=" + sys.argv[1] + " failed::" + t.replace("%", "%25").replace("\r", "").replace("\n", "%0A"))' "$1" "${log}"
fi
rm -f "${log}"
exit "${rc}"
