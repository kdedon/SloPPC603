"""Literal ADDIC semantics and D-form modifier boundaries."""
import json
import unittest

import control_memory_program as program
import isa_generate


class AddImmediateTest(unittest.TestCase):
    def test_all_immediate_bits_and_record_permission(self):
        spec = json.loads(isa_generate.ISA_PATH.read_text())
        sources = json.loads(isa_generate.SOURCE_PATH.read_text())
        timing = json.loads(isa_generate.TIMING_PATH.read_text())
        entries = [e for e in spec['decode_entries'] if e.get('family') == 'addic']
        self.assertEqual(len(entries), 2)
        p = program.Program()
        for entry in entries:
            for imm in range(65536):
                self.assertTrue(isa_generate.decode_matches(entry, p.encode(0, entry['id'], (7, 0, imm))))
        next(e for e in entries if e['id'] == 'addic.')['writes'].remove('CR0')
        with self.assertRaisesRegex(isa_generate.MetadataError, 'ADDIC encoding/operand/flags'):
            isa_generate.validate(spec, sources, timing)

    def test_signed_immediate_real_r0_and_no_overflow_write(self):
        anchors = [(0x7fffffff, 1, 0x80000000, 0),
                   (0xffffffff, 1, 0, 1), (1, 0xffff, 0, 1),
                   (0, 0xffff, 0xffffffff, 0),
                   (0x80000000, 0x8000, 0x7fff8000, 1)]
        for old_ca in (0, 1):
            for op in ('addic', 'addic.'):
                for a, imm, result, carry in anchors:
                    p = program.Program()
                    p.emit('addis', 18, 0, 0x8000 if old_ca else 0)
                    p.emit('addco', 20, 18, 18)
                    p.emit('addis', 0, 0, a >> 16)
                    p.emit('ori', 0, 0, a & 65535)
                    p.emit('cmpi', 5, 20, 0)
                    p.emit(op, 0, 0, imm)
                    p.emit('illegal')
                    rows, _ = p.simulate()
                    self.assertEqual(rows[-1][2], result)
                    cr = rows[-3][34]
                    if op == 'addic.':
                        field = (8 if result & 0x80000000 else 4 if result else 2) | old_ca
                        cr = (cr & 0x0fffffff) | (field << 28)
                    self.assertEqual(rows[-1][34], cr)
                    self.assertEqual(rows[-1][35], (0xc0000000 if old_ca else 0) | (carry << 29))


if __name__ == '__main__':
    unittest.main()
