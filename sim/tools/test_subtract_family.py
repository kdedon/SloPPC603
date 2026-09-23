"""Encoding policy and literal signed-subtraction oracle anchors."""
import json
import unittest

import control_memory_program as program
import isa_generate


class SubtractFamilyTest(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(isa_generate.ISA_PATH.read_text())
        self.sources = json.loads(isa_generate.SOURCE_PATH.read_text())
        self.timing = json.loads(isa_generate.TIMING_PATH.read_text())

    def test_eight_encodings_and_neg_reserved_field(self):
        entries = [e for e in self.spec['decode_entries'] if e.get('family') in ('subf', 'neg')]
        self.assertEqual(len(entries), 8)
        p = program.Program()
        for entry in entries:
            oe, rc = (int(entry['modifiers'][k][-1]) for k in ('OE', 'Rc'))
            args = (7, 0, 9, oe, rc) if entry['family'] == 'subf' else (7, 0, oe, rc)
            word = p.encode(0, entry['family'], args)
            self.assertTrue(isa_generate.decode_matches(entry, word))
            if entry['family'] == 'neg':
                for rb in range(1, 32):
                    self.assertFalse(isa_generate.decode_matches(entry, word | (rb << 11)))

    def test_carry_permission_mutation_rejected(self):
        entry = next(e for e in self.spec['decode_entries'] if e['id'] == 'subfo.')
        entry['writes'].append('XER.CA')
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract operand/flag'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_neg_reserved_mask_mutation_rejected(self):
        entry = next(e for e in self.spec['decode_entries'] if e['id'] == 'neg')
        entry['mask'] = '0xfc0007ff'
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract encoding/reserved'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_subtract_direction_profile_mutation_rejected(self):
        self.spec['subtract_family_semantics']['profiles'][0]['expression'] = 'u32(rA-rB)'
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract semantic'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_subfc_encoding_and_required_carry(self):
        entries = [e for e in self.spec['decode_entries'] if e.get('family') == 'subfc']
        self.assertEqual(len(entries), 4)
        for entry in entries:
            oe, rc = (int(entry['modifiers'][k][-1]) for k in ('OE', 'Rc'))
            word = program.Program().encode(0, 'subfc', (7, 0, 9, oe, rc))
            self.assertTrue(isa_generate.decode_matches(entry, word))
            self.assertIn('XER.CA', entry['writes'])
        entries[0]['writes'].remove('XER.CA')
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract operand/flag'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_subfc_literal_no_borrow_ignores_old_carry(self):
        anchors = [(0, 0, 0, 1), (1, 0, 0xffffffff, 0),
                   (0, 1, 1, 1), (0xffffffff, 0xffffffff, 0, 1),
                   (0x80000000, 0x7fffffff, 0xffffffff, 0)]
        for old_ca in (0, 1):
            for a, b, result, new_ca in anchors:
                p = program.Program()
                p.emit('addis', 18, 0, 0x8000 if old_ca else 0)
                p.emit('addco', 20, 18, 18)
                for reg, value in ((9, a), (10, b)):
                    p.emit('addis', reg, 0, value >> 16)
                    p.emit('ori', reg, reg, value & 65535)
                p.emit('subfc', 11, 9, 10, 0, 0)
                p.emit('illegal')
                rows, _ = p.simulate()
                self.assertEqual(rows[-1][13], result)
                self.assertEqual(rows[-1][35], (0xc0000000 if old_ca else 0) | (new_ca << 29))

    def test_subfe_encodings_require_carry_operand(self):
        entries = [e for e in self.spec['decode_entries'] if e.get('family') == 'subfe']
        self.assertEqual(len(entries), 4)
        for entry in entries:
            oe, rc = (int(entry['modifiers'][k][-1]) for k in ('OE', 'Rc'))
            self.assertTrue(isa_generate.decode_matches(entry, program.Program().encode(0, 'subfe', (7, 0, 9, oe, rc))))
            self.assertIn('XER.CA', entry['operands'])
        entries[0]['operands'].remove('XER.CA')
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract operand/flag'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_subfe_literal_carry_adjusted_overflow(self):
        # CA, A, B, result, output CA, overflow: mathematical boundary anchors.
        anchors = [(0, 0, 0, 0xffffffff, 0, 0), (1, 0, 0, 0, 1, 0),
                   (0, 0x80000000, 0, 0x7fffffff, 0, 0),
                   (1, 0x80000000, 0, 0x80000000, 0, 1),
                   (0, 0x80000000, 0xffffffff, 0x7ffffffe, 1, 0),
                   (1, 0x80000000, 0xffffffff, 0x7fffffff, 1, 0),
                   (0, 0x7fffffff, 0x80000000, 0, 1, 1)]
        for carry, a, b, result, out_carry, overflow in anchors:
            p = program.Program()
            p.emit('addis', 18, 0, 0x8000 if carry else 0)
            p.emit('addco', 20, 18, 18)
            for reg, value in ((9, a), (10, b)):
                p.emit('addis', reg, 0, value >> 16)
                p.emit('ori', reg, reg, value & 65535)
            p.emit('subfe', 11, 9, 10, 1, 1)
            p.emit('illegal')
            rows, _ = p.simulate()
            self.assertEqual(rows[-1][13], result)
            self.assertEqual(rows[-1][35], ((carry | overflow) << 31) | (overflow << 30) | (out_carry << 29))

    def test_unary_subtract_encodings_and_reserved_rb(self):
        entries = [e for e in self.spec['decode_entries'] if e.get('family') in ('subfme', 'subfze')]
        self.assertEqual(len(entries), 8)
        for entry in entries:
            oe, rc = (int(entry['modifiers'][k][-1]) for k in ('OE', 'Rc'))
            word = program.Program().encode(0, entry['family'], (7, 0, oe, rc))
            self.assertTrue(isa_generate.decode_matches(entry, word))
            self.assertEqual(entry['operands'], ['rA', 'XER.CA'])
            for rb in range(1, 32):
                self.assertFalse(isa_generate.decode_matches(entry, word | (rb << 11)))
        entries[0]['mask'] = '0xfc0007ff'
        with self.assertRaisesRegex(isa_generate.MetadataError, 'subtract encoding/reserved'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_unary_subtract_literal_carry_and_overflow(self):
        anchors = [('subfme', 0xffffffff, 0, 0xffffffff, 0, 0),
                   ('subfme', 0xffffffff, 1, 0, 1, 0),
                   ('subfme', 0x7fffffff, 0, 0x7fffffff, 1, 1),
                   ('subfme', 0x7fffffff, 1, 0x80000000, 1, 0),
                   ('subfze', 0, 0, 0xffffffff, 0, 0),
                   ('subfze', 0, 1, 0, 1, 0),
                   ('subfze', 0x80000000, 0, 0x7fffffff, 0, 0),
                   ('subfze', 0x80000000, 1, 0x80000000, 0, 1)]
        for op, a, carry, result, out_carry, overflow in anchors:
            p = program.Program()
            p.emit('addis', 18, 0, 0x8000 if carry else 0)
            p.emit('addco', 20, 18, 18)
            p.emit('addis', 9, 0, a >> 16)
            p.emit('ori', 9, 9, a & 65535)
            p.emit(op, 12, 9, 1, 1)
            p.emit('illegal')
            rows, _ = p.simulate()
            self.assertEqual(rows[-1][14], result)
            self.assertEqual(rows[-1][35], ((carry | overflow) << 31) | (overflow << 30) | (out_carry << 29))

    def test_subfic_all_immediate_bits_are_data(self):
        entry = next(e for e in self.spec['decode_entries'] if e['id'] == 'subfic')
        p = program.Program()
        for imm in range(65536):
            self.assertTrue(isa_generate.decode_matches(entry, p.encode(0, 'subfic', (7, 0, imm))))
        self.assertEqual(entry['writes'], ['rD', 'XER.CA'])
        entry['modifiers']['Rc'] = 'fixed_1'
        with self.assertRaisesRegex(isa_generate.MetadataError, 'SUBFIC encoding/operand/flags'):
            isa_generate.validate(self.spec, self.sources, self.timing)

    def test_subfic_signed_immediate_real_zero_register_and_flags(self):
        anchors = [(1, 0, 0xffffffff, 0), (0, 0xffff, 0xffffffff, 1),
                   (0xffffffff, 0xffff, 0, 1),
                   (0x80000000, 0x8000, 0x7fff8000, 1),
                   (0x80000000, 0x7fff, 0x80007fff, 0)]
        for old_ca in (0, 1):
            for a, imm, result, carry in anchors:
                p = program.Program()
                p.emit('addis', 18, 0, 0x8000 if old_ca else 0)
                p.emit('addco', 20, 18, 18)
                p.emit('addis', 0, 0, a >> 16)
                p.emit('ori', 0, 0, a & 65535)
                p.emit('cmpi', 7, 20, 0)
                p.emit('subfic', 0, 0, imm)
                p.emit('illegal')
                rows, _ = p.simulate()
                self.assertEqual(rows[-1][2], result)
                self.assertEqual(rows[-1][34], rows[-3][34])
                self.assertEqual(rows[-1][35], (0xc0000000 if old_ca else 0) | (carry << 29))

    def test_literal_overflow_and_carry_preservation(self):
        p = program.Program()
        p.emit('addis', 1, 0, 0x8000)
        p.emit('addco', 2, 1, 1)  # SO/OV/CA all set
        p.emit('neg', 3, 1, 1, 1)
        p.emit('subf', 4, 1, 1, 1, 1)  # zero, clear OV, preserve SO/CA
        p.emit('illegal')
        rows, _ = p.simulate()
        self.assertEqual((rows[2][5], rows[2][34], rows[2][35]), (0x80000000, 0x90000000, 0xe0000000))
        self.assertEqual((rows[3][6], rows[3][34], rows[3][35]), (0, 0x30000000, 0xa0000000))


if __name__ == '__main__':
    unittest.main()
