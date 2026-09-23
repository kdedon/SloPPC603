"""DIVWU defined semantics and separately labeled undefined-result policy."""
import unittest
import control_memory_program as program

def run(dividend,divisor,oe,rc,seed=False):
    p=program.Program()
    if seed:p.emit('addis',18,0,0x8000);p.emit('addco',20,18,18)
    for r,v in [(0,dividend),(6,divisor)]:
        p.emit('addis',r,0,v>>16);p.emit('ori',r,r,v&65535)
    p.emit('divwu',0,0,6,oe,rc);p.emit('illegal')
    return p.simulate()[0][-1]

class DivideUnsignedOracleTest(unittest.TestCase):
    def test_literal_quotients_and_remainder_relation(self):
        for a,b,q in [(0xffffffff,1,0xffffffff),(0xffffffff,3,0x55555555),
                      (0x80000000,2,0x40000000),(3,7,0),(0,1,0),
                      (0xffffffff,0x80000000,1),(0xfffffffe,0xffffffff,0)]:
            for oe in (0,1):
                for rc in (0,1):
                    r=run(a,b,oe,rc,True)
                    self.assertEqual(r[2],q)
                    remainder=a-q*b;self.assertGreaterEqual(remainder,0);self.assertLess(remainder,b)
                    self.assertEqual(r[35],0xa0000000 if oe else 0xe0000000)
                    nibble=(8 if q&0x80000000 else 4 if q else 2)|1
                    self.assertEqual(r[34],nibble<<28 if rc else 0)

    def test_zero_divisor_defined_flags(self):
        # Deliberately do not inspect architecturally undefined GPR or CR LT/GT/EQ.
        for seed in (False,True):
            for oe in (0,1):
                for rc in (0,1):
                    r=run(0x81234567,0,oe,rc,seed)
                    self.assertEqual(r[35],0xe0000000 if seed else 0xc0000000 if oe else 0)
                    if rc:self.assertEqual((r[34]>>28)&1,int(seed or oe))
                    self.assertEqual(r[34]&0x0fffffff,0)

    def test_zero_divisor_scaffold_policy_only(self):
        # Zero quotient and EQ are reproducibility choices, not ISA conformance claims.
        r=run(0xffffffff,0,1,1)
        self.assertEqual(r[2],0);self.assertEqual(r[34]>>28,3)
        p=program.Program()
        self.assertEqual(p.encode(0,'divwu',(4,1,6,1,1)),0x7c813797)
        self.assertEqual(p.encode(0,'divwu',(4,1,0,1,1)),0x7c810797)

    def test_profile(self):
        p=program.make_divide_unsigned();rows,counts=p.simulate(limit=10000)
        self.assertEqual(len(p.ops),2031);self.assertEqual(len(rows),1979)
        self.assertEqual(counts['divwu'],308)
        self.assertEqual({a[3:] for op,a in p.ops if op=='divwu'},
                         {(0,0),(0,1),(1,0),(1,1)})
