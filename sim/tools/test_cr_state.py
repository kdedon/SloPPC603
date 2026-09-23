"""Independent literal anchors for CR state moves and flag clearing."""
import unittest
import control_memory_program as program

class CrStateOracleTest(unittest.TestCase):
    def test_field_moves_and_aliases(self):
        for source in range(8):
            for dest in range(8):
                p=program.Program()
                p.emit('addis',6,0,0x1234);p.emit('ori',6,6,0x5678)
                p.emit('mtcrf',255,6);p.emit('mcrf',dest,source);p.emit('illegal')
                rows,_=p.simulate()
                digits=list('12345678');digits[dest]=digits[source]
                self.assertEqual(rows[-1][34],int(''.join(digits),16))
                self.assertEqual(rows[-1][35],0)
        self.assertEqual(p.encode(0,'mcrf',(5,2)),0x4e880000)
        self.assertEqual(p.encode(0,'mcrxr',(5,)),0x7e800400)

    def test_copy_clear_and_consumers(self):
        for dest in range(8):
            p=program.Program()
            p.emit('addis',18,0,0x8000);p.emit('addco',20,18,18)
            p.emit('addis',6,0,0x1234);p.emit('ori',6,6,0x5678)
            p.emit('mtcrf',255,6);p.emit('mcrxr',dest)
            p.emit('mfcr',9);p.emit('adde',13,0,0)
            p.emit('andi.',14,6,1);p.emit('illegal')
            rows,_=p.simulate()
            digits=list('12345678');digits[dest]='e'
            self.assertEqual(rows[5][34],int(''.join(digits),16))
            self.assertEqual(rows[5][35],0)
            self.assertEqual(rows[6][11],int(''.join(digits),16))
            self.assertEqual(rows[-1][15],0)
            self.assertEqual(rows[-1][34]>>28,2)
            self.assertEqual(rows[-1][35],0)

    def test_profile_coverage(self):
        p=program.make_crstate();rows,counts=p.simulate(limit=10000)
        self.assertEqual(len(p.ops),1512);self.assertEqual(len(rows),1460)
        self.assertEqual(counts['mcrf'],160);self.assertEqual(counts['mcrxr'],144)
        self.assertEqual({a for op,a in p.ops if op=='mcrf'},
                         {(d,s) for d in range(8) for s in range(8)})
        self.assertEqual({a[0] for op,a in p.ops if op=='mcrxr'},set(range(8)))
