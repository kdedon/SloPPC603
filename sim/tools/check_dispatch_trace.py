#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Compare a core dispatch/retire event trace with an expected schedule.

Trace lines come from ppc_core's +DISPATCH_TRACE monitor:
    <cycle> D<n> R<n> <dispatch pcs...> | <retire pcs...>
An expected schedule uses the same format; '#' starts a comment.

--rules checks a trace of any length, streamed, against the 603e dispatch and
completion rules (sim/spec/timing.json), with instruction words from a RAM
image. See DUAL_DISPATCH_DESIGN.md.
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


IU, SRU, LSU, FPU, BPU = 'IU', 'SRU', 'LSU', 'FPU', 'BPU'
UPDATE_LOADS = {33, 35, 41, 43}
UPDATE_X_LOADS = {55, 119, 311, 375}


def classify(word, sru):
    """Return the dispatch/completion class of one instruction word.

    units: the units it may issue to; dser/cser: dispatch-/completion-
    serialized (TIM-SER-*); cq1: may complete from CQ[1] (TIM-CQ-CQ1/ORDER,
    plus branches, which this core keeps in the CQ); writes: (GPR, CR, FPR,
    LR, CTR) updates for TIM-WB-LIMITS; isync and multiple for the trace.
    """
    op, xo = word >> 26, (word >> 1) & 1023
    rc = word & 1 if op in (20, 21, 23, 31, 59, 63) else 0  # D-form bit 31 is immediate
    c = dict(units={IU}, dser=False, cser=False, cq1=True, writes=[1, rc, 0, 0, 0],
             isync=False, multiple=False)
    sru_unit = lambda: c.update(units={SRU}, cser=True, cq1=False, writes=[0, 0, 0, 0, 0])
    if op in (16, 18) or (op == 19 and xo in (16, 528)):
        lk = word & 1
        ctr = op == 19 and xo == 16 and not (word >> 23) & 1 or op == 16 and not (word >> 23) & 1
        c.update(units={BPU}, writes=[0, 0, 0, lk, int(bool(ctr))])
    elif op == 19:
        sru_unit()
        c['writes'][1] = int(xo != 150 and xo != 50)
        if xo in (150, 50):
            c['dser'] = True
        c['isync'] = xo == 150
    elif op == 17:
        sru_unit()
        c['dser'] = True
    elif op in (32, 33, 34, 35, 40, 41, 42, 43):
        c.update(units={LSU}, writes=[1 + (op in UPDATE_LOADS), 0, 0, 0, 0])
    elif op in (36, 37, 38, 39, 44, 45):
        c.update(units={LSU}, cq1=False, writes=[op & 1, 0, 0, 0, 0])
    elif op in (46, 47):
        c.update(units={LSU}, cq1=False, cser=True, dser=op == 46, multiple=True, writes=[0, 0, 0, 0, 0])
    elif 48 <= op <= 51:
        c.update(units={LSU}, writes=[op & 1, 0, 1, 0, 0])
    elif 52 <= op <= 55:
        c.update(units={LSU}, cq1=False, writes=[op & 1, 0, 0, 0, 0])
    elif op in (59, 63):
        c.update(units={FPU}, cq1=False, writes=[0, rc, 1, 0, 0])
        if op == 63 and xo in (0, 32, 64):
            c['writes'][1:3] = [1, 0]  # fcmpu, fcmpo, mcrfs
        elif op == 63 and xo in (38, 70, 134, 711):
            c['writes'][2] = 0  # FPSCR moves
        if op == 63 and xo in (38, 64, 70, 134, 583, 711):
            c['cser'] = True
    elif op in (14, 15, 11, 10):
        c['units'] = {IU, SRU} if sru else {IU}
        c['writes'] = [0, 1, 0, 0, 0] if op in (10, 11) else [1, 0, 0, 0, 0]
    elif op in (13, 28, 29):
        c['writes'] = [1, 1, 0, 0, 0]
    elif op in (3, 2):
        c['writes'] = [0, 0, 0, 0, 0]
    elif op == 31:
        if xo in (0, 32):
            c['units'] = {IU, SRU} if sru else {IU}
            c['writes'] = [0, 1, 0, 0, 0]
        elif (xo & 511) == 266 and not rc:
            c['units'] = {IU, SRU} if sru else {IU}
        elif xo in (4,):
            c['writes'] = [0, 0, 0, 0, 0]
        elif xo in (23, 55, 87, 119, 279, 311, 343, 375, 534, 790, 20, 310):
            c.update(units={LSU}, writes=[1 + (xo in UPDATE_X_LOADS), 0, 0, 0, 0])
        elif xo in (533, 597):
            c.update(units={LSU}, cq1=False, cser=True, dser=True, multiple=True, writes=[0, 0, 0, 0, 0])
        elif xo in (151, 183, 215, 247, 407, 439, 662, 918, 438):
            c.update(units={LSU}, cq1=False, writes=[int(xo in (183, 247, 439)), 0, 0, 0, 0])
        elif xo == 150:
            c.update(units={LSU}, cq1=False, writes=[0, 1, 0, 0, 0])
        elif xo in (661, 725):
            c.update(units={LSU}, cq1=False, cser=True, multiple=True, writes=[0, 0, 0, 0, 0])
        elif xo in (535, 567, 599, 631):
            c.update(units={LSU}, writes=[int(xo in (567, 631)), 0, 1, 0, 0])
        elif xo in (663, 695, 727, 759, 983):
            c.update(units={LSU}, cq1=False, writes=[int(xo in (695, 759)), 0, 0, 0, 0])
        elif xo in (1014, 86, 54, 470, 982, 278, 246, 854):
            c.update(units={LSU}, cq1=False, cser=xo != 854, writes=[0, 0, 0, 0, 0])
        elif xo in (306, 566, 978, 1010):
            sru_unit()
        elif xo == 598:
            sru_unit()
            c['dser'] = True
        elif xo in (339, 371, 83, 19, 595, 659):
            sru_unit()
            c['writes'][0] = 1
        elif xo in (467, 146, 144, 210, 242, 512):
            sru_unit()
            spr = ((word >> 16) & 31) | ((word >> 11) & 31) << 5
            c['dser'] = xo in (146, 512) or (xo == 467 and spr == 1)
            c['writes'][1] = int(xo in (144, 512))
            c['writes'][3] = int(xo == 467 and spr == 8)
            c['writes'][4] = int(xo == 467 and spr == 9)
    return c


class Rules:
    """Streaming check of TIM-DISP-WIDTH/DQ1, TIM-SER-DISPATCH/COMPLETE/REFETCH,
    TIM-CQ-CQ1/ORDER and TIM-WB-LIMITS over one trace."""

    def __init__(self, width, words, sru, flush):
        self.width, self.words, self.sru, self.flush = width, words, sru, flush
        self.inflight = []      # [pc, dispatch cycle, sequence number] in dispatch order
        self.seq = 0
        self.block = None       # dispatch-serialized instruction not yet retired: [seq, cycle]
        self.last_dser = None   # (seq, dispatch cycle) of the latest dispatch-serialized dispatch
        self.isync_retired = None
        self.last_retired_pc = None
        self.stats = dict(cycles=0, dispatches=0, retirements=0, pairs_dispatched=0, pairs_retired=0,
                          flushed=0, dser=0, cser=0, isync=0, unknown=0, sru_pairs=0)

    def cls(self, pc):
        word = self.words.get(pc)
        if word is None:
            self.stats['unknown'] += 1
        return None if word is None else classify(word, self.sru)

    def event(self, cycle, dispatched, retired):
        st = self.stats
        st['cycles'] = cycle
        require(len(dispatched) <= self.width and len(retired) <= self.width,
                f'cycle {cycle}: more than {self.width} dispatched or retired (TIM-DISP-WIDTH)')
        # Retirements first: one cannot retire in its dispatch cycle.
        classes = []
        for slot, pc in enumerate(retired):
            c = self.cls(pc)
            classes.append(c)
            if c and c['multiple'] and pc == self.last_retired_pc and not self.inflight_has(pc):
                continue  # further micro-op of the same multiple/string instruction
            index = next((i for i, e in enumerate(self.inflight) if e[0] == pc), None)
            require(index is not None, f'cycle {cycle}: retired {pc:08x} was not dispatched (in order)')
            require(self.flush or index == 0,
                    f'cycle {cycle}: {pc:08x} retired ahead of {self.inflight[0][0]:08x} (TIM-CQ-ORDER)')
            st['flushed'] += index
            seq, dcycle = self.inflight[index][2], self.inflight[index][1]
            del self.inflight[:index + 1]
            require(dcycle < cycle, f'cycle {cycle}: {pc:08x} retired in its dispatch cycle')
            st['retirements'] += 1
            if self.last_dser and seq < self.last_dser[0]:
                require(cycle <= self.last_dser[1],
                        f'cycle {cycle}: {pc:08x} older than a dispatch-serialized instruction dispatched '
                        f'at {self.last_dser[1]} still retiring (TIM-DISP-DQ0, empty CQ)')
            if self.block and seq >= self.block[0]:
                self.block = None
            if c and slot == 1:
                require(c['cq1'], f'cycle {cycle}: {pc:08x} completed from CQ[1] (TIM-CQ-CQ1/ORDER)')
                require(not c['cser'], f'cycle {cycle}: completion-serialized {pc:08x} in CQ[1] '
                                       '(TIM-SER-COMPLETE)')
            if c and c['isync']:
                self.isync_retired = cycle
                st['isync'] += 1
            self.last_retired_pc = pc
        if len(retired) == 2:
            st['pairs_retired'] += 1
            if all(classes):
                totals = [a + b for a, b in zip(classes[0]['writes'], classes[1]['writes'])]
                require(totals[0] <= 2 and all(t <= 1 for t in totals[1:]),
                        f'cycle {cycle}: retired pair exceeds writeback limits {totals} (TIM-WB-LIMITS)')
        if dispatched:
            require(self.block is None, f'cycle {cycle}: dispatch while a dispatch-serialized instruction '
                                        'is in flight (TIM-SER-DISPATCH)')
            require(self.isync_retired is None or cycle > self.isync_retired,
                    f'cycle {cycle}: dispatch in the cycle isync retired (TIM-SER-REFETCH)')
            self.isync_retired = None
        classes = [self.cls(pc) for pc in dispatched]
        if len(dispatched) == 2:
            st['pairs_dispatched'] += 1
            if all(classes):
                a, b = classes
                require(not a['dser'] and not b['dser'],
                        f'cycle {cycle}: dispatch-serialized instruction paired (TIM-DISP-DQ1)')
                require(BPU in a['units'] | b['units'] or
                        any(x != y for x in a['units'] for y in b['units']),
                        f'cycle {cycle}: {dispatched[0]:08x} and {dispatched[1]:08x} need the same unit '
                        '(TIM-DISP-DQ1 same unit)')
                if a['units'] == {IU} and b['units'] == {IU, SRU} or \
                        b['units'] == {IU} and a['units'] == {IU, SRU} or \
                        a['units'] == b['units'] == {IU, SRU}:
                    st['sru_pairs'] += 1
        for pc, c in zip(dispatched, classes):
            self.seq += 1
            self.inflight.append([pc, cycle, self.seq])
            st['dispatches'] += 1
            if c and c['dser']:
                st['dser'] += 1
                self.block = [self.seq, cycle]
                self.last_dser = (self.seq, cycle)
            if c and c['cser']:
                st['cser'] += 1

    def inflight_has(self, pc):
        return any(e[0] == pc for e in self.inflight)


def parse_line(raw):
    head, _, retired = raw.partition('|')
    fields = head.split()
    require(len(fields) >= 3 and fields[1][0] == 'D' and fields[2][0] == 'R', f'malformed event {raw!r}')
    dispatched = [int(x, 16) for x in fields[3:]]
    retired = [int(x, 16) for x in retired.split()]
    require(len(dispatched) == int(fields[1][1:]) and len(retired) == int(fields[2][1:]),
            f'count does not match pcs in {raw!r}')
    return int(fields[0]), dispatched, retired


def read_image(path, base):
    """64-bit words, one per line ('@' sets the word address), loaded at base."""
    words, offset = {}, 0
    for line in path.read_text().split():
        if line.startswith('@'):
            offset = int(line[1:], 16) * 8
            continue
        value = int(line, 16)
        words[base + offset] = value >> 32
        words[base + offset + 4] = value & 0xffffffff
        offset += 8
    return words


def check_rules(lines, width, words, sru, flush=False):
    """flush allows dispatched instructions that never retire (exceptions)."""
    rules = Rules(width, words, sru, flush)
    previous = -1
    for raw in lines:
        raw = raw.split('#', 1)[0].strip()
        if raw:
            cycle, dispatched, retired = parse_line(raw)
            require(cycle > previous, f'cycle {cycle} out of order')
            previous = cycle
            rules.event(cycle, dispatched, retired)
    return rules.stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('expected', type=Path, nargs='?')
    parser.add_argument('--stage', type=Path, help='cross-check against a stage-timing edge trace')
    parser.add_argument('--rules', action='store_true', help='check the 603e dispatch/completion rules')
    parser.add_argument('--width', type=int, default=1)
    parser.add_argument('--sru', action='store_true', help='add/compare may issue to the SRU')
    parser.add_argument('--image', type=Path, help='RAM image of 64-bit words for --rules')
    parser.add_argument('--allow-flush', action='store_true',
                        help='dispatched instructions may be flushed by exceptions')
    parser.add_argument('--image-base', type=lambda x: int(x, 16), default=0xfff00000)
    parser.add_argument('--min-pairs', type=int, default=0,
                        help='require this many dispatched and retired pairs')
    args = parser.parse_args()
    try:
        if args.rules:
            words = read_image(args.image, args.image_base) if args.image else {}
            with args.trace.open() as lines:
                st = check_rules(lines, args.width, words, args.sru, args.allow_flush)
            require(st['retirements'] > 0, 'no retirements')
            require(st['pairs_dispatched'] >= args.min_pairs and st['pairs_retired'] >= args.min_pairs,
                    f'fewer than {args.min_pairs} dispatched or retired pairs: {st}')
            print('PASS dispatch rules: ' + ' '.join(f'{k}={v}' for k, v in st.items()))
            return
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
