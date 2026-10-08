#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Cycle model of an MPC603e running a retired-instruction stream.

Input is the demo SoC's retirement trace (`retire N cycle C pc P insn I`, from
`+TRACE`/`+TRACE_TO`). Each instruction is scheduled in program order against
the MPC603e User's Manual (MPC603EUM/AD 11/97) timing rules, warm caches.
Every constraint names its source: "UM 6.3.3" is a manual section, "T6-4" a
table, "F6-3" a figure, and "A<n>" an assumption listed in ASSUMPTIONS.

The model is greedy: every rule depends only on older instructions, which an
in-order dispatch/completion machine guarantees, so one pass gives the cycle
of each stage. Cycle numbers follow the figures: F (in IQ), D (dispatch),
E (execute start .. finish), C (completion/writeback).
"""

import argparse
import re
import sys
from collections import defaultdict

ASSUMPTIONS = {
    "A1": "I-cache and D-cache always hit (warm caches, the programs fit).",
    "A2": "Fetch delivers the two instructions of one aligned doubleword per cycle "
          "(64-bit cache read, UM 6.3.1 'two per cycle'); --fetch any allows any pair.",
    "A3": "Branches take a fetch slot but no IQ entry, dispatch slot, CQ entry or "
          "rename (UM 6.3.1 'bypassing the dispatch queue', 6.4.1.1 folding).",
    "A4": "A bc whose CR producer is cmp-class gets the CR the cycle after the compare "
          "finishes (T6-4 '^'); any other CR producer makes it available in its "
          "completion cycle (F6-5: bc resolves in the add's writeback cycle).",
    "A5": "bc on CTR after a bc on CTR waits one cycle after the first resolves; the "
          "manual says 'until the first branch is completed' (UM 6.4.1.1).",
    "A6": "A load overlapping an older store reads the cache the cycle after the store "
          "writes it, which is the cycle after the store completes: loads pass stores "
          "only 'when free of data dependencies' and stores wait in the store queue "
          "for completion (UM 1.1.4.3); the manual documents no store-to-load "
          "forwarding. Addresses are not in the trace, so only D-form accesses whose "
          "bases derive from one register through addi, mr and update forms are "
          "compared; no cache-port conflict between store-queue writes and loads.",
    "A7": "Completion of an instruction behind a correctly predicted branch may occur "
          "in the branch's resolve cycle (UM 6.6.1.3).",
    "A8": "Multiply takes 1 + the bytes holding the multiplier as a signed value (T6-4 "
          "lists 2,3 for mulli but no operand mapping; the rule is the project's "
          "inference, TIM-U02); mullw/mulhw without operand values use --mul cycles.",
    "A9": "A unit's reservation station accepts the next instruction in the cycle the "
          "previous one starts executing (UM 6.3.3: 'stall until the first instruction "
          "completes execution' read as leaving the station).",
    "A10": "The SRU executes addi, addis, add, addo, cmpi, cmp, cmpli and cmpl beside the "
           "IU (UM 6.4.5; T6-4 note 1 excludes add.; UM 1.1.2.2.3 lists the SRU adder as a "
           "603e enhancement, and the 602 lacks it, UM C.2.3). The manual names no steering "
           "rule; an add or compare takes the unit that starts it first, and on a tie the "
           "SRU when the next non-branch instruction needs the IU, else the IU. UM 6.4.5 "
           "runs it 'in parallel with another integer instruction', and an IU station "
           "held by it would stall that instruction's dispatch (UM 6.3.3).",
    "A11": "A completion-serialized instruction starts the cycle after every older "
           "instruction has completed, and its GPR result is forwarded the cycle after "
           "it completes (UM 6.3.3.2, 1.1.4.4).",
    "A12": "mfspr/mtspr (not BATs), mfcr, mtcrf, mcrf and CR logicals are "
           "completion-serialized SRU work (UM 6.3.3.2 first bullet; T6-2/T6-3 cycles).",
    "A13": "The single CR rename (UM 6.3.3.1) is not a dispatch condition (UM 6.6.1.2 "
           "lists only GPR and FPR renames); a CR writer finishes, writing the rename, "
           "no earlier than the cycle after the previous CR writer completes.",
    "A14": "A held branch (UM 6.4.1.1 'Fetching is stopped') stops fetch after its own "
           "fetch: the word fetched beside it stays, the next fetch is the cycle after "
           "the branch executes.",
    "A15": "An instruction after a branch dispatches no earlier than the branch executes: "
           "a held branch is not yet predicted, and the 603e executes through one level "
           "of prediction only (UM 6.4.1.1 seventh case, 6.4.1.2).",
}

GPR_LIMIT = 5   # UM 6.3.3.1: five GPR renames
CQ_LIMIT = 5    # UM 6.3.3: five completion buffers
IQ_LIMIT = 6    # UM 6.3.1: six-entry IQ


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


class Insn:
    """Decoded resources of one instruction (UM ch. 6 tables)."""

    def __init__(self, pc, word, mul_default):
        self.pc, self.word = pc, word
        self.unit = "IU"          # IU, SRU, ADD (IU or SRU), LSU, BPU, FPU
        self.lat = 1
        self.src = set()          # GPRs read
        self.dst = set()          # GPRs written
        self.crs = set()          # CR fields read
        self.crd = set()          # CR fields written
        self.cr_fast = False      # T6-4 '^'
        self.store = self.load = False
        self.serial = False       # completion-serialized (UM 6.3.3.2)
        self.dserial = False      # dispatch-serialized (UM 6.3.3.2)
        self.lr_r = self.lr_w = self.ctr_r = self.ctr_w = False
        self.bo = self.bi = 0
        self.disp = 0
        self.lk = False
        self.kind = ""
        self._decode(mul_default)

    def _decode(self, mul_default):
        w = self.word
        op = w >> 26
        rd, ra, rb = (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31
        rc = w & 1
        xo10, xo9 = (w >> 1) & 0x3FF, (w >> 1) & 0x1FF
        ra_or_0 = {ra} if ra else set()

        def cr0():
            if rc:
                self.crd.add(0)

        if op == 7:                                        # mulli, T6-4
            imm = sext(w & 0xFFFF, 16)
            self.lat = 1 + significant_bytes(imm)
            self.src, self.dst, self.kind = {ra}, {rd}, "mul"
        elif op in (8, 12, 13):                            # subfic, addic[.]
            self.src, self.dst, self.kind = {ra}, {rd}, "int"
            if op == 13:
                self.crd.add(0)
        elif op in (10, 11):                               # cmpli, cmpi: IU & SRU, 1^
            self.unit, self.src, self.kind = "ADD", {ra}, "cmp"
            self.crd, self.cr_fast = {rd >> 2}, True
        elif op in (14, 15):                               # addi, addis: IU & SRU
            self.unit, self.src, self.dst, self.kind = "ADD", ra_or_0, {rd}, "add"
        elif op == 16:                                     # bc, T6-1
            self._branch(w, "bc")
            self.disp = sext(w & 0xFFFC, 16)
        elif op == 18:                                     # b
            self.unit, self.kind, self.lk = "BPU", "b", bool(w & 1)
            self.lr_w = self.lk
            self.disp = sext(w & 0x3FFFFFC, 26)
        elif op == 19:
            if xo10 == 16:
                self._branch(w, "bclr")
                self.lr_r = True
            elif xo10 == 528:
                self._branch(w, "bcctr")
                self.ctr_r = True
            elif xo10 == 0:                                # mcrf, T6-3
                self._sru(1, crs={ra >> 2}, crd={rd >> 2})
            elif xo10 in (33, 129, 193, 225, 257, 289, 417, 449):
                self._sru(1, crs={ra >> 2, rb >> 2}, crd={rd >> 2})
            else:                                          # isync, rfi
                self._sru(1)
                self.dserial = True
        elif op in (20, 21, 23):                           # rlwimi, rlwinm, rlwnm
            self.src = {rd} | ({rb} if op == 23 else set()) | ({ra} if op == 20 else set())
            self.dst, self.kind = {ra}, "int"
            cr0()
        elif op in (24, 25, 26, 27, 28, 29):               # ori .. andis.
            self.src, self.dst, self.kind = {rd}, {ra}, "int"
            if op in (28, 29):
                self.crd.add(0)
        elif 32 <= op <= 45:                               # D-form load/store, T6-6 2:1
            self.unit, self.lat = "LSU", 2
            store = op in (36, 37, 38, 39, 44, 45)
            update = op in (33, 35, 37, 39, 41, 43, 45)
            self.src = set(ra_or_0) if not update else {ra}
            if store:
                self.src.add(rd)
                self.store, self.kind = True, "store"
            else:
                self.dst.add(rd)
                self.load, self.kind = True, "load"
            if update:
                self.dst.add(ra)
        elif op in (46, 47):                               # lmw/stmw, 2+n& / 1+n&
            n = 32 - rd
            self.unit, self.lat, self.serial = "LSU", (2 + n) if op == 46 else (1 + n), True
            self.dserial = op == 46
            self.src = set(ra_or_0) | (set(range(rd, 32)) if op == 47 else set())
            self.dst = set(range(rd, 32)) if op == 46 else set()
            self.load, self.store = op == 46, op == 47
            self.kind = "lsmw"
        elif 48 <= op <= 55:                               # FP load/store
            self.unit, self.lat = "LSU", 2
            self.src = set(ra_or_0)
            self.store = op >= 52
            self.load = not self.store
            self.kind = "fpls"
        elif op in (59, 63):
            self.unit, self.lat, self.kind = "FPU", 3, "fp"
        elif op == 31:
            self._x31(w, rd, ra, rb, rc, xo10, xo9, ra_or_0, mul_default)
        else:
            self.kind = "other"

    def _branch(self, w, kind):
        self.unit, self.kind = "BPU", kind
        self.bo, self.bi, self.lk = (w >> 21) & 31, (w >> 16) & 31, bool(w & 1)
        self.lr_w = self.lk
        if not self.bo & 0x10:
            self.crs = {self.bi >> 2}
        if not self.bo & 0x04:
            self.ctr_r = self.ctr_w = True

    def _sru(self, lat, crs=(), crd=()):
        self.unit, self.lat, self.serial, self.kind = "SRU", lat, True, "sru"
        self.crs, self.crd = set(crs), set(crd)

    def _x31(self, w, rd, ra, rb, rc, xo10, xo9, ra_or_0, mul_default):
        loads = {23: 0, 55: 1, 87: 0, 119: 1, 279: 0, 311: 1, 343: 0, 375: 1, 534: 0, 790: 0, 20: 0}
        stores = {151: 0, 183: 1, 215: 0, 247: 1, 407: 0, 439: 1, 662: 0, 918: 0}
        if xo10 in loads or xo10 in stores:                # T6-6 2:1
            self.unit, self.lat = "LSU", 2
            update = (loads.get(xo10) or stores.get(xo10)) == 1
            self.src = ({ra} if update else set(ra_or_0)) | {rb}
            if xo10 in stores:
                self.src.add(rd)
                self.store, self.kind = True, "store"
            else:
                self.dst.add(rd)
                self.load, self.kind = True, "load"
            if update:
                self.dst.add(ra)
            return
        if xo10 in (0, 32):                                # cmp, cmpl: 1^
            self.unit, self.src, self.kind = "ADD", {ra, rb}, "cmp"
            self.crd, self.cr_fast = {rd >> 2}, True
            return
        if xo10 == 339 or xo10 == 371:                     # mfspr, mftb (A12)
            spr = ((w >> 16) & 31) | (((w >> 11) & 31) << 5)
            self._sru(1)
            self.dst = {rd}
            self.lr_r, self.ctr_r = spr == 8, spr == 9
            return
        if xo10 == 467:                                    # mtspr, T6-2: 2
            spr = ((w >> 16) & 31) | (((w >> 11) & 31) << 5)
            self._sru(2)
            self.src = {rd}
            self.lr_w, self.ctr_w = spr == 8, spr == 9
            self.dserial = spr == 1                        # mtspr(XER), UM 6.3.3.2
            return
        if xo10 == 19:                                     # mfcr
            self._sru(1, crs=set(range(8)))
            self.dst = {rd}
            return
        if xo10 == 144:                                    # mtcrf
            fxm = (w >> 12) & 0xFF
            self._sru(1, crd={i for i in range(8) if fxm & (0x80 >> i)})
            self.src = {rd}
            return
        if xo10 in (598, 854, 83, 146, 512, 86, 54, 278, 246, 1014, 982, 150):
            self._sru(1)                                   # sync, eieio, MSR, cache ops
            self.dserial = xo10 in (598, 146, 512)
            return
        xo_arith = {8, 10, 11, 40, 75, 104, 136, 138, 200, 202, 232, 234, 235, 266, 459, 491}
        if xo9 in xo_arith:
            self.dst = {rd}
            self.src = {ra} | ({rb} if xo9 not in (104, 200, 202, 232, 234) else set())
            self.kind = "int"
            if xo9 == 266 and not rc:                      # add, addo: IU & SRU (T6-4 note 1)
                self.unit, self.kind = "ADD", "add"
            elif xo9 in (11, 75, 235):                     # mulhwu, mulhw, mullw (A8)
                self.lat, self.kind = mul_default, "mul"
            elif xo9 in (459, 491):                        # divwu, divw: T6-4 37, PID7v 20
                self.lat, self.kind = Insn.div_cycles, "div"
            if rc:
                self.crd.add(0)
            return
        # X-form logical, shift, count, extend: rA <- rS op rB
        self.dst = {ra}
        self.src = {rd} | ({rb} if xo10 not in (26, 824, 922, 954) else set())
        self.kind = "int"
        if rc:
            self.crd.add(0)

    div_cycles = 20


def access_bytes(word):
    """Bytes a D-form load or store accesses, or 0."""
    op = word >> 26
    if op == 46 or op == 47:
        return 4 * (32 - ((word >> 21) & 31))
    return {32: 4, 33: 4, 34: 1, 35: 1, 36: 4, 37: 4, 38: 1, 39: 1, 40: 2, 41: 2, 42: 2,
            43: 2, 44: 2, 45: 2, 48: 4, 49: 4, 50: 8, 51: 8, 52: 4, 53: 4, 54: 8,
            55: 8}.get(op, 0)


def significant_bytes(v):
    """Fewest bytes holding v as a signed value (MULTIPLY_TIMING.md rB classes)."""
    v &= 0xFFFFFFFF
    if v & 0x80000000:
        v = ~v & 0xFFFFFFFF
    n = 1
    while v >> (8 * n - 1) and n < 4:
        n += 1
    return n


def predict_taken(ins):
    """Static prediction, UM 6.4.1.2: y bit flips the default (backward taken)."""
    if ins.bo & 0x14 == 0x14:
        return True
    y = ins.bo & 1
    backward = ins.kind == "bc" and ins.disp < 0
    return backward != bool(y)


# Restrictions of this core that the 603e does not have, or rule variants,
# each switched on by name to price it against the model (perf_diff.py).
CORE_RULES = {
    "branch-slot": "a branch takes a dispatch slot, the BPU one per cycle, a CQ "
                   "entry and a completion slot; it executes when it dispatches",
    "cr-token": "a CR writer dispatches the cycle after the previous CR writer completes",
    "dq0-iu": "an add or compare uses the SRU only from DQ1 beside an IU instruction in DQ0",
    "lsu-base": "a load or store dispatches only once its address operands are written",
    "late-retire": "an instruction completes two cycles after it finishes, not one",
    "miss-late": "the correct path after a misprediction dispatches four cycles after "
                 "resolution, not two",
    "cq-same": "a CQ entry freed by completion takes a dispatch in the same cycle "
               "(the model's default is the next cycle)",
}


def schedule(stream, fetch_any=False, core=frozenset()):
    """Schedule (pc, word, next_pc) records. Returns per-instruction dicts.

    core names CORE_RULES to apply."""
    out = []
    last = {"nb": None}                       # last non-branch record
    gpr_prod, cr_prod = {}, {}
    lr_ready = ctr_ready = 0
    unit_start = defaultdict(lambda: -1)      # A9 station frees at execute start
    unit_free = defaultdict(lambda: 0)        # earliest next execute start
    last_x = -1                               # BPU: one branch per cycle
    pending_pred = -1                         # resolve cycle of an outstanding prediction
    redirect = 0                              # earliest fetch of the next instruction
    fetch_hist = []                           # (F, pc) of every instruction, in order
    nb_hist = []                              # non-branch records, in order
    ser_until = 0                             # dispatch-serialized retire + 1
    cr_free = 0                               # previous CR writer completion + 1
    stop_f, stop_until = -1, 0                # A14: fetch of a held branch, restart
    branch_x = 0                              # A15: execute cycle of the last branch
    cq_late = 0 if "cq-same" in core else 1   # entry busy through its completion cycle
    sym, fresh = {}, [0]                      # GPR as (root, offset) for A6
    stores = []                               # (root, lo, hi, completion) of recent stores

    def gpr_sym(g):
        if g not in sym:
            fresh[0] += 1
            sym[g] = (fresh[0], 0)
        return sym[g]

    def track(ins, word):
        """The access's symbolic EA and its wait on older stores (A6)."""
        ra = (word >> 16) & 31
        n = access_bytes(word)
        ea, wait = None, 0
        if n:
            root, off = gpr_sym(ra) if ra else (0, 0)
            ea = (root, (off + sext(word & 0xFFFF, 16)) & 0xFFFFFFFF)
            lo, hi = ea[1], ea[1] + n
            if ins.load:
                wait = max([sc + 1 for r, slo, shi, sc in stores
                            if r == root and slo < hi and lo < shi], default=0)
        return ea, wait

    def written(ins, word, ea, c):
        """Record a store and the GPR values this instruction writes."""
        op, rd, ra, rb = word >> 26, (word >> 21) & 31, (word >> 16) & 31, (word >> 11) & 31
        if ins.store and ea is not None:
            stores.append((ea[0], ea[1], ea[1] + access_bytes(word), c))
            del stores[:-8]
        for g in ins.dst:
            if op == 14 and ra and g == rd:                      # addi
                root, off = gpr_sym(ra)
                sym[g] = (root, (off + sext(word & 0xFFFF, 16)) & 0xFFFFFFFF)
            elif op == 31 and (word >> 1) & 0x3FF == 444 and rd == rb and g == ra:   # mr
                sym[g] = gpr_sym(rd)
            elif ea is not None and g == ra and ra != rd:        # update form
                sym[g] = ea
            else:
                fresh[0] += 1
                sym[g] = (fresh[0], 0)

    def dispatch_cycle(ins, d, units):
        """First cycle >= d with a slot, a free unit, a CQ entry and renames."""
        prev = nb_hist[-1] if nb_hist else None
        while True:
            pair = prev is not None and prev["D"] == d
            if pair and (len([q for q in nb_hist[-2:] if q["D"] == d]) >= 2
                         or prev["ins"].dserial or ins.dserial):
                d += 1
                continue
            us = units
            if "dq0-iu" in core and ins.unit == "ADD":
                us = ["SRU"] if pair and prev["unit"] == "IU" else ["IU"]
            avail = [u for u in us if unit_start[u] <= d and not (pair and prev["unit"] == u)]
            if not avail:
                d += 1
                continue
            busy = sum(1 for q in nb_hist[-CQ_LIMIT - 2:] if q["C"] + cq_late > d)
            ren = sum(len(q["ins"].dst) for q in nb_hist[-GPR_LIMIT - 2:] if q["C"] >= d)
            if busy + 1 > CQ_LIMIT or ren + len(ins.dst) > GPR_LIMIT:
                d += 1
                continue
            return d, avail
    def next_unit(i):
        """Unit of the next non-branch instruction (branches leave the IQ at fetch)."""
        for p, w, _ in stream[i + 1:i + 1 + IQ_LIMIT]:
            u = Insn(p, w, ARGS.mul).unit
            if u != "BPU":
                return u
        return None

    for idx, (pc, word, npc) in enumerate(stream):
        ins = Insn(pc, word, ARGS.mul)
        r = {"pc": pc, "ins": ins}
        # Fetch: UM 6.3.2.2 hit returns next cycle; 6.3.1 two per cycle, IQ of six.
        f = max(redirect, fetch_hist[-1][0] if fetch_hist else 0)
        while True:
            if f != stop_f and f < stop_until:
                f = stop_until                     # UM 6.4.1.1, A14
            ok = True
            if fetch_hist and fetch_hist[-1][0] == f:
                first = len(fetch_hist) < 2 or fetch_hist[-2][0] != f
                seq = fetch_hist[-1][1] + 4 == pc and (fetch_any or pc % 8 == 4)   # A2
                ok = first and seq
            if ok:
                occ = sum(1 for q in nb_hist[-IQ_LIMIT - 2:] if q["F"] < f <= q["D"])
                occ += sum(1 for q in nb_hist[-2:] if q["F"] == f)
                if ins.unit != "BPU" and occ + 1 > IQ_LIMIT:
                    ok = False
            if ok:
                break
            f += 1
        r["F"] = f
        fetch_hist.append((f, pc))
        taken = npc != pc + 4
        if ins.unit == "BPU":
            # UM 6.4.1: BPU decode/execute the cycle after fetch (F6-3: br 2F 3E).
            x = max(f + 1, last_x + 1)
            x0 = x
            if "branch-slot" in core:
                prev = nb_hist[-1] if nb_hist else None
                d, _ = dispatch_cycle(ins, max(f + 1, prev["D"] if prev else 0, ser_until),
                                      ["BPU"])
                x = max(x, d)
            need = x
            if ins.lr_r:
                need = max(need, lr_ready)         # UM 6.4.1.1: wait for mtspr(LR)
            if ins.ctr_r:
                need = max(need, ctr_ready)        # UM 6.4.1.1, A5
            x = max(x, need)                       # no prediction on LR/CTR (UM 6.4.1.2)
            cr_avail = max([cr_prod.get(c, 0) for c in ins.crs], default=0)
            resolve = x
            if ins.crs and pending_pred > x:
                x = pending_pred                   # UM 6.4.1.1, 6.6.1.1: behind a prediction
            if ins.crs and cr_avail > x:
                    resolve = cr_avail             # predicted, resolves later (A4)
            last_x = x
            branch_x = x
            r.update(X=x, R=resolve)
            if x > x0:                             # held: fetch stops (UM 6.4.1.1, A14)
                stop_f, stop_until = f, x + 1
            if resolve > x:
                pending_pred = resolve
                pred = predict_taken(ins)
                if pred == taken:
                    redirect = x + 1 if taken else 0
                else:
                    redirect = resolve + 1         # F6-5: resolve 5E, target 6F
                    if "miss-late" in core:
                        redirect += 2
                r["mispredict"] = pred != taken
            else:
                redirect = x + 1 if taken else 0   # F6-3: br 3E, target 4F
            if ins.lr_w:
                lr_ready = x + 1
            if ins.ctr_w:
                ctr_ready = resolve + 1
            r["C"] = out[-1]["C"] if out else 0
            if "branch-slot" in core:
                prev = nb_hist[-1] if nb_hist else None
                c = max(resolve, prev["C"] if prev else 0)
                while prev and prev["C"] == c and \
                        len([q for q in nb_hist[-2:] if q["C"] == c]) >= 2:
                    c += 1
                r.update(D=d, S=x, E=x, C=c, unit="BPU")
                nb_hist.append(r)
            out.append(r)
            continue
        redirect = 0
        prev = nb_hist[-1] if nb_hist else None
        # Dispatch: UM 6.3.3, 6.6.1.2.
        d = max(f + 1, prev["D"] if prev else 0, ser_until, branch_x)   # A15
        if ins.dserial and prev:
            d = max(d, max(q["C"] for q in nb_hist[-CQ_LIMIT:]) + 1)
        if "cr-token" in core and ins.crd:
            d = max(d, cr_free)
        if "lsu-base" in core and ins.unit == "LSU":
            base = ins.src - ({(ins.word >> 21) & 31} if ins.store else set())
            d = max([d] + [gpr_prod.get(g, 0) for g in base])
        units = ["IU", "SRU"] if ins.unit == "ADD" and ARGS.sru_add else \
            ["IU"] if ins.unit == "ADD" else [ins.unit]
        d, avail = dispatch_cycle(ins, d, units)
        # Execute: operands from rename/forwarding (UM 6.3.3.1).
        ready = max([gpr_prod.get(g, 0) for g in ins.src], default=0)
        ea, st_wait = track(ins, word)
        ready = max(ready, st_wait)               # A6: cache read after the store's write
        ready = max(ready, max([cr_prod.get(c, 0) for c in ins.crs], default=0))
        if ins.lr_r:
            ready = max(ready, lr_ready)
        if ins.ctr_r:
            ready = max(ready, ctr_ready)
        best = None
        sru_s = None
        if ins.crd:
            ready = max(ready, cr_free - ins.lat + 1)   # UM 6.3.3.1: one CR rename, A13
        for u in avail:
            s = max(d + 1, ready, unit_free[u])
            if ins.serial and prev:
                s = max(s, prev["C"] + 1)          # A11
            if u == "SRU":
                sru_s = s
            if best is None or s < best[0]:
                best = (s, u)
        s, u = best
        if u == "IU" and sru_s == s and next_unit(idx) == "IU":
            u = "SRU"                              # A10: leave the IU to the next one
        fin = s + ins.lat - 1
        unit_start[u] = s
        unit_free[u] = s + 1 if u in ("LSU", "FPU") else fin + 1   # T6-6 2:1; UM 6.4.2
        # Completion: UM 6.3.3, 6.6.1.3.
        late = 2 if "late-retire" in core else 1
        c = max(fin + late, prev["C"] if prev else 0, pending_pred)       # A7
        while True:
            if prev and prev["C"] == c:
                two = len([q for q in nb_hist[-2:] if q["C"] == c]) >= 2
                kind_ok = not (ins.store or ins.serial or ins.unit == "FPU")
                gpr = len(ins.dst) + len(prev["ins"].dst) <= 2
                crw = len(ins.crd) + len(prev["ins"].crd) <= 1
                if two or not kind_ok or not gpr or not crw:
                    c += 1
                    continue
            break
        r.update(D=d, S=s, E=fin, C=c, unit=u)
        written(ins, word, ea, c)
        avail_at = c + 1 if ins.serial else fin + 1
        for g in ins.dst:
            gpr_prod[g] = avail_at
        for cr in ins.crd:
            cr_prod[cr] = fin + 1 if ins.cr_fast else (c + 1 if ins.serial else c)  # A4
        if ins.lr_w:
            lr_ready = fin + 1                     # UM 6.4.1.1: after mtspr executes
        if ins.ctr_w:
            ctr_ready = fin + 1
        if ins.dserial:
            ser_until = c + 1
        if ins.crd:
            cr_free = c + 1
        nb_hist.append(r)
        out.append(r)
    return out


TRACE_RE = re.compile(r"retire (\d+) cycle (\d+) pc ([0-9a-f]{8}) insn ([0-9a-f]{8})")


def read_trace(path, dump=None):
    """(cycle, pc, word) per retirement. Branches removed by the core
    (BRANCH_REMOVAL) count as retirements but print no line; with the
    disassembly they are restored from the gap in retirement numbers."""
    recs, words, last = [], read_words(dump), None
    with open(path) as fh:
        for line in fh:
            m = TRACE_RE.match(line)
            if not m:
                continue
            n, cyc, pc = int(m.group(1)), int(m.group(2)), int(m.group(3), 16)
            if last is not None and n > last + 1:
                if not words:
                    sys.exit("removed branches in the trace: pass --dump")
                recs.extend((cyc, b, words[b]) for b in removed_path(recs[-1], n - last - 1,
                                                                     pc, words))
            recs.append((cyc, pc, int(m.group(4), 16)))
            last = n
    return recs


def branch_targets(pc, word):
    """Possible next PCs of a branch whose target is in the word."""
    op = word >> 26
    if op == 18:
        return [(0 if word & 2 else pc) + sext(word & 0x3FFFFFC, 26) & 0xFFFFFFFF]
    if op == 16:
        return [pc + 4, (0 if word & 2 else pc) + sext(word & 0xFFFC, 16) & 0xFFFFFFFF]
    return [pc + 4]


def removed_path(prev, count, nxt, words):
    """The count removed branches between retired record prev and PC nxt."""
    _, ppc, pword = prev
    def walk(starts, left):
        for b in starts:
            w = words.get(b)
            if w is None or Insn(b, w, 3).unit != "BPU":
                continue
            if left == 1:
                return [b]
            rest = walk(branch_targets(b, w), left - 1)
            if rest:
                return [b] + rest
        return None
    starts = branch_targets(ppc, pword) if Insn(ppc, pword, 3).unit == "BPU" else [ppc + 4]
    path = walk(starts, count)
    if path is None:
        sys.exit(f"cannot place {count} removed branches after {ppc:08x} before {nxt:08x}")
    return path


def read_words(path):
    words = {}
    if not path:
        return words
    with open(path) as fh:
        for line in fh:
            m = re.match(r"([0-9a-f]{8}):\s+((?:[0-9a-f]{2} ){4})", line)
            if m:
                words[int(m.group(1), 16)] = int(m.group(2).replace(" ", ""), 16)
    return words


def read_dump(path):
    text = {}
    if not path:
        return text
    with open(path) as fh:
        for line in fh:
            m = re.match(r"([0-9a-f]{8}):\s+(?:[0-9a-f]{2} ){4}\s*(.*)", line)
            if m:
                text[int(m.group(1), 16)] = " ".join(m.group(2).split()[:2])
    return text


def main():
    global ARGS
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("trace", help="retirement trace from tb_demo_soc +TRACE")
    ap.add_argument("--mark", type=lambda v: int(v, 16),
                    help="PC (hex) that starts each iteration of the timed loop; "
                         "without it the whole trace after 1000 instructions is one window")
    ap.add_argument("--dump", help="objdump -d output, for the per-PC table")
    ap.add_argument("--div", type=int, default=20, help="divw cycles: 20 PID7v, 37 PID6")
    ap.add_argument("--mul", type=int, default=3, help="mullw/mulhw cycles (A8)")
    ap.add_argument("--fetch", choices=("aligned", "any"), default="aligned")
    ap.add_argument("--no-sru-add", dest="sru_add", action="store_false",
                    help="add/cmp only in the IU (A10 off; the 603 without the SRU adder)")
    ap.add_argument("--top", type=int, default=25, help="rows of the per-PC gap table")
    ap.add_argument("--core", action="append", default=[], choices=sorted(CORE_RULES),
                    help="apply a restriction of this core (repeatable)")
    ap.add_argument("--assumptions", action="store_true")
    ARGS = ap.parse_args()
    if ARGS.assumptions:
        for k, v in ASSUMPTIONS.items():
            print(f"{k}: {v}")
        return
    Insn.div_cycles = ARGS.div
    recs = read_trace(ARGS.trace, ARGS.dump)
    if len(recs) < 3:
        sys.exit("trace has no retirements")
    stream = [(pc, w, recs[i + 1][1]) for i, (_, pc, w) in enumerate(recs[:-1])]
    sched = schedule(stream, ARGS.fetch == "any", frozenset(ARGS.core))
    if ARGS.mark is None:
        marks = [0, min(1000, len(stream) // 4), len(stream) - 1]
    else:
        marks = [i for i, (pc, _, _) in enumerate(stream) if pc == ARGS.mark]
        if len(marks) < 4:
            sys.exit("fewer than four iterations in the trace")
    lo, hi = marks[1], marks[-1]               # skip the first iteration (model warm-up)
    iters = len(marks) - 2
    insns = (hi - lo) / iters
    ours = (recs[hi][0] - recs[lo][0]) / iters
    model = (sched[hi]["C"] - sched[lo]["C"]) / iters
    print(f"iterations {iters}, instructions per iteration {insns:.1f}")
    print(f"603e model: {model:.1f} cycles per iteration, CPI {model / insns:.3f}")
    print(f"this core:  {ours:.1f} cycles per iteration, CPI {ours / insns:.3f}")
    print(f"ratio core/model {ours / model:.2f}")
    # Per-PC gap: retirement spacing on the core minus completion spacing in the model.
    text = read_dump(ARGS.dump)
    gap = defaultdict(float)
    core_pc = defaultdict(float)
    model_pc = defaultdict(float)
    cnt = defaultdict(int)
    for i in range(lo + 1, hi + 1):
        pc = stream[i][0]
        dc = recs[i][0] - recs[i - 1][0]
        dm = sched[i]["C"] - sched[i - 1]["C"]
        gap[pc] += dc - dm
        core_pc[pc] += dc
        model_pc[pc] += dm
        cnt[pc] += 1
    kinds = defaultdict(lambda: [0.0, 0.0, 0])
    for pc in gap:
        ins = Insn(pc, next(w for p, w, _ in stream if p == pc), ARGS.mul)
        k = ins.kind
        if ins.unit == "BPU":
            k = "branch:" + ins.kind
        kinds[k][0] += core_pc[pc] / iters
        kinds[k][1] += model_pc[pc] / iters
        kinds[k][2] += cnt[pc] / iters
    print("\nby retiring class (cycles per iteration charged to the class):")
    print(f"{'class':14} {'count':>6} {'core':>8} {'603e':>8} {'gap':>8}")
    for k, (cc, mm, n) in sorted(kinds.items(), key=lambda kv: kv[1][1] - kv[1][0]):
        print(f"{k:14} {n:6.1f} {cc:8.1f} {mm:8.1f} {cc - mm:8.1f}")
    mis = sum(1 for i in range(lo, hi) if sched[i].get("mispredict")) / iters
    print(f"\n603e model mispredictions per iteration: {mis:.1f}")
    print(f"\nlargest per-PC gaps (cycles per iteration):")
    for pc, g in sorted(gap.items(), key=lambda kv: -kv[1])[:ARGS.top]:
        print(f"{pc:08x} {text.get(pc, ''):28} n={cnt[pc] / iters:4.1f} "
              f"core={core_pc[pc] / iters:6.1f} 603e={model_pc[pc] / iters:5.1f} gap={g / iters:6.1f}")


ARGS = None

if __name__ == "__main__":
    main()
