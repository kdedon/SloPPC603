"""Literal multiplication boundaries independent of RTL datapath/masks."""
import unittest
import control_memory_program as program

class MultiplyOracleTest(unittest.TestCase):
    def test_literal_boundaries_and_flags(self):
        vectors=[(0x80000000,0xffffffff,0x80000000,True),
                 (0x80000000,1,0x80000000,False),
                 (0x7fffffff,2,0xfffffffe,True),
                 (0xffffffff,0xffffffff,1,False),
                 (0x10000,0x10000,0,True),
                 (0xffff0000,0x7fff,0x80010000,False)]
        for av,bv,value,overflow in vectors:
            for oe in (0,1):
                for rc in (0,1):
                    p=program.Program()
                    for r,v in [(4,av),(6,bv)]:
                        p.emit('addis',r,0,v>>16);p.emit('ori',r,r,v&65535)
                    p.emit('mullw',4,4,6,oe,rc);p.emit('illegal')
                    rows,_=p.simulate();last=rows[-1]
                    self.assertEqual(last[6],value)
                    self.assertEqual(last[35],0xc0000000 if oe and overflow else 0)
                    nibble=(8 if value&0x80000000 else 4 if value else 2)|int(oe and overflow)
                    self.assertEqual(last[34],nibble<<28 if rc else 0)

    def test_immediate_sign_real_r0_and_literal_encoding(self):
        for imm,expected in [(-1,0xfffffffd),(-32768,0xfffe8000),(32767,0x17ffd),(0,0)]:
            p=program.Program();p.emit('addi',0,0,3)
            p.emit('mulli',0,0,imm);p.emit('illegal');rows,_=p.simulate()
            self.assertEqual(rows[-1][2],expected)
            self.assertEqual(rows[-1][34:38],[0,0,0,0])
        self.assertEqual(p.encode(0,'mulli',(4,1,-1)),0x1c81ffff)
        self.assertEqual(p.encode(0,'mullw',(4,1,6,1,1)),0x7c8135d7)
        self.assertEqual(p.encode(0,'mullw',(4,1,1,1,1)),0x7c810dd7)

    def test_profile_and_modes(self):
        p=program.make_multiply();rows,counts=p.simulate(limit=10000)
        self.assertEqual(len(p.ops),2166);self.assertEqual(len(rows),2114)
        self.assertEqual(counts['mullw'],272);self.assertEqual(counts['mulli'],80)
        self.assertEqual({a[3:] for op,a in p.ops if op=='mullw'},
                         {(0,0),(0,1),(1,0),(1,1)})
