# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Require disk headroom before creating a Quartus build; never delete files."""

from pathlib import Path
import shutil
import sys


def main():
    minimum = 4 * 1024**3
    paths = [Path(arg).resolve(strict=True) for arg in sys.argv[1:]]
    if not paths:
        raise SystemExit("usage: check_disk_space.py DIRECTORY [DIRECTORY ...]")
    checked_devices = set()
    for path in paths:
        device = path.stat().st_dev
        if device in checked_devices:
            continue
        checked_devices.add(device)
        free = shutil.disk_usage(path).free
        print(f"Build disk headroom at {path}: {free / 1024**3:.2f} GiB free")
        if free < minimum:
            raise SystemExit(
                "ERROR: Quartus requires at least 4 GiB free before starting; "
                "remove completed generated builds or free space, then retry."
            )


if __name__ == "__main__":
    main()
