"""Literal truth tables, MSB-first CR destinations and source aliases."""
import unittest
import control_memory_program as program


class CrLogicalOracleTest(unittest.TestCase):
    def test_truth_tables_destination_bits_and_aliases(self):
        tables={'crand':8,'crandc':4,'creqv':9,'crnand':7,
                'crnor':1,'cror':14,'crorc':13,'crxor':6}
        for op,table in tables.items():
            for truth in range(4):
                for dest in range(32):
                    source=(0xa55ac33c & ~((1<<24)|(1<<7))) | ((truth>>1)<<24) | ((truth&1)<<7)
                    result=(source & ~(1<<(31-dest))) | (((table>>truth)&1)<<(31-dest))
                    p=program.Program()
                    p.emit('addis',18,0,0x8000);p.emit('addco',20,18,18)
                    p.emit('addis',0,0,source>>16);p.emit('ori',0,0,source&65535)
                    p.emit('mtcrf',255,0);p.emit(op,dest,7,24);p.emit('mfcr',0);p.emit('illegal')
                    rows,_=p.simulate()
                    self.assertEqual(rows[-1][2],result)
                    self.assertEqual(rows[-1][34],result)
                    self.assertEqual(rows[-1][35],0xe0000000)
                    self.assertEqual(rows[-3][2:34],rows[-4][2:34])

    def test_profile_fits_rom_and_covers_all_operations(self):
        p=program.make_crlogical();rows,counts=p.simulate(limit=10000)
        self.assertLessEqual(len(p.ops),4096)
        self.assertEqual(len(rows),3851)
        for op in program.CROPS:self.assertEqual(counts[op],140)
        for op in program.CROPS:
            self.assertEqual({a[0] for name,a in p.ops if name==op},set(range(32)))


if __name__=='__main__':unittest.main()
