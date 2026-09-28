"""Load/store-extension streams: split scalars, byte-reverse, multiples,
strings and the reservation pair, all inside the 256-byte flat RAM."""
from collections import Counter

RAM = 0x1000
# Mnemonic -> (mask, value) for coverage; independent of the RTL decoder.
NEW_FORMS = {
    'lmw': (0xfc000000, 0xb8000000), 'stmw': (0xfc000000, 0xbc000000),
    'lswi': (0xfc0007ff, 0x7c0004aa), 'lswx': (0xfc0007ff, 0x7c00042a),
    'stswi': (0xfc0007ff, 0x7c0005aa), 'stswx': (0xfc0007ff, 0x7c00052a),
    'lwarx': (0xfc0007ff, 0x7c000028), 'stwcx.': (0xfc0007ff, 0x7c00012d),
    'lhbrx': (0xfc0007ff, 0x7c00062c), 'lwbrx': (0xfc0007ff, 0x7c00042c),
    'sthbrx': (0xfc0007ff, 0x7c00072c), 'stwbrx': (0xfc0007ff, 0x7c00052c),
}


def corpus():
    words = []
    groups = Counter()

    def emit(word, name):
        words.append(word & 0xffffffff)
        groups[name] += 1

    def d(op, rt, ra, imm, name):
        emit((op << 26) | (rt << 21) | (ra << 16) | (imm & 65535), name)

    def x(xo, rt, ra, rb, name, rc=0):
        emit((31 << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc, name)

    def const(reg, value):
        d(15, reg, 0, (value >> 16) & 0xffff, 'addis')
        d(24, reg, reg, value, 'ori')

    def mtxer(reg, value):
        const(reg, value)
        emit((31 << 26) | (reg << 21) | (1 << 16) | (467 << 1), 'mtxer')

    for offset in range(0, 256, 4):
        const(3, 0x81ff7e02 ^ (offset * 0x01030507))
        d(36, 3, 0, RAM + offset, 'stw')
    # Unaligned scalars: every offset class, D and indexed, update forms.
    for offset in range(1, 8):
        const(4, RAM + 0x10 + offset)
        d(32, 5, 4, 0, 'lwz'); d(40, 6, 4, 0, 'lhz'); d(42, 7, 4, 0, 'lha')
        const(8, 0x40)
        x(23, 9, 4, 8, 'lwzx'); x(343, 10, 4, 8, 'lhax')
        const(11, 0xa1b2c3d4 ^ offset)
        d(36, 11, 4, 0x20, 'stw'); d(44, 11, 4, 0x30, 'sth')
        x(151, 11, 4, 8, 'stwx')
        const(16, RAM + 0x10 + offset)
        d(33, 12, 16, 0x48, 'lwzu'); d(45, 11, 16, 0x10, 'sthu')
        x(534, 13, 4, 8, 'lwbrx'); x(790, 14, 4, 8, 'lhbrx')
        const(15, 0x90)
        x(662, 11, 4, 15, 'stwbrx'); x(918, 5, 4, 15, 'sthbrx')
    # Multiples, including a single register and an absolute rA=0 base.
    for rt in range(20, 32):
        const(rt, 0x5a000000 | rt * 0x010101)
    const(3, RAM + 0x80)
    d(47, 20, 3, 0, 'stmw'); d(47, 31, 3, 0x40, 'stmw'); d(47, 25, 0, RAM + 0xc4, 'stmw')
    for rt in range(20, 32):
        d(14, rt, 0, 0, 'addi')
    d(46, 22, 3, 4, 'lmw'); d(46, 31, 3, 0x40, 'lmw'); d(46, 29, 0, RAM + 0xc8, 'lmw')
    d(46, 4, 3, -0x40, 'lmw')
    # Strings: every tail length, unaligned EAs, wrap through r0, rA in the
    # loaded range (a valid 603e form), zero XER count.
    const(3, RAM + 0x21)
    for nb in [1, 2, 3, 4, 5, 7, 8, 9, 13, 0]:
        x(597, 24, 3, nb, 'lswi')
        const(6, RAM + 0x40 + nb)
        x(725, 24, 6, nb, 'stswi')
    x(597, 30, 3, 11, 'lswi')                      # r30, r31, r0
    const(5, RAM + 0x53); x(597, 4, 5, 8, 'lswi')  # rA = r5 is loaded
    const(7, RAM + 0x60)
    for count in [0, 1, 3, 6, 11, 16, 23]:
        mtxer(8, count)
        x(533, 29, 0, 7, 'lswx')
        const(9, 0x3)
        x(661, 29, 7, 9, 'stswx')
    mtxer(8, 0x80000000 | 9)                       # SO set, count 9
    const(10, RAM + 0x31); x(533, 10, 0, 10, 'lswx')  # rB = r10 is loaded
    # Reservation pair.
    const(12, RAM + 0xa0); const(13, 4)
    const(14, 0x11112222); const(15, 0x33334444)
    x(150, 14, 0, 12, 'stwcx.', 1)                 # no reservation
    x(20, 16, 0, 12, 'lwarx')
    x(150, 15, 0, 12, 'stwcx.', 1)                 # succeeds, copies SO
    x(150, 14, 0, 12, 'stwcx.', 1)                 # reservation gone
    x(20, 17, 12, 13, 'lwarx')
    x(20, 18, 0, 12, 'lwarx')                      # replaces reservation
    x(150, 14, 12, 13, 'stwcx.', 1)                # other address succeeds
    mtxer(8, 0)
    x(20, 19, 12, 13, 'lwarx')
    x(150, 15, 0, 12, 'stwcx.', 1)
    x(150, 15, 0, 12, 'stwcx.', 1)
    d(14, 31, 0, 123, 'addi')
    return words, dict(sorted(groups.items()))


SCALAR_D = {32: (4, 0), 33: (4, 0), 34: (1, 0), 35: (1, 0), 36: (4, 1), 37: (4, 1),
            38: (1, 1), 39: (1, 1), 40: (2, 0), 41: (2, 0), 42: (2, 0), 43: (2, 0),
            44: (2, 1), 45: (2, 1)}
SCALAR_X = {23: (4, 0), 55: (4, 0), 87: (1, 0), 119: (1, 0), 151: (4, 1), 183: (4, 1),
            215: (1, 1), 247: (1, 1), 279: (2, 0), 311: (2, 0), 343: (2, 0), 375: (2, 0),
            407: (2, 1), 439: (2, 1), 790: (2, 0), 534: (4, 0), 918: (2, 1), 662: (4, 1),
            20: (4, 0)}


def split(ea, size):
    return 1 + (((ea & 3) + size) > 4)


def accesses(rows):
    """Word requests and stores the core must issue, from pre-instruction state."""
    requests = stores = 0
    gpr, xer = [0] * 32, 0
    reserved = False
    for row in rows:
        w = row[1]
        primary, xo = w >> 26, (w >> 1) & 1023
        rt, ra, rb = (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31
        base = gpr[ra] if ra else 0
        simm = (w & 0xffff) - ((w & 0x8000) << 1)
        if primary in SCALAR_D:
            size, store = SCALAR_D[primary]
            n = split((base + simm) & 0xffffffff, size)
            requests += n; stores += n * store
        elif primary in (46, 47):
            requests += 32 - rt; stores += (32 - rt) * (primary == 47)
        elif primary == 31 and xo in SCALAR_X:
            size, store = SCALAR_X[xo]
            n = split((base + gpr[rb]) & 0xffffffff, size)
            requests += n; stores += n * store
            if xo == 20: reserved = True
        elif primary == 31 and xo == 150:
            requests += 1; stores += reserved; reserved = False
        elif primary == 31 and xo in (597, 725, 533, 661):
            count = (rb or 32) if xo in (597, 725) else xer & 127
            ea = base if xo in (597, 725) else base + gpr[rb]
            for k in range(0, count, 4):
                n = split((ea + k) & 0xffffffff, min(4, count - k))
                requests += n; stores += n * (xo in (725, 661))
        gpr, xer = list(row[2:34]), row[35]
    return requests, stores
