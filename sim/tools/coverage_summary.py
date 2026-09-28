#!/usr/bin/env python3
"""Summarize Verilator line coverage of rtl/ and gate uncovered control arms.

Points from all inputs merge by source location, so a line counts as covered
when any run and any instance reached it. Every case arm in a CONTROL file
must be covered or listed in the waiver file with a reason.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

# Modules whose case arms are the control states of the translated cached
# 60x path: bus masters, router, caches, TLB and exception sequencing.
CONTROL = (
    'rtl/ppc_bus60x.sv',
    'rtl/ppc_bus60x_line_read.sv',
    'rtl/ppc_bus60x_two_master.sv',
    'rtl/ppc_bat_memory_router.sv',
    'rtl/ppc_icache.sv',
    'rtl/ppc_icache_managed.sv',
    'rtl/ppc_icache_bus60x.sv',
    'rtl/ppc_tlb_service.sv',
    'rtl/ppc_fetch.sv',
)
POINT = re.compile(r"^C '(.*)' (\d+)$")


def parse(path):
    for line in Path(path).read_text().splitlines():
        match = POINT.match(line)
        if not match:
            continue
        fields = dict(item.split('\x02', 1) for item in match.group(1).split('\x01') if item)
        yield fields, int(match.group(2))


def rtl_name(source):
    parts = Path(source).parts
    return 'rtl/' + parts[-1] if 'rtl' in parts else None


def load_waivers(path):
    waivers = {}
    if path and Path(path).exists():
        for line in Path(path).read_text().splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            name, text, reason = (field.strip() for field in line.split('|', 2))
            waivers[(name, text)] = reason
    return waivers


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dat', nargs='+', help='coverage.dat files')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--waivers', help='file of "rtl/file.sv | source text | reason" lines')
    parser.add_argument('--min-total', type=float, default=0.0, help='minimum rtl/ line coverage, percent')
    args = parser.parse_args()

    counts = defaultdict(int)
    kinds = {}
    for dat in args.dat:
        for fields, count in parse(dat):
            name = rtl_name(fields.get('f', ''))
            if name is None:
                continue
            key = (name, int(fields['l']), int(fields.get('n', 0)))
            counts[key] += count
            kinds[key] = fields.get('o', '')

    per_file = defaultdict(lambda: [0, 0])
    for (name, _, _), count in counts.items():
        per_file[name][0] += 1
        per_file[name][1] += count > 0
    total = sum(points for points, _ in per_file.values())
    covered = sum(hit for _, hit in per_file.values())
    print(f'{"file":44} {"points":>6} {"covered":>7} {"%":>6}')
    for name in sorted(per_file):
        points, hit = per_file[name]
        print(f'{name:44} {points:6} {hit:7} {100.0 * hit / points:6.1f}')
    percent = 100.0 * covered / total if total else 0.0
    print(f'{"total":44} {total:6} {covered:7} {percent:6.1f}')

    waivers = load_waivers(args.waivers)
    used = set()
    unwaived = []
    for key in sorted(counts):
        name, line, _ = key
        if name not in CONTROL or kinds[key] != 'case' or counts[key]:
            continue
        lines = (args.root/name).read_text().splitlines()
        text = ' '.join(lines[line - 1].split()) if line <= len(lines) else ''
        if (name, text) in waivers:
            used.add((name, text))
            print(f'waived   {name}:{line}: {text}  ({waivers[(name, text)]})')
        else:
            unwaived.append(f'{name}:{line}: {text}')
    for entry in unwaived:
        print(f'UNCOVERED {entry}')
    for name, text in sorted(set(waivers) - used):
        print(f'stale waiver (now covered or moved): {name} | {text}')

    failed = False
    if percent < args.min_total:
        print(f'FAIL: rtl/ line coverage {percent:.1f}% below {args.min_total:.1f}%')
        failed = True
    if unwaived:
        print(f'FAIL: {len(unwaived)} uncovered control arm(s) without a waiver')
        failed = True
    if not failed:
        print(f'PASS: rtl/ line coverage {percent:.1f}% ({covered}/{total}), '
              f'{len(used)} waived control arm(s), {len(args.dat)} run(s)')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
