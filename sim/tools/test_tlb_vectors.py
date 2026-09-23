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

    def test_duplicate_rejection_and_invalidation(self):
        m = Model()
        for bank in (0, 1):
            for way in (0, 1):
                m.accept(request(kind=1, bank=bank, ea=way*0x20000,
                                 way=way, vsid=3, rpn=way+1, pp=2))
        self.assertEqual(m.accept(request(kind=1, bank=1, way=1, vsid=3))['refill_rejected'], 1)
        self.assertEqual(m.accept(request(kind=2, pr=1))['privileged'], 1)
        self.assertEqual(len(m.slots), 4)
        m.accept(request(kind=2, ea=0xfffe0000, vsid=0xffffff))
        self.assertEqual(len(m.slots), 0)

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
