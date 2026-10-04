#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Runs one workflow step and, on failure, posts an error annotation, which the
# public run page shows without login: the first 20 lines that look like errors
# (parallel make interleaves them far from the end), then the end of the output,
# within GitHub's annotation size limit.
set -uo pipefail
log="$(mktemp)"
"$@" 2>&1 | tee "${log}"
rc=${PIPESTATUS[0]}
if ((rc != 0)); then
  python3 - "$1" "${log}" <<'PY'
import re, sys
text = open(sys.argv[2], errors="replace").read()
errors = [l for l in text.splitlines()
          if re.search(r"FAIL|error:|Error [0-9]|\*\*\*|%Error|%Fatal|Assertion|negative slack", l)
          and not re.search(r"-Werror|^\S*gcc ", l)][:20]
tail = text[-1500:]
body = "end of output:\n" + tail + "\n--- error lines:\n" + "\n".join(l[:200] for l in errors)
body = body[:3500]
print("::error title=" + sys.argv[1] + " failed::" + body.replace("%", "%25").replace("\r", "").replace("\n", "%0A"))
PY
fi
rm -f "${log}"
exit "${rc}"
