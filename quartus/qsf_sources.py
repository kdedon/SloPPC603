#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Regenerate each project's QSF source assignments from its files.f.

Every PROJECT_DIR holds one *.qsf and a files.f. Existing SYSTEMVERILOG_FILE
and VERILOG_FILE lines are replaced, in files.f order, at the position of the
first one. With --check, nothing is written and any difference fails.
"""
import argparse
import difflib
from pathlib import Path
import re
import sys

SOURCE = re.compile(r'^set_global_assignment -name (SYSTEM)?VERILOG_FILE ')


def generate(project: Path) -> tuple[Path, str, str]:
    qsfs = sorted(project.glob('*.qsf'))
    if len(qsfs) != 1:
        raise ValueError(f'{project}: expected exactly one .qsf, found {len(qsfs)}')
    qsf = qsfs[0]
    sources = [line.strip() for line in (project/'files.f').read_text().splitlines() if line.strip()]
    if not sources:
        raise ValueError(f'{project}/files.f is empty')
    missing = [s for s in sources if not (project/s).is_file()]
    if missing:
        raise ValueError(f'{project}/files.f lists missing sources: {missing}')
    block = [f'set_global_assignment -name SYSTEMVERILOG_FILE {s}' for s in sources]
    old = qsf.read_text()
    lines = old.splitlines()
    kept = [line for line in lines if not SOURCE.match(line)]
    first = next((i for i, line in enumerate(lines) if SOURCE.match(line)), None)
    if first is None:
        # No existing block: place sources before the first instance assignment.
        first = next((i for i, line in enumerate(kept) if line.startswith('set_instance_assignment')), len(kept))
    new = '\n'.join(kept[:first] + block + kept[first:]) + '\n'
    return qsf, old, new


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='fail on drift instead of rewriting')
    parser.add_argument('projects', nargs='+', type=Path, metavar='PROJECT_DIR')
    args = parser.parse_args()
    status = 0
    for project in args.projects:
        qsf, old, new = generate(project)
        if old == new:
            continue
        if args.check:
            sys.stderr.writelines(difflib.unified_diff(
                old.splitlines(True), new.splitlines(True), str(qsf), f'{qsf} (from files.f)'))
            print(f'ERROR: {qsf} sources differ from files.f; run {sys.argv[0]} {project}', file=sys.stderr)
            status = 1
        else:
            qsf.write_text(new)
            print(f'Updated {qsf} from files.f')
    return status


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        sys.exit(f'ERROR: {error}')
