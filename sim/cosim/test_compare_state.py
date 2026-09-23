"""Independent format/diagnostic tests; actual reference-vs-RTL is run_reference.py."""
from pathlib import Path
import tempfile
import unittest

from compare_state import FIELDS, Mismatch, compare, read_trace
from reference_program import corpus


class StateComparisonTests(unittest.TestCase):
    def test_exact_and_each_architectural_field(self):
        row=tuple(range(38))
        compare([row],[row])
        for index,name in enumerate(FIELDS):
            bad=list(row); bad[index] ^= 1
            with self.subTest(field=name), self.assertRaisesRegex(Mismatch, f' {name}:'):
                compare([row],[bad])

    def test_missing_and_extra_retirement(self):
        row=(0,)*38
        for rows in [[],[row,row]]:
            with self.assertRaisesRegex(Mismatch,'row count'):
                compare([row],rows)

    def test_first_divergence_precedes_length(self):
        expected=[(0,)*38,(4,)*38]
        actual=[(1,)*38]
        with self.assertRaisesRegex(Mismatch, 'row 0 pc=00000000 pc:'):
            compare(expected,actual)
        with self.assertRaisesRegex(Mismatch, 'row 1 pc=00000004: missing retirement'):
            compare(expected,expected[:1])

    def test_strict_text(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'trace'
            path.write_text(' '.join(['01234567']*38)+'\n')
            self.assertEqual(read_trace(path),[(0x1234567,)*38])
            for text in ['', '\n', ' '.join(['00000000']*37),
                         ' '.join(['000000000']*38), ' '.join(['xxxxxxxx']*38),
                         ' '.join(['-0000001']*38), ' '.join(['0x000001']*38)]:
                path.write_text(text)
                with self.subTest(text=text[:15]), self.assertRaises(Mismatch):
                    read_trace(path)

    def test_program_whitelist_groups(self):
        words,groups=corpus()
        self.assertGreater(len(words),1000)
        self.assertLess(len(words),16384)  # RTL trace memory size
        expected={f'{name}/oe{oe}/rc{rc}' for name in
                  ['add','addc','adde','addme','addze','subf','subfc','subfe','subfme','subfze','neg',
                   'mullw','divw','divwu']
                  for oe in range(2) for rc in range(2)}
        expected |= {f'{name}/rc{rc}' for name in
                    ['and','andc','eqv','nand','nor','or','orc','xor','slw','srw','sraw','srawi',
                     'rlwimi','rlwinm','rlwnm','mulhw','mulhwu','cntlzw','extsb','extsh'] for rc in range(2)}
        expected |= {'subfic','cmpli','cmpi','cmp','cmpl','addic','addic.','addi','addis',
                     'ori','oris','xori','xoris','andi.','andis.',
                     'crand','crandc','creqv','crnand','crnor','cror','crorc','crxor'}
        expected |= {f'{name}/aa{aa}/lk{lk}' for name in ['b','bc'] for aa in range(2) for lk in range(2)}
        expected |= {f'{name}/lk{lk}' for name in ['bclr','bcctr'] for lk in range(2)}
        expected |= {'b/call','b/skip-return'}
        expected |= {'mulli','mfcr','mtcrf','mcrf','mcrxr',
                     'mfspr/8','mfspr/9','mtspr/8','mtspr/9'}
        self.assertEqual(set(groups),expected)
        # Hand encoding anchors, independent of arithmetic/state execution.
        self.assertEqual(words[0],0x38000007)
        self.assertEqual(words[-1],0x3be0007b)
        for word in words:
            self.assertGreaterEqual(word,0)
            self.assertLess(word,1<<32)
        for index,word in enumerate(words):
            if word >> 26 == 16 and word & 2:
                self.assertEqual(word & 0xfffc,(index+1)*4)
                self.assertLess((index+1)*4,32768)

    def test_new_mask_and_branch_structure(self):
        words,_=corpus()
        masks={(w >> 12) & 255 for w in words if w >> 26 == 31 and ((w >> 1)&1023)==144}
        self.assertEqual(masks,set(range(256)))
        fields={((w >> 23)&7,(w >> 18)&7) for w in words if w >> 26 == 19 and ((w >> 1)&1023)==0}
        self.assertEqual(fields,{(a,b) for a in range(8) for b in range(8)})
        taken=[(i,w) for i,w in enumerate(words) if w >> 26 == 19 and
               ((w >> 1)&1023)==528 and ((w >> 21)&31)==20]
        self.assertEqual(len(taken),2)
        for index,word in taken:
            self.assertEqual(words[index-1],0x7c0903a6)  # mtctr r0
            self.assertEqual(words[index-2]&65535,((index+2)*4)|3)


if __name__ == '__main__':
    unittest.main()
