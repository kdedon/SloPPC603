# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Anchor the independent TLB oracle to literal boundary cases."""
import unittest
from tlb_vectors import Model, REQUEST, RESPONSE, pack, request


class TlbOracleTests(unittest.TestCase):
    def test_wire_widths(self):
        self.assertEqual(sum(REQUEST.values()), 93)
        self.assertEqual(sum(RESPONSE.values()), 90)
        self.assertEqual(pack(REQUEST, request()), 0)
        with self.assertRaises(ValueError):
            request(vsid=0x1000000)

    def test_aliases_offsets_and_full_tag(self):
        m = Model()
        m.accept(request(kind=1, bank=1, ea=0x12345000, vsid=9, rpn=0xfffff, pp=2))
        s = m.accept(request(bank=1, ea=0xe2345fff, vsid=9))
        self.assertEqual((s['allow'], s['pa']), (1, 0xffffffff))
        self.assertEqual(m.accept(request(bank=1, ea=0x12345000, vsid=8))['miss'], 1)
        self.assertEqual(m.accept(request(bank=1, ea=0x12365000, vsid=9))['miss'], 1)

    def test_page_pp_zero_and_changed(self):
        m = Model()
        m.accept(request(kind=1, bank=1, pp=0, rpn=1))
        self.assertEqual(m.accept(request(bank=1))['allow'], 1)
        self.assertEqual(m.accept(request(bank=1, ks=1))['pp_fault'], 1)
        s = m.accept(request(bank=1, write=1))
        self.assertEqual((s['needs_c'], s['pa'], s['c']), (1, 0, 0))
        self.assertEqual(m.accept(request(bank=1, write=1))['needs_c'], 1)
        m.accept(request(kind=1, bank=1, pp=0, rpn=1, c=1))
        self.assertEqual(m.accept(request(bank=1, write=1))['pa'], 4096)

    def test_duplicate_replacement_and_invalidation(self):
        m = Model()
        for bank in (0, 1):
            for way in (0, 1):
                m.accept(request(kind=1, bank=bank, ea=way*0x20000,
                                 way=way, vsid=3, rpn=way+1, pp=2))
        # The tag in way 0 moves to way 1, overwriting that way's old tag.
        self.assertEqual(m.accept(request(kind=1, bank=1, way=1, vsid=3, rpn=9))['refill_rejected'], 0)
        self.assertEqual(m.accept(request(kind=2, pr=1))['privileged'], 1)
        self.assertEqual(len(m.slots), 3)
        self.assertEqual(m.slots[1, 0, 1]['rpn'], 9)
        m.accept(request(kind=2, ea=0xfffe0000, vsid=0xffffff))
        self.assertEqual(len(m.slots), 0)

    def test_miss_reports_lru_way(self):
        m = Model()
        self.assertEqual(m.accept(request(bank=1))['way'], 0)
        m.accept(request(kind=1, bank=1, way=0, vsid=1, rpn=1, pp=2))
        self.assertEqual(m.accept(request(bank=1, vsid=2))['way'], 1)
        m.accept(request(kind=1, bank=1, way=1, vsid=2, rpn=2, pp=2))
        self.assertEqual(m.accept(request(bank=1, vsid=3))['way'], 0)
        self.assertEqual(m.accept(request(bank=1, vsid=1))['way'], 0)
        self.assertEqual(m.accept(request(bank=1, vsid=3))['way'], 1)
        self.assertEqual(m.accept(request(bank=0, vsid=3))['way'], 0)

    def test_sixteen_set_geometry(self):
        # 602UM 5.4.4: EA16..19 index 16 sets, so page 0x10 shares set 0.
        m = Model(16)
        m.accept(request(kind=1, bank=1, ea=0x00000000, way=0, vsid=4, rpn=1, pp=2))
        m.accept(request(kind=1, bank=1, ea=0x00010000, way=1, vsid=4, rpn=2, pp=2))
        self.assertEqual(m.accept(request(bank=1, ea=0x00010abc, vsid=4))['pa'], 0x2abc)
        self.assertEqual(m.accept(request(bank=1, ea=0x00020000, vsid=4))['way'], 0)
        m.accept(request(kind=2, ea=0xffff0000))
        self.assertEqual(len(m.slots), 0)
        # With 32 sets the same two pages sit in different sets.
        m = Model()
        m.accept(request(kind=1, bank=1, ea=0x00000000, vsid=4, rpn=1, pp=2))
        m.accept(request(kind=2, ea=0xffff0000))
        self.assertEqual(len(m.slots), 1)

    def test_fault_precedence(self):
        m = Model()
        m.accept(request(kind=1, wimg=1, pp=0))
        self.assertEqual(m.accept(request(ks=1))['pp_fault'], 1)
        self.assertEqual(m.accept(request())['g_fault'], 1)
        self.assertEqual(m.accept(request(n=1))['n_fault'], 1)
        self.assertEqual(m.accept(request(n=1, t=1))['t_unsupported'], 1)
        self.assertEqual(m.accept(request(n=1, t=1, write=1))['invalid_input'], 1)


if __name__ == '__main__':
    unittest.main()
