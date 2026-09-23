"""Independent expected-state boundaries for update-addressing programs."""
import unittest
from control_memory_program import Program, BASE, make_lsu_update

class UpdateMemoryTests(unittest.TestCase):
    def test_literal_words(self):
        p=Program()
        for op,args,word in [
            ('lwzu',(6,4,-4),0x84c4fffc),
            ('lwzux',(6,4,7),0x7cc4386e),
            ('stwu',(4,4,4),0x94840004),
            ('stwux',(4,4,4),0x7c84216e),
            ('lhaux',(0,4,0),0x7c0402ee)]:
            self.assertEqual(p.encode(0,op,args),word)

    def test_old_store_source_and_two_load_destinations(self):
        p=Program();e=p.emit
        e('addi',4,0,BASE);e('stwu',4,4,4)
        e('addi',7,0,-4);e('lwzux',7,4,7);e('illegal')
        rows,_=p.simulate()
        self.assertEqual(rows[1][6],BASE+4)
        # Original initialized bytes at BASE, not the newly stored BASE+4 word.
        self.assertEqual(rows[3][9],0xa580efca)
        self.assertEqual(rows[3][6],BASE)
        self.assertEqual(rows[1][34:38],[0,0,0,0])
        p=Program();e=p.emit
        e('addi',4,0,BASE);e('stwu',4,4,4);e('lwz',6,4,0);e('illegal')
        self.assertEqual(p.simulate()[0][2][8],BASE)

    def test_illegal_aliases_reject(self):
        for op,d,r,off in [('lwzu',4,4,BASE),('lbzu',6,0,BASE),('stwu',6,0,BASE)]:
            p=Program();p.emit(op,d,r,off);p.emit('illegal')
            with self.assertRaisesRegex(AssertionError,'invalid update'):
                p.simulate()

    def test_profile_forms_and_count(self):
        rows,counts=make_lsu_update().simulate(limit=10000)
        for stem in ('lbz','lhz','lha','lwz','stb','sth','stw'):
            for suffix in ('u','ux'):self.assertGreater(counts[stem+suffix],0)
        self.assertEqual(len(rows),1370)

if __name__=='__main__':unittest.main()
