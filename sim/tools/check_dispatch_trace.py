#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Compare a core dispatch/retire event trace with an expected schedule.

Trace lines come from ppc_core's +DISPATCH_TRACE monitor:
    <cycle> D<n> R<n> <dispatch pcs...> | <retire pcs...>
An expected schedule uses the same format; '#' starts a comment.
"""
import argparse
import json
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse(text):
    """Return {cycle: (dispatch pcs, retire pcs)}."""
    events = {}
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        head, _, retired = line.partition('|')
        fields = head.split()
        require(len(fields) >= 3 and fields[1][0] == 'D' and fields[2][0] == 'R',
                f'line {number}: malformed event')
        cycle, dispatched = int(fields[0]), [int(x, 16) for x in fields[3:]]
        retired = [int(x, 16) for x in retired.split()]
        require(len(dispatched) == int(fields[1][1:]) and len(retired) == int(fields[2][1:]),
                f'line {number}: count does not match pcs')
        require(dispatched or retired, f'line {number}: empty event')
        require(cycle not in events, f'line {number}: duplicate cycle {cycle}')
        events[cycle] = (dispatched, retired)
    return events


def compare(actual, expected):
    """Exact per-cycle match; returns (dispatch count, retire count, last cycle)."""
    for cycle in sorted(set(actual) | set(expected)):
        require(actual.get(cycle) == expected.get(cycle),
                f'cycle {cycle}: got {actual.get(cycle)}, expected {expected.get(cycle)}')
    return (sum(len(d) for d, _ in actual.values()), sum(len(r) for _, r in actual.values()),
            max(actual, default=-1))


def stage_events(rows):
    """Events implied by the stage bench's own edge trace (retire counted when accepted)."""
    events = {}
    for row in rows:
        dispatched = [row['dispatch']['pc']] if 'dispatch' in row else []
        retired = [row['retire']['pc']] if 'retire' in row and row['retire_ready'] else []
        if dispatched or retired:
            events[row['edge']] = (dispatched, retired)
    return events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('expected', type=Path, nargs='?')
    parser.add_argument('--stage', type=Path, help='cross-check against a stage-timing edge trace')
    args = parser.parse_args()
    try:
        actual = parse(args.trace.read_text())
        require(actual, 'empty trace')
        if args.stage:
            compare(actual, stage_events([json.loads(s) for s in args.stage.read_text().splitlines()]))
        if args.expected:
            dispatched, retired, last = compare(actual, parse(args.expected.read_text()))
            print(f'PASS dispatch schedule {args.expected.name}: {dispatched} dispatches, '
                  f'{retired} retirements, last event cycle {last}')
        elif args.stage:
            print('PASS dispatch trace matches the stage edge trace')
    except (ValueError, KeyError) as error:
        parser.exit(1, f'FAIL dispatch schedule: {error}\n')


if __name__ == '__main__':
    main()
