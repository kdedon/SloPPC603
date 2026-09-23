#!/usr/bin/env python3
import json
import unittest

import isa_generate
import shift_family


class ShiftFamilyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads(isa_generate.ISA_PATH.read_text())
        cls.entries = [
            entry for entry in cls.spec["decode_entries"]
            if entry.get("semantic_class") == "word_shift"
        ]

    def test_eight_concrete_encodings_match_independent_encoder(self):
        self.assertEqual(len(self.entries), 8)
        for entry in self.entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            word = shift_family.encode(entry["family"], rc=rc, rs=7, ra=13, rb_or_sh=31)
            self.assertEqual(word & int(entry["mask"], 16), int(entry["value"], 16), entry["id"])
            self.assertEqual(entry["implementation"]["status"], "implemented")
        self.assertEqual(
            shift_family.encode("srawi", rc=1, rs=7, ra=13, rb_or_sh=31),
            0x7CED_FE71,
        )

    def test_logical_counts_zero_thirty_one_and_32_through_63(self):
        slw_expected = {0: 0x0000_0001, 31: 0x8000_0000, 32: 0, 47: 0, 63: 0, 64: 1}
        srw_expected = {0: 0x8000_0000, 31: 1, 32: 0, 47: 0, 63: 0, 64: 0x8000_0000}
        for count, expected in slw_expected.items():
            self.assertEqual(shift_family.evaluate("slw", 1, count).value, expected)
        for count, expected in srw_expected.items():
            self.assertEqual(shift_family.evaluate("srw", 0x8000_0000, count).value, expected)

    def test_arithmetic_counts_and_carry_hand_anchors(self):
        anchors = (
            (0xF000_0001, 0, 0xF000_0001, 0),
            (0xF000_0001, 1, 0xF800_0000, 1),
            (0xF000_0000, 1, 0xF800_0000, 0),
            (0xF000_0008, 4, 0xFF00_0000, 1),
            (0xF000_0000, 4, 0xFF00_0000, 0),
            (0x8000_0000, 31, 0xFFFF_FFFF, 0),
            (0x8000_0000, 32, 0xFFFF_FFFF, 1),
            (0x8000_0000, 63, 0xFFFF_FFFF, 1),
            (0x7FFF_FFFF, 32, 0, 0),
        )
        for source, count, value, ca in anchors:
            result = shift_family.evaluate("sraw", source, count)
            self.assertEqual((result.value, result.ca), (value, ca), (source, count))

    def test_srawi_carry_matches_discarded_negative_one_bits(self):
        anchors = (
            (0xFFFF_FFFF, 0, 0xFFFF_FFFF, 0),
            (0xF000_0001, 1, 0xF800_0000, 1),
            (0xF000_0000, 1, 0xF800_0000, 0),
            (0x8000_0001, 31, 0xFFFF_FFFF, 1),
        )
        for source, count, value, ca in anchors:
            result = shift_family.evaluate("srawi", source, count)
            self.assertEqual((result.value, result.ca), (value, ca), (source, count))

    def test_xer_preservation_exceptions_and_cr0_current_so(self):
        logical = shift_family.evaluate("slw", 1, 1, rc=1, ca=1, ov=1, so=1)
        self.assertEqual(logical, shift_family.ShiftResult(2, 1, 1, 1, 0b0101))
        arithmetic = shift_family.evaluate("sraw", 0xF000_0001, 1, rc=1, ca=0, ov=1, so=1)
        self.assertEqual(arithmetic, shift_family.ShiftResult(0xF800_0000, 1, 1, 1, 0b1001))
        cleared_ca = shift_family.evaluate("srawi", 0x8000_0000, 0, rc=0, ca=1, ov=1, so=1, old_cr0=0b1010)
        self.assertEqual(cleared_ca, shift_family.ShiftResult(0x8000_0000, 0, 1, 1, 0b1010))

    def test_invalid_fields_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown"):
            shift_family.evaluate("bogus", 0, 0)
        with self.assertRaisesRegex(ValueError, "five-bit"):
            shift_family.evaluate("srawi", 0, 32)
        with self.assertRaisesRegex(ValueError, "five-bit"):
            shift_family.encode("slw", rc=0, rs=32, ra=0, rb_or_sh=0)
        with self.assertRaisesRegex(ValueError, "rc"):
            shift_family.encode("slw", rc=2, rs=0, ra=0, rb_or_sh=0)

    def test_anchor_vectors_are_deterministic(self):
        first, second = shift_family.anchor_vectors(), shift_family.anchor_vectors()
        self.assertEqual(first, second)
        for vector in first:
            shift_family.evaluate(**vector)


if __name__ == "__main__":
    unittest.main()
