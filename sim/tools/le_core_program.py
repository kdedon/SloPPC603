#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Program image for tb_core_le: little-endian mode on ppc_core.

The program enters little-endian mode with mtmsr and rfi, loads and stores
every integer size at every byte offset across a doubleword boundary, runs
byte-reverse, update, reservation, FP, multiple and string forms, branches
and exceptions with MSR[ILE] clear and set, and returns to big-endian mode.

Expected memory follows PEM 3.1.4 independently of the RTL: a little-endian
access of n bytes at EA moves byte i at physical address (EA + i) XOR 7, as
if the bytes were accessed one at a time; instructions sit at EA XOR 4.
A misaligned little-endian access takes the alignment exception unless the
part handles it in hardware (UM 1.3: PID7v-603e); multiples and strings
always do (UM 2.3.4.3.6-7). Handlers log SRR0, SRR1, DAR, DSISR and the
vector, then resume after the faulting instruction.

--chip-image writes a self-checking byte image for tb_chip_firmware: the
program runs from the hard reset vector with both caches enabled, compares
every expected word against a table itself and reports through the mailbox.
It omits the DSI section and the MSR[ILE] section, which need a protected
region and low exception vectors.
"""
import argparse
from pathlib import Path

RESET_PC = 0x4000
LE_ENTRY, BE_ENTRY = 0x20000, 0x21000
DATA, STORE, FPDATA, RES, LOG, DONE = 0x40000, 0x44000, 0x48000, 0x50000, 0x60000, 0x70000
CHIP = False
CHIP_BASE, CHIP_IMAGE_BYTES, TABLE = 0xfff00000, 0x10000, 0xfff07000


def use_chip_layout():
    global CHIP, RESET_PC, LE_ENTRY, BE_ENTRY, DATA, STORE, FPDATA, RES, LOG, DONE
    CHIP = True
    RESET_PC, LE_ENTRY, BE_ENTRY = 0xfff02000, 0xfff06000, 0xfff06800
    DATA, STORE, FPDATA = 0xfff0c000, 0xfff0c400, 0xfff0e000
    RES, LOG, DONE = 0xfff10000, 0xfff20000, 0xfff3ff00
PROT_LO, PROT_HI = 0x7F000, 0x7F0FC
MSR_LE, MSR_ILE, MSR_IP, MSR_FP = 0x1, 0x10000, 0x40, 0x2000
SENTINEL = 0xdeadbeef
VARIANTS = {'pid7v': 0, 'pid6': 1, '603': 3, '602': 4}
VECTORS = (0x300, 0x600, 0x700, 0xc00, 0x1600)
SRR0, SRR1, DAR, DSISR, LR, CTR, XER = 26, 27, 19, 18, 8, 9, 1


def d_form(op, rt, ra, d):
    return (op << 26) | (rt << 21) | (ra << 16) | (d & 0xffff)


def x_form(op, rt, ra, rb, xo, rc=0):
    return (op << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc


def mfspr(rt, spr):
    return x_form(31, rt, spr & 31, spr >> 5, 339)


def mtspr(spr, rs):
    return x_form(31, rs, spr & 31, spr >> 5, 467)


def dsisr_d(insn):
    return (((insn >> 26) & 1) << 14) | (((insn >> 27) & 0xf) << 10) | \
        (((insn >> 21) & 31) << 5) | ((insn >> 16) & 31)


def dsisr_x(insn):
    return (((insn >> 1) & 3) << 15) | (((insn >> 6) & 1) << 14) | \
        (((insn >> 7) & 0xf) << 10) | (((insn >> 21) & 31) << 5) | ((insn >> 16) & 31)


def byterev(value, n):
    return int.from_bytes(value.to_bytes(n, 'big'), 'little')


RFI = x_form(19, 0, 0, 0, 50)
SC = (17 << 26) | 2
SYNC = x_form(31, 0, 0, 0, 598)
ISYNC = x_form(19, 0, 0, 0, 150)
BLR = x_form(19, 20, 0, 0, 16)
NOP = d_form(24, 0, 0, 0)
BDNZ_BO = 16


class Program:
    def __init__(self, variant):
        self.variant = variant
        self.init = {}      # physical byte -> initial value
        self.cur = {}       # physical byte -> value after the run
        self.checked = set()
        self.pc = RESET_PC
        self.le = False
        self.msr = MSR_IP
        self.res_next = RES
        self.log_next = LOG
        self.events = 0
        # Vector base selected by MSR[IP]; the low handlers are little-endian.
        self.handler_le = False

    # ---- memory model -------------------------------------------------
    def poke(self, addr, value):
        self.init[addr] = value
        self.cur[addr] = value

    def put32(self, addr, word):
        for i in range(4):
            self.poke(addr + i, (word >> (24 - 8 * i)) & 0xff)

    def write(self, ea, n, value, le, check=True):
        """A store of n bytes as the program sees it (PEM 3.1.4.2)."""
        for i in range(n):
            if le:
                addr, byte = (ea + i) ^ 7, (value >> (8 * i)) & 0xff
            else:
                addr, byte = ea + i, (value >> (8 * (n - 1 - i))) & 0xff
            self.cur[addr] = byte
            if check:
                self.checked.add(addr)

    def read(self, ea, n, le):
        value = 0
        for i in range(n):
            if le:
                value |= self.cur.get((ea + i) ^ 7, 0) << (8 * i)
            else:
                value = (value << 8) | self.cur.get(ea + i, 0)
        return value

    def fill(self, base, size, seed):
        for k in range(size):
            self.poke(base + k, (seed + 37 * k) & 0xff)
            self.checked.add(base + k)

    # ---- code ---------------------------------------------------------
    def emit(self, insn):
        at = self.pc
        addr = at ^ (4 if self.le else 0)
        assert addr not in self.init, f'code overlaps at {addr:#x}'
        self.put32(addr, insn & 0xffffffff)
        self.pc += 4
        return at

    def li32(self, r, value):
        self.emit(d_form(15, r, 0, value >> 16))
        self.emit(d_form(24, r, r, value & 0xffff))

    def mtmsr(self, value):
        """mtmsr refetches the next instruction in the new mode."""
        self.li32(9, value)
        # The next mode starts on a fresh doubleword.
        if self.pc % 8 == 0:
            self.emit(NOP)
        self.emit(x_form(31, 9, 0, 0, 146))
        self.msr = value
        self.le = bool(value & MSR_LE)
        self.handler_le = not (value & MSR_IP)

    def store_result(self, r, value):
        slot = self.res_next
        self.res_next += 4
        self.li32(21, slot)
        self.emit(d_form(36, r, 21, 0))
        self.write(slot, 4, value, self.le)

    def event(self, vector, srr0, dar=None, dsisr=None):
        """Logged by the handler in the mode MSR[ILE] selects."""
        assert bool(self.msr & MSR_ILE) == self.handler_le
        base = self.log_next
        self.log_next += 20
        srr1 = self.msr & 0xffff
        for off, value in ((0, srr0), (4, srr1), (8, dar), (12, dsisr), (16, vector)):
            if value is not None:
                self.write(base + off, 4, value, self.handler_le)
        self.events += 1

    def misaligned_traps(self, ea, n):
        return ea % n != 0 and self.variant != 'pid7v'


def handlers(p, base, le):
    for vector in VECTORS if not CHIP else VECTORS[:4]:
        p.pc, p.le = base | vector, le
        for spr, off in ((SRR0, 0), (SRR1, 4), (DAR, 8), (DSISR, 12)):
            p.emit(mfspr(26, spr))
            p.emit(d_form(36, 26, 29, off))
        p.emit(d_form(14, 26, 0, vector))
        p.emit(d_form(36, 26, 29, 16))
        p.emit(d_form(14, 29, 29, 20))
        if vector != 0xc00:
            # sc saves the next instruction; the others resume past the fault.
            p.emit(mfspr(26, SRR0))
            p.emit(d_form(14, 26, 26, 4))
            p.emit(mtspr(SRR0, 26))
        p.emit(RFI)


LOADS = (  # name, form, op or xo, bytes, signed, reversed
    ('lbz', 'd', 34, 1, False, False),
    ('lhz', 'd', 40, 2, False, False),
    ('lha', 'd', 42, 2, True, False),
    ('lwz', 'd', 32, 4, False, False),
    ('lbzx', 'x', 87, 1, False, False),
    ('lhbrx', 'x', 790, 2, False, True),
    ('lwbrx', 'x', 534, 4, False, True),
)
STORES = (
    ('stb', 'd', 38, 1, False),
    ('sth', 'd', 44, 2, False),
    ('stw', 'd', 36, 4, False),
    ('stwx', 'x', 151, 4, False),
    ('sthbrx', 'x', 918, 2, True),
    ('stwbrx', 'x', 662, 4, True),
)


def access(form, op, rt, ea_reg):
    if form == 'd':
        return d_form(op, rt, ea_reg, 0)
    return x_form(31, rt, 0, ea_reg, op)


def loads(p):
    base = DATA + 0x10
    for name, form, op, n, signed, rev in LOADS:
        for off in range(16):
            ea = base + off
            p.li32(5, ea)
            p.li32(10, SENTINEL)
            insn = access(form, op, 10, 5)
            at = p.emit(insn)
            if p.misaligned_traps(ea, n):
                dsisr = dsisr_d(insn) if form == 'd' else dsisr_x(insn)
                p.event(0x600, at, ea, dsisr)
                value = SENTINEL
            else:
                value = p.read(ea, n, True)
                if rev:
                    value = byterev(value, n)
                if signed and value >> (8 * n - 1):
                    value -= 1 << (8 * n)
            p.store_result(10, value & 0xffffffff)


def stores(p):
    region = STORE
    for name, form, op, n, rev in STORES:
        for off in range(16):
            p.fill(region, 32, off * 13 + n)
            ea = region + 4 + off
            p.li32(5, ea)
            p.li32(11, 0x8899aabb)
            insn = access(form, op, 11, 5)
            at = p.emit(insn)
            if p.misaligned_traps(ea, n):
                dsisr = dsisr_d(insn) if form == 'd' else dsisr_x(insn)
                p.event(0x600, at, ea, dsisr)
            else:
                value = 0x8899aabb & ((1 << (8 * n)) - 1)
                p.write(ea, n, byterev(value, n) if rev else value, True)
            region += 32


def update_forms(p):
    """lwzu and stwu update rA only when no exception is taken."""
    for off in (8, 10):
        ea = DATA + 0x30 + off
        p.li32(5, ea - 4)
        p.li32(10, SENTINEL)
        insn = d_form(33, 10, 5, 4)
        at = p.emit(insn)
        trap = p.misaligned_traps(ea, 4)
        if trap:
            p.event(0x600, at, ea, dsisr_d(insn))
        p.store_result(10, SENTINEL if trap else p.read(ea, 4, True))
        p.store_result(5, ea - 4 if trap else ea)
    p.fill(STORE + 0x1000, 16, 0x5a)
    ea = STORE + 0x1000 + 4
    p.li32(5, ea - 8)
    p.li32(11, 0x01020304)
    p.emit(d_form(37, 11, 5, 8))
    p.write(ea, 4, 0x01020304, True)
    p.store_result(5, ea)


def reservation(p):
    ea = DATA + 0x20
    p.fill(STORE + 0x1100, 16, 0x33)
    p.li32(5, ea)
    p.emit(x_form(31, 10, 0, 5, 20))                  # lwarx r10, 0, r5
    p.store_result(10, p.read(ea, 4, True))
    st = STORE + 0x1100 + 8
    p.li32(5, st)
    p.li32(11, 0xcafef00d)
    p.emit(x_form(31, 10, 0, 5, 20))                  # lwarx r10, 0, r5
    p.emit(x_form(31, 11, 0, 5, 150, 1))              # stwcx. r11, 0, r5
    p.write(st, 4, 0xcafef00d, True)
    # A misaligned lwarx traps on every part.
    p.li32(5, ea + 2)
    insn = x_form(31, 10, 0, 5, 20)
    at = p.emit(insn)
    p.event(0x600, at, ea + 2, dsisr_x(insn))


def nonscalars(p):
    """Multiples and strings take the alignment exception in little-endian
    mode (the 602 traps strings to its emulation vector first)."""
    p.li32(5, DATA)
    p.li32(30, 0x30303030)
    p.li32(31, 0x31313131)
    for insn, dar, kind in (
            (d_form(46, 30, 5, 0), DATA + 4, 'd'),              # lmw r30, 0(r5)
            (d_form(47, 30, 5, 8), DATA + 12, 'd'),             # stmw r30, 8(r5)
            (x_form(31, 10, 5, 4, 597), DATA, 'x'),             # lswi r10, r5, 4
            (x_form(31, 10, 0, 5, 533), DATA, 'x'),             # lswx (count 0)
            (x_form(31, 30, 5, 8, 725), DATA, 'x'),             # stswi r30, r5, 8
            (x_form(31, 30, 0, 5, 661), DATA, 'x')):            # stswx
        at = p.emit(insn)
        string = kind == 'x'
        if string and p.variant == '602':
            p.event(0x1600, at)
        else:
            p.event(0x600, at, dar, dsisr_d(insn) if kind == 'd' else dsisr_x(insn))
    p.store_result(30, 0x30303030)
    p.store_result(31, 0x31313131)


def floating(p):
    value = 0x400921fb54442d18
    other = 0xc01e000000000000
    single = 0x3fc00000
    for ea, v in ((FPDATA, value), (FPDATA + 0x10, other), (FPDATA + 0x24, value)):
        p.write(ea, 8, v, True, check=False)
        for i in range(8):
            p.init[(ea + i) ^ 7] = p.cur[(ea + i) ^ 7]
    p.write(FPDATA + 0x30, 4, single, True, check=False)
    for i in range(4):
        p.init[(FPDATA + 0x30 + i) ^ 7] = p.cur[(FPDATA + 0x30 + i) ^ 7]

    def store_fpr(fr, v):
        slot = (p.res_next + 7) & ~7
        p.res_next = slot + 8
        p.li32(21, slot)
        p.emit(d_form(54, fr, 21, 0))                 # stfd
        p.write(slot, 8, v, True)

    p.li32(5, FPDATA)
    p.emit(d_form(50, 1, 5, 0))                       # lfd f1, 0(r5)
    store_fpr(1, value)
    p.emit(d_form(50, 2, 5, 0x10))                    # lfd f2, 16(r5)
    # lfd at a word-aligned, doubleword-misaligned EA.
    insn = d_form(50, 2, 5, 0x24)
    at = p.emit(insn)
    trap = p.misaligned_traps(FPDATA + 0x24, 8)
    if trap:
        p.event(0x600, at, FPDATA + 0x24, dsisr_d(insn))
    store_fpr(2, other if trap else value)
    p.fill(STORE + 0x1200, 32, 0x77)
    p.li32(6, STORE + 0x1200)
    for off in (0, 12):
        insn = d_form(54, 1, 6, off)                  # stfd f1, off(r6)
        at = p.emit(insn)
        if p.misaligned_traps(STORE + 0x1200 + off, 8):
            p.event(0x600, at, STORE + 0x1200 + off, dsisr_d(insn))
        else:
            p.write(STORE + 0x1200 + off, 8, value, True)
    p.emit(d_form(48, 3, 5, 0x30))                    # lfs f3, 48(r5)
    slot = p.res_next
    p.res_next += 4
    p.li32(21, slot)
    p.emit(d_form(52, 3, 21, 0))                      # stfs f3, 0(r21)
    p.write(slot, 4, single, True)
    slot = p.res_next
    p.res_next += 4
    p.li32(21, slot)
    p.emit(x_form(31, 1, 0, 21, 983))                 # stfiwx f1, 0, r21
    p.write(slot, 4, value & 0xffffffff, True)
    # Not word-aligned: alignment on every part.
    insn = d_form(48, 3, 5, 0x32)
    at = p.emit(insn)
    p.event(0x600, at, FPDATA + 0x32, dsisr_d(insn))


def branches(p):
    p.li32(12, 0)
    skip = p.emit(0)
    sub = p.pc
    p.emit(mfspr(10, LR))
    p.emit(d_form(14, 12, 12, 1))
    p.emit(BLR)
    target = p.pc
    p.put32(skip ^ (4 if p.le else 0), (18 << 26) | ((target - skip) & 0x3fffffc))
    at = p.emit((18 << 26) | ((sub - p.pc) & 0x3fffffc) | 1)    # bl sub
    p.store_result(10, at + 4)
    # bdnz loop: three passes, independent adds that may pair.
    p.li32(13, 3)
    p.emit(mtspr(CTR, 13))
    p.li32(14, 0)
    loop = p.pc
    p.emit(d_form(14, 14, 14, 5))
    p.emit(d_form(14, 15, 0, 7))
    p.emit(d_form(14, 16, 0, 9))
    p.emit((16 << 26) | (BDNZ_BO << 21) | ((loop - p.pc) & 0xfffc))
    p.store_result(14, 15)
    p.store_result(12, 1)


def protection(p):
    """A DSI in little-endian mode reports the instruction's EA."""
    for name, insn_of, n, store in (('lhz', lambda: d_form(40, 10, 5, 0), 2, False),
                                    ('stw', lambda: d_form(36, 11, 5, 0), 4, True)):
        ea = PROT_LO + 0x10 + (6 if n == 2 else 4)
        p.li32(5, ea)
        insn = insn_of()
        at = p.emit(insn)
        p.event(0x300, at, ea, 0x0a000000 if store else 0x08000000)


def build(variant):
    p = Program(variant)
    fp = variant in ('pid7v', 'pid6', '603')
    handlers(p, 0xfff00000, False)
    if CHIP:
        p.put32(0xfff00100, (18 << 26) | ((RESET_PC - 0xfff00100) & 0x3fffffc))
    else:
        handlers(p, 0x00000000, True)
    p.fill(DATA, 0x80, 0x11)
    for k in range(0x80):
        p.checked.discard(DATA + k)
    p.pc, p.le = RESET_PC, False
    p.li32(29, LOG)
    if CHIP:
        p.emit(mfspr(7, 1008))
        p.emit(d_form(24, 7, 7, 0xc000))                  # ori r7, r7, ICE | DCE
        p.emit(SYNC)
        p.emit(mtspr(1008, 7))
        p.emit(ISYNC)
    base = MSR_IP | (MSR_FP if fp else 0)
    # mtmsr into little-endian mode.
    p.mtmsr(base | MSR_LE)
    loads(p)
    stores(p)
    update_forms(p)
    reservation(p)
    nonscalars(p)
    if fp:
        floating(p)
    branches(p)
    if not CHIP:
        protection(p)
    at = p.emit(SC)
    p.event(0xc00, at + 4)
    if not CHIP:
        ile(p, base)
    rfi_round_trip(p, base)
    if CHIP:
        self_check(p)
    else:
        p.li32(5, DONE)
        p.emit(d_form(36, 0, 5, 0))
    return p


def ile(p, base):
    """Little-endian handlers (MSR[IP] clear, MSR[ILE] set) from both modes."""
    p.mtmsr((base & ~MSR_IP) | MSR_LE | MSR_ILE)
    at = p.emit(SC)
    p.event(0xc00, at + 4)
    p.li32(5, DATA + 1)
    insn = x_form(31, 10, 0, 5, 20)                   # misaligned lwarx
    at = p.emit(insn)
    p.event(0x600, at, DATA + 1, dsisr_x(insn))
    p.mtmsr((base & ~MSR_IP) | MSR_ILE)               # big-endian, ILE set
    at = p.emit(SC)
    p.event(0xc00, at + 4)
    p.li32(5, DATA + 0x10)
    p.emit(d_form(32, 10, 5, 0))
    p.store_result(10, p.read(DATA + 0x10, 4, False))


def rfi_round_trip(p, base):
    p.mtmsr(base)
    assert p.pc < LE_ENTRY
    le_entry = LE_ENTRY
    p.li32(9, le_entry)
    p.emit(mtspr(SRR0, 9))
    p.li32(9, base | MSR_LE)
    p.emit(mtspr(SRR1, 9))
    p.emit(RFI)
    p.pc, p.le, p.msr = le_entry, True, base | MSR_LE
    p.li32(5, DATA + 0x18)
    p.emit(d_form(32, 10, 5, 0))
    p.store_result(10, p.read(DATA + 0x18, 4, True))
    be_entry = BE_ENTRY
    p.li32(9, be_entry)
    p.emit(mtspr(SRR0, 9))
    p.li32(9, base)
    p.emit(mtspr(SRR1, 9))
    p.emit(RFI)
    p.pc, p.le, p.msr = be_entry, False, base
    p.li32(5, DATA + 0x18)
    p.emit(d_form(32, 10, 5, 0))
    p.store_result(10, p.read(DATA + 0x18, 4, False))


def expected_words(p):
    for w in sorted({a & ~3 for a in p.checked}):
        value = mask = 0
        for i in range(4):
            value = (value << 8) | p.cur.get(w + i, 0)
            mask = (mask << 8) | (0xff if (w + i) in p.checked else 0)
        yield w, value & mask, mask


def self_check(p):
    """Compare every expected word from a table; the mailbox gets 1, or 2
    on a mismatch (r3 then points past the failing entry)."""
    table = list(expected_words(p))
    p.li32(3, TABLE)
    p.li32(4, len(table))
    p.li32(30, DONE)
    p.emit(mtspr(CTR, 4))
    loop = p.emit(d_form(32, 6, 3, 0))                 # lwz r6, 0(r3)
    p.emit(d_form(32, 7, 3, 4))
    p.emit(d_form(32, 8, 3, 8))
    p.emit(d_form(14, 3, 3, 12))
    p.emit(d_form(32, 5, 6, 0))
    p.emit(x_form(31, 5, 5, 8, 28))                   # and r5, r5, r8
    p.emit(x_form(31, 0, 5, 7, 0))                    # cmpw r5, r7
    p.emit((16 << 26) | (4 << 21) | (2 << 16) | 16)   # bne +16
    p.emit((16 << 26) | (BDNZ_BO << 21) | ((loop - p.pc) & 0xfffc))
    p.emit(d_form(14, 5, 0, 1))
    p.emit((18 << 26) | 8)                            # b +8
    p.emit(d_form(14, 5, 0, 2))
    p.emit(d_form(36, 5, 30, 0))
    p.emit(x_form(31, 0, 0, 30, 86))                  # dcbf 0, r30
    p.emit(SYNC)
    p.emit(18 << 26)                                  # b .
    for k, (w, value, mask) in enumerate(table):
        for i, v in enumerate((w, value, mask)):
            p.put32(TABLE + 12 * k + 4 * i, v)
    assert TABLE + 12 * len(table) <= DATA, 'table overlaps data'


def write_chip_image(p, path):
    image = bytearray(CHIP_IMAGE_BYTES)
    for addr, byte in p.init.items():
        offset = addr - CHIP_BASE
        assert 0 <= offset < CHIP_IMAGE_BYTES, hex(addr)
        image[offset] = byte
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(''.join(f'{b:02x}\n' for b in image))


def write_image(p, path):
    lines = []
    words = sorted({a & ~3 for a in p.init})
    for w in words:
        value = 0
        for i in range(4):
            value = (value << 8) | p.init.get(w + i, 0)
        lines.append(f'M {w:08x} {value:08x}')
    lines += [f'E {w:08x} {v:08x} {m:08x}' for w, v, m in expected_words(p)]
    lines += [f'D {DONE:08x}', f'P {PROT_LO:08x} {PROT_HI:08x}']
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text('\n'.join(lines) + '\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--image')
    ap.add_argument('--chip-image')
    ap.add_argument('--variant', choices=sorted(VARIANTS), default='pid7v')
    args = ap.parse_args()
    if args.chip_image:
        use_chip_layout()
    p = build(args.variant)
    if args.chip_image:
        write_chip_image(p, args.chip_image)
    else:
        write_image(p, args.image)
    print(f'le_core_program: variant={args.variant} events={p.events} '
          f'checked_bytes={len(p.checked)}')


if __name__ == '__main__':
    main()
