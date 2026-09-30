#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Program image for tb_core_fpu: the FPU attached to ppc_core.

Directed sections cover FP unavailable (lazy enable and retry), illegal
forms, every load/store form, moves, fsel, compares, FPSCR instructions,
estimate specials, alignment, DSI and FP enabled exceptions. The random
section runs enabled-exception arithmetic cases from the standalone FPU
generator, each with its own FPSCR, MSR[FE0/FE1] and Rc. Expected words come
from the independent Python reference model; exception handlers log SRR0,
SRR1, DAR, DSISR and the vector to memory. The latency section probes
dispatch-to-retirement cycles of independent instructions.

--chip-image writes a self-checking byte image for tb_chip_firmware instead:
the program runs from the hard reset vector with the data cache enabled,
compares every expected word itself and reports through the mailbox. It
omits the DSI section, which needs a protected region.
"""
import argparse
from pathlib import Path
import random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fpu'))
from enabled_vectors import case_603, fpscr_after  # noqa: E402
from ppc_reference import arithmetic  # noqa: E402
from production_vectors import widen  # noqa: E402

RESET_PC = 0x1000
DATA, RES, LOG, DONE = 0x40000, 0x50000, 0x60000, 0x70000
PROT_LO, PROT_HI = 0x7F000, 0x7FFFC
CHIP = False
CHIP_BASE, CHIP_IMAGE_BYTES = 0xfff00000, 0x10000


def use_chip_layout():
    global CHIP, RESET_PC, DATA, RES, LOG, DONE
    CHIP = True
    RESET_PC, DATA = 0xfff01000, 0xfff0c000
    RES, LOG, DONE = 0xfff10000, 0xfff20000, 0xfff3ff00
MSR_FP, MSR_IP, FE0, FE1 = 0x2000, 0x40, 0x800, 0x100
SRR1_ILLEGAL, SRR1_FP = 0x00080000, 0x00100000
VECTORS = (0x300, 0x600, 0x700, 0x800)
ONE, TWO, HALF = 0x3ff0000000000000, 0x4000000000000000, 0x3fe0000000000000
QNAN, SNAN = 0x7ff8000000001234, 0x7ff0000000000042
PINF, NINF, NZERO = 0x7ff0000000000000, 0xfff0000000000000, 1 << 63
# Host FPSCR bit positions (architectural bit = 31 - host).
EXCEPTION_BITS = [31 - b for b in (3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 21, 22, 23)]
VX_BITS = [31 - b for b in (7, 8, 9, 10, 11, 12, 21, 22, 23)]
# UM Table 6-5: execute latency and initiation interval (the structural
# minimum for staged rows; divides and estimates block the unit).
TABLE_6_5 = {
    'fadd': (3, 1), 'fadds': (3, 1), 'fmul': (4, 2), 'fmuls': (3, 1),
    'fmadd': (4, 2), 'fmadds': (3, 1), 'fdiv': (33, 33), 'fdivs': (18, 18),
    'fres': (18, 18), 'frsqrte': (3, 1), 'fsel': (3, 1), 'fmr': (3, 1),
    'fcmpu': (3, 1), 'frsp': (3, 1), 'fctiw': (3, 1), 'mffs': (3, 3),
    'mtfsf': (3, 3), 'mtfsfi': (3, 3), 'mcrfs': (3, 3),
}
# The standalone FPU finishes moves, fsel and FPSCR instructions one cycle
# before Table 6-5; its timing record owns that schedule.
FPU_EARLY = {'fsel', 'fmr', 'mffs', 'mtfsf', 'mtfsfi', 'mcrfs'}
# Figure 6-3: an instruction dispatched in cycle n executes from n+1 and
# completes the cycle after its last execute stage.
LATENCY = {name: lat + 1 - (name in FPU_EARLY)
           for name, (lat, _) in TABLE_6_5.items()}
# FP loads and stores run through the serialized lane: word accesses, one
# cycle of bench memory each.
LATENCY.update({'lfd': 10, 'lfs': 8, 'stfd': 11, 'stfs': 9, 'stfiwx': 9,
                'add': 3})
SYNC = (31 << 26) | (598 << 1)


def d_form(op, rt, ra, d):
    return (op << 26) | (rt << 21) | (ra << 16) | (d & 0xffff)


def x_form(op, rt, ra, rb, xo, rc=0):
    return (op << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc


def a_form(op, frt, fra, frb, frc, xo, rc=0):
    return (op << 26) | (frt << 21) | (fra << 16) | (frb << 11) | (frc << 6) | \
        (xo << 1) | rc


def recompute(fpscr):
    vx = any(fpscr >> b & 1 for b in VX_BITS)
    fpscr = (fpscr & ~(1 << 29)) | (int(vx) << 29)
    fex = any(fpscr >> s & fpscr >> e & 1 for s, e in
              ((29, 7), (28, 6), (27, 5), (26, 4), (25, 3)))
    return (fpscr & ~(1 << 30)) | (int(fex) << 30)


def narrow(bits):
    """binary32 bits of a binary64 value exactly representable as normal."""
    sign = bits >> 63
    exponent = (bits >> 52) & 0x7ff
    if exponent == 0:
        return sign << 31
    return (sign << 31) | ((exponent - 1023 + 127) << 23) | ((bits >> 29) & 0x7fffff)


def f32(value):
    import struct
    return struct.unpack('>I', struct.pack('>f', value))[0]


def f64(value):
    import struct
    return struct.unpack('>Q', struct.pack('>d', value))[0]


class Program:
    def __init__(self):
        self.words = {}
        self.pc = RESET_PC
        self.expects = []
        self.probes = {}
        self.spacings = []
        self.data_next = DATA
        self.res_next = RES
        self.log = []
        self.fpscr = 0
        self.cr = 0
        self.msr = MSR_IP

    def emit(self, insn):
        self.words[self.pc] = insn & 0xffffffff
        self.pc += 4
        return self.pc - 4

    def li32(self, r, value):
        self.emit(d_form(15, r, 0, value >> 16))
        self.emit(d_form(24, r, r, value & 0xffff))

    def data(self, *values64):
        addr = self.data_next
        for v in values64:
            self.words[self.data_next] = v >> 32
            self.words[self.data_next + 4] = v & 0xffffffff
            self.data_next += 8
        return addr

    def expect(self, addr, value, mask=0xffffffff):
        self.expects.append((addr, value & 0xffffffff, mask & 0xffffffff))

    def result_slot(self, words=2):
        addr = self.res_next
        self.res_next += 4 * words
        return addr

    def mtmsr(self, value):
        self.li32(9, value)
        self.emit(x_form(31, 9, 0, 0, 146))
        self.msr = value

    def event(self, vector, srr0, srr1, dar=None, dsisr=None):
        self.log.append((vector, srr0, srr1, dar, dsisr))

    # r21 points at the next result slot; stores go through it.
    def store_fpr(self, fr, value, mask64=(1 << 64) - 1):
        addr = self.result_slot(2)
        self.li32(21, addr)
        self.emit(d_form(54, fr, 21, 0))
        self.expect(addr, value >> 32, mask64 >> 32)
        self.expect(addr + 4, value, mask64)

    def store_gpr(self, r, value):
        addr = self.result_slot(1)
        self.li32(21, addr)
        self.emit(d_form(36, r, 21, 0))
        self.expect(addr, value)

    def check_fpscr(self, mask=0xffffffff):
        self.emit(x_form(63, 30, 0, 0, 583))
        self.store_fpr(30, self.fpscr, mask)

    def check_cr(self):
        self.emit(x_form(31, 8, 0, 0, 19))
        self.store_gpr(8, self.cr)

    def set_cr_field(self, field, value):
        shift = 28 - 4 * field
        self.cr = (self.cr & ~(0xf << shift)) | ((value & 0xf) << shift)

    def load_fpr(self, fr, value):
        addr = self.data(value)
        self.li32(5, addr)
        self.emit(d_form(50, fr, 5, 0))
        return addr

    def clear_fpscr(self):
        self.emit((63 << 26) | (0xff << 17) | (31 << 11) | (711 << 1))
        self.fpscr = 0


def handlers(p):
    for vector in VECTORS:
        pc = 0xfff00000 | vector
        seq = []
        for spr, off in ((26, 0), (27, 4), (19, 8), (18, 12)):
            seq += [x_form(31, 26, spr & 31, spr >> 5, 339), d_form(36, 26, 29, off)]
        seq += [d_form(14, 26, 0, vector), d_form(36, 26, 29, 16), d_form(14, 29, 29, 20)]
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


def dsisr_d(insn):
    return (((insn >> 26) & 1) << 14) | (((insn >> 27) & 0xf) << 10) | \
        (((insn >> 21) & 31) << 5) | ((insn >> 16) & 31)


def dsisr_x(insn):
    return (((insn >> 1) & 3) << 15) | (((insn >> 6) & 1) << 14) | \
        (((insn >> 7) & 0xf) << 10) | (((insn >> 21) & 31) << 5) | ((insn >> 16) & 31)


def directed(p):
    p.li32(29, LOG)
    p.li32(20, DATA)
    p.li32(31, PROT_LO)
    p.li32(30, DONE)
    if CHIP:
        # HID0[DCE]: FP accesses go through the data cache.
        p.emit(x_form(31, 5, 1008 & 31, 1008 >> 5, 339))
        p.emit(d_form(24, 5, 5, 0x4000))
        p.emit(x_form(31, 5, 1008 & 31, 1008 >> 5, 467))
        p.emit(x_form(19, 0, 0, 0, 150))
    zero = p.data(0)
    # Illegal outranks FP unavailable: a reserved field (fadd with frC) and
    # the unimplemented fsqrt, both with MSR[FP] = 0.
    at = p.emit(a_form(63, 1, 1, 1, 1, 21))
    p.event(0x700, at, p.msr | SRR1_ILLEGAL)
    at = p.emit(a_form(63, 1, 0, 1, 0, 22))
    p.event(0x700, at, p.msr | SRR1_ILLEGAL)
    # FP unavailable, then the handler enables FP and the load retries.
    p.li32(5, zero)
    at = p.emit(d_form(50, 31, 5, 0))
    p.event(0x800, at, p.msr)
    p.msr |= MSR_FP
    p.clear_fpscr()
    p.check_fpscr()

    # Loads and stores: every form, update base values, stfiwx.
    s0, s1 = f32(1.5), f32(-0.375)
    sw = p.data((s0 << 32) | s1)
    d0 = f64(3.25)
    dw = p.data(d0, f64(-7.0), 0x123456789abcdef0)
    p.li32(5, sw)
    p.emit(d_form(48, 1, 5, 0))           # lfs f1
    p.store_fpr(1, widen(s0))
    p.emit(d_form(48, 2, 5, 4))           # lfs f2 (second word)
    p.store_fpr(2, widen(s1))
    p.li32(6, dw)
    p.emit(d_form(50, 3, 6, 0))           # lfd f3
    p.store_fpr(3, d0)
    slot = p.result_slot(1)
    p.li32(7, slot)
    p.emit(d_form(52, 3, 7, 0))           # stfs f3
    p.expect(slot, f32(3.25))
    p.li32(8, 8)
    p.emit(x_form(31, 4, 6, 8, 599))      # lfdx f4 = -7.0
    p.store_fpr(4, f64(-7.0))
    p.li32(8, 4)
    p.emit(x_form(31, 5, 5, 8, 535))      # lfsx f5 = s1
    p.store_fpr(5, widen(s1))
    p.li32(10, dw)
    p.emit(d_form(51, 6, 10, 16))         # lfdu f6, 16(r10)
    p.store_gpr(10, dw + 16)
    p.store_fpr(6, 0x123456789abcdef0)
    slot = p.result_slot(1)
    p.li32(10, slot)
    p.li32(8, 0)
    p.emit(x_form(31, 6, 10, 8, 983))     # stfiwx f6
    p.expect(slot, 0x9abcdef0)
    p.li32(10, sw)
    p.emit(d_form(49, 7, 10, 4))          # lfsu f7, 4(r10)
    p.store_gpr(10, sw + 4)
    p.store_fpr(7, widen(s1))
    p.li32(10, sw)
    p.li32(8, 4)
    p.emit(x_form(31, 8, 10, 8, 567))     # lfsux f8
    p.store_gpr(10, sw + 4)
    p.li32(10, dw)
    p.li32(8, 8)
    p.emit(x_form(31, 9, 10, 8, 631))     # lfdux f9
    p.store_gpr(10, dw + 8)
    p.store_fpr(9, f64(-7.0))
    for xo, name in ((663, 'stfsx'), (695, 'stfsux'), (727, 'stfdx'), (759, 'stfdux'),
                     (53, 'stfsu'), (55, 'stfdu'), (54, 'stfd')):
        double = name.startswith('stfd')
        slot = p.result_slot(2)
        if xo > 100:
            p.li32(10, slot - 8)
            p.li32(8, 8)
            p.emit(x_form(31, 3, 10, 8, xo))
        else:
            p.li32(10, slot - 8)
            p.emit(d_form(xo, 3, 10, 8))
        if double:
            p.expect(slot, d0 >> 32)
            p.expect(slot + 4, d0)
        else:
            p.expect(slot, f32(3.25))
        if 'u' in name[4:]:
            p.store_gpr(10, slot)
    # A doubleword at a word-aligned, not doubleword-aligned address.
    odd = p.data(0x1111111122222222, 0x3333333344444444)
    p.li32(10, odd + 4)
    p.emit(d_form(50, 10, 10, 0))
    p.store_fpr(10, 0x2222222233333333)

    # Moves keep NaN payloads and signs; Rc copies FPSCR[0:3] to CR1.
    p.emit(x_form(63, 3, 0, 0, 38))       # mtfsb1 3 (OX): FX and OX set
    p.fpscr = recompute(p.fpscr | (1 << 28) | (1 << 31))
    p.load_fpr(11, SNAN)
    p.load_fpr(12, NZERO)
    for xo, fn in ((72, lambda v: v), (40, lambda v: v ^ (1 << 63)),
                   (264, lambda v: v & ~(1 << 63)), (136, lambda v: v | (1 << 63))):
        for src in (11, 12):
            value = SNAN if src == 11 else NZERO
            p.emit(x_form(63, 13, 0, src, xo, 1))
            p.set_cr_field(1, p.fpscr >> 28)
            p.store_fpr(13, fn(value))
    p.check_cr()
    p.check_fpscr()
    # fsel: frA >= 0 (either zero) selects frC; negative or NaN selects frB.
    p.load_fpr(14, ONE)
    p.load_fpr(15, TWO)
    for sel, pick in ((NZERO, ONE), (0, ONE), (f64(-1.0), TWO), (QNAN, TWO),
                      (PINF, ONE)):
        p.load_fpr(16, sel)
        p.emit(a_form(63, 17, 16, 15, 14, 23))
        p.store_fpr(17, pick)
    # Compares into CR3/CR4 and FPCC; fcmpo signals VXVC for a QNaN.
    p.clear_fpscr()
    for opx, crf, a, b in ((0, 3, ONE, TWO), (32, 4, TWO, ONE), (0, 5, NZERO, 0),
                           (32, 6, QNAN, ONE), (0, 2, SNAN, ONE)):
        p.load_fpr(18, a)
        p.load_fpr(19, b)
        p.emit((63 << 26) | (crf << 23) | (18 << 16) | (19 << 11) | (opx << 1))
        exp = arithmetic('cmpo' if opx else 'cmpu', a, b)
        p.fpscr = fpscr_after(p.fpscr, exp)
        p.fpscr = (p.fpscr & ~(0xf << 12)) | (exp['fpcc'] << 12)
        p.set_cr_field(crf, exp['fpcc'])
    p.check_cr()
    p.check_fpscr()
    # mcrfs copies a nibble and clears its exception bits but FEX/VX.
    p.emit((63 << 26) | (7 << 23) | (0 << 18) | (64 << 1))
    p.set_cr_field(7, p.fpscr >> 28)
    p.fpscr = recompute(p.fpscr & ~((1 << 31) | (1 << 28)))
    p.emit((63 << 26) | (1 << 23) | (1 << 18) | (64 << 1))   # mcrfs 1, 1
    p.set_cr_field(1, p.fpscr >> 24)
    p.fpscr = recompute(p.fpscr & ~(0xf << 24 & sum(1 << b for b in EXCEPTION_BITS)))
    p.check_cr()
    p.check_fpscr()
    # mtfsfi, mtfsf with a field mask, mtfsb0; record forms update CR1.
    p.emit((63 << 26) | (7 << 23) | (0x3 << 12) | (134 << 1) | 1)   # RN = 3
    p.fpscr = recompute((p.fpscr & ~0xf) | 0x3)
    p.set_cr_field(1, p.fpscr >> 28)
    p.load_fpr(20, 0x00000000a5000000)
    p.emit((63 << 26) | (0x60 << 17) | (20 << 11) | (711 << 1) | 1)  # fields 1, 2
    p.fpscr = recompute((p.fpscr & ~0x0ff00000) | 0x05000000)
    p.set_cr_field(1, p.fpscr >> 28)
    p.emit(x_form(63, 5, 0, 0, 70, 1))    # mtfsb0 5 (ZX)
    p.fpscr = recompute(p.fpscr & ~(1 << 26))
    p.set_cr_field(1, p.fpscr >> 28)
    p.check_cr()
    p.check_fpscr()
    p.clear_fpscr()
    # Estimate specials, whose results are exact. FR/FI are undefined.
    for primary, xo, src, value, extra in ((59, 24, 0, PINF, 1 << 26),
                                           (59, 24, NINF, NZERO, 0),
                                           (63, 26, PINF, 0, 0),
                                           (63, 26, f64(-1.0), 0x7ff8000000000000,
                                            (1 << 9) | (1 << 29))):
        p.load_fpr(21, src)
        p.emit(a_form(primary, 22, 0, 21, 0, xo))
        p.store_fpr(22, value)
        classes = {PINF: 0b00101, NZERO: 0b10010, 0: 0b00010,
                   0x7ff8000000000000: 0b10001}
        new = p.fpscr | extra
        if new & ~p.fpscr & sum(1 << b for b in EXCEPTION_BITS):
            new |= 1 << 31
        p.fpscr = recompute((new & ~(0x1f << 12)) | (classes[value] << 12))
        p.check_fpscr(0xffffffff & ~(3 << 17))

    # Alignment: no FPR, memory or base update.
    for insn, xform, ea in ((d_form(50, 23, 20, 2), False, DATA + 2),
                            (d_form(55, 23, 20, 6), False, DATA + 6),
                            (x_form(31, 23, 20, 8, 599), True, DATA + 0x12)):
        if xform:
            p.li32(8, 0x12)
        p.load_fpr(23, ONE)
        p.li32(20, DATA)
        at = p.emit(insn)
        p.event(0x600, at, p.msr, ea, dsisr_x(insn) if xform else dsisr_d(insn))
        p.store_fpr(23, ONE)
        p.store_gpr(20, DATA)
    # DSI: protected load, store (store bit) and a doubleword whose second
    # word faults; an update form leaves its base.
    if not CHIP:
        dsi(p)
    fp_enabled(p)


def dsi(p):
    p.load_fpr(24, ONE)
    at = p.emit(d_form(50, 24, 31, 0))
    p.event(0x300, at, p.msr, PROT_LO, 0x08000000)
    at = p.emit(d_form(54, 24, 31, 8))
    p.event(0x300, at, p.msr, PROT_LO + 8, 0x0a000000)
    at = p.emit(d_form(51, 24, 31, -4 & 0xffff))
    p.event(0x300, at, p.msr, PROT_LO, 0x08000000)
    p.store_fpr(24, ONE)
    p.store_gpr(31, PROT_LO)


def fp_enabled(p):
    # FP enabled program exception from mtfsb1 with FE0|FE1 set; FPSCR keeps
    # the update.
    p.clear_fpscr()
    p.mtmsr(p.msr | FE0 | FE1)
    p.emit(x_form(63, 24, 0, 0, 38))      # mtfsb1 24 (VE)
    at = p.emit(x_form(63, 21, 0, 0, 38))  # mtfsb1 21 (VXSOFT)
    p.event(0x700, at, p.msr | SRR1_FP)
    p.fpscr = recompute(p.fpscr | (1 << 7) | (1 << 10) | (1 << 31))
    p.mtmsr(p.msr & ~(FE0 | FE1))
    p.check_fpscr()
    p.clear_fpscr()


def random_cases(p, rng, count):
    base_msr = p.msr
    for _ in range(count):
        (insn, a, b, c, old, fe, exc, write, result, mask, new, fmask, rc,
         cr1) = case_603(rng)
        sentinel = 0x5a5a5a5a5a5a5a5a
        addr = p.data(a, b, c, sentinel)
        p.li32(5, addr)
        for fr in range(1, 5):
            p.emit(d_form(50, fr, 5, 8 * (fr - 1)))
        p.clear_fpscr()
        p.emit((63 << 26) | (6 << 23) | (((old >> 4) & 0xf) << 12) | (134 << 1))
        p.emit((63 << 26) | (7 << 23) | ((old & 0xf) << 12) | (134 << 1))
        fe_bits = (FE0 if fe & 2 else 0) | (FE1 if fe & 1 else 0)
        if fe_bits:
            p.mtmsr(base_msr | fe_bits)
        at = p.emit(insn)
        if exc:
            p.event(0x700, at, p.msr | SRR1_FP)
        if fe_bits:
            p.mtmsr(base_msr)
        p.fpscr = new
        if rc:
            p.set_cr_field(1, cr1)
        p.store_fpr(4, result if write else sentinel, mask if write else (1 << 64) - 1)
        p.emit(x_form(63, 5, 0, 0, 583))
        p.store_fpr(5, new, fmask)
        p.check_cr()


def latency_forms():
    return {
        'fadd': a_form(63, 4, 1, 2, 0, 21), 'fadds': a_form(59, 4, 1, 2, 0, 21),
        'fmul': a_form(63, 4, 1, 0, 2, 25), 'fmuls': a_form(59, 4, 1, 0, 2, 25),
        'fmadd': a_form(63, 4, 1, 2, 3, 29), 'fmadds': a_form(59, 4, 1, 2, 3, 29),
        'fdiv': a_form(63, 4, 1, 2, 0, 18), 'fdivs': a_form(59, 4, 1, 2, 0, 18),
        'fres': a_form(59, 4, 0, 2, 0, 24), 'frsqrte': a_form(63, 4, 0, 2, 0, 26),
        'fsel': a_form(63, 4, 1, 2, 3, 23), 'fmr': x_form(63, 4, 0, 2, 72),
        'fcmpu': (63 << 26) | (3 << 23) | (1 << 16) | (2 << 11),
        'frsp': x_form(63, 4, 0, 2, 12), 'fctiw': x_form(63, 4, 0, 2, 14),
        'mffs': x_form(63, 4, 0, 0, 583), 'mtfsf': (63 << 26) | (0x01 << 17) | (31 << 11) | (711 << 1),
        'mtfsfi': (63 << 26) | (7 << 23) | (134 << 1), 'mcrfs': (63 << 26) | (2 << 23) | (64 << 1),
        'lfd': d_form(50, 4, 5, 0), 'lfs': d_form(48, 4, 5, 0),
        'stfd': d_form(54, 1, 21, 0), 'stfs': d_form(52, 1, 21, 0),
        'stfiwx': x_form(31, 1, 21, 8, 983), 'add': x_form(31, 10, 10, 11, 266),
    }


def with_dst(insn, frt):
    return (insn & ~(31 << 21)) | (frt << 21)


def latency(p):
    """Isolated latency, then retirement spacing of independent and
    dependent groups and dispatch spacing of mixed streams. Each group
    follows a sync, which drains the machine while the six-entry IQ fills,
    so fetch never limits a group."""
    p.clear_fpscr()
    one = p.load_fpr(1, ONE)
    p.load_fpr(2, TWO)
    p.load_fpr(3, HALF)
    slot = p.result_slot(2)
    p.li32(21, slot)
    p.li32(8, 0)
    p.li32(5, one)
    forms = latency_forms()
    for name, insn in forms.items():
        p.emit(SYNC)
        p.probes[p.emit(insn)] = LATENCY[name]
    # Independent: four instances with distinct destinations retire one
    # initiation interval apart. Compares write distinct CR fields.
    for name, (lat, ii) in TABLE_6_5.items():
        if name.startswith('m'):
            continue
        count = 2 if ii > 2 else 4
        p.emit(SYNC)
        pcs = []
        for k in range(count):
            insn = forms[name]
            insn = ((insn & ~(7 << 23)) | ((4 + k) << 23)) if name == 'fcmpu' \
                else with_dst(insn, 4 + k)
            pcs.append(p.emit(insn))
        p.spacings.append(('R', pcs[0], pcs[-1], (count - 1) * ii))
    # Dependent: each instance reads the previous result as frA.
    for name in ('fadd', 'fadds', 'fmul', 'fmuls', 'fmadd', 'fmadds', 'frsp',
                 'fmr', 'fsel'):
        lat = TABLE_6_5[name][0]
        p.emit(SYNC)
        pcs = []
        src = 1
        for k in range(4):
            insn = with_dst(forms[name], 4 + k)
            if name in ('frsp', 'fmr'):
                insn = (insn & ~(31 << 11)) | (src << 11)
            else:
                insn = (insn & ~(31 << 16)) | (src << 16)
            pcs.append(p.emit(insn))
            src = 4 + k
        p.spacings.append(('R', pcs[0], pcs[-1], 3 * lat))
    # Mixed integer and FP: one dispatch per cycle, integer retirement in
    # order behind the FP instructions.
    p.emit(SYNC)
    pcs = [p.emit(a_form(63, 4, 1, 2, 0, 21)), p.emit(d_form(14, 10, 10, 1)),
           p.emit(a_form(59, 5, 1, 0, 2, 25)), p.emit(d_form(14, 11, 11, 1)),
           p.emit(a_form(63, 6, 1, 2, 3, 29)), p.emit(d_form(14, 12, 12, 1))]
    p.spacings.append(('I', pcs[0], pcs[-1], 5))
    p.spacings.append(('R', pcs[0], pcs[1], 1))
    p.spacings.append(('R', pcs[4], pcs[5], 1))


def build(seed, count):
    rng = random.Random(seed)
    p = Program()
    handlers(p)
    directed(p)
    random_cases(p, rng, count)
    latency(p)
    if not CHIP:
        p.emit(d_form(36, 0, 30, 0))      # stw r0 to DONE ends the run
        p.emit(18 << 26)                  # b .
    for i, (vector, srr0, srr1, dar, dsisr) in enumerate(p.log):
        base = LOG + 20 * i
        p.expect(base, srr0)
        p.expect(base + 4, srr1)
        p.expect(base + 8, dar or 0, 0 if dar is None else 0xffffffff)
        p.expect(base + 12, dsisr or 0, 0 if dsisr is None else 0xffffffff)
        p.expect(base + 16, vector)
    p.expect(LOG + 20 * len(p.log) + 16, 0)
    if CHIP:
        self_check(p)
    return p


def self_check(p):
    """Compare every expected word; the mailbox gets 1, or 2 on a mismatch."""
    p.probes = {}
    p.spacings = []
    p.words[0xfff00100] = (18 << 26) | ((RESET_PC - 0xfff00100) & 0x3fffffc)
    branches = []
    for addr, value, mask in p.expects:
        if mask == 0:
            continue
        p.li32(6, addr)
        p.emit(d_form(32, 5, 6, 0))
        if mask != 0xffffffff:
            p.li32(8, mask)
            p.emit(x_form(31, 5, 5, 8, 28))
        p.li32(7, value & mask)
        p.emit(x_form(31, 0, 5, 7, 0))    # cmpw r5, r7
        p.emit((16 << 26) | (12 << 21) | (2 << 16) | 8)
        branches.append(p.emit(0))
    for mailbox in (1, 2):
        if mailbox == 2:
            for at in branches:
                p.words[at] = (18 << 26) | ((p.pc - at) & 0x3fffffc)
        p.emit(d_form(14, 5, 0, mailbox))
        p.emit(d_form(36, 5, 30, 0))
        p.emit(x_form(31, 0, 0, 30, 86))  # dcbf 0, r30
        p.emit(x_form(31, 0, 0, 0, 598))  # sync
        p.emit(18 << 26)
    assert p.pc <= DATA, 'code overlaps data'


def write_chip_image(p, path):
    image = bytearray(CHIP_IMAGE_BYTES)
    for addr, word in p.words.items():
        offset = addr - CHIP_BASE
        assert 0 <= offset < CHIP_IMAGE_BYTES, hex(addr)
        image[offset:offset + 4] = word.to_bytes(4, 'big')
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(''.join(f'{b:02x}\n' for b in image))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image')
    parser.add_argument('--chip-image')
    parser.add_argument('--seed', type=lambda s: int(s, 0), default=0x603e)
    parser.add_argument('--random', type=int, default=200)
    args = parser.parse_args()
    if args.chip_image:
        use_chip_layout()
    p = build(args.seed, args.random)
    print(f'fpu_core_program: {len(p.words)} words, {len(p.expects)} expected, '
          f'{len(p.log)} exceptions, {len(p.probes)} probes')
    if args.chip_image:
        write_chip_image(p, args.chip_image)
        return
    lines = [f'P {PROT_LO:08x} {PROT_HI:08x} 0', f'D {DONE:08x} 0 0']
    lines += [f'M {a:08x} {v:08x} 0' for a, v in sorted(p.words.items())]
    lines += [f'E {a:08x} {v:08x} {m:08x}' for a, v, m in p.expects]
    lines += [f'L {pc:08x} {cycles:x} 0' for pc, cycles in p.probes.items()]
    lines += [f'{kind} {a:08x} {b:08x} {cycles:x}' for kind, a, b, cycles in p.spacings]
    Path(args.image).parent.mkdir(parents=True, exist_ok=True)
    Path(args.image).write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
