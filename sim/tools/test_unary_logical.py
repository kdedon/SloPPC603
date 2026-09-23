"""Literal unary result anchors and full architectural flag preservation."""
import unittest
import control_memory_program as program


class UnaryLogicalOracleTest(unittest.TestCase):
    def test_literal_results_aliases_and_flags(self):
        anchors = [('cntlzw', 0, 32), ('cntlzw', 1, 31),
                   ('cntlzw', 0x80000000, 0), ('cntlzw', 0x00010001, 15),
                   ('extsb', 0x1234567f, 127), ('extsb', 0x12345680, 0xffffff80),
                   ('extsb', 0xffffff00, 0), ('extsb', 0x123400ff, 0xffffffff),
                   ('extsh', 0xffff7fff, 32767), ('extsh', 0x12348000, 0xffff8000),
                   ('extsh', 0xffff0000, 0), ('extsh', 0x1234ffff, 0xffffffff)]
        for seed in (0, 1):
            for rc in (0, 1):
                for op, source, result in anchors:
                    p = program.Program()
                    p.emit('addis', 18, 0, 0x8000 if seed else 0)
                    p.emit('addco', 20, 18, 18)
                    p.emit('cmpi', 0, 20, 0)
                    p.emit('cmpi', 5, 20, 0)
                    p.emit('addis', 0, 0, source >> 16)
                    p.emit('ori', 0, 0, source & 65535)
                    p.emit(op, 0, 0, rc)
                    p.emit('illegal')
                    rows, _ = p.simulate()
                    self.assertEqual(rows[-1][2], result)
                    prior_cr = rows[-3][34]
                    field = (8 if result & 0x80000000 else 4 if result else 2) | seed
                    self.assertEqual(rows[-1][34], ((prior_cr & 0x0fffffff) | (field << 28)) if rc else prior_cr)
                    self.assertEqual(rows[-1][35], 0xe0000000 if seed else 0)

    def test_profile_fits_rom_and_covers_each_family(self):
        p = program.make_unarylogical()
        self.assertLessEqual(len(p.ops), 4096)
        rows, counts = p.simulate(limit=10000)
        self.assertEqual(len(rows), 3459)
        for op in ('cntlzw', 'extsb', 'extsh'):
            self.assertEqual(counts[op], 720)


if __name__ == '__main__':
    unittest.main()
