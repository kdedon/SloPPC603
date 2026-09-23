"""Independent interval/arithmetic oracle for the selected-bank BAT contract."""
import argparse
from pathlib import Path


def expected(controls, ea, pairs):
    valid, instruction, write, ir, dr, user = [(controls >> n) & 1 for n in range(5, -1, -1)]
    if not valid:
        return 0
    entries = []
    bad = 0
    for index, (upper, lower) in enumerate(pairs):
        enabled = upper % 4
        length = (upper // 4) % 2048
        size = 131072 * (length + 1)
        base = (upper // 131072) * 131072
        physical = (lower // 131072) * 131072
        legal = (length + 1) & length == 0
        reserved = (upper // 8192) % 16 or (lower // 128) % 1024 or (lower // 4) % 2
        malformed = bool(enabled and (not legal or reserved or base % size or physical % size or
                                      (instruction and (lower // 64) % 2)))
        if malformed:
            bad |= 1 << index
        entries.append((enabled, base, base + size, physical, malformed, (lower // 8) % 16, lower % 4))
    overlap = any(a[0] & b[0] and not a[4] and not b[4] and max(a[1], b[1]) < min(a[2], b[2])
                  for i, a in enumerate(entries) for b in entries[i+1:])
    invalid = bool(instruction and write)
    if bad or overlap or invalid:
        return (1 << 50) | (int(invalid) << 49) | (int(overlap) << 48) | (bad << 44)
    if not (ir if instruction else dr):
        return (1 << 56) | (1 << 55) | (ea << 6) | ((1 if instruction else 3) << 2)
    matches = [(i, e) for i, e in enumerate(entries) if e[0] & (1 if user else 2) and e[1] <= ea < e[2]]
    if not matches:
        return 1 << 53
    assert len(matches) == 1
    index, entry = matches[0]
    _, base, _, physical, _, wimg, pp = entry
    denied = pp == 0 or (write and pp != 2)
    guarded = bool(instruction and wimg % 2)
    allow = not denied and not guarded
    pa = physical + (ea - base) if allow else 0
    return ((int(allow) << 56) | (1 << 54) | (int(denied) << 52) | (int(guarded) << 51) |
            (1 << (40 + index)) | (index << 38) | (pa << 6) | (wimg << 2) | pp)


def vectors():
    for power in range(12):
        size = 131072 * 2**power
        for way in range(4):
            for instruction in range(2):
                for user in range(2):
                    for pp in range(4):
                        for flags in range(4):
                            for write in range(2):
                                # Deliberately dirty inactive entries must be ignored.
                                pairs = [(0xfffffffc, 0xffffffff)] * 4
                                wimg = [0, 2, 4, 1][pp] if instruction else (pp + flags * 3) % 16
                                pairs[way] = (0x40000000 + (2**power-1)*4 + flags,
                                              0x80000000 + wimg*8 + pp)
                                for offset in [-1, 0, 1, size//2, size-1, size, size+1]:
                                    ea = 0x40000000 + offset
                                    controls = 32 + instruction*16 + write*8 + 4 + 2 + user
                                    yield controls, ea, pairs
    # Independent bypass enables and all WIMG values, including the narrower
    # IBAT W rejection and 603e guarded instruction fault.
    for instruction in range(2):
        for enables in range(4):
            for wimg in range(16):
                for flags in range(4):
                    pairs = [(0x20000000+flags, 0x60000000+wimg*8+2), (0, 0), (0, 0), (0, 0)]
                    yield 32+instruction*16+enables*2, 0x20012345, pairs
    # Invalid BL, each reserved bit, alignment, overlap, and privilege-disjoint
    # same-address entries. Configuration diagnostics apply even on bypass.
    base = [(0x20000003, 0x60000002), (0, 0), (0, 0), (0, 0)]
    malformed = []
    for bit in range(13, 17):
        malformed.append([(base[0][0] | 1 << bit, base[0][1]), *base[1:]])
    for bit in [2, *range(7, 17)]:
        malformed.append([(base[0][0], base[0][1] | 1 << bit), *base[1:]])
    for length in [2, 4, 5, 6, 8, 0x155, 0x400, 0x7fe]:
        malformed.append([(0x20000003+4*length, 0x60000002), *base[1:]])
    malformed.extend([
        [(0x20020007, 0x60000002), *base[1:]],
        [(0x20000007, 0x60020002), *base[1:]],
        [base[0], (0x20000003, 0x80000002), (0, 0), (0, 0)],
        [(0x20000002, 0x60000002), (0x20000001, 0x80000002), (0, 0), (0, 0)],
        [(0x2000000f, 0x60000002), (0x20040003, 0x80000002), (0, 0), (0, 0)],
    ])
    for pairs in malformed:
        for controls in range(64):
            yield controls, 0x20000000, pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with args.output.open('w') as stream:
        for controls, ea, pairs in vectors():
            values = [controls, ea, *(v for pair in pairs for v in pair), expected(controls, ea, pairs)]
            stream.write(' '.join(f'{v:x}' for v in values)+'\n')
            count += 1
    print(f'Generated {count} independent BAT interval vectors: {args.output}')


if __name__ == '__main__':
    main()
