"""Literal CR field numbering, readback and architectural preservation."""
import unittest
import control_memory_program as program


class CrTransferOracleTest(unittest.TestCase):
    def test_literal_masks_real_r0_and_xer_preservation(self):
        for mask, expected in [(0, 0x12345678), (255, 0xabcdef01),
                               (128, 0xa2345678), (1, 0x12345671),
                               (0xa5, 0xa2c45f71), (0x5a, 0x1b3de608)]:
            for seed in (0, 1):
                p=program.Program()
                p.emit('addis',18,0,0x8000 if seed else 0)
                p.emit('addco',20,18,18)
                p.emit('addis',0,0,0x1234);p.emit('ori',0,0,0x5678)
                p.emit('mtcrf',255,0)
                p.emit('addis',0,0,0xabcd);p.emit('ori',0,0,0xef01)
                p.emit('mtcrf',mask,0);p.emit('mfcr',0);p.emit('illegal')
                rows,_=p.simulate()
                self.assertEqual(rows[-1][2],expected)
                self.assertEqual(rows[-1][34],expected)
                self.assertEqual(rows[-1][35],0xe0000000 if seed else 0)
                self.assertEqual(rows[-2][34:],rows[-3][34:])

    def test_profile_size_and_coverage(self):
        p=program.make_crtransfer()
        rows,counts=p.simulate(limit=10000)
        self.assertLessEqual(len(p.ops),4096)
        self.assertEqual(len(rows),2914)
        self.assertEqual(counts['mfcr'],523)
        self.assertEqual(counts['mtcrf'],522)
        self.assertEqual({a[0] for op,a in p.ops if op=='mtcrf'},set(range(256)))


if __name__=='__main__':unittest.main()
