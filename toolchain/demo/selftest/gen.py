#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Generates the opcode self-test cases and their expected results.

gen.py <variant> <isa.json> <out-dir>

Writes cases.S (each case's code, as instruction words), cases.h (the case
table: inputs and expected outputs) and check.S (the same instructions as
assembler mnemonics, for check_enc.py). Expected results come from the model
below, written from the manuals: UM (MPC603e User's Manual), PEM
(Programming Environments Manual) and 602UM for the 602.
"""
import ast
import pathlib
import re
import sys

M32 = 0xFFFFFFFF

# ---- memory map (runner.S, selftest.ld) --------------------------------------
SCRATCH = 0xFFF3C000  # 16 KiB outside the image
BUF = SCRATCH  # 256-byte data buffer, reset from the default before each case
BUF_WORDS = 64
STUB = SCRATCH + 0x800  # self-modifying-code stub
# DBAT2: EA 0x10020000, 128 KiB, read-only alias of 0xfff20000.
RO_EA, RO_PA, BAT_BYTES = 0x10020000, 0xFFF20000, 0x20000
# IBAT2: EA 0x20020000, 128 KiB, no access (PP 00).
NX_EA = 0x20020000
DIRECT_EA = 0x30000000  # segment 3: T = 1
MISS_EA = 0x40000000  # segment 4: no BAT, empty TLB
IO_EA = 0xF0100FE0  # DBAT1: cache-inhibited register block, unused words

MSR_EE, MSR_PR, MSR_FP, MSR_ME = 0x8000, 0x4000, 0x2000, 0x1000
MSR_IP, MSR_IR, MSR_DR, MSR_TGPR = 0x40, 0x20, 0x10, 0x20000
MSR_SUP = MSR_ME | MSR_IP | MSR_IR | MSR_DR
MSR_USER = MSR_SUP | MSR_PR

# Program exception SRR1 flags (PEM Table 6-17, UM Table 4-12).
P_ILLEGAL, P_PRIV, P_TRAP = 0x00080000, 0x00040000, 0x00020000

# State fields, in struct st_state order (selftest.h).
F_CR, F_XER, F_LR, F_CTR = 32, 33, 34, 35
F_VEC, F_SRR0, F_SRR1, F_MSR, F_DAR, F_DSISR = 36, 37, 38, 39, 40, 41
F_BUF = 42
N_FIELDS = F_BUF + BUF_WORDS
FIELD_NAMES = [f"r{i}" for i in range(32)] + [
    "cr", "xer", "lr", "ctr", "vec", "srr0", "srr1", "msr", "dar", "dsisr"] + [
    f"m{4 * i:02x}" for i in range(BUF_WORDS)]
# The value is relative to the case's first instruction.
REL = 0x80

GROUPS = ["INT", "ROT", "CMP/BR", "LD/ST", "SPR", "EXC", "CACHE", "FP"]

VARIANTS = {
    # PVR version (UM 2.1.1, 602UM 2.1.1.3); the revision is not fixed.
    "603e": {"isa": "PID7v-603e", "pvr": 0x00070000, "ear": True, "multiple_dar_plus4": True},
    # The EA + 4 rule for multiples is a 603e note; not established for the 602.
    "602": {"isa": "602", "pvr": 0x00050000, "ear": False, "multiple_dar_plus4": False},
}


def s32(x):
    x &= M32
    return x - (1 << 32) if x & 0x80000000 else x


def rotl(x, n):
    n &= 31
    x &= M32
    return ((x << n) | (x >> (32 - n))) & M32 if n else x


def mask(mb, me):
    m = 0
    i = mb
    while True:
        m |= 1 << (31 - i)
        if i == me:
            break
        i = (i + 1) & 31
    return m


class Trap(Exception):
    """An exception taken by the modelled instruction."""

    def __init__(self, vec, flags=0, dar=None, dsisr=None, dsisr_mask=M32, next_pc=False,
                 target=None, srr1_mask=M32):
        super().__init__(hex(vec))
        self.vec, self.flags, self.dar, self.dsisr = vec, flags, dar, dsisr
        self.dsisr_mask, self.next_pc, self.target, self.srr1_mask = (
            dsisr_mask, next_pc, target, srr1_mask)


# ---- instructions -------------------------------------------------------------
class Insn:
    def __init__(self, word, text, m, **f):
        self.word, self.text, self.m, self.f = word & M32, text, m, f
        self.asm = None  # assembler text when the word needs a relocation

    def __getattr__(self, k):
        try:
            return self.f[k]
        except KeyError:
            raise AttributeError(k) from None


def sfx(oe, rc):
    return ("o" if oe else "") + ("." if rc else "")


def d_form(m, op, rt, ra, imm, **kw):
    w = (op << 26) | (rt << 21) | (ra << 16) | (imm & 0xFFFF)
    return Insn(w, f"{m} {rt},{ra},{s32(imm << 16) >> 16 if kw.get('signed', True) else imm & 0xffff}",
                m, rt=rt, ra=ra, imm=imm & 0xFFFF, op=op)


def d_mem(m, op, rt, d, ra):
    w = (op << 26) | (rt << 21) | (ra << 16) | (d & 0xFFFF)
    return Insn(w, f"{m} {rt},{d}({ra})", m, rt=rt, ra=ra, imm=d & 0xFFFF, op=op)


def x_form(m, xo, rt, ra, rb, rc=0, text=None):
    w = (31 << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc
    return Insn(w, text or f"{m}{'.' if rc else ''} {rt},{ra},{rb}", m, rt=rt, ra=ra, rb=rb,
                rc=rc, xo=xo, oe=0)


def xo_form(m, xo, rt, ra, rb, oe=0, rc=0):
    w = (31 << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (oe << 10) | (xo << 1) | rc
    ops = f"{rt},{ra}" + (f",{rb}" if m not in UNARY else "")
    return Insn(w, f"{m}{sfx(oe, rc)} {ops}", m, rt=rt, ra=ra, rb=rb, oe=oe, rc=rc, xo=xo)


UNARY = {"addme", "addze", "subfme", "subfze", "neg"}

XO_OPS = {"add": 266, "addc": 10, "adde": 138, "addme": 234, "addze": 202, "subf": 40,
          "subfc": 8, "subfe": 136, "subfme": 232, "subfze": 200, "neg": 104, "mullw": 235,
          "mulhw": 75, "mulhwu": 11, "divw": 491, "divwu": 459}
# Logical X-forms: rA <- f(rS, rB).
LOG_OPS = {"and": 28, "andc": 60, "or": 444, "orc": 412, "xor": 316, "nand": 476, "nor": 124,
           "eqv": 284, "slw": 24, "srw": 536, "sraw": 792}
UN_OPS = {"extsb": 954, "extsh": 922, "cntlzw": 26}


def xo(m, rt, ra, rb=0, oe=0, rc=0):
    return xo_form(m, XO_OPS[m], rt, ra, rb, oe, rc)


def logx(m, ra, rs, rb, rc=0):
    w = (31 << 26) | (rs << 21) | (ra << 16) | (rb << 11) | (LOG_OPS[m] << 1) | rc
    return Insn(w, f"{m}{'.' if rc else ''} {ra},{rs},{rb}", m, rs=rs, ra=ra, rb=rb, rc=rc, oe=0)


def unx(m, ra, rs, rc=0):
    w = (31 << 26) | (rs << 21) | (ra << 16) | (UN_OPS[m] << 1) | rc
    return Insn(w, f"{m}{'.' if rc else ''} {ra},{rs}", m, rs=rs, ra=ra, rc=rc, oe=0)


def srawi(ra, rs, sh, rc=0):
    w = (31 << 26) | (rs << 21) | (ra << 16) | (sh << 11) | (824 << 1) | rc
    return Insn(w, f"srawi{'.' if rc else ''} {ra},{rs},{sh}", "srawi", rs=rs, ra=ra, sh=sh, rc=rc,
                oe=0)


def dimm(m, op, rt, ra, imm):
    """addi-style: rT, rA, SIMM."""
    return d_form(m, op, rt, ra, imm)


def dlog(m, op, ra, rs, uimm):
    """ori-style: rA, rS, UIMM."""
    w = (op << 26) | (rs << 21) | (ra << 16) | (uimm & 0xFFFF)
    return Insn(w, f"{m} {ra},{rs},{uimm & 0xffff}", m, rs=rs, ra=ra, imm=uimm & 0xFFFF, rc=0)


def mform(m, op, rs, ra, sh_rb, mb, me, rc=0):
    w = (op << 26) | (rs << 21) | (ra << 16) | (sh_rb << 11) | (mb << 6) | (me << 1) | rc
    return Insn(w, f"{m}{'.' if rc else ''} {ra},{rs},{sh_rb},{mb},{me}", m, rs=rs, ra=ra,
                sh=sh_rb, mb=mb, me=me, rc=rc)


def cmp_(m, bf, ra, rb_imm):
    if m in ("cmp", "cmpl"):
        w = (31 << 26) | (bf << 23) | (ra << 16) | (rb_imm << 11) | ((0 if m == "cmp" else 32) << 1)
        return Insn(w, f"{m} {bf},0,{ra},{rb_imm}", m, bf=bf, ra=ra, rb=rb_imm)
    op = 11 if m == "cmpi" else 10
    w = (op << 26) | (bf << 23) | (ra << 16) | (rb_imm & 0xFFFF)
    v = s32(rb_imm << 16) >> 16 if m == "cmpi" else rb_imm & 0xFFFF
    return Insn(w, f"{m} {bf},0,{ra},{v}", m, bf=bf, ra=ra, imm=rb_imm & 0xFFFF)


CR_OPS = {"crand": 257, "crandc": 129, "creqv": 289, "crnand": 225, "crnor": 33, "cror": 449,
          "crorc": 417, "crxor": 193}


def xl(m, xo_, a, b, c, lk=0, text=None):
    w = (19 << 26) | (a << 21) | (b << 16) | (c << 11) | (xo_ << 1) | lk
    return Insn(w, text or f"{m} {a},{b},{c}", m, a=a, b=b, c=c, lk=lk)


def spr_field(spr):
    return ((spr & 0x1F) << 5) | (spr >> 5)


def mfspr(rt, spr):
    return Insn((31 << 26) | (rt << 21) | (spr_field(spr) << 11) | (339 << 1),
                f"mfspr {rt},{spr}", "mfspr", rt=rt, spr=spr)


def mtspr(spr, rs):
    return Insn((31 << 26) | (rs << 21) | (spr_field(spr) << 11) | (467 << 1),
                f"mtspr {spr},{rs}", "mtspr", rs=rs, spr=spr)


def mftb(rt, tbr):
    return Insn((31 << 26) | (rt << 21) | (spr_field(tbr) << 11) | (371 << 1),
                f"mftb {rt},{tbr}", "mftb", rt=rt, spr=tbr)


def raw(m, word, text=None, **f):
    return Insn(word, text or m, m, **f)


# Load/store opcodes: (primary, bytes, kind) or (X xo, bytes, kind).
LS_D = {"lwz": (32, 4, "l"), "lwzu": (33, 4, "lu"), "lbz": (34, 1, "l"), "lbzu": (35, 1, "lu"),
        "stw": (36, 4, "s"), "stwu": (37, 4, "su"), "stb": (38, 1, "s"), "stbu": (39, 1, "su"),
        "lhz": (40, 2, "l"), "lhzu": (41, 2, "lu"), "lha": (42, 2, "la"), "lhau": (43, 2, "lau"),
        "sth": (44, 2, "s"), "sthu": (45, 2, "su"), "lmw": (46, 4, "lm"), "stmw": (47, 4, "sm")}
LS_X = {"lwzx": (23, 4, "l"), "lwzux": (55, 4, "lu"), "lbzx": (87, 1, "l"),
        "lbzux": (119, 1, "lu"), "stwx": (151, 4, "s"), "stwux": (183, 4, "su"),
        "stbx": (215, 1, "s"), "stbux": (247, 1, "su"), "lhzx": (279, 2, "l"),
        "lhzux": (311, 2, "lu"), "lhax": (343, 2, "la"), "lhaux": (375, 2, "lau"),
        "sthx": (407, 2, "s"), "sthux": (439, 2, "su"), "lhbrx": (790, 2, "lbr"),
        "lwbrx": (534, 4, "lbr"), "sthbrx": (918, 2, "sbr"), "stwbrx": (662, 4, "sbr"),
        "lwarx": (20, 4, "larx"), "stwcx.": (150, 4, "stcx"), "lswx": (533, 0, "lsx"),
        "stswx": (661, 0, "ssx"), "eciwx": (310, 4, "eci"), "ecowx": (438, 4, "eco")}


def ldst(m, rt, d, ra):
    op, n, kind = LS_D[m]
    i = d_mem(m, op, rt, d, ra)
    i.f.update(n=n, kind=kind, xform=False)
    return i


def ldstx(m, rt, ra, rb):
    xo_, n, kind = LS_X[m]
    rc = 1 if m == "stwcx." else 0
    i = x_form(m.rstrip("."), xo_, rt, ra, rb, rc, text=f"{m} {rt},{ra},{rb}")
    i.m = m
    i.f.update(n=n, kind=kind, xform=True)
    return i


def lswi(rt, ra, nb):
    i = x_form("lswi", 597, rt, ra, nb & 31, text=f"lswi {rt},{ra},{nb}")
    i.f.update(nb=nb or 32, kind="lsi", xform=True)
    return i


def stswi(rs, ra, nb):
    i = x_form("stswi", 725, rs, ra, nb & 31, text=f"stswi {rs},{ra},{nb}")
    i.f.update(nb=nb or 32, kind="ssi", xform=True)
    return i


CACHE_OPS = {"dcbf": 86, "dcbi": 470, "dcbst": 54, "dcbt": 278, "dcbtst": 246, "dcbz": 1014,
             "icbi": 982}


def cache(m, ra, rb):
    i = x_form(m, CACHE_OPS[m], 0, ra, rb, text=f"{m} {ra},{rb}")
    i.f.update(xform=True)
    return i


def b_(off, lk=0):
    """Relative branch to byte offset off within the case (resolved later)."""
    return Insn(0, "", "b", target=off, lk=lk, aa=0)


def bc(bo, bi, off, lk=0):
    return Insn(0, "", "bc", bo=bo, bi=bi, target=off, lk=lk, aa=0)


def bclr(bo, bi, lk=0):
    i = xl("bclr", 16, bo, bi, 0, lk, text=f"bclr{'l' if lk else ''} {bo},{bi},0")
    i.f.update(bo=bo, bi=bi)
    return i


def bcctr(bo, bi, lk=0):
    i = xl("bcctr", 528, bo, bi, 0, lk, text=f"bcctr{'l' if lk else ''} {bo},{bi},0")
    i.f.update(bo=bo, bi=bi)
    return i


def tw(to, ra, rb):
    return x_form("tw", 4, to, ra, rb, text=f"tw {to},{ra},{rb}")


def twi(to, ra, simm):
    return Insn((3 << 26) | (to << 21) | (ra << 16) | (simm & 0xFFFF),
                f"twi {to},{ra},{simm}", "twi", rt=to, ra=ra, imm=simm & 0xFFFF)


SC = raw("sc", 0x44000002)
RFI = raw("rfi", 0x4C000064)
ISYNC = raw("isync", 0x4C00012C)
SYNC = raw("sync", 0x7C0004AC)
EIEIO = raw("eieio", 0x7C0006AC)
TLBSYNC = raw("tlbsync", 0x7C00046C)


def mfmsr(rt):
    return raw("mfmsr", (31 << 26) | (rt << 21) | (83 << 1), f"mfmsr {rt}", rt=rt)


def mtmsr(rs):
    return raw("mtmsr", (31 << 26) | (rs << 21) | (146 << 1), f"mtmsr {rs}", rs=rs)


def mfcr(rt):
    return raw("mfcr", (31 << 26) | (rt << 21) | (19 << 1), f"mfcr {rt}", rt=rt)


def mtcrf(fxm, rs):
    return raw("mtcrf", (31 << 26) | (rs << 21) | (fxm << 12) | (144 << 1), f"mtcrf {fxm},{rs}",
               rs=rs, fxm=fxm)


def mcrxr(bf):
    return raw("mcrxr", (31 << 26) | (bf << 23) | (512 << 1), f"mcrxr {bf}", bf=bf)


def mcrf(bf, bfa):
    return raw("mcrf", (19 << 26) | (bf << 23) | (bfa << 18), f"mcrf {bf},{bfa}", bf=bf, bfa=bfa)


def mfsr(rt, sr):
    return raw("mfsr", (31 << 26) | (rt << 21) | (sr << 16) | (595 << 1), f"mfsr {rt},{sr}",
               rt=rt, sr=sr)


def mtsr(sr, rs):
    return raw("mtsr", (31 << 26) | (rs << 21) | (sr << 16) | (210 << 1), f"mtsr {sr},{rs}",
               rs=rs, sr=sr)


def mfsrin(rt, rb):
    return raw("mfsrin", (31 << 26) | (rt << 21) | (rb << 11) | (659 << 1), f"mfsrin {rt},{rb}",
               rt=rt, rb=rb)


def mtsrin(rs, rb):
    return raw("mtsrin", (31 << 26) | (rs << 21) | (rb << 11) | (242 << 1), f"mtsrin {rs},{rb}",
               rs=rs, rb=rb)


def tlbie(rb):
    return raw("tlbie", (31 << 26) | (rb << 11) | (306 << 1), f"tlbie {rb}", rb=rb)


def tlbld(rb):
    return raw("tlbld", (31 << 26) | (rb << 11) | (978 << 1), f"tlbld {rb}", rb=rb)


def tlbli(rb):
    return raw("tlbli", (31 << 26) | (rb << 11) | (1010 << 1), f"tlbli {rb}", rb=rb)


# SPRs by number: (name, user-accessible, bits kept).
SPRS = {1: ("xer", True), 8: ("lr", True), 9: ("ctr", True), 18: ("dsisr", False),
        19: ("dar", False), 26: ("srr0", False), 27: ("srr1", False), 272: ("sprg0", False),
        273: ("sprg1", False), 274: ("sprg2", False), 275: ("sprg3", False),
        282: ("ear", False), 287: ("pvr", False)}


# ---- model --------------------------------------------------------------------
class Machine:
    def __init__(self, variant):
        self.v = VARIANTS[variant]
        self.variant = variant

    # -- helpers
    def so(self, st):
        return (st["xer"] >> 31) & 1

    def cr0(self, st, val):
        v = s32(val)
        c = 8 if v < 0 else 4 if v > 0 else 2
        self.setcrf(st, 0, c | self.so(st))

    def setcrf(self, st, bf, v4):
        sh = 28 - 4 * bf
        st["cr"] = (st["cr"] & ~(0xF << sh) & M32) | ((v4 & 0xF) << sh)

    def crbit(self, st, i):
        return (st["cr"] >> (31 - i)) & 1

    def setcrbit(self, st, i, b):
        st["cr"] = (st["cr"] & ~(1 << (31 - i)) & M32) | (b << (31 - i))

    def ov(self, st, ov):
        x = st["xer"] & ~0x40000000 & M32
        if ov:
            x |= 0xC0000000
        st["xer"] = x

    def ca(self, st, c):
        st["xer"] = (st["xer"] & ~0x20000000 & M32) | (0x20000000 if c else 0)

    def carry(self, st):
        return (st["xer"] >> 29) & 1

    def ra0(self, st, ra):
        return 0 if ra == 0 else st["gpr"][ra]

    # -- translation (the BATs and segments runner.S and selftest.c set up)
    def xlate_data(self, st, ea, store, ins, n):
        ea &= M32
        if ea - RO_EA < BAT_BYTES and st["msr"] & MSR_DR:
            if store:
                raise Trap(0x300, dar=ea, dsisr=0x0A000000)
            return RO_PA + (ea - RO_EA)
        if ea >> 28 == DIRECT_EA >> 28 and st["msr"] & MSR_DR:
            raise Trap(0x300, dar=ea, dsisr=0x04000000 | (0x02000000 if store else 0))
        if ea >> 28 == MISS_EA >> 28 and st["msr"] & MSR_DR:
            raise Trap(0x1200 if store else 0x1100)
        return ea

    def mem_ok(self, pa, n):
        if not (BUF <= pa and pa + n <= BUF + BUF_WORDS * 4):
            raise RuntimeError(f"model access outside the buffer: {pa:08x}")

    def load(self, st, ea, n, ins):
        pa = self.xlate_data(st, ea, False, ins, n)
        self.mem_ok(pa, n)
        v = 0
        for k in range(n):
            v = (v << 8) | st["mem"][pa - BUF + k]
        return v

    def store(self, st, ea, n, v, ins):
        pa = self.xlate_data(st, ea, True, ins, n)
        if 0 <= pa - STUB < 8:
            return  # the icbi stub: its effect is modelled by the case
        self.mem_ok(pa, n)
        for k in range(n):
            st["mem"][pa - BUF + k] = (v >> (8 * (n - 1 - k))) & 0xFF

    def align_trap(self, ea, ins):
        """Alignment exception DAR/DSISR (UM Table 4-13, PEM Table 6-12)."""
        w = ins.word
        if ins.f.get("xform"):
            ds = (((w >> 1) & 3) << 15) | (((w >> 6) & 1) << 14) | (((w >> 7) & 0xF) << 10)
        else:
            ds = (((w >> 26) & 1) << 14) | (((w >> 27) & 0xF) << 10)
        ds |= ((w >> 21) & 0x1F) << 5
        ds |= (w >> 16) & 0x1F
        # DSISR[27-31] (rA) is defined only for update forms (PEM Table 6-12),
        # DSISR[22-26] not for dcbz (UM Table 4-13).
        m = M32 if ins.m.endswith(("u", "ux")) else M32 & ~0x1F
        if ins.m == "dcbz":
            m &= ~0x3E0
        # A misaligned lmw or stmw puts EA + 4 in DAR (UM 4.5.6.2).
        if ins.m in ("lmw", "stmw") and self.v["multiple_dar_plus4"]:
            ea += 4
        return Trap(0x600, dar=ea & M32, dsisr=ds, dsisr_mask=m)

    def cross_page(self, st, ea, n):
        return st["msr"] & MSR_DR and (ea & 0xFFF) + n > 0x1000

    # -- execution
    def legal(self, st, ins):
        """Illegal, privileged and FP-unavailable checks, in that order."""
        isa = self.v["isa"]
        status = ins.f.get("status", {}).get(isa, "legal")
        if ins.m in ("eciwx", "ecowx") and not self.v["ear"]:
            status = "illegal"
        if ins.m in ("mfspr", "mtspr") and ins.spr == 282 and not self.v["ear"]:
            status = "illegal"
        if status == "illegal":
            raise Trap(0x700, P_ILLEGAL)
        # SPR numbers with bit 4 set are privileged (PEM 3.3.13).
        priv = ins.f.get("priv", False) or (ins.m in ("mfspr", "mtspr") and ins.spr & 0x10)
        if priv and st["msr"] & MSR_PR:
            raise Trap(0x700, P_PRIV)
        if ins.f.get("fp") and not st["msr"] & MSR_FP:
            raise Trap(0x800)
        if status == "emulation_trap":
            raise Trap(0x1600)

    def step(self, st, ins, pc):
        if ins.m == "external":
            ins.f["sem"](st)
            return None
        self.legal(st, ins)
        g = st["gpr"]
        m = ins.m
        if m in XO_OPS:
            return self.xo_op(st, ins)
        if m in LOG_OPS:
            a, b = g[ins.rs], g[ins.rb]
            if m in ("slw", "srw", "sraw"):
                n = b & 0x3F
                if m == "slw":
                    r = 0 if n > 31 else (a << n) & M32
                elif m == "srw":
                    r = 0 if n > 31 else a >> n
                else:
                    r = (s32(a) >> min(n, 32)) & M32
                    out = a & ((1 << min(n, 32)) - 1)
                    self.ca(st, s32(a) < 0 and out != 0)
            else:
                r = {"and": a & b, "andc": a & ~b, "or": a | b, "orc": a | ~b, "xor": a ^ b,
                     "nand": ~(a & b), "nor": ~(a | b), "eqv": ~(a ^ b)}[m] & M32
            g[ins.ra] = r
            if ins.rc:
                self.cr0(st, r)
            return None
        if m in UN_OPS:
            a = g[ins.rs]
            if m == "extsb":
                r = (s32(a << 24) >> 24) & M32
            elif m == "extsh":
                r = (s32(a << 16) >> 16) & M32
            else:
                r = 32 - a.bit_length()
            g[ins.ra] = r
            if ins.rc:
                self.cr0(st, r)
            return None
        if m == "srawi":
            a, n = g[ins.rs], ins.sh
            r = (s32(a) >> n) & M32
            self.ca(st, s32(a) < 0 and (a & ((1 << n) - 1)) != 0)
            g[ins.ra] = r
            if ins.rc:
                self.cr0(st, r)
            return None
        if m in ("addi", "addis"):
            imm = s32(ins.imm << 16) >> 16
            g[ins.rt] = (self.ra0(st, ins.ra) + (imm << 16 if m == "addis" else imm)) & M32
            return None
        if m in ("addic", "addic.", "subfic"):
            imm = (s32(ins.imm << 16) >> 16) & M32
            a = g[ins.ra]
            t = (~a & M32) + imm + 1 if m == "subfic" else a + imm
            g[ins.rt] = t & M32
            self.ca(st, t >> 32)
            if m == "addic.":
                self.cr0(st, t)
            return None
        if m == "mulli":
            g[ins.rt] = (s32(g[ins.ra]) * (s32(ins.imm << 16) >> 16)) & M32
            return None
        if m in ("andi.", "andis.", "ori", "oris", "xori", "xoris"):
            u = ins.imm << 16 if m.endswith(("is", "is.")) else ins.imm
            a = g[ins.rs]
            r = (a & u) if m.startswith("and") else (a | u) if m.startswith("or") else (a ^ u)
            g[ins.ra] = r & M32
            if m.startswith("and"):
                self.cr0(st, r)
            return None
        if m in ("rlwinm", "rlwnm", "rlwimi"):
            n = ins.sh if m != "rlwnm" else g[ins.sh] & 31
            r = rotl(g[ins.rs], n)
            mk = mask(ins.mb, ins.me)
            r = (r & mk) | (g[ins.ra] & ~mk & M32) if m == "rlwimi" else r & mk
            g[ins.ra] = r
            if ins.rc:
                self.cr0(st, r)
            return None
        if m in ("cmp", "cmpi", "cmpl", "cmpli"):
            a = g[ins.ra]
            if m == "cmp":
                x, y = s32(a), s32(g[ins.rb])
            elif m == "cmpl":
                x, y = a, g[ins.rb]
            elif m == "cmpi":
                x, y = s32(a), s32(ins.imm << 16) >> 16
            else:
                x, y = a, ins.imm
            c = 8 if x < y else 4 if x > y else 2
            self.setcrf(st, ins.bf, c | self.so(st))
            return None
        if m in CR_OPS:
            a, b = self.crbit(st, ins.b), self.crbit(st, ins.c)
            r = {"crand": a & b, "crandc": a & (1 - b), "creqv": 1 - (a ^ b),
                 "crnand": 1 - (a & b), "crnor": 1 - (a | b), "cror": a | b,
                 "crorc": a | (1 - b), "crxor": a ^ b}[m]
            self.setcrbit(st, ins.a, r)
            return None
        if m == "mcrf":
            self.setcrf(st, ins.bf, (st["cr"] >> (28 - 4 * ins.bfa)) & 0xF)
            return None
        if m == "mcrxr":
            self.setcrf(st, ins.bf, st["xer"] >> 28)
            st["xer"] &= 0x0FFFFFFF
            return None
        if m == "mfcr":
            g[ins.rt] = st["cr"]
            return None
        if m == "mtcrf":
            mk = 0
            for i in range(8):
                if ins.fxm & (0x80 >> i):
                    mk |= 0xF << (28 - 4 * i)
            st["cr"] = (g[ins.rs] & mk) | (st["cr"] & ~mk & M32)
            return None
        if m in ("b", "bc", "bclr", "bcctr"):
            return self.branch(st, ins, pc)
        if m in ("mfspr", "mtspr"):
            return self.spr(st, ins)
        if m == "mftb":
            g[ins.rt] = None  # time base: not predicted
            return None
        if m == "mfmsr":
            g[ins.rt] = st["msr"]
            return None
        if m == "mtmsr":
            st["msr"] = g[ins.rs] & 0x0007FF73
            return None
        if m in ("mfsr", "mfsrin"):
            g[ins.rt] = st["sr"][ins.sr if m == "mfsr" else g[ins.rb] >> 28]
            return None
        if m in ("mtsr", "mtsrin"):
            st["sr"][ins.sr if m == "mtsr" else g[ins.rb] >> 28] = g[ins.rs]
            return None
        if m in ("sync", "isync", "eieio", "tlbsync", "tlbie", "dcbt", "dcbtst"):
            return None
        if m == "sc":
            raise Trap(0xC00, next_pc=True)
        if m == "rfi":
            st["msr"] = st["srr1"] & 0x0007FF73
            t = st["srr0"]
            return t[1] & ~3 if isinstance(t, tuple) else ("abs", t & ~3 & M32)
        if m in ("tw", "twi"):
            a = g[ins.ra]
            b = g[ins.rb] if m == "tw" else (s32(ins.imm << 16) >> 16) & M32
            to = ins.rt
            t = ((to & 16 and s32(a) < s32(b)) or (to & 8 and s32(a) > s32(b)) or
                 (to & 4 and a == b) or (to & 2 and a < b) or (to & 1 and a > b))
            if t:
                raise Trap(0x700, P_TRAP)
            return None
        if m in CACHE_OPS:
            return self.cache_op(st, ins)
        if "kind" in ins.f:
            return self.mem_op(st, ins)
        raise RuntimeError(f"no model for {m}")

    def xo_op(self, st, ins):
        g = st["gpr"]
        m, a, b = ins.m, g[ins.ra], g[ins.rb]
        ca = self.carry(st)
        ov = None
        if m in ("add", "addc", "adde", "addme", "addze"):
            y = {"add": b, "addc": b, "adde": b, "addme": M32, "addze": 0}[m]
            cin = {"add": 0, "addc": 0}.get(m, ca)
            t = a + y + cin
            r = t & M32
            ov = s32(a) + s32(y) + cin != s32(r)
            if m != "add":
                self.ca(st, t >> 32)
        elif m in ("subf", "subfc", "subfe", "subfme", "subfze", "neg"):
            na = ~a & M32
            y = {"subf": b, "subfc": b, "subfe": b, "subfme": M32, "subfze": 0, "neg": 0}[m]
            cin = {"subf": 1, "subfc": 1, "neg": 1}.get(m, ca)
            t = na + y + cin
            r = t & M32
            ov = s32(na) + s32(y) + cin != s32(r)
            if m not in ("subf", "neg"):
                self.ca(st, t >> 32)
        elif m == "mullw":
            p = s32(a) * s32(b)
            r = p & M32
            ov = p != s32(r)
        elif m == "mulhw":
            r = ((s32(a) * s32(b)) >> 32) & M32
        elif m == "mulhwu":
            r = ((a * b) >> 32) & M32
        elif m == "divw":
            if b == 0 or (a == 0x80000000 and b == M32):
                r, ov = None, True
            else:
                q = abs(s32(a)) // abs(s32(b))
                r = (q if (s32(a) < 0) == (s32(b) < 0) else -q) & M32
                ov = False
        elif m == "divwu":
            if b == 0:
                r, ov = None, True
            else:
                r, ov = a // b, False
        if ins.oe:
            self.ov(st, ov)
        g[ins.rt] = r
        if ins.rc:
            if r is None:
                # LT, GT and EQ undefined (PEM divw/divwu); SO defined.
                self.setcrf(st, 0, self.so(st))
                st.setdefault("dontcare", {})["cr"] = 0x0FFFFFFF | 0x10000000
            else:
                self.cr0(st, r)
        return None

    def branch(self, st, ins, pc):
        m = ins.m
        if m == "b":
            tgt = ins.target
            if ins.lk:
                st["lr"] = ("rel", pc + 4)
            return tgt if not isinstance(tgt, tuple) else tgt
        bo, bi = ins.bo, ins.bi
        if not bo & 4:
            if m == "bcctr":
                raise RuntimeError("bcctr with decrement is an invalid form")
            st["ctr"] = self.relsub(st["ctr"], 1)
        ctr_ok = bo & 4 or ((self.relval(st["ctr"]) != 0) ^ bool(bo & 2))
        cond_ok = bo & 16 or self.crbit(st, bi) == ((bo >> 3) & 1)
        take = ctr_ok and cond_ok
        if m == "bc":
            tgt = ins.target
        elif m == "bclr":
            tgt = st["lr"]
        else:
            tgt = st["ctr"]
        if ins.lk:
            st["lr"] = ("rel", pc + 4)
        if not take:
            return None
        if m == "bc":
            return tgt
        if isinstance(tgt, tuple):
            return tgt[1] & ~3 if tgt[0] == "rel" else tgt
        return ("abs", tgt & ~3)

    def relval(self, v):
        if isinstance(v, tuple):
            raise RuntimeError("CTR compare with a relative value")
        return v

    def relsub(self, v, n):
        return (v - n) & M32

    def spr(self, st, ins):
        g = st["gpr"]
        name = SPRS.get(ins.spr, (None,))[0]
        if name is None:
            raise Trap(0x700, P_ILLEGAL)
        if ins.m == "mfspr":
            if name == "pvr":
                g[ins.rt] = ("mask", self.v["pvr"], 0xFFFF0000)
            elif name.startswith("sprg"):
                g[ins.rt] = st["sprg"][int(name[4])]
            elif name == "ear":
                g[ins.rt] = st["ear"]
            else:
                g[ins.rt] = st[name]
        else:
            v = g[ins.rs]
            if name == "pvr":
                raise Trap(0x700, P_ILLEGAL)
            if name.startswith("sprg"):
                st["sprg"][int(name[4])] = v
            elif name == "ear":
                st["ear"] = v & 0x8000003F
            elif name == "xer":
                st["xer"] = v & 0xE000007F
            else:
                st[name] = v
        return None

    def mem_op(self, st, ins):
        g = st["gpr"]
        kind = ins.kind
        if ins.f.get("xform"):
            ea = (self.ra0(st, ins.ra) + (0 if kind in ("lsi", "ssi") else g[ins.rb])) & M32
        else:
            ea = (self.ra0(st, ins.ra) + (s32(ins.imm << 16) >> 16)) & M32
        n = ins.f.get("n", 0)
        if kind in ("lm", "sm", "larx", "stcx", "eci", "eco") and ea & 3:
            raise self.align_trap(ea, ins)
        if kind in ("l", "lu", "la", "lau", "s", "su", "lbr", "sbr") and n > 1 and \
                self.cross_page(st, ea, n):
            raise self.align_trap(ea, ins)
        if kind in ("l", "lu", "la", "lau", "lbr", "larx"):
            v = self.load(st, ea, n, ins)
            if kind == "lbr":
                v = int.from_bytes(v.to_bytes(n, "big"), "little")
            if kind in ("la", "lau"):
                v = (s32(v << 16) >> 16) & M32
            if kind == "larx":
                st["resv"] = ea
            g[ins.rt] = v
            if kind in ("lu", "lau"):
                g[ins.ra] = ea
        elif kind in ("s", "su", "sbr"):
            v = g[ins.rt] & ((1 << (8 * n)) - 1)
            if kind == "sbr":
                v = int.from_bytes(v.to_bytes(n, "big"), "little")
            self.store(st, ea, n, v, ins)
            if kind == "su":
                g[ins.ra] = ea
        elif kind == "stcx":
            ok = st.get("resv") is not None
            if ok:
                self.store(st, ea, 4, g[ins.rt], ins)
            st["resv"] = None
            self.setcrf(st, 0, (2 if ok else 0) | self.so(st))
        elif kind == "lm":
            for r in range(ins.rt, 32):
                g[r] = self.load(st, ea + 4 * (r - ins.rt), 4, ins)
        elif kind == "sm":
            for r in range(ins.rt, 32):
                self.store(st, ea + 4 * (r - ins.rt), 4, g[r], ins)
        elif kind in ("lsi", "lsx"):
            nb = ins.nb if kind == "lsi" else st["xer"] & 0x7F
            r = ins.rt - 1
            for k in range(nb):
                if k % 4 == 0:
                    r = (r + 1) & 31
                    g[r] = 0
                g[r] |= self.load(st, ea + k, 1, ins) << (24 - 8 * (k % 4))
        elif kind in ("ssi", "ssx"):
            nb = ins.nb if kind == "ssi" else st["xer"] & 0x7F
            r = ins.rt - 1
            for k in range(nb):
                if k % 4 == 0:
                    r = (r + 1) & 31
                self.store(st, ea + k, 1, (g[r] >> (24 - 8 * (k % 4))) & 0xFF, ins)
        elif kind in ("eci", "eco"):
            if not st["ear"] & 0x80000000:
                raise Trap(0x300, dar=ea, dsisr=0x00100000 | (0x02000000 if kind == "eco" else 0))
            raise RuntimeError("enabled external control transfer is not modelled")
        else:
            raise RuntimeError(kind)
        return None

    def cache_op(self, st, ins):
        g = st["gpr"]
        ea = (self.ra0(st, ins.ra) + g[ins.rb]) & M32
        m = ins.m
        blk = ea & ~31 & M32
        if m == "dcbz":
            # A write-through or cache-inhibited block takes the alignment
            # exception (UM Table 4-13).
            if ea >> 28 == 0xF and ea - 0xF0000000 < 0x400000 and st["msr"] & MSR_DR:
                raise self.align_trap(ea, ins)
            pa = self.xlate_data(st, ea, True, ins, 32)
            self.mem_ok(pa & ~31, 32)
            for k in range(32):
                st["mem"][(pa & ~31) - BUF + k] = 0
        elif m in ("dcbf", "dcbst"):
            pa = self.xlate_data(st, ea, False, ins, 32)
            if not BUF <= pa < BUF + BUF_WORDS * 4:
                return None
            st.setdefault("backing", {})[pa & ~31] = bytes(
                st["mem"][(pa & ~31) - BUF:(pa & ~31) - BUF + 32])
        elif m == "dcbi":
            pa = self.xlate_data(st, ea, True, ins, 32)
            back = st.get("backing", {}).get(pa & ~31)
            if back is None:
                raise RuntimeError("dcbi of a block with unknown memory contents")
            st["mem"][(pa & ~31) - BUF:(pa & ~31) - BUF + 32] = back
        elif m == "icbi":
            st["icbi"] = blk
        return None


# ---- cases --------------------------------------------------------------------
def default_state():
    g = [((0x11 * i) << 24 | (i << 16) | (0xC0DE ^ (i * 0x0101))) & M32 for i in range(32)]
    g[0] = 0x0BADF00D
    mem = bytearray(((i * 29 + 0x5B) ^ (i >> 3)) & 0xFF for i in range(BUF_WORDS * 4))
    return {"gpr": g, "cr": 0, "xer": 0, "lr": 0, "ctr": 0, "msr": MSR_SUP, "srr0": 0,
            "srr1": 0, "dar": 0, "dsisr": 0, "sprg": [0, 0, 0, 0],
            "sr": [0x80000000 if i == 3 else 0 for i in range(16)], "ear": 0, "mem": mem}


def flatten(st):
    """State dict to a list of N_FIELDS (value, mask, rel)."""
    out = []

    def put(v, mk=M32):
        if v is None:
            out.append((0, 0, 0))
        elif isinstance(v, tuple) and v[0] == "rel":
            out.append((v[1] & M32, mk, 1))
        elif isinstance(v, tuple) and v[0] == "mask":
            out.append((v[1] & v[2], v[2], 0))
        elif isinstance(v, tuple) and v[0] == "abs":
            out.append((v[1] & M32, mk, 0))
        else:
            out.append((v & M32, mk, 0))
    for r in st["gpr"]:
        put(r)
    dc = st.get("dontcare", {})
    for k in ("cr", "xer", "lr", "ctr", "vec", "srr0", "srr1", "msr", "dar", "dsisr"):
        put(st.get(k, 0), dc.get(k, M32))
    mem = st["mem"]
    for i in range(BUF_WORDS):
        put(int.from_bytes(mem[4 * i:4 * i + 4], "big"))
    return out


class Case:
    def __init__(self, group, name, code, inp=None, msr=MSR_SUP, need=None, note=""):
        self.group, self.name, self.code = group, name, code
        self.inp = inp or {}
        self.msr, self.need, self.note = msr, need, note


def lookup_status(isa, ins):
    """Variant status from the ISA matrix, by decode mask and value."""
    for e in isa:
        if ins.word & int(e["mask"], 16) == int(e["value"], 16):
            return e
    return None


class Builder:
    def __init__(self, variant, isa):
        self.variant, self.isa = variant, isa
        self.cases = []

    def add(self, group, name, code, **kw):
        if not isinstance(code, list):
            code = [code]
        self.cases.append(Case(group, name, code, **kw))


# Operand values: edges and a few irregular words.
EDGE = [0, 1, M32, 0x7FFFFFFF, 0x80000000, 0x12345678, 0xFEDCBA98, 0x0000FFFF]
PAIRS = [(0x12345678, 0x0FEDCBA9), (0x7FFFFFFF, 1), (0x80000000, M32), (M32, M32),
         (0, 0), (0x80000000, 0x80000000), (0xFFFF0000, 0x00010000), (5, 0xFFFFFFFB)]


def build_int(B):
    G = "INT"
    for m in ["add", "addc", "adde", "subf", "subfc", "subfe", "mullw", "divw", "divwu"]:
        for oe in (0, 1):
            for rc in (0, 1):
                for k, (a, b) in enumerate(PAIRS[:4] if oe or rc else PAIRS[:6]):
                    xer = 0x20000000 if k % 2 else 0
                    if m.startswith("div") and k == 3:
                        b = 0  # divide by zero: result undefined, OV set
                    B.add(G, f"{m}{sfx(oe, rc)}", xo(m, 5, 3, 4, oe, rc),
                          inp={"r3": a, "r4": b, "xer": xer | (0x80000000 if k == 2 else 0)})
    for m in ["mulhw", "mulhwu"]:
        for rc in (0, 1):
            for a, b in PAIRS[:5]:
                B.add(G, f"{m}{sfx(0, rc)}", xo(m, 5, 3, 4, 0, rc), inp={"r3": a, "r4": b})
    for m in ["addme", "addze", "subfme", "subfze", "neg"]:
        for oe in (0, 1):
            for rc in (0, 1):
                for k, a in enumerate([0, M32, 0x7FFFFFFF, 0x80000000]):
                    B.add(G, f"{m}{sfx(oe, rc)}", xo(m, 5, 3, 0, oe, rc),
                          inp={"r3": a, "xer": 0x20000000 if k % 2 == 0 else 0})
    for a in [0, M32, 0x7FFF]:
        for imm in [1, -1, 0x7FFF, -0x8000]:
            B.add(G, "addi", dimm("addi", 14, 5, 3, imm), inp={"r3": a})
            B.add(G, "addis", dimm("addis", 15, 5, 3, imm), inp={"r3": a})
    B.add(G, "addi r0", dimm("addi", 14, 5, 0, 0x123))
    B.add(G, "addis r0", dimm("addis", 15, 5, 0, -2))
    for m, op in [("addic", 12), ("addic.", 13), ("subfic", 8), ("mulli", 7)]:
        for a in [0, 1, M32, 0x80000000, 0x7FFFFFFF]:
            for imm in [1, -1, 0x1234]:
                B.add(G, m, dimm(m, op, 5, 3, imm), inp={"r3": a, "xer": 0x80000000})
    for m in ["and", "andc", "or", "orc", "xor", "nand", "nor", "eqv"]:
        for rc in (0, 1):
            for a, b in [(0x12345678, 0xF0F0F0F0), (0, 0), (M32, 0x80000000)]:
                B.add(G, f"{m}{sfx(0, rc)}", logx(m, 5, 3, 4, rc), inp={"r3": a, "r4": b})
    for m, op in [("andi.", 28), ("andis.", 29), ("ori", 24), ("oris", 25), ("xori", 26),
                  ("xoris", 27)]:
        for a in [0x12345678, 0, 0x8000FFFF]:
            B.add(G, m, dlog(m, op, 5, 3, 0x8421), inp={"r3": a, "xer": 0x80000000})
    for m in ["extsb", "extsh", "cntlzw"]:
        for rc in (0, 1):
            for a in [0, 0x80, 0x7F7F, 0x8000, 0x00010000, M32, 1]:
                B.add(G, f"{m}{sfx(0, rc)}", unx(m, 5, 3, rc), inp={"r3": a})


def build_rot(B):
    G = "ROT"
    vals = [0x12345678, 0x80000001, M32, 0]
    for rc in (0, 1):
        for sh, mb, me in [(0, 0, 31), (4, 0, 27), (31, 31, 31), (8, 24, 7), (16, 16, 31)]:
            for a in vals[:3]:
                B.add(G, f"rlwinm{sfx(0, rc)}", mform("rlwinm", 21, 3, 5, sh, mb, me, rc),
                      inp={"r3": a})
                B.add(G, f"rlwimi{sfx(0, rc)}", mform("rlwimi", 20, 3, 5, sh, mb, me, rc),
                      inp={"r3": a, "r5": 0xCAFEBABE})
        for n, mb, me in [(3, 0, 31), (35, 4, 27), (0xFFFFFFE0, 28, 3)]:
            B.add(G, f"rlwnm{sfx(0, rc)}", mform("rlwnm", 23, 3, 5, 4, mb, me, rc),
                  inp={"r3": 0x12345678, "r4": n})
        for m in ["slw", "srw", "sraw"]:
            for a in [0x12345678, 0x80000001, M32]:
                for n in [0, 1, 31, 32, 63, 0xFFFFFF04]:
                    if n in (63,) and a != 0x80000001:
                        continue
                    B.add(G, f"{m}{sfx(0, rc)}", logx(m, 5, 3, 4, rc),
                          inp={"r3": a, "r4": n, "xer": 0x20000000})
        for a in [0x12345678, 0x80000001, M32, 0xFFFFFFF0]:
            for sh in [0, 1, 4, 31]:
                B.add(G, f"srawi{sfx(0, rc)}", srawi(5, 3, sh, rc), inp={"r3": a, "xer": 0x20000000})


def build_cmp_br(B):
    G = "CMP/BR"
    for m in ["cmp", "cmpl"]:
        for bf in (0, 3, 7):
            for a, b in [(1, 2), (M32, 1), (5, 5), (0x80000000, 0x7FFFFFFF)]:
                B.add(G, m, cmp_(m, bf, 3, 4), inp={"r3": a, "r4": b, "xer": 0x80000000 if bf == 7 else 0})
    for m in ["cmpi", "cmpli"]:
        for bf in (0, 5):
            for a, imm in [(1, 2), (M32, 0xFFFF), (5, 5), (0x8000, 0x8000)]:
                B.add(G, m, cmp_(m, bf, 3, imm), inp={"r3": a})
    for m in CR_OPS:
        for cr in [0x9A3C5F00, 0x5A5A5A5A]:
            B.add(G, m, xl(m, CR_OPS[m], 5, 2, 30), inp={"cr": cr})
            B.add(G, m, xl(m, CR_OPS[m], 31, 7, 7), inp={"cr": cr ^ 0xFFFFFFFF})
    B.add(G, "mcrf", mcrf(6, 1), inp={"cr": 0x0A000000})
    B.add(G, "mcrf", mcrf(0, 7), inp={"cr": 0x5000000F})
    B.add(G, "mcrxr", mcrxr(2), inp={"xer": 0xE000007F, "cr": 0x12345678})
    B.add(G, "mfcr", mfcr(5), inp={"cr": 0x89ABCDEF})
    for fxm in (0xFF, 0x81, 0x10, 0x00):
        B.add(G, "mtcrf", mtcrf(fxm, 3), inp={"r3": 0x13579BDF, "cr": 0x2468ACE0})
    # Unconditional, relative and absolute.
    skip = dimm("addi", 14, 3, 3, 1)
    B.add(G, "b", [b_(8), skip, dimm("addi", 14, 4, 4, 2)])
    B.add(G, "bl", [b_(8, lk=1), skip, dimm("addi", 14, 4, 4, 2)])
    B.add(G, "b back", [b_(12), dimm("addi", 14, 4, 4, 2), b_(16), b_(4)])
    abs_ = Insn(0, "", "babs", lk=0)
    B.add(G, "ba", [abs_])
    B.add(G, "bla", [Insn(0, "", "babs", lk=1)])
    # bc: every BO class.
    for bo, bi, cr, ctr in [(12, 2, 0x20000000, 0), (12, 2, 0, 0), (4, 0, 0x80000000, 0),
                            (4, 0, 0, 0), (16, 0, 0, 2), (16, 0, 0, 1), (18, 0, 0, 1),
                            (18, 0, 0, 5), (8, 1, 0x40000000, 3), (8, 1, 0x40000000, 1),
                            (0, 3, 0, 3), (10, 3, 0x10000000, 1), (2, 3, 0, 1), (20, 0, 0, 0)]:
        for lk in (0, 1):
            B.add(G, "bcl" if lk else "bc", [bc(bo, bi, 8, lk), skip, dimm("addi", 14, 4, 4, 2)],
                  inp={"cr": cr, "ctr": ctr})
    B.add(G, "bdnz loop", [dimm("addi", 14, 3, 3, 3), bc(16, 0, 0)], inp={"ctr": 5, "r3": 0})
    # bclr / bcctr to a label two instructions on.
    for bo, bi, cr in [(20, 0, 0), (12, 2, 0x20000000), (12, 2, 0), (4, 6, 0)]:
        for lk in (0, 1):
            B.add(G, "bclrl" if lk else "bclr", [bclr(bo, bi, lk), skip, dimm("addi", 14, 4, 4, 2)],
                  inp={"cr": cr, "lr": ("rel", 8)})
            B.add(G, "bcctrl" if lk else "bcctr", [bcctr(bo, bi, lk), skip,
                  dimm("addi", 14, 4, 4, 2)], inp={"cr": cr, "ctr": ("rel", 8)})
    B.add(G, "bdnzlr", [bclr(16, 0), skip, dimm("addi", 14, 4, 4, 2)],
          inp={"ctr": 2, "lr": ("rel", 8)})
    B.add(G, "bdzlr", [bclr(18, 0), skip, dimm("addi", 14, 4, 4, 2)],
          inp={"ctr": 1, "lr": ("rel", 8)})
    B.add(G, "blrl lr", [bclr(20, 0, 1), skip], inp={"lr": ("rel", 4)})


def build_ldst(B):
    G = "LD/ST"
    base = BUF + 0x40
    for m in ["lwz", "lbz", "lhz", "lha", "lwzu", "lbzu", "lhzu", "lhau"]:
        for d in [0, 6, -0x10]:
            B.add(G, m, ldst(m, 5, d, 3), inp={"r3": base})
    for m in ["stw", "stb", "sth", "stwu", "stbu", "sthu"]:
        for d in [0, 6, -0x10]:
            B.add(G, m, ldst(m, 5, d, 3), inp={"r3": base, "r5": 0x8899AABB})
    for m in ["lwzx", "lbzx", "lhzx", "lhax", "lwzux", "lbzux", "lhzux", "lhaux", "lhbrx",
              "lwbrx"]:
        for off in [4, 0x22]:
            B.add(G, m, ldstx(m, 5, 3, 4), inp={"r3": base, "r4": off})
    for m in ["stwx", "stbx", "sthx", "stwux", "stbux", "sthux", "sthbrx", "stwbrx"]:
        for off in [8, 0x2A]:
            B.add(G, m, ldstx(m, 5, 3, 4), inp={"r3": base, "r4": off, "r5": 0x8899AABB})
    B.add(G, "lwzx r0", ldstx("lwzx", 5, 0, 4), inp={"r4": BUF + 0x10})
    # Unaligned scalars inside a page: split by the processor (UM 4.5.6.1).
    for m, d in [("lwz", 1), ("lwz", 2), ("lwz", 3), ("lhz", 1), ("lha", 3), ("stw", 1),
                 ("stw", 3), ("sth", 5)]:
        B.add(G, f"{m} +{d}", ldst(m, 5, d, 3), inp={"r3": base, "r5": 0x8899AABB})
    B.add(G, "lmw", ldst("lmw", 20, 0, 3), inp={"r3": BUF + 0x20})
    B.add(G, "lmw", ldst("lmw", 28, 4, 3), inp={"r3": BUF + 0x20})
    # rA outside the loaded range (PEM lmw: invalid form otherwise).
    B.add(G, "lmw r3", ldst("lmw", 3, 0x10, 2), inp={"r2": BUF})
    for rs in (25, 30):
        B.add(G, "stmw", ldst("stmw", rs, 8, 3), inp={"r3": BUF + 0x20})
    for nb in (1, 4, 7, 0):
        B.add(G, "lswi", lswi(5, 3, nb), inp={"r3": BUF + 0x13})
    for cnt in (0, 3, 9):
        B.add(G, "lswx", ldstx("lswx", 5, 3, 4), inp={"r3": BUF + 0x10, "r4": 1, "xer": cnt})
    for nb in (1, 6, 8):
        B.add(G, "stswi", stswi(5, 3, nb), inp={"r3": BUF + 0x31, "r5": 0x11223344,
                                                  "r6": 0x55667788})
    for cnt in (0, 5):
        B.add(G, "stswx", ldstx("stswx", 5, 3, 4), inp={"r3": BUF + 0x30, "r4": 2, "xer": cnt,
                                                        "r5": 0xA1B2C3D4, "r6": 0xE5F60718})
    B.add(G, "lwarx", ldstx("lwarx", 5, 3, 4), inp={"r3": BUF, "r4": 0x18})
    B.add(G, "stwcx. ok", [ldstx("lwarx", 5, 3, 4), ldstx("stwcx.", 6, 3, 4)],
          inp={"r3": BUF, "r4": 0x18, "r6": 0x600DF00D})
    B.add(G, "stwcx. so", [ldstx("lwarx", 5, 3, 4), ldstx("stwcx.", 6, 3, 4)],
          inp={"r3": BUF, "r4": 0x18, "r6": 0x600DF00D, "xer": 0x80000000})
    B.add(G, "stwcx. fail", [ldstx("lwarx", 5, 3, 4), ldstx("stwcx.", 6, 3, 4),
                              ldstx("stwcx.", 7, 3, 4)],
          inp={"r3": BUF, "r4": 0x18, "r6": 0x600DF00D, "r7": 0xBAD0BAD0})


def build_spr(B):
    G = "SPR"
    for n in range(4):
        B.add(G, f"sprg{n}", [mtspr(272 + n, 3), mfspr(5, 272 + n)], inp={"r3": 0x5A5A0000 + n})
    for spr, v in [(26, 0x12345678), (27, 0x0000FF73), (19, 0xDEADBEE0), (18, 0x42000000)]:
        B.add(G, f"mt/mf {SPRS[spr][0]}", [mtspr(spr, 3), mfspr(5, spr)], inp={"r3": v})
    B.add(G, "mfspr xer", mfspr(5, 1), inp={"xer": 0xA000001F})
    B.add(G, "mtspr xer", mtspr(1, 3), inp={"r3": 0x6000007F})
    B.add(G, "mtlr/mflr", [mtspr(8, 3), mfspr(5, 8)], inp={"r3": 0x0000ABCC})
    B.add(G, "mtctr/mfctr", [mtspr(9, 3), mfspr(5, 9)], inp={"r3": 0xFFFF0001})
    B.add(G, "mfxer user", mfspr(5, 1), inp={"xer": 0x20000005}, msr=MSR_USER)
    B.add(G, "mfpvr", mfspr(5, 287))
    if VARIANTS[B.variant]["ear"]:
        # EAR is not reset between cases: leave E clear. With E set, the demo
        # SoC would take eciwx/ecowx tenures (TT3 = 0) as address-only.
        B.add(G, "mt/mf ear", [mtspr(282, 3), mfspr(5, 282), mtspr(282, 6)],
              inp={"r3": 0x80000005, "r6": 0})
    B.add(G, "mfmsr", mfmsr(5))
    B.add(G, "mtmsr pr", [mtmsr(3), dimm("addi", 14, 4, 4, 1)], inp={"r3": MSR_USER})
    B.add(G, "mtmsr dr", [mtmsr(3), dimm("addi", 14, 4, 4, 1), mtmsr(6)],
          inp={"r3": MSR_SUP & ~MSR_DR, "r6": MSR_SUP})
    B.add(G, "mtmsr ir", [mtmsr(3), ISYNC, dimm("addi", 14, 4, 4, 1), mtmsr(6), ISYNC],
          inp={"r3": MSR_SUP & ~MSR_IR, "r6": MSR_SUP})
    for sr in (5, 9, 15):
        B.add(G, "mtsr/mfsr", [mtsr(sr, 3), mfsr(5, sr)], inp={"r3": 0x00ABCDE0 | sr})
    B.add(G, "mtsrin/mfsrin", [mtsrin(3, 4), mfsrin(5, 4), mfsr(6, 6)],
          inp={"r3": 0x60123456, "r4": 0x6FFF0000})
    B.add(G, "rfi", [mtspr(26, 3), mtspr(27, 4), RFI, dimm("addi", 14, 5, 5, 1),
                     dimm("addi", 14, 6, 6, 1)], inp={"r3": ("rel", 16), "r4": MSR_SUP})
    B.add(G, "rfi to user", [mtspr(26, 3), mtspr(27, 4), RFI, dimm("addi", 14, 5, 5, 1),
                             dimm("addi", 14, 6, 6, 1)], inp={"r3": ("rel", 16), "r4": MSR_USER})
    B.add(G, "sync", [SYNC, dimm("addi", 14, 5, 3, 1)])
    B.add(G, "isync", [ISYNC, dimm("addi", 14, 5, 3, 1)])
    B.add(G, "eieio", [EIEIO, dimm("addi", 14, 5, 3, 1)])
    B.add(G, "sync user", SYNC, msr=MSR_USER)
    B.add(G, "mftb", [mftb(5, 268), mftb(6, 269)])
    B.add(G, "mftb user", [mftb(5, 268), mftb(6, 269)], msr=MSR_USER)


def build_exc(B):
    G = "EXC"
    for to, a, b in [(4, 5, 5), (4, 5, 6), (16, M32, 0), (8, M32, 0), (2, M32, 0), (1, M32, 0),
                     (31, 1, 1), (0, 1, 1)]:
        B.add(G, "tw", tw(to, 3, 4), inp={"r3": a, "r4": b})
    for to, a, imm in [(4, 7, 7), (24, 7, 7), (1, 1, -1), (2, 1, -1)]:
        B.add(G, "twi", twi(to, 3, imm), inp={"r3": a})
    B.add(G, "trap user", tw(31, 3, 3), msr=MSR_USER)
    B.add(G, "sc", [SC, dimm("addi", 14, 5, 5, 1)])
    B.add(G, "sc user", [SC], msr=MSR_USER)
    ill = {VARIANTS[B.variant]["isa"]: "illegal"}
    for w in [0x00000000, 0x04000000, 0x7C000002, 0x7C0007FE, 0x10000000, 0xE4000000]:
        assert lookup_status(B.isa, raw("", w)) is None, hex(w)
        B.add(G, "illegal", raw(".long", w, f".long 0x{w:08x}", status=ill))
    B.add(G, "illegal user", raw(".long", 0, ".long 0x00000000", status=ill), msr=MSR_USER)
    B.add(G, "tlbia", raw("tlbia", 0x7C0002E4, "tlbia", status={"PID7v-603e": "illegal",
                                                                "602": "illegal"}))
    B.add(G, "mfspr 0", mfspr(5, 0))
    B.add(G, "mfspr 0 user", mfspr(5, 0), msr=MSR_USER)
    for name, ins in [("mfmsr", mfmsr(5)), ("mtmsr", mtmsr(3)), ("rfi", RFI),
                      ("mfsr", mfsr(5, 1)), ("mtsr", mtsr(1, 3)), ("mfsrin", mfsrin(5, 4)),
                      ("mtsrin", mtsrin(3, 4)), ("mfsprg0", mfspr(5, 272)),
                      ("mtsrr0", mtspr(26, 3)), ("mfdar", mfspr(5, 19)), ("mfpvr", mfspr(5, 287)),
                      ("mtdec", mtspr(22, 3)), ("mttbl", mtspr(284, 3)), ("mfsdr1", mfspr(5, 25)),
                      ("mfhid0", mfspr(5, 1008)), ("mtibat0u", mtspr(528, 3)),
                      ("tlbie", tlbie(4)), ("tlbsync", TLBSYNC), ("tlbld", tlbld(4)),
                      ("tlbli", tlbli(4)), ("dcbi", cache("dcbi", 0, 4))]:
        ins.f["priv"] = True
        B.add(G, f"{name} user", ins, msr=MSR_USER, inp={"r4": BUF})
    # Alignment (UM Table 4-13).
    B.add(G, "lmw align", ldst("lmw", 28, 2, 3), inp={"r3": BUF})
    B.add(G, "stmw align", ldst("stmw", 28, 1, 3), inp={"r3": BUF})
    B.add(G, "lwarx align", ldstx("lwarx", 5, 3, 4), inp={"r3": BUF, "r4": 2})
    B.add(G, "stwcx. align", ldstx("stwcx.", 5, 3, 4), inp={"r3": BUF, "r4": 6})
    B.add(G, "lwz page", ldst("lwz", 5, 0xFFE, 3), inp={"r3": BUF})
    B.add(G, "lwzu page", ldst("lwzu", 5, 0xFFD, 3), inp={"r3": BUF})
    B.add(G, "sthx page", ldstx("sthx", 5, 3, 4), inp={"r3": BUF, "r4": 0xFFF})
    B.add(G, "dcbz inhib", cache("dcbz", 3, 4), inp={"r3": IO_EA, "r4": 4})
    # DSI: store through the read-only BAT alias; a load through it succeeds.
    B.add(G, "dsi store", ldst("stw", 5, 0x10, 3), inp={"r3": RO_EA + (BUF - RO_PA)})
    B.add(G, "dsi stb", ldst("stbu", 5, 3, 3), inp={"r3": RO_EA + (BUF - RO_PA)})
    B.add(G, "ro load", ldst("lwz", 5, 0x10, 3), inp={"r3": RO_EA + (BUF - RO_PA)})
    B.add(G, "dsi dcbz", cache("dcbz", 3, 4), inp={"r3": RO_EA + (BUF - RO_PA), "r4": 0x40})
    B.add(G, "dsi t=1 ld", ldst("lwz", 5, 8, 3), inp={"r3": DIRECT_EA})
    B.add(G, "dsi t=1 st", ldst("stw", 5, 8, 3), inp={"r3": DIRECT_EA})
    if VARIANTS[B.variant]["ear"]:
        B.add(G, "eciwx E=0", ldstx("eciwx", 5, 3, 4), inp={"r3": BUF, "r4": 8})
        B.add(G, "ecowx E=0", ldstx("ecowx", 5, 3, 4), inp={"r3": BUF, "r4": 8})
    else:
        B.add(G, "eciwx", ldstx("eciwx", 5, 3, 4), inp={"r3": BUF, "r4": 8})
        B.add(G, "ecowx", ldstx("ecowx", 5, 3, 4), inp={"r3": BUF, "r4": 8})
    # ISI: fetch through the no-access BAT alias.
    B.add(G, "isi bat", [bcctr(20, 0)], inp={"ctr": NX_EA + 0x100})
    B.add(G, "isi bat user", [bcctr(20, 0)], inp={"ctr": NX_EA + 0x100}, msr=MSR_USER)
    # TLB misses (UM 4.5.14-16): no BAT and an empty TLB.
    B.add(G, "itlb miss", [bcctr(20, 0)], inp={"ctr": MISS_EA + 0x40, "cr": 0x50000000})
    B.add(G, "dtlb miss ld", ldst("lwz", 5, 0x20, 3), inp={"r3": MISS_EA, "cr": 0xA0000000})
    B.add(G, "dtlb miss st", ldst("stw", 5, 0x20, 3), inp={"r3": MISS_EA})
    B.add(G, "dtlb miss user", ldst("lbz", 5, 0x21, 3), inp={"r3": MISS_EA}, msr=MSR_USER)


def build_cache(B):
    G = "CACHE"
    B.add(G, "dcbz", cache("dcbz", 3, 4), inp={"r3": BUF + 0x40, "r4": 5})
    B.add(G, "dcbz r0", cache("dcbz", 0, 4), inp={"r4": BUF + 0xA0})
    B.add(G, "dcbz user", cache("dcbz", 3, 4), inp={"r3": BUF, "r4": 0x80}, msr=MSR_USER)
    for m in ["dcbf", "dcbst", "dcbt", "dcbtst"]:
        B.add(G, m, [ldst("stw", 5, 0x14, 3), cache(m, 3, 4), ldst("lwz", 6, 0x14, 3)],
              inp={"r3": BUF, "r4": 0x14, "r5": 0x31415926})
        B.add(G, f"{m} user", [ldst("stw", 5, 0x14, 3), cache(m, 3, 4), ldst("lwz", 6, 0x14, 3)],
              inp={"r3": BUF, "r4": 0x14, "r5": 0x27182818}, msr=MSR_USER)
    # dcbi discards the modified block: the flushed value comes back.
    B.add(G, "dcbi", [cache("dcbf", 3, 4), ldst("stw", 5, 0x24, 3), cache("dcbi", 3, 4),
                      ldst("lwz", 6, 0x24, 3)], inp={"r3": BUF, "r4": 0x20, "r5": 0xD15CA4D0})
    # icbi: rewrite a stub and run it (PEM 5.1.5.2 sequence).
    for k, v in [(0, 5), (1, 9)]:
        insn = 0x38630000 | v  # addi r3,r3,v
        code = [ldst("stw", 4, 0, 5), ldst("stw", 6, 4, 5), cache("dcbst", 0, 5), SYNC,
                cache("icbi", 0, 5), ISYNC, mtspr(9, 5), bcctr(20, 0, 1)]
        stub = Insn(0, "", "external", sem=lambda st, v=v: st["gpr"].__setitem__(
            3, (st["gpr"][3] + v) & M32))
        B.add(G, f"icbi {k}", code, inp={"r3": 100, "r4": insn, "r5": STUB, "r6": 0x4E800020},
              need=("stub", stub))
    B.add(G, "tlbie", [tlbie(4), SYNC, TLBSYNC, SYNC, ldst("lwz", 5, 0, 3)],
          inp={"r3": BUF, "r4": 0x12345000})
    B.add(G, "tlbsync", [TLBSYNC, dimm("addi", 14, 5, 3, 1)])


FP_ONE = {"fres", "frsqrte", "frsp", "fctiw", "fctiwz", "fneg", "fmr", "fnabs", "fabs",
          "fsqrt", "fsqrts"}
FP_FMA = {"fmadd", "fmsub", "fnmadd", "fnmsub", "fmadds", "fmsubs", "fnmadds", "fnmsubs",
          "fsel"}


def fp_word(m, value):
    """Operand fields for each FP form: frD 1, frA 2, frB 4, frC 5; rA 3, rB 4."""
    base = m.rstrip(".")
    w = value
    if base.startswith(("lf", "stf")):
        return w | (1 << 21) | (3 << 16) | (8 if (w >> 26) != 31 else 4 << 11)
    if base in FP_ONE:
        return w | (1 << 21) | (4 << 11)
    if base in FP_FMA:
        return w | (1 << 21) | (2 << 16) | (4 << 11) | (5 << 6)
    if base in ("fmul", "fmuls"):
        return w | (1 << 21) | (2 << 16) | (5 << 6)
    if base in ("fcmpu", "fcmpo"):
        return w | (1 << 23) | (2 << 16) | (4 << 11)
    if base in ("mffs", "mtfsb0", "mtfsb1"):
        return w | (1 << 21)
    if base == "mcrfs":
        return w | (1 << 23) | (2 << 18)
    if base == "mtfsfi":
        return w | (1 << 23) | (6 << 12)
    if base == "mtfsf":
        return w | (0x0F << 17) | (4 << 11)
    return w | (1 << 21) | (2 << 16) | (4 << 11)


def fp_text(m, w):
    t, a, b, c = (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31, (w >> 6) & 31
    base = m.rstrip(".")
    if base.startswith(("lf", "stf")):
        return f"{m} {t},{a},{b}" if (w >> 26) == 31 else f"{m} {t},{w & 0xffff}({a})"
    if base in FP_ONE:
        return f"{m} {t},{b}"
    if base in FP_FMA:
        return f"{m} {t},{a},{c},{b}"
    if base in ("fmul", "fmuls"):
        return f"{m} {t},{a},{c}"
    if base in ("fcmpu", "fcmpo"):
        return f"{m} {t >> 2},{a},{b}"
    if base in ("mffs", "mtfsb0", "mtfsb1"):
        return f"{m} {t}"
    if base == "mcrfs":
        return f"{m} {t >> 2},{a >> 2}"
    if base == "mtfsfi":
        return f"{m} {t >> 2},{(w >> 12) & 15}"
    if base == "mtfsf":
        return f"{m} {(w >> 17) & 0xff},{b}"
    return f"{m} {t},{a},{b}"


def fp_insns(isa):
    out = [(e["mnemonic"], fp_word(e["mnemonic"], int(e["value"], 16)), e["variants"])
           for e in isa if e["unit"] == "FPU"]
    # Optional in the 603e and absent from the 602: illegal (UM Table B-1).
    ill = {"PID7v-603e": "illegal", "602": "illegal"}
    out += [(m, fp_word(m, v), ill) for m, v in (("fsqrt", 0xFC00002C), ("fsqrts", 0xEC00002C))]
    return out


def build_fp(B, isa):
    """Without an FPU every FP instruction takes FP unavailable (UM 4.5.8)."""
    G = "FP"
    isa_name = VARIANTS[B.variant]["isa"]
    for m, w, var in fp_insns(isa):
        st = {isa_name: "illegal" if var.get(isa_name) == "illegal" else "legal"}
        B.add(G, m, raw(m, w, fp_text(m, w), status=st, fp=True), inp={"r3": BUF})
        if m in ("fadd", "fmr", "lfd", "mffs"):
            B.add(G, f"{m} user", raw(m, w, fp_text(m, w), status=st, fp=True),
                  inp={"r3": BUF}, msr=MSR_USER)
    for m, v in [("fadd.", 0xFC00002B), ("fmr.", 0xFC000091)]:
        w = fp_word(m, v)
        B.add(G, m, raw(m, w, fp_text(m, w), fp=True), inp={"r3": BUF})
    # Hook: with an FPU (ST_HAVE_FPU), cases with MSR[FP] set and computed
    # results belong here.


# ---- evaluation and output ----------------------------------------------------
def reg_index(k):
    return {"cr": F_CR, "xer": F_XER, "lr": F_LR, "ctr": F_CTR, "dar": F_DAR,
            "dsisr": F_DSISR}.get(k, None) if not k.startswith("r") else int(k[1:])


def evaluate(machine, case, isa):
    st = default_state()
    for k, v in case.inp.items():
        if k.startswith("r"):
            st["gpr"][int(k[1:])] = v
        else:
            st[k] = v
    for ins in case.code:
        if ins.m not in ("b", "bc", "babs", "external"):
            e = lookup_status(isa, ins)
            if e and "status" not in ins.f:
                ins.f["status"] = e["variants"]
            if e and e.get("privilege") == "supervisor":
                ins.f["priv"] = True
    inp = flatten(st)
    inp[F_MSR] = (case.msr, M32, 0)
    msr0 = case.msr
    code = list(case.code)
    # Absolute branches go to a fixed routine that adds 1 to r3.
    babs = [i for i in code if i.m == "babs"]
    if babs:
        ins = babs[0]
        ins.m = "b"
        ins.f["target"] = ("abs", "st_abs")
        ins.asm = f"b{'l' if ins.lk else ''}a st_abs"
    trap, pc = run_case(machine, st, code, msr0, case)
    exp_msr = st["msr"]
    if trap:
        srr1 = (exp_msr & 0xFFFF) | trap.flags
        st["vec"] = trap.vec
        if trap.vec in (0x1000, 0x1100, 0x1200):
            # SRR1: CR0, key, I/D, way (not predicted), store (UM Table 4-4).
            key = 0
            srr1 = (st["cr"] & 0xF0000000) | (exp_msr & 0xFFFF) | (key << 19) | (
                0x40000 if trap.vec == 0x1000 else 0) | (0x10000 if trap.vec == 0x1200 else 0)
            trap.srr1_mask = M32 & ~0x20000
        elif trap.vec == 0x400:
            srr1 |= 0x08000000
        st["srr1"] = srr1
        st.setdefault("dontcare", {})["srr1"] = trap.srr1_mask
        if trap.target is not None:
            st["srr0"] = trap.target
        elif isinstance(pc, tuple):
            st["srr0"] = pc
        else:
            st["srr0"] = ("rel", pc + (4 if trap.next_pc else 0))
        if trap.dar is not None:
            st["dar"] = trap.dar
            st["dsisr"] = trap.dsisr
            st["dontcare"]["dsisr"] = trap.dsisr_mask
        st["msr"] = (exp_msr & (MSR_ME | MSR_IP)) | (
            MSR_TGPR if trap.vec in (0x1000, 0x1100, 0x1200) else 0)
    else:
        # The runner reports no SRR0/SRR1 for a completed case.
        st["vec"] = st["srr0"] = st["srr1"] = 0
    out = flatten(st)
    out[F_MSR] = (st["msr"] & M32, M32, 0)
    return inp, out


def run_case(machine, st, code, msr, case):
    """Runs the case, following absolute targets: st_abs and the stub."""
    st["msr"] = msr
    pc = 0
    for _ in range(400):
        if isinstance(pc, tuple):
            where = pc[1]
            if where == "st_abs":
                st["gpr"][3] = (st["gpr"][3] + 1) & M32
                return None, None
            if where == STUB:
                stub = case.need[1]
                stub.f["sem"](st)
                pc = st["lr"][1] & ~3 if isinstance(st["lr"], tuple) else None
                if pc is None:
                    raise RuntimeError("stub return")
                continue
            if 0 <= where - NX_EA < BAT_BYTES:
                return Trap(0x400, target=("abs", where)), pc
            if where >> 28 == MISS_EA >> 28:
                return Trap(0x1000, target=("abs", where)), pc
            if where >> 28 == 0xF and where >= SCRATCH:
                raise RuntimeError(f"branch to {where:08x}")
            raise RuntimeError(f"branch to {where:08x}")
        if pc == len(code) * 4:
            return None, None
        ins = code[pc // 4]
        try:
            nxt = machine.step(st, ins, pc)
        except Trap as t:
            return t, pc
        if isinstance(nxt, tuple) and nxt[0] == "abs":
            v = nxt[1]
            pc = ("abs", v) if isinstance(v, str) else ("abs", v & M32)
            # A relative value that came through LR/CTR.
            continue
        pc = pc + 4 if nxt is None else nxt
    raise RuntimeError(f"{case.name}: case does not end")


def resolve(case):
    """Fills in branch words; returns the words and the check-file lines."""
    words, lines = [], []
    for i, ins in enumerate(case.code):
        here = 4 * i
        if ins.m == "b" and ins.asm:
            words.append(None)
            lines.append(ins.asm)
            continue
        if ins.m == "b":
            d = ins.target - here
            ins.word = (18 << 26) | (d & 0x03FFFFFC) | ins.lk
            ins.text = f"b{'l' if ins.lk else ''} .{'+' if d >= 0 else ''}{d}"
        elif ins.m == "bc":
            d = ins.target - here
            ins.word = (16 << 26) | (ins.bo << 21) | (ins.bi << 16) | (d & 0xFFFC) | ins.lk
            ins.text = f"bc{'l' if ins.lk else ''} {ins.bo},{ins.bi},.{'+' if d >= 0 else ''}{d}"
        words.append(ins.word)
        lines.append(ins.text)
    return words, lines


def c_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def load_json(path):
    """JSON as a Python literal (the build container has no json module)."""
    text = re.sub(r"\b(true|false|null)\b",
                  lambda m: {"true": "True", "false": "False", "null": "None"}[m.group(1)],
                  pathlib.Path(path).read_text())
    return ast.literal_eval(text)


def main():
    variant, isa_path, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    isa = load_json(isa_path)["decode_entries"]
    B = Builder(variant, isa)
    build_int(B)
    build_rot(B)
    build_cmp_br(B)
    build_ldst(B)
    build_spr(B)
    build_exc(B)
    build_cache(B)
    build_fp(B, isa)
    machine = Machine(variant)
    base = default_state()
    base_flat = flatten(base)

    asm = ["/* Generated by gen.py: the self-test cases. */",
           '    .section .text.st_cases,"ax",@progbits', "    .align 2"]
    chk = ["/* Generated by gen.py: the case instructions as mnemonics. */", "    .text"]
    kv, cases_c, meta = [], [], []
    for n, case in enumerate(B.cases):
        inp, outp = evaluate(machine, case, isa)
        words, lines = resolve(case)
        asm.append(f"    .globl st_case_{n}\nst_case_{n}:")
        for w, t in zip(words, lines):
            asm.append(f"    {t}" if w is None else f"    .long 0x{w:08x}  /* {t} */")
            if w is not None:
                chk.append(f"    {t}")
            else:
                chk.append("    nop")
        asm.append("    b st_done")
        # Inputs: the fields that differ from the default state.
        in_first = len(kv)
        for f in range(N_FIELDS):
            if inp[f] != base_flat[f] or f == F_MSR:
                kv.append((f | (REL if inp[f][2] else 0), inp[f][0], M32))
        in_n = len(kv) - in_first
        # Expected: the fields that differ from the inputs, or are masked.
        ex_first = len(kv)
        for f in range(N_FIELDS):
            if outp[f] != (inp[f][0], M32, inp[f][2]) or f in (F_VEC,):
                if f == F_VEC and outp[f][0] == 0:
                    continue
                kv.append((f | (REL if outp[f][2] else 0), outp[f][0], outp[f][1]))
        ex_n = len(kv) - ex_first
        meta.append((in_first, in_n, ex_first, ex_n))
        text = "; ".join(t for t in lines)
        g = GROUPS.index(case.group)
        cases_c.append(f"  {{{c_str(case.name[:12])}, {c_str(text[:60])}, st_case_{n}, {g}, "
                       f"{len(words)}, {in_first}, {in_n}, {ex_first}, {ex_n}}},")
    (out / "cases.S").write_text("\n".join(asm) + "\n    .section .note.GNU-stack,\"\",@progbits\n")
    (out / "check.S").write_text("\n".join(chk) + "\n")
    hdr = [f"/* Generated by gen.py for the {variant}. */",
           f"#define ST_VARIANT {c_str(variant)}",
           f"#define ST_NCASES {len(B.cases)}",
           f"#define ST_HAVE_EAR {int(VARIANTS[variant]['ear'])}",
           f"#define ST_NGROUPS {len(GROUPS)}",
           "static const char *const st_group_name[] = {" +
           ", ".join(c_str(g) for g in GROUPS) + "};",
           "static const char *const st_field_name[] = {" +
           ", ".join(c_str(f) for f in FIELD_NAMES) + "};",
           "static const uint32_t st_default[ST_NFIELDS] = {"]
    hdr += [f"  0x{v[0]:08x}," for v in base_flat]
    hdr.append("};")
    hdr += [f"void st_case_{n}(void);" for n in range(len(B.cases))]
    hdr.append("static const struct st_kv st_kv[] = {")
    hdr += [f"  {{0x{f:02x}, 0x{v:08x}, 0x{m:08x}}}," for f, v, m in kv]
    hdr.append("};")
    hdr.append("static const struct st_case st_cases[ST_NCASES] = {")
    hdr += cases_c
    hdr.append("};")
    (out / "cases.h").write_text("\n".join(hdr) + "\n")
    if len(sys.argv) > 4:
        # Debug: the inputs and expected values of the named case numbers.
        for n in map(int, sys.argv[4:]):
            i0, i_n, e0, e_n = meta[n]
            print(cases_c[n])
            for f, v, m in kv[int(i0):int(i0) + int(i_n)]:
                print(f"  in  {FIELD_NAMES[f & 0x7f]:6} {v:08x}{' rel' if f & REL else ''}")
            for f, v, m in kv[int(e0):int(e0) + int(e_n)]:
                print(f"  exp {FIELD_NAMES[f & 0x7f]:6} {v:08x} mask {m:08x}"
                      f"{' rel' if f & REL else ''}")
    counts = {g: sum(1 for c in B.cases if c.group == g) for g in GROUPS}
    print(f"{variant}: {len(B.cases)} cases " + " ".join(f"{g} {n}" for g, n in counts.items()))


if __name__ == "__main__":
    main()
