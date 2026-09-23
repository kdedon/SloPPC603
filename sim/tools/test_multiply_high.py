"""Literal high-product boundaries, signedness and XER preservation."""
import unittest
import control_memory_program as program

class MultiplyHighOracleTest(unittest.TestCase):
    def test_signed_unsigned_literal_products(self):
        vectors=[(0xffffffff,0xffffffff,0,0xfffffffe),
                 (0x80000000,1,0xffffffff,0),
                 (0x80000000,0x80000000,0x40000000,0x40000000),
                 (0x7fffffff,0xffffffff,0xffffffff,0x7ffffffe),
                 (0x10000,0x10000,1,1),(0,0xffffffff,0,0)]
        for av,bv,sh,uh in vectors:
            for op,expected in [('mulhw',sh),('mulhwu',uh)]:
                for rc in (0,1):
                    p=program.Program()
                    p.emit('addis',18,0,0x8000);p.emit('addco',20,18,18)
                    for r,v in [(0,av),(6,bv)]:
                        p.emit('addis',r,0,v>>16);p.emit('ori',r,r,v&65535)
                    p.emit(op,0,0,6,rc);p.emit('illegal');rows,_=p.simulate()
                    self.assertEqual(rows[-1][2],expected)
                    self.assertEqual(rows[-1][35],0xe0000000)
                    nibble=(8 if expected&0x80000000 else 4 if expected else 2)|1
                    self.assertEqual(rows[-1][34],nibble<<28 if rc else 0)
        self.assertEqual(p.encode(0,'mulhw',(4,1,6,1)),0x7c813097)
        self.assertEqual(p.encode(0,'mulhwu',(4,1,6,1)),0x7c813017)

    def test_full_product_reconstruction(self):
        for op in ('mulhw','mulhwu'):
            for av,bv in [(0x80000001,0xfedcba98),(0x12345678,0x89abcdef),
                          (0xffffffff,2),(0x7fffffff,0x7fffffff)]:
                p=program.Program()
                for r,v in [(4,av),(6,bv)]:
                    p.emit('addis',r,0,v>>16);p.emit('ori',r,r,v&65535)
                p.emit(op,7,4,6,0);p.emit('mullw',8,4,6,0,0);p.emit('illegal')
                rows,_=p.simulate();r=rows[-1]
                product=(program.signed(av)*program.signed(bv)) if op=='mulhw' else av*bv
                self.assertEqual((r[9]<<32)|r[10],product&((1<<64)-1))

    def test_profile(self):
        p=program.make_multiply_high();rows,counts=p.simulate(limit=10000)
        self.assertEqual(len(p.ops),2128);self.assertEqual(len(rows),2076)
        self.assertEqual(counts['mulhw'],164);self.assertEqual(counts['mulhwu'],164)
        self.assertEqual({a[3] for op,a in p.ops if op=='mulhw'},{0,1})
