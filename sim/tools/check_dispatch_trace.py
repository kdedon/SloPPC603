#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Compare a core dispatch/retire event trace with an expected schedule.

Trace lines come from ppc_core's +DISPATCH_TRACE monitor:
    <cycle> D<n> R<n> <dispatch pcs...> | <retire pcs...> [!<n>]
'!<n>' marks a branch misprediction recovery that removed the n youngest
dispatched instructions; '!<n>*<m>' when the branch was itself removed at
dispatch, m counting every dispatch after it. The schedule comparison
ignores both. A dispatch pc
ending in '*' is a branch removed at dispatch, which never retires. An expected schedule uses the same format; '#' starts a comment.

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
        retired, recovery, _ = retired.partition('!')
        fields = head.split()
        require(len(fields) >= 3 and fields[1][0] == 'D' and fields[2][0] == 'R',
                f'line {number}: malformed event')
        if recovery and fields[1:3] == ['D0', 'R0']:
            continue
        cycle, dispatched = int(fields[0]), [int(x.rstrip('*'), 16) for x in fields[3:]]
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
    LR, CTR) updates for TIM-WB-LIMITS; isync and multiple for the trace;
    cond: a conditional branch, after which a misprediction flushes younger work.
    branch: 'b', 'bc', 'bclr' or 'bcctr'; cr_test: the condition reads CR
    (BO[0] clear); ctr_test: it decrements and tests CTR (BO[2] clear).
    mtspr: 'LR' or 'CTR' for a move to that register.
    """
    op, xo = word >> 26, (word >> 1) & 1023
    rc = word & 1 if op in (20, 21, 23, 31, 59, 63) else 0  # D-form bit 31 is immediate
    c = dict(units={IU}, dser=False, cser=False, cq1=True, writes=[1, rc, 0, 0, 0],
             isync=False, multiple=False, cond=False, branch=None, cr_test=False, ctr_test=False,
             mtspr=None)
    sru_unit = lambda: c.update(units={SRU}, cser=True, cq1=False, writes=[0, 0, 0, 0, 0])
    if op in (16, 18) or (op == 19 and xo in (16, 528)):
        lk = word & 1
        ctr = op == 19 and xo == 16 and not (word >> 23) & 1 or op == 16 and not (word >> 23) & 1
        c.update(units={BPU}, writes=[0, 0, 0, lk, int(bool(ctr))],
                 cond=op != 18 and (word >> 21) & 0x14 != 0x14,
                 branch='b' if op == 18 else 'bc' if op == 16 else 'bclr' if xo == 16 else 'bcctr',
                 cr_test=op != 18 and not (word >> 25) & 1, ctr_test=bool(ctr))
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
            c['mtspr'] = {8: 'LR', 9: 'CTR'}.get(spr) if xo == 467 else None
    return c


def cr_field(word):
    """The CR field a compare or record-form integer instruction writes, else None."""
    if word is None:
        return None
    op, xo = word >> 26, (word >> 1) & 1023
    if op in (10, 11) or op == 31 and xo in (0, 32):
        return (word >> 23) & 7
    if op in (13, 28, 29) or op in (20, 21, 23) and word & 1:
        return 0
    if op == 31 and word & 1 and xo not in (150,):
        return 0 if classify(word, False)['units'] == {IU} else None
    return None


CQ_DEPTH, GPR_RENAMES, FPR_RENAMES = 5, 5, 4


def fetch_stop(older, younger):
    """UM 6.4.1.1 (PDF 261): how branch `younger` waits on `older`, or None.

    'retire': it waits for the move to LR/CTR, whose result is not forwarded
    before it retires (UM 6.3.3.2, PDF 259); 'complete': for the older
    branch to complete."""
    if older['mtspr'] == 'LR' and younger['branch'] == 'bclr' or \
            older['mtspr'] == 'CTR' and (younger['branch'] == 'bcctr' or younger['ctr_test']):
        return 'retire'
    if older['ctr_test'] and (younger['ctr_test'] or younger['branch'] == 'bcctr'):
        return 'complete'
    # A bl does not wait for an older branch with LK set.
    if older['branch'] and older['writes'][3] and younger['writes'][3] and younger['branch'] != 'b':
        return 'complete'
    return None


class Rules:
    """Streaming check of TIM-DISP-WIDTH/DQ1, TIM-SER-DISPATCH/COMPLETE/REFETCH,
    TIM-CQ-ALLOC/CQ1/ORDER, TIM-RENAME-LIMITS, TIM-WB-LIMITS, TIM-BPU-MISPREDICT and the branch
    fetch-stop rules (TIM-BPU-*) over one trace."""

    def __init__(self, width, words, sru, flush):
        self.width, self.words, self.sru, self.flush = width, words, sru, flush
        # [pc, dispatch cycle, sequence number, flushed, class, order] in dispatch order
        self.inflight = []
        self.seq = 0
        self.order = 0          # dispatch order, counting removed branches
        self.stream = []        # (order, class, removed, cycle, pc) of recent dispatches
        self.redirect = None    # earliest correct-path dispatch after a recovery
        self.stops = []         # [older entry or None, waiting branch order, waiting pc, kind]
        self.block = None       # dispatch-serialized instruction not yet retired: [seq, cycle]
        self.last_dser = None   # (seq, dispatch cycle) of the latest dispatch-serialized dispatch
        self.isync_retired = None
        self.last_retired_pc = None
        self.cond_retired = False  # the latest retirement was a conditional branch
        self.stats = dict(cycles=0, dispatches=0, retirements=0, pairs_dispatched=0, pairs_retired=0,
                          flushed=0, mispredicts=0, removed=0, dser=0, cser=0, isync=0, unknown=0, sru_pairs=0,
                          cq_max=0, gpr_max=0, fetch_stops=0, wrong_path_branches=0,
                          redirects=0, redirects_at_floor=0)

    def cls(self, pc):
        word = self.words.get(pc)
        if word is None:
            self.stats['unknown'] += 1
        return None if word is None else classify(word, self.sru)

    def event(self, cycle, dispatched, retired, mispredict=None, removed=(), after=None):
        """mispredict: None, or the count a recovery this cycle removes;
        after: for a removed branch, every dispatch after it."""
        st = self.stats
        recovery, mispredict = mispredict is not None, mispredict or 0
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
            # Work dispatched down a mispredicted path never retires
            # (UM 6.4.1.2); it is what a recovery removed behind the
            # conditional branch that retired last, or that was removed at
            # dispatch and so never retires.
            wrong_path = 0
            if self.cond_retired or (self.inflight and self.inflight[0][3] == 'removed'):
                while wrong_path < len(self.inflight) and self.inflight[wrong_path][3]:
                    wrong_path += 1
            index = next((i for i, e in enumerate(self.inflight) if i >= wrong_path and e[0] == pc), None)
            require(index is not None, f'cycle {cycle}: retired {pc:08x} was not dispatched (in order)')
            require(self.flush or index == wrong_path,
                    f'cycle {cycle}: {pc:08x} retired ahead of {self.inflight[wrong_path][0]:08x} '
                    '(TIM-CQ-ORDER)')
            require(not self.inflight[index][3], f'cycle {cycle}: {pc:08x} retired after its recovery removed it')
            st['flushed'] += index
            st['mispredicts'] += int(wrong_path > 0)
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
            self.cond_retired = bool(c and c['cond'])
        if len(retired) == 2:
            st['pairs_retired'] += 1
            if all(classes):
                totals = [a + b for a, b in zip(classes[0]['writes'], classes[1]['writes'])]
                require(totals[0] <= 2 and all(t <= 1 for t in totals[1:]),
                        f'cycle {cycle}: retired pair exceeds writeback limits {totals} (TIM-WB-LIMITS)')
        if dispatched and self.redirect is not None:
            floor, pc = self.redirect
            require(cycle >= floor, f'cycle {cycle}: dispatch {floor - cycle} cycle(s) early after the '
                                    f'misprediction of branch {pc:08x} (TIM-BPU-MISPREDICT)')
            self.stats['redirects'] += 1
            self.stats['redirects_at_floor'] += int(cycle == floor)
            self.redirect = None
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
        for slot, (pc, c) in enumerate(zip(dispatched, classes)):
            gone = slot < len(removed) and removed[slot]
            self.fetch_stops(cycle, pc, c, gone)
            self.order += 1
            self.stream = self.stream[-31:] + [(self.order, c, gone, cycle, pc)]
            if gone:
                # UM 6.3.1: only a branch with no LR or CTR write retires
                # without a completion entry.
                require(c is None or (c['units'] == {BPU} and not any(c['writes'][3:])),
                        f'cycle {cycle}: {pc:08x} removed at dispatch but is not a branch that '
                        'writes no LR or CTR (TIM-BPU-FOLD)')
                st['dispatches'] += 1
                st['removed'] += 1
                continue
            self.seq += 1
            self.inflight.append([pc, cycle, self.seq, False, c, self.order])
            st['dispatches'] += 1
            if c and c['dser']:
                st['dser'] += 1
                self.block = [self.seq, cycle]
                self.last_dser = (self.seq, cycle)
            if c and c['cser']:
                st['cser'] += 1
        self.occupancy(cycle)
        require(mispredict <= len(self.inflight),
                f'cycle {cycle}: recovery removes {mispredict} of {len(self.inflight)} in flight')
        if recovery:
            self.wrong_path(cycle, mispredict, after)
        for entry in self.inflight[len(self.inflight) - mispredict:]:
            entry[3] = True if after is None else 'removed'

    def occupancy(self, cycle):
        """TIM-CQ-ALLOC (UM 6.3.3, PDF 258; 6.6.1.2, PDF 267): five completion
        buffers. TIM-RENAME-LIMITS (UM 6.6, PDF 266-267): five GPR and four
        FPR destinations, two for a load with update. Counted after the
        cycle's retirements, so a buffer freed and reused in one cycle passes;
        renames held past completion only add to the count."""
        live = [e[4] for e in self.inflight if not e[3]]
        gpr = sum(c['writes'][0] for c in live if c)
        fpr = sum(c['writes'][2] for c in live if c)
        st = self.stats
        st['cq_max'], st['gpr_max'] = max(st['cq_max'], len(live)), max(st['gpr_max'], gpr)
        require(len(live) <= CQ_DEPTH, f'cycle {cycle}: {len(live)} instructions in the completion queue '
                                       '(TIM-CQ-ALLOC)')
        require(gpr <= GPR_RENAMES and fpr <= FPR_RENAMES,
                f'cycle {cycle}: {gpr} GPR and {fpr} FPR destinations in flight (TIM-RENAME-LIMITS)')

    def blocking(self, older):
        """Whether a fetch stop on `older` still holds after this cycle's retirements."""
        return any(e is older for e in self.inflight if not e[3])

    def fetch_stops(self, cycle, pc, c, gone):
        """UM 6.4.1.1 (PDF 261), 6.6.1.1 (PDF 267): after mtspr(LR)/bclr,
        mtspr(CTR)/bcctr or bc(CTR), bc(CTR)/bc(CTR) or bcctr, and
        branch(LK)/branch(LK) other than bl, fetching stops until the older
        instruction completes. Nothing younger than the waiting
        branch dispatches meanwhile, and a branch removed at dispatch (resolved
        there) cannot be the one waiting."""
        self.stops = [s for s in self.stops if self.blocking(s[0])]
        for older, _, waiter, kind in self.stops:
            require(False, f'cycle {cycle}: {pc:08x} dispatched while branch {waiter:08x} waits for '
                           f'{older[0]:08x} to {kind} (TIM-BPU-FETCH-STOP)')
        if not (c and c['branch']):
            return
        for older in reversed([e for e in self.inflight if not e[3] and e[4]]):
            kind = fetch_stop(older[4], c)
            if kind and self.blocking(older):
                require(not gone, f'cycle {cycle}: branch {pc:08x} resolved at dispatch while it waits for '
                                  f'{older[0]:08x} to {kind} (TIM-BPU-FETCH-STOP)')
                self.stops.append([older, self.order + 1, pc, kind])
                self.stats['fetch_stops'] += 1
                break

    def wrong_path(self, cycle, mispredict, after=None):
        """TIM-BPU-ONE-PREDICTION (UM 6.4.1.2, PDF 262; 6.6.1.1, PDF 267;
        6.4.1.1 last case, PDF 261): behind an unresolved predicted branch, a
        branch conditional on CR is not executed and fetching stops at it.
        Only mispredicted branches show their predicted path. A branch that
        also tests CTR may resolve on CTR alone, so it is not checked."""
        younger = mispredict
        if after is not None:
            if after >= len(self.stream):
                return
            order = self.stream[-1 - after][0]
        else:
            for order, _, gone, *_ in reversed(self.stream):
                if not gone:
                    if younger == 0:
                        break
                    younger -= 1
            else:
                return
        branch = order
        path = [(c, gone) for order, c, gone, *_ in self.stream if order > branch]
        self.mispredict_floor(cycle, branch)
        self.stops = [s for s in self.stops if s[1] <= branch]
        for i, (c, gone) in enumerate(path):
            if c and c['branch'] and c['cr_test'] and not c['ctr_test']:
                self.stats['wrong_path_branches'] += 1
                require(not gone and i == len(path) - 1,
                        f'cycle {cycle}: a branch on CR was resolved or followed by dispatch behind an '
                        'unresolved predicted branch (TIM-BPU-ONE-PREDICTION)')

    def mispredict_floor(self, cycle, branch):
        """TIM-BPU-MISPREDICT (UM 6.4.1.2.1, Figure 6-5, PDF 263): the CR
        producer executes no earlier than the cycle after its dispatch and
        resolves the branch no earlier than the cycle after that; the correct
        path is fetched the cycle after resolution and dispatched the cycle
        after that. So the first dispatch after a recovery is at least four
        cycles after the dispatch of the branch's CR producer, and after the
        recovery cycle."""
        floor = cycle + 1
        entry = next((e for e in self.stream if e[0] == branch), None)
        if entry and entry[1] and entry[1]['branch'] and entry[1]['cr_test']:
            field = (self.words[entry[4]] >> 18) & 7
            older = [e for e in self.stream
                     if e[0] < branch and not e[2] and cr_field(self.words.get(e[4])) == field]
            if older:
                floor = max(floor, older[-1][3] + 4)
            else:
                return
        self.redirect = (floor, entry[4] if entry else 0)

    def inflight_has(self, pc):
        return any(e[0] == pc for e in self.inflight)


def parse_line(raw):
    head, _, retired = raw.partition('|')
    retired, _, removed = retired.partition('!')
    removed, star, after = removed.partition('*')
    mispredict = int(removed) if removed else None
    after = int(after) if star else None
    fields = head.split()
    require(len(fields) >= 3 and fields[1][0] == 'D' and fields[2][0] == 'R', f'malformed event {raw!r}')
    dispatched = [int(x.rstrip('*'), 16) for x in fields[3:]]
    removed = [x.endswith('*') for x in fields[3:]]
    retired = [int(x, 16) for x in retired.split()]
    require(len(dispatched) == int(fields[1][1:]) and len(retired) == int(fields[2][1:]),
            f'count does not match pcs in {raw!r}')
    return int(fields[0]), dispatched, retired, mispredict, removed, after


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
            cycle, dispatched, retired, mispredict, removed, after = parse_line(raw)
            require(cycle > previous, f'cycle {cycle} out of order')
            previous = cycle
            rules.event(cycle, dispatched, retired, mispredict, removed, after)
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
