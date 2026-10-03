#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Fails when a tracked file declares a licence other than the project's.

The project is GPL-2.0-or-later; files that build against DingusPPC are
GPL-3.0-or-later. Anything else, such as a stale MIT header, is reported.
"""
import pathlib
import re
import subprocess
import sys

ALLOWED = {"GPL-2.0-or-later", "GPL-3.0-or-later"}
TAG = "SPDX-License-" + "Identifier:"

root = pathlib.Path(__file__).resolve().parents[2]
files = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], check=True,
                       capture_output=True).stdout.decode().split("\0")
bad = []
for name in filter(None, files):
    path = root / name
    if not path.is_file():
        continue
    try:
        head = path.read_text(errors="strict").splitlines()[:6]
    except (UnicodeDecodeError, OSError):
        continue
    for line in head:
        m = re.search(re.escape(TAG) + r"\s*([A-Za-z0-9.+-]+)", line)
        if m and m.group(1) not in ALLOWED:
            bad.append(f"{name}: {m.group(1)}")
if bad:
    print("FAIL: licence identifiers outside " + ", ".join(sorted(ALLOWED)))
    print("\n".join(bad))
    sys.exit(1)
print("PASS: every SPDX identifier is " + " or ".join(sorted(ALLOWED)))
