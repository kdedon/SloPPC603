"""Signed division: defined quotient/flags versus local undefined-result policy."""
import unittest
import control_memory_program as program

def run(a,b,oe,rc,seed=False):
    p=program.Program()
    if seed:p.emit('addis',18,0,0x8000);p.emit('addco',20,18,18)
    for r,v in [(0,a&program.MASK),(6,b&program.MASK)]:
        p.emit('addis',r,0,v>>16);p.emit('ori',r,r,v&65535)
    p.emit('divw',0,0,6,oe,rc);p.emit('illegal')
    return p.simulate()[0][-1]

class DivideSignedOracleTest(unittest.TestCase):
    def test_literal_quotients_truncate_toward_zero(self):
        for a,b,q in [(10,3,3),(-10,3,-3),(10,-3,-3),(-10,-3,3),
                      (-1,2,0),(1,-2,0),(-2147483648,1,-2147483648),
                      (2147483647,-1,-2147483647),(-2147483648,3,-715827882),
                      (1,-2147483648,0)]:
            for oe in (0,1):
                for rc in (0,1):
                    r=run(a,b,oe,rc,True);value=q&program.MASK
                    self.assertEqual(r[2],value)
                    rem=a-q*b;self.assertLess(abs(rem),abs(b))
                    self.assertTrue(rem==0 or (rem<0)==(a<0))
                    self.assertEqual(r[35],0xa0000000 if oe else 0xe0000000)
                    nibble=(8 if q<0 else 4 if q else 2)|1
                    self.assertEqual(r[34],nibble<<28 if rc else 0)

    def test_exception_defined_flags_only(self):
        for a,b in [(1,0),(-2147483648,-1)]:
            for seed in (False,True):
                for oe in (0,1):
                    for rc in (0,1):
                        r=run(a,b,oe,rc,seed)
                        # GPR and CR LT/GT/EQ are deliberately not inspected.
                        self.assertEqual(r[35],0xe0000000 if seed else 0xc0000000 if oe else 0)
                        if rc:self.assertEqual((r[34]>>28)&1,int(seed or oe))
                        self.assertEqual(r[34]&0x0fffffff,0)

    def test_scaffold_undefined_result_policy_only(self):
        for a,b in [(1,0),(-2147483648,-1)]:
            r=run(a,b,1,1);self.assertEqual(r[2],0);self.assertEqual(r[34]>>28,3)
        p=program.Program()
        self.assertEqual(p.encode(0,'divw',(4,1,6,1,1)),0x7c8137d7)
        self.assertEqual(p.encode(0,'divw',(4,1,0,1,1)),0x7c8107d7)

    def test_profile(self):
        p=program.make_divide_signed();rows,counts=p.simulate(limit=10000)
        self.assertEqual(len(p.ops),2031);self.assertEqual(len(rows),1979)
        self.assertEqual(counts['divw'],308)
        self.assertEqual({a[3:] for op,a in p.ops if op=='divw'},
                         {(0,0),(0,1),(1,0),(1,1)})
