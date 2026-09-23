"""Independent stateful transaction oracle for the bounded BAT service.

Uses the prior arithmetic/interval BAT oracle, never simulator hierarchy or RTL
functions. Each response is predicted from the request and committed model banks.
All fields are hexadecimal; the last field packs the documented 137-bit response.
"""
import argparse
import random
from pathlib import Path

from bat_vectors import expected as translate


class Model:
    def __init__(self):
        self.banks = [[(0, 0) for _ in range(4)] for _ in range(2)]
        self.counts = {'translation': 0, 'write': 0, 'read': 0,
                       'privileged': 0, 'unsupported': 0, 'rejected': 0}

    def accept(self, kind, ea, spr, data, ir, dr, pr):
        response = kind * 2**134 + ea * 2**102 + spr * 2**92
        if kind <= 2:
            self.counts['translation'] += 1
            controls = 32 + (kind == 0)*16 + (kind == 2)*8 + ir*4 + dr*2 + pr
            return response + translate(controls, ea, self.banks[kind != 0])
        if kind not in (3, 4) or not 528 <= spr <= 543:
            self.counts['unsupported'] += 1
            return response + 2**58
        if pr:
            self.counts['privileged'] += 1
            return response + 2**59
        bank, half = divmod(spr-528, 8)
        entry, lower = divmod(half, 2)
        if kind == 3:
            self.counts['read'] += 1
            return response + self.banks[bank][entry][lower] * 2**60
        candidate = self.banks[bank].copy()
        old = candidate[entry]
        candidate[entry] = (old[0], data) if lower else (data, old[1])
        if lower:
            bad_encoding = bool((data // 128) % 1024 or (data // 4) % 2 or
                                (bank == 0 and (data // 64) % 2))
        else:
            length = (data // 4) % 2048
            bad_encoding = bool((data // 8192) % 16 or (length + 1) & length)
        observation = translate(32 + (bank == 0)*16, 0, candidate)
        if bad_encoding or observation & 2**50:
            self.counts['rejected'] += 1
            bad_entries = (observation // 2**44) % 16
            if bad_encoding:
                bad_entries |= 2**entry
            overlap = (observation // 2**48) % 2
            return response + 2**57 + 2**50 + overlap*2**48 + bad_entries*2**44
        self.counts['write'] += 1
        self.banks[bank] = candidate
        return response


def requests():
    # Every bank/half starts at the documented local reset value.
    for spr in range(528, 544):
        yield 3, 0xabc00000 + spr, spr, 0, 0, 0, 0
    # Each mapping is installed by disabling the old upper half before changing
    # its lower half. Other ways and the opposite bank remain live throughout.
    for power in range(12):
        size = 131072 * 2**power
        for way in range(4):
            base = (way + 1)*0x10000000
            for bank in range(2):
                spr = 528 + 8*bank + 2*way
                for pp in range(4):
                    for flags in (1, 2, 3):
                        attrs = ((pp + flags) % 8) if bank == 0 else ((pp*4 + flags) % 16)
                        yield 4, 0, spr, 0, 0, 0, 0
                        yield 4, 0, spr+1, 0x80000000 + attrs*8 + pp, 0, 0, 0
                        upper = base + (2**power-1)*4 + flags
                        yield 4, 0, spr, upper, 0, 0, 0
                        yield 3, 0, spr, 0, 0, 0, 0
                        yield 3, 0, spr+1, 0, 0, 0, 0
                        for pr in range(2):
                            for kind in (0, 1, 2):
                                for offset in (-1, 0, 3, size-1, size):
                                    yield kind, base+offset, spr, 0, 1, 1, pr
                        # Independent IR/DR control and opposite-bank selection.
                        for enables in range(4):
                            yield 0, base+16, spr, 0, enables//2, enables%2, 0
                            yield 2, base+16, spr, 0, enables//2, enables%2, 1
    # Invalid candidate updates must preserve both the partner half and every
    # previously accepted mapping. Read each bank after rejected transactions.
    mutations = [0xffffffff, 0x20020007, 0x2000000b, 0x20002003,
                 0x80000006, 0x80000042, 0x80010002, 0x00000000]
    for spr in range(528, 544):
        for data in mutations:
            for pr in range(2):
                yield 4, 0x76543210, spr, data, 1, 1, pr
                for read_spr in range(528, 544):
                    yield 3, 0, read_spr, 0, 0, 0, 0
    # Exact aliases of an existing bank entry reject for overlapping privilege;
    # then a disabled lower half + privilege-disjoint alias is legal.
    for bank in range(2):
        for way in range(4):
            yield 4, 0, 528 + bank*8 + way*2, 0, 0, 0, 0
        for spr, data in [(529+bank*8, 0x60000002), (528+bank*8, 0x20000002),
                          (531+bank*8, 0x80000002), (530+bank*8, 0x20000002),
                          (530+bank*8, 0x20000001)]:
            yield 4, 0, spr, data, 0, 0, 0
        for pr in range(2):
            for kind in range(3):
                yield kind, 0x20012345, 0, 0, 1, 1, pr
    rng = random.Random(0x603e0038)
    for _ in range(4000):
        kind = rng.randrange(8)
        spr = rng.choice([0, 26, 27, 527, *range(528, 544), 544, 1023])
        data = rng.choice([rng.getrandbits(32), 0, 1, 2, 3, 0x20000003, 0x80000002])
        ea = rng.choice([rng.getrandbits(32), 0x20012345, 0x40000000, 0xffffffff])
        yield kind, ea, spr, data, rng.randrange(2), rng.randrange(2), rng.randrange(2)
    for spr in range(528, 544):
        yield 3, 0, spr, 0, 0, 0, 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model = Model()
    count = 0
    with args.output.open('w') as stream:
        for count, request in enumerate(requests(), 1):
            response = model.accept(*request)
            # Zero exercises consecutive turnover; longer stalls offer the next
            # request early, proving it cannot affect a held prior response.
            stall = (count*7) % 6
            stream.write(' '.join(f'{value:x}' for value in (*request, stall, response))+'\n')
    print(f'Generated {count} independent BAT service transactions: {model.counts}')


if __name__ == '__main__':
    main()
