"""Unsigned immediate placement, mandatory recording and source-conflict gates."""
import json
import unittest

import control_memory_program as program
import isa_generate


class AndImmediateTest(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(isa_generate.ISA_PATH.read_text())
        self.sources = json.loads(isa_generate.SOURCE_PATH.read_text())
        self.timing = json.loads(isa_generate.TIMING_PATH.read_text())

    def test_all_payload_bits_and_mandatory_record(self):
        entries = [e for e in self.spec['decode_entries'] if e.get('semantic_class') == 'logical_immediate_record']
        self.assertEqual(len(entries), 2)
        p = program.Program()
        for e in entries:
            for imm in range(65536):
                self.assertTrue(isa_generate.decode_matches(e, p.encode(0, e['id'], (7, 0, imm))))
        entries[0]['modifiers']['Rc'] = 'fixed_0'
        with self.assertRaisesRegex(isa_generate.MetadataError, 'AND-immediate encoding/operand/flags'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_secondary_typo_must_remain_explicit(self):
        self.spec['and_immediate_semantics'].pop('secondary_conflict')
        with self.assertRaisesRegex(isa_generate.MetadataError, 'ANDIS secondary conflict'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_literal_unsigned_masks_real_r0_and_full_xer_preservation(self):
        anchors = [('andi.', 0xffffffff, 0x8000, 0x00008000),
                   ('andis.', 0xffffffff, 0x8000, 0x80000000),
                   ('andi.', 0x12345678, 0xffff, 0x00005678),
                   ('andis.', 0x12345678, 0xffff, 0x12340000),
                   ('andis.', 0x80000001, 0x8001, 0x80000000),
                   ('andi.', 0xffffffff, 0, 0),
                   ('andis.', 1, 0xffff, 0)]
        for seed in (0, 1):
            for op, source, imm, result in anchors:
                p = program.Program()
                p.emit('addis', 18, 0, 0x8000 if seed else 0)
                p.emit('addco', 20, 18, 18)
                p.emit('addis', 0, 0, source >> 16)
                p.emit('ori', 0, 0, source & 65535)
                p.emit('cmpi', 5, 20, 0)
                p.emit(op, 0, 0, imm)
                p.emit('illegal')
                rows, _ = p.simulate()
                self.assertEqual(rows[-1][2], result)
                field = (8 if result & 0x80000000 else 4 if result else 2) | seed
                self.assertEqual(rows[-1][34], (rows[-3][34] & 0x0fffffff) | (field << 28))
                self.assertEqual(rows[-1][35], 0xe0000000 if seed else 0)


if __name__ == '__main__':
    unittest.main()
