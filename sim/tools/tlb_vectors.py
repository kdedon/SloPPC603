"""Independent software-loaded page-TLB oracle, using a virtual-page dictionary.

The lookup permission table is PEM Table 7-21. Address decomposition and
indexed invalidation are UM 5.4.3.1/2. See docs/TLB_SERVICE.md for the local
refill/response contract. This model does not import or inspect RTL.
"""
import argparse
import itertools
import random
from pathlib import Path

REQUEST = dict(kind=2, bank=1, ea=32, vsid=24, pr=1, ks=1, kp=1, n=1,
               t=1, write=1, way=1, rpn=20, c=1, wimg=4, pp=2)
RESPONSE = dict(kind=2, bank=1, ea=32, allow=1, hit=1, miss=1, pp_fault=1,
                g_fault=1, n_fault=1, t_unsupported=1, needs_c=1, privileged=1,
                refill_rejected=1, unsupported=1, invalid_input=1, matched=2,
                way=1, pa=32, wimg=4, pp=2, c=1, r=1)
# Read, write permissions, indexed by selected segment key and PTE PP.
PERMISSIONS = (((1, 1), (1, 1), (1, 1), (1, 0)),
               ((0, 0), (1, 0), (1, 1), (1, 0)))


def pack(layout, fields):
    result = 0
    for name, width in layout.items():
        value = fields.get(name, 0)
        if not 0 <= value < 2**width:
            raise ValueError((name, value))
        result = result * 2**width + value
    return result


def request(**fields):
    result = dict.fromkeys(REQUEST, 0)
    result.update(fields)
    pack(REQUEST, result)
    return result


class Model:
    def __init__(self):
        # Slots are identified independently from the virtual-page key.
        self.slots = {}

    def accept(self, q):
        s = dict.fromkeys(RESPONSE, 0)
        s.update(kind=q['kind'], bank=q['bank'], ea=q['ea'])
        page = (q['ea'] % 0x10000000) // 4096
        index = page % 32
        key = (q['vsid'], page)
        matches = [(slot, entry) for slot, entry in self.slots.items()
                   if slot[0] == q['bank'] and entry['key'] == key]
        if q['kind'] == 1:
            if q['pr']:
                s['privileged'] = 1
            elif any(slot[2] != q['way'] for slot, _ in matches):
                s['refill_rejected'] = 1
            else:
                self.slots[q['bank'], index, q['way']] = dict(
                    key=key, **{k: q[k] for k in ('rpn', 'c', 'wimg', 'pp')})
        elif q['kind'] == 2:
            if q['pr']:
                s['privileged'] = 1
            else:
                self.slots = {slot: entry for slot, entry in self.slots.items()
                              if slot[1] != index}
        elif q['kind'] == 3:
            s['unsupported'] = 1
        elif not q['bank'] and q['write']:
            s['invalid_input'] = 1
        elif q['t']:
            s['t_unsupported'] = 1
        elif not q['bank'] and q['n']:
            s['n_fault'] = 1
        elif not matches:
            s['miss'] = 1
        else:
            assert len(matches) == 1
            slot, entry = matches[0]
            s.update(hit=1, matched=2**slot[2], way=slot[2], r=1,
                     **{k: entry[k] for k in ('c', 'wimg', 'pp')})
            key_bit = q['kp'] if q['pr'] else q['ks']
            if not PERMISSIONS[key_bit][entry['pp']][q['write']]:
                s['pp_fault'] = 1
            elif not q['bank'] and entry['wimg'] % 2:
                s['g_fault'] = 1
            elif q['write'] and not entry['c']:
                s['needs_c'] = 1
            else:
                s.update(allow=1, pa=4096*entry['rpn'] + q['ea'] % 4096)
        return s


def requests():
    # All 128 entries, tags distinguish both banks and both ways in every set.
    for bank, index, way in itertools.product(range(2), range(32), range(2)):
        ea = (index + 32*way)*4096
        yield request(kind=1, bank=bank, ea=ea, vsid=0x123456,
                      way=way, rpn=0x80000+index+32*way+64*bank, c=1, pp=2)
    for bank, index, way, offset in itertools.product(range(2), range(32),
                                                     range(2), (0, 1, 4095)):
        yield request(bank=bank, ea=(index+32*way)*4096+offset, vsid=0x123456)
    # Same VSID/page aliases across segment selectors; different VSID must miss.
    for segment, bank, way in itertools.product(range(16), range(2), range(2)):
        yield request(bank=bank, ea=segment*0x10000000+way*0x20000+0xfff,
                      vsid=0x123456)
        yield request(bank=bank, ea=segment*0x10000000+way*0x20000,
                      vsid=0x123457)
    # Invalidation is set-only, both ways/banks; unselected sets must survive.
    for index in range(32):
        yield request(kind=2, bank=index % 2, ea=0xfffff000-index*4096,
                      vsid=0xffffff)
        for bank, way in itertools.product(range(2), range(2)):
            yield request(bank=bank, ea=(31-index+32*way)*4096, vsid=0x123456)
            yield request(bank=bank, ea=(32*way)*4096, vsid=0x123456)
    # Exhaustive page permissions, attributes, banks, selected keys, and C.
    for bank, pp, c, wimg in itertools.product(range(2), range(4), range(2), range(16)):
        yield request(kind=1, bank=bank, ea=0x23456000, vsid=0xabcdef,
                      rpn=0xfffff, pp=pp, c=c, wimg=wimg)
        for pr, ks, kp, write in itertools.product(range(2), repeat=4):
            yield request(bank=bank, ea=0x23456fff, vsid=0xabcdef,
                          pr=pr, ks=ks, kp=kp, write=write)
    # Rejected user mutations, duplicate refills, selected-way overwrites,
    # and T/N/invalid-I-write precedence on both hits and misses.
    for bank in range(2):
        yield request(kind=2, ea=0x55000)
        yield request(kind=1, bank=bank, ea=0x55000, vsid=7, rpn=1, pp=2)
        for kind, pr, way in itertools.product((1, 2, 3), range(2), range(2)):
            yield request(kind=kind, bank=bank, ea=0x55000, vsid=7,
                          pr=pr, way=way, rpn=2, pp=1, c=1)
            yield request(bank=bank, ea=0x55001, vsid=7)
        for t, n, write, vsid in itertools.product(range(2), range(2), range(2), (7, 8)):
            yield request(bank=bank, ea=0x55000, vsid=vsid, t=t, n=n, write=write)
    # Deterministic mixed traffic uses a bounded tag pool to exercise hits,
    # evictions and conflicts repeatedly, including extreme RPNs/offsets.
    rng = random.Random(0x603e39)
    for _ in range(12000):
        yield request(kind=rng.choices((0, 1, 2, 3), (6, 3, 1, 1))[0],
                      bank=rng.randrange(2), ea=rng.randrange(128)*4096+rng.randrange(4096),
                      vsid=rng.randrange(4), pr=rng.randrange(2), ks=rng.randrange(2),
                      kp=rng.randrange(2), n=rng.randrange(2), t=int(rng.randrange(8)==0),
                      write=rng.randrange(2), way=rng.randrange(2), rpn=rng.randrange(2**20),
                      c=rng.randrange(2), wimg=rng.randrange(16), pp=rng.randrange(4))


def generate(path):
    model = Model()
    counts = dict.fromkeys(list(RESPONSE)[3:15], 0)
    total = 0
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        for total, q in enumerate(requests(), 1):
            s = model.accept(q)
            for flag in counts:
                counts[flag] += s[flag]
            stream.write(f'{pack(REQUEST, q):024x} {total % 33:x} {pack(RESPONSE, s):023x}\n')
    assert all(counts.values()), counts
    print(f'{total} independent TLB transactions: {counts}')
    return total, counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
