"""Independent v2 protocol/schema and encoded-memory coverage anchors."""
from pathlib import Path
import tempfile
import unittest
from compare_state import Mismatch, compare, read_trace as read_v1
from compare_memory import FIELDS, HEADER, read_trace
from memory_program import corpus, FORMS


class MemoryReferenceTests(unittest.TestCase):
    def test_v1_v2_are_explicitly_separate(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'trace'
            path.write_text(HEADER+'\n'+' '.join(['01234567']*102)+'\n')
            self.assertEqual(read_trace(path),[(0x1234567,)*102])
            with self.assertRaises(Mismatch): read_v1(path)
            path.write_text(' '.join(['00000000']*38)+'\n')
            with self.assertRaises(Mismatch): read_trace(path)

    def test_bad_headers_and_shapes(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'trace'
            for content in ['',HEADER+'\n',HEADER.replace('00001000','00002000')+'\n',
                            HEADER+'\n'+' '.join(['0']*102),
                            HEADER+'\n'+' '.join(['00000000']*101),
                            HEADER+'\n'+' '.join(['00000000']*103)]:
                path.write_text(content)
                with self.subTest(content=content[:60]), self.assertRaises(Mismatch): read_trace(path)

    def test_all_ram_words_and_byte_lanes(self):
        expected=[(0,)*102]
        for field in range(38,102):
            for shift in [0,8,16,24]:
                actual=[list(expected[0])];actual[0][field]=1<<shift
                with self.subTest(field=field,shift=shift), self.assertRaises(Mismatch) as error:
                    compare(expected,actual,fields=FIELDS)
                self.assertIn(FIELDS[field],str(error.exception))
        compare(expected,expected,fields=FIELDS)

    def test_all_28_names_and_literal_encodings(self):
        words,groups=corpus()
        names={name+('u' if update else '')+('x' if indexed else '')
               for name,_,_,_,_ in FORMS for update in range(2) for indexed in range(2)}
        self.assertEqual(len(names),28)
        self.assertTrue(names.issubset(groups))
        self.assertLess(len(words),16384)
        # Literal legal old-source-alias anchors: stw r0,0x1084(0),
        # lwzx r7,0,r0; store-update may use old rS=rA=rB.
        self.assertIn(0x90001084,words)
        self.assertIn(0x7ce0002e,words)
        self.assertIn(0x7c84216e,words)
        # Source-defined negative and positive signed-halfword values are
        # generated via real STW, then read by all four LHA variants.
        self.assertIn(0x3c608000,words)
        self.assertIn(0x60637fff,words)
        self.assertGreaterEqual(groups['lhau'],2)
        self.assertGreaterEqual(groups['lhaux'],2)


if __name__=='__main__': unittest.main()
