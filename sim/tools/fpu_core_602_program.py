#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Program image for tb_core_fpu with the 602 core and its FPU.

Directed sections cover illegal fsqrt, FP unavailable ahead of the emulation
trap, the SP and LT registers (mtspr, mfspr and mftb forms, tag updates from
loads, fctiwz and mffs, privilege, no MSR[FP] requirement), SP and LT tag
traps, double-precision forms, lfd exact-fit and stfd expansion, loads at
every byte offset (602 UM 2.2.3) with DSI on the first and a later word,
alignment of unaligned stores, a store cancelled by an older trapping
instruction, the FP enabled program exception of an FPSCR write, and the
completion stall of a newly set sticky bit (602 UM 4.5.7.1). The random
section runs the standalone FPU's 602 enabled-exception cases. Expected
values come from the Python reference model; handlers log SRR0, SRR1, DAR,
DSISR and the vector to memory.
"""
import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpu'))
from fpu_core_program import (  # noqa: E402
    CHANGED_HI, CHANGED_LO, DATA, DONE, EXCEPTION_BITS, FE0, FE1, LOG, MSR_FP,
    PROT_HI, PROT_LO, SRR1_FP, SRR1_ILLEGAL, SYNC, TEA_HI, TEA_LO, Program, a_form,
    access_faults, clear_fe_if_fp, d_form, dsisr_d, dsisr_x, f32, f64,
    fp_enable_deferred, fp_enable_rfi, x_form)
from enabled_vectors import case_602, fpscr_after  # noqa: E402
from ppc_reference import arithmetic  # noqa: E402
from production_vectors_602 import expected_602, widen_raw  # noqa: E402
from reference import calculate  # noqa: E402

MSR_PR = 0x4000
SRR1_PRIV = 0x00040000
VECTORS = (0x200, 0x300, 0x600, 0x700, 0x800, 0x1200, 0x1600)
SPR_SP, SPR_LT = 1021, 1022
STICKY = sum(1 << b for b in EXCEPTION_BITS)
# lfd trap value: 1/3 is not a binary32.
THIRD = 0x3fd5555555555555


def narrow(bits):
    return calculate('to32', bits, 0)['bits']


def mtspr(spr, rs):
    return x_form(31, rs, spr & 31, spr >> 5, 467)


def mfspr(rd, spr, xo=339):
    return x_form(31, rd, spr & 31, spr >> 5, xo)


def tag(fr):
    return 1 << (31 - fr)


class Program602(Program):
    def __init__(self):
        super().__init__()
        self.sticky = 0
        self.sp = 0
        self.lt = 0

    def fpscr_update(self, new):
        """Retire an FP result: count a completion stall for a newly set
        sticky bit with MSR[FE0/FE1] clear."""
        if not self.msr & (FE0 | FE1) and new & ~self.fpscr & STICKY:
            self.sticky += 1
        self.fpscr = new

    def write_fpr(self, fr, sp, lt):
        self.sp = (self.sp & ~tag(fr)) | (tag(fr) if sp else 0)
        self.lt = (self.lt & ~tag(fr)) | (tag(fr) if lt else 0)

    def clear_fpscr(self):
        for field in range(8):
            self.emit((63 << 26) | (field << 23) | (134 << 1))   # mtfsfi field, 0
        self.fpscr = 0

    def lfs(self, fr, bits):
        addr = self.data(bits << 32)
        self.li32(5, addr)
        self.emit(d_form(48, fr, 5, 0))
        self.write_fpr(fr, True, False)

    def store_sp(self, fr, bits, mask=0xffffffff):
        addr = self.result_slot(1)
        self.li32(21, addr)
        self.emit(d_form(52, fr, 21, 0))                           # stfs
        self.expect(addr, bits, mask)

    def store_lt(self, fr, bits, mask=0xffffffff):
        addr = self.result_slot(1)
        self.li32(21, addr)
        self.li32(22, 0)
        self.emit(x_form(31, fr, 21, 22, 983))                     # stfiwx
        self.expect(addr, bits, mask)

    def check_fpscr(self, mask=0xffffffff):
        self.emit(x_form(63, 30, 0, 0, 583))                       # mffs f30
        self.write_fpr(30, False, True)
        self.store_lt(30, self.fpscr, mask)

    def check_tags(self):
        self.emit(mfspr(6, SPR_SP))
        self.store_gpr(6, self.sp)
        self.emit(mfspr(6, SPR_LT))
        self.store_gpr(6, self.lt)

    def set_tags(self, sp, lt):
        self.li32(6, sp)
        self.emit(mtspr(SPR_SP, 6))
        self.li32(6, lt)
        self.emit(mtspr(SPR_LT, 6))
        self.sp, self.lt = sp, lt

    def arith(self, insn, op, dst, a=0, b=0, c=0):
        """A single-precision instruction on binary32 sources; returns the
        binary32 result."""
        exp = expected_602(op, widen_raw(a), widen_raw(b), widen_raw(c),
                           self.fpscr & 3, 0, 0, 0, 0, 0)
        self.emit(insn)
        self.fpscr_update(fpscr_after(self.fpscr, exp))
        if op == 'fctiwz':
            self.write_fpr(dst, False, True)
            return exp['result'] & 0xffffffff
        self.write_fpr(dst, True, False)
        return narrow(exp['result'])


def handlers(p):
    for vector in VECTORS:
        pc = 0xfff00000 | vector
        seq = []
        for spr, off in ((26, 0), (27, 4), (19, 8), (18, 12)):
            seq += [x_form(31, 26, spr & 31, spr >> 5, 339), d_form(36, 26, 29, off)]
        seq += [d_form(14, 26, 0, vector), d_form(36, 26, 29, 16), d_form(14, 29, 29, 20)]
        if vector == 0x700:
            seq += clear_fe_if_fp()
        if vector == 0x800:
            # Lazy FP enable: set MSR[FP] in SRR1 and retry.
            seq += [x_form(31, 26, 27, 0, 339), d_form(24, 26, 26, MSR_FP),
                    x_form(31, 26, 27, 0, 467)]
        else:
            seq += [x_form(31, 26, 26, 0, 339), d_form(14, 26, 26, 4),
                    x_form(31, 26, 26, 0, 467)]
        seq.append(x_form(19, 0, 0, 0, 50))
        for insn in seq:
            p.words[pc] = insn
            pc += 4
    # sc returns to supervisor state: clear SRR1[PR].
    pc = 0xfff00c00
    for insn in (x_form(31, 26, 27, 0, 339),
                 (21 << 26) | (26 << 21) | (26 << 16) | (18 << 6) | (16 << 1),
                 x_form(31, 26, 27, 0, 467), x_form(19, 0, 0, 0, 50)):
        p.words[pc] = insn
        pc += 4


def trap(p, insn):
    at = p.emit(insn)
    p.event(0x1600, at, p.msr)
    return at


def unavailable_and_illegal(p):
    # fsqrt is illegal, not emulated (602 UM 4.5.7.2); FP unavailable comes
    # before the emulation trap of a double-precision form.
    at = p.emit(a_form(63, 1, 0, 1, 0, 22))
    p.event(0x700, at, p.msr | SRR1_ILLEGAL)
    at = p.emit(a_form(63, 1, 1, 1, 0, 21))                       # fadd
    p.event(0x800, at, p.msr)
    p.msr |= MSR_FP
    p.event(0x1600, at, p.msr)
    p.clear_fpscr()
    p.set_tags(0, 0)


def sp_lt(p):
    p.li32(5, 0x12345678)
    p.emit(mtspr(SPR_SP, 5))
    p.li32(5, 0x0f0f0f0f)
    p.emit(mtspr(SPR_LT, 5))
    p.sp, p.lt = 0x12345678, 0x0f0f0f0f
    p.check_tags()
    p.emit(mfspr(7, SPR_SP, 371))                                  # mftb form
    p.store_gpr(7, 0x12345678)
    # No MSR[FP] needed.
    p.mtmsr(p.msr & ~MSR_FP)
    p.li32(5, 0x00ff00ff)
    p.emit(mtspr(SPR_SP, 5))
    p.emit(mfspr(7, SPR_SP))
    p.store_gpr(7, 0x00ff00ff)
    p.mtmsr(p.msr | MSR_FP)
    p.set_tags(0, 0)
    # Tags follow the instruction writing the register.
    p.lfs(3, f32(1.5))
    v = p.arith(x_form(63, 4, 0, 3, 15), 'fctiwz', 4, b=f32(1.5))
    p.store_lt(4, v)
    p.check_fpscr()
    p.check_tags()
    # Supervisor only: problem-state mfspr and mtspr take the privileged
    # program exception; sc returns to supervisor state.
    p.mtmsr(p.msr | MSR_PR)
    at = p.emit(mfspr(7, SPR_SP))
    p.event(0x700, at, p.msr | SRR1_PRIV)
    at = p.emit(mtspr(SPR_LT, 7))
    p.event(0x700, at, p.msr | SRR1_PRIV)
    p.emit(0x44000002)                                             # sc
    p.msr &= ~MSR_PR
    p.check_tags()
    p.clear_fpscr()


def tag_traps(p):
    for fr, bits in ((10, f32(1.5)), (11, f32(0.25)), (12, f32(4.0)), (13, f32(3.0))):
        p.lfs(fr, bits)
    # A source without SP traps; nothing is written.
    p.lfs(14, f32(-2.0))
    p.set_tags(p.sp & ~tag(10), p.lt)
    trap(p, a_form(59, 14, 10, 11, 0, 21))                        # fadds f14, f10, f11
    p.set_tags(p.sp | tag(10), p.lt)
    p.store_sp(14, f32(-2.0))
    # Double-precision arithmetic and fctiw trap whatever the operands.
    trap(p, a_form(63, 14, 10, 11, 0, 21))                        # fadd
    trap(p, a_form(63, 14, 10, 0, 12, 25))                        # fmul
    trap(p, x_form(63, 14, 0, 10, 14))                            # fctiw
    # mtfsf needs an LT source.
    trap(p, (63 << 26) | (0xff << 17) | (10 << 11) | (711 << 1))
    # stfiwx needs LT; stfd needs SP.
    p.li32(21, p.result_slot(2))
    p.li32(22, 0)
    trap(p, x_form(31, 10, 21, 22, 983))
    p.emit(x_form(63, 15, 0, 0, 583))                              # mffs f15
    p.write_fpr(15, False, True)
    trap(p, d_form(54, 15, 21, 0))
    # lfd of a value that is no binary32 traps and leaves frD.
    addr = p.data(THIRD)
    p.li32(5, addr)
    trap(p, d_form(50, 14, 5, 0))
    p.store_sp(14, f32(-2.0))
    p.check_tags()
    p.check_fpscr()


def arithmetic_602(p):
    p.clear_fpscr()
    one_half, quarter, four, three = f32(1.5), f32(0.25), f32(4.0), f32(3.0)
    r = p.arith(a_form(59, 16, 10, 11, 0, 21), 'add', 16, one_half, quarter)
    p.store_sp(16, r)
    r = p.arith(a_form(59, 17, 10, 0, 12, 25), 'mul', 17, one_half, 0, four)
    p.store_sp(17, r)
    r = p.arith(a_form(59, 18, 10, 12, 11, 29), 'madd', 18, one_half, four, quarter)
    p.store_sp(18, r)
    r = p.arith(a_form(59, 19, 0, 12, 0, 24), 'fres', 19, 0, four)
    p.store_sp(19, r)
    p.check_fpscr()
    r = p.arith(a_form(59, 20, 11, 13, 0, 18), 'div', 20, quarter, three)   # inexact
    p.store_sp(20, r)
    r = p.arith(a_form(59, 21, 10, 13, 0, 18), 'div', 21, one_half, three)
    p.store_sp(21, r)
    r = p.arith(x_form(63, 22, 0, 10, 12), 'frsp', 22, b=one_half)
    p.store_sp(22, r)
    p.check_fpscr()
    # Moves and fsel copy binary32 bits and leave the FPSCR.
    p.emit(x_form(63, 23, 0, 10, 40))                              # fneg
    p.write_fpr(23, True, False)
    p.store_sp(23, one_half ^ 0x80000000)
    p.emit(a_form(63, 24, 23, 12, 11, 23))                         # fsel: -1.5 < 0
    p.write_fpr(24, True, False)
    p.store_sp(24, four)
    exp = arithmetic('cmpu', widen_raw(one_half), widen_raw(four))
    p.emit((63 << 26) | (3 << 23) | (10 << 16) | (12 << 11))      # fcmpu cr3
    new = fpscr_after(p.fpscr, exp)
    p.fpscr_update((new & ~(0xf << 12)) | (exp['fpcc'] << 12))
    p.set_cr_field(3, exp['fpcc'])
    p.check_cr()
    p.check_fpscr()
    # lfd of an exact value narrows; stfd widens back.
    addr = p.data(f64(-6.5))
    p.li32(5, addr)
    p.emit(d_form(50, 25, 5, 0))
    p.write_fpr(25, True, False)
    p.store_sp(25, f32(-6.5))
    slot = p.result_slot(2)
    p.li32(21, slot)
    p.emit(d_form(54, 25, 21, 0))
    p.expect(slot, f64(-6.5) >> 32)
    p.expect(slot + 4, f64(-6.5))
    p.check_tags()
    p.clear_fpscr()


def unaligned(p):
    """lfs and lfd at every byte offset: a word load spans two words, a
    doubleword three."""
    rng = random.Random(0x602)
    base = p.data(*(rng.getrandbits(64) for _ in range(3)))
    raw = b''.join(p.words[base + 4 * i].to_bytes(4, 'big') for i in range(6))
    p.li32(20, base)
    for off in (1, 2, 3, 5, 6, 7):
        p.emit(d_form(48, 26, 20, off))                            # lfs
        p.write_fpr(26, True, False)
        p.store_sp(26, int.from_bytes(raw[off:off + 4], 'big'))
    for off in range(1, 8):
        value = f64(1.0 + off / 16) ^ (off & 1) << 63
        area = p.data(0xa5a5a5a5a5a5a5a5, 0xa5a5a5a5a5a5a5a5)
        for i in range(8):
            addr = area + off + i
            word = addr & ~3
            shift = 8 * (3 - (addr & 3))
            byte = (value >> (8 * (7 - i))) & 0xff
            p.words[word] = (p.words[word] & ~(0xff << shift)) | (byte << shift)
        p.li32(5, area)
        if off == 3:
            p.li32(8, off)
            p.emit(x_form(31, 27, 5, 8, 599))                      # lfdx
        else:
            p.emit(d_form(50, 27, 5, off))                         # lfd
        p.write_fpr(27, True, False)
        slot = p.result_slot(2)
        p.li32(21, slot)
        p.emit(d_form(54, 27, 21, 0))
        p.expect(slot, value >> 32)
        p.expect(slot + 4, value)
    # Update forms leave EA in rA.
    p.li32(10, base)
    p.emit(d_form(49, 26, 10, 6))                                  # lfsu
    p.store_sp(26, int.from_bytes(raw[6:10], 'big'))
    p.store_gpr(10, base + 6)
    # DSI on the second word, the third, and the first (DAR = EA).
    p.lfs(28, f32(7.0))
    for insn, dar in ((d_form(48, 28, 31, -2 & 0xffff), PROT_LO),
                      (d_form(50, 28, 31, -6 & 0xffff), PROT_LO),
                      (d_form(50, 28, 31, 1), PROT_LO + 1)):
        at = p.emit(insn)
        p.event(0x300, at, p.msr, dar, 0x08000000)
    p.store_sp(28, f32(7.0))
    # Unaligned stores take alignment; nothing is written or updated.
    slot = p.result_slot(2)
    p.li32(20, slot)
    for insn, xform, ea in ((d_form(52, 28, 20, 1), False, slot + 1),
                            (d_form(55, 28, 20, 2), False, slot + 2),
                            (x_form(31, 28, 20, 8, 663), True, slot + 3)):
        if xform:
            p.li32(8, 3)
        at = p.emit(insn)
        p.event(0x600, at, p.msr, ea, dsisr_x(insn) if xform else dsisr_d(insn))
    p.expect(slot, 0)
    p.expect(slot + 4, 0)
    p.store_gpr(20, slot)


def in_flight(p):
    """A pipelined trapping fadds cancels the overlapped store behind it;
    the handler returns to the store, which then writes once."""
    p.li32(10, 0)
    p.lfs(1, f32(1.0))
    p.set_tags(p.sp & ~tag(2), p.lt)
    slot = p.result_slot(1)
    p.li32(23, slot)
    p.emit(SYNC)
    trap(p, a_form(59, 4, 1, 2, 0, 21))                            # fadds f4, f1, f2
    p.emit(d_form(52, 1, 23, 0))                                   # stfs f1
    p.emit(d_form(14, 10, 10, 1))
    p.expect(slot, f32(1.0))
    p.store_gpr(10, 1)
    p.set_tags(p.sp | tag(2), p.lt)


def fp_enabled(p):
    # An FPSCR write that sets FEX with FE0/FE1 set is a program exception
    # (602 UM Table 4-2); the FPSCR keeps the update.
    p.clear_fpscr()
    p.mtmsr(p.msr | FE0 | FE1)
    p.emit(x_form(63, 24, 0, 0, 38))                               # mtfsb1 VE
    p.fpscr_update(p.fpscr | 1 << 7)
    at = p.emit(x_form(63, 21, 0, 0, 38))                          # mtfsb1 VXSOFT
    p.fpscr_update(p.fpscr | (1 << 10) | (1 << 29) | (1 << 30) | (1 << 31))
    p.event(0x700, at, p.msr | SRR1_FP)
    p.mtmsr(p.msr & ~(FE0 | FE1))
    p.check_fpscr()
    p.clear_fpscr()


def sticky_timing(p):
    """Retirement spacing of independent fadds: one cycle, two when the
    second newly sets XX."""
    one, two, tiny = f32(1.0), f32(2.0), f32(2.0 ** -30)
    p.lfs(1, one)
    p.lfs(2, two)
    p.lfs(3, tiny)
    p.clear_fpscr()
    for spacing in (2, 1):
        p.emit(SYNC)
        first = p.pc
        p.arith(a_form(59, 6, 1, 2, 0, 21), 'add', 6, one, two)
        last = p.pc
        p.arith(a_form(59, 7, 1, 3, 0, 21), 'add', 7, one, tiny)
        p.spacings.append(('R', first, last, spacing))
    p.check_fpscr()
    p.clear_fpscr()


# 602 UM Table 6-6, latency:throughput: lfs, stfs and stfiwx 2:1, lfd and
# stfd 3:2. Probes count dispatch to retirement, one more than the latency
# (Figure 6-3), and the retirement spacing of the first and last of four
# independent accesses. Through the pipelined unit over a memory taking one
# access per cycle the table is met; otherwise the memory or the serialized
# lane is slower.
MEMORY_TIMING = {
    'lane': {'lfs': (6, 15), 'lfd': (6, 15), 'stfs': (7, 18), 'stfd': (7, 18),
             'stfiwx': (7, 18)},
    'unit': {'lfs': (3, 6), 'lfd': (4, 6), 'stfs': (3, 3), 'stfd': (4, 6),
             'stfiwx': (3, 3)},
    'table': {'lfs': (3, 3), 'lfd': (4, 6), 'stfs': (3, 3), 'stfd': (4, 6),
              'stfiwx': (3, 3)},
}


def memory_timing(p, timing):
    """Isolated latency and the spacing of four independent accesses for
    each FP load and store row of Table 6-6."""
    p.res_next = (p.res_next + 7) & ~7
    doubles = [f64(1.0 + k) for k in range(4)]
    singles = [f32(0.5 + k) for k in range(4)]
    dbase = p.data(*doubles)
    sbase = p.data((singles[0] << 32) | singles[1], (singles[2] << 32) | singles[3])
    words = []
    for k in range(4):
        p.lfs(12 + k, singles[k])
        words.append(p.arith(x_form(63, 12 + k, 0, 12 + k, 15), 'fctiwz', 12 + k,
                             0, singles[k]))
    p.li32(20, dbase)
    p.li32(19, sbase)
    for k in range(4):
        p.li32(24 + k, 4 * k)
    rows = (
        ('lfd', lambda k: d_form(50, 4 + k, 20, 8 * k), doubles, 0),
        ('stfd', lambda k: d_form(54, 4 + k, 21, 8 * k), doubles, 8),
        ('lfs', lambda k: d_form(48, 4 + k, 19, 4 * k), singles, 0),
        ('stfs', lambda k: d_form(52, 4 + k, 21, 4 * k), singles, 4),
        ('stfiwx', lambda k: x_form(31, 12 + k, 21, 24 + k, 983), words, 4),
    )
    for name, form, values, size in rows:
        lat, spacing = timing[name]
        slots = [p.result_slot(size // 4), p.result_slot(size)] if size else []
        if size:
            p.li32(21, slots[0])
        p.emit(SYNC)
        p.probes[p.emit(form(0))] = lat
        if size:
            p.li32(21, slots[1])
        p.emit(SYNC)
        pcs = [p.emit(form(k)) for k in range(4)]
        p.spacings.append(('R', pcs[0], pcs[-1], spacing))
        if not size:
            for k in range(4):
                p.write_fpr(4 + k, True, False)
            continue
        for addr, ks in ((slots[0], (0,)), (slots[1], range(4))):
            for k in ks:
                at = addr + size * k
                if size == 8:
                    p.expect(at, values[k] >> 32)
                    p.expect(at + 4, values[k])
                else:
                    p.expect(at, values[k])


def random_cases(p, rng, count):
    base_msr = p.msr
    for _ in range(count):
        (insn, a, b, c, old, fe, exc, write, result, _mask, new, fmask, rc,
         cr1) = case_602(rng)
        sentinel = 0x5a5a5a5a
        addr = p.data((a << 32) | b, (c << 32) | sentinel)
        p.li32(5, addr)
        for fr in range(1, 5):
            p.emit(d_form(48, fr, 5, 4 * (fr - 1)))
            p.write_fpr(fr, True, False)
        p.clear_fpscr()
        p.emit((63 << 26) | (6 << 23) | (((old >> 4) & 0xf) << 12) | (134 << 1))
        p.emit((63 << 26) | (7 << 23) | ((old & 0xf) << 12) | (134 << 1))
        p.fpscr = old
        fe_bits = (FE0 if fe & 2 else 0) | (FE1 if fe & 1 else 0)
        if fe_bits:
            p.mtmsr(base_msr | fe_bits)
        if exc:
            trap(p, insn)
        else:
            p.emit(insn)
            p.fpscr_update(new)
            if rc:
                p.set_cr_field(1, cr1)
        if fe_bits:
            p.mtmsr(base_msr)
        fctiwz = (insn >> 26) == 63 and (insn >> 1) & 0x3ff == 15
        if write and not exc and fctiwz:
            p.write_fpr(4, False, True)
            p.store_lt(4, result)
        else:
            p.store_sp(4, result if write and not exc else sentinel)
        p.emit(x_form(63, 5, 0, 0, 583))
        p.write_fpr(5, False, True)
        p.store_lt(5, p.fpscr, fmask if not exc else 0xffffffff)
        p.check_cr()


def build(seed, count, timing='lane'):
    rng = random.Random(seed)
    p = Program602()
    handlers(p)
    p.li32(29, LOG)
    p.li32(31, PROT_LO)
    p.li32(30, DONE)
    unavailable_and_illegal(p)
    sp_lt(p)
    tag_traps(p)
    arithmetic_602(p)
    unaligned(p)
    access_faults(p, True)
    in_flight(p)
    fp_enabled(p)
    def fex(q):
        q.fpscr_update(q.fpscr | (1 << 7) | (1 << 10) | (1 << 29) | (1 << 30) | (1 << 31))

    fp_enable_deferred(p, fex)
    fp_enable_rfi(p, fex)
    random_cases(p, rng, count)
    sticky_timing(p)
    memory_timing(p, MEMORY_TIMING[timing])
    p.check_tags()
    p.emit(d_form(36, 0, 30, 0))          # stw r0 to DONE ends the run
    p.emit(18 << 26)                      # b .
    for i, (vector, srr0, srr1, dar, dsisr) in enumerate(p.log):
        base = LOG + 20 * i
        p.expect(base, srr0)
        p.expect(base + 4, srr1 or 0, 0 if srr1 is None else 0xffffffff)
        p.expect(base + 8, dar or 0, 0 if dar is None else 0xffffffff)
        p.expect(base + 12, dsisr or 0, 0 if dsisr is None else 0xffffffff)
        p.expect(base + 16, vector)
    p.expect(LOG + 20 * len(p.log) + 16, 0)
    assert p.pc <= DATA, 'code overlaps data'
    return p


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--seed', type=lambda s: int(s, 0), default=0x602)
    parser.add_argument('--random', type=int, default=150)
    parser.add_argument('--lsu-pipe', action='store_true',
                        help='FP accesses run in the pipelined load/store unit')
    parser.add_argument('--pipe-mem', action='store_true',
                        help='the bench memory takes one access per cycle')
    args = parser.parse_args()
    timing = ('table' if args.pipe_mem else 'unit') if args.lsu_pipe else 'lane'
    p = build(args.seed, args.random, timing)
    print(f'fpu_core_602_program: {len(p.words)} words, {len(p.expects)} expected, '
          f'{len(p.log)} exceptions, {p.sticky} sticky stalls')
    lines = [f'P {PROT_LO:08x} {PROT_HI:08x} 0', f'D {DONE:08x} 0 0',
             f'C {CHANGED_LO:08x} {CHANGED_HI:08x} 0', f'T {TEA_LO:08x} {TEA_HI:08x} 0',
             f'S {p.sticky:x} 0 0']
    lines += [f'M {a:08x} {v:08x} 0' for a, v in sorted(p.words.items())]
    lines += [f'E {a:08x} {v:08x} {m:08x}' for a, v, m in p.expects]
    lines += [f'L {pc:08x} {cycles:x} 0' for pc, cycles in p.probes.items()]
    lines += [f'{kind} {a:08x} {b:08x} {cycles:x}' for kind, a, b, cycles in p.spacings]
    Path(args.image).parent.mkdir(parents=True, exist_ok=True)
    Path(args.image).write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
