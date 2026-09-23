#!/usr/bin/env python3
import json
import unittest

import compare_family
import isa_generate


class CompareFamilyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads(isa_generate.ISA_PATH.read_text())
        cls.entries = {
            entry["family"]: entry for entry in cls.spec["decode_entries"]
            if entry.get("semantic_class") == "compare_32bit"
        }

    def test_four_literal_encodings_match_metadata_masks(self):
        expected_words = {
            "cmp": 0x7E91_1800,
            "cmpi": 0x2E91_8001,
            "cmpl": 0x7E91_1840,
            "cmpli": 0x2A91_8001,
        }
        for family, expected in expected_words.items():
            rhs = 3 if family in {"cmp", "cmpl"} else 0x8001
            word = compare_family.encode(family, bf=5, ra=17, rhs=rhs)
            self.assertEqual(word, expected)
            entry = self.entries[family]
            self.assertTrue(isa_generate.decode_matches(entry, word))
            self.assertEqual(entry["implementation"]["status"], "implemented")

    def test_masks_accept_bf_but_reject_reserved_l_and_final_bits(self):
        for family, entry in self.entries.items():
            rhs = 19 if family in {"cmp", "cmpl"} else 0xA55A
            word = compare_family.encode(family, bf=0, ra=7, rhs=rhs)
            self.assertTrue(isa_generate.decode_matches(entry, word | (7 << 23)))
            self.assertFalse(isa_generate.decode_matches(entry, word | 0x0040_0000))
            self.assertFalse(isa_generate.decode_matches(entry, word | 0x0020_0000))
            if family in {"cmp", "cmpl"}:
                self.assertFalse(isa_generate.decode_matches(entry, word | 1))

    def test_signed_and_unsigned_relations_use_hand_anchors(self):
        signed = compare_family.evaluate("cmp", 0xFFFF_FFFF, 0)
        unsigned = compare_family.evaluate("cmpl", 0xFFFF_FFFF, 0)
        self.assertEqual((signed.field, unsigned.field), (0b1000, 0b0100))
        self.assertEqual(compare_family.evaluate("cmp", 0x8000_0000, 0x7FFF_FFFF).field, 0b1000)
        self.assertEqual(compare_family.evaluate("cmpl", 0x8000_0000, 0x7FFF_FFFF).field, 0b0100)
        self.assertEqual(compare_family.evaluate("cmp", 0xDEAD_BEEF, 0xDEAD_BEEF).field, 0b0010)

    def test_immediate_sign_and_zero_extension(self):
        self.assertEqual(compare_family.evaluate("cmpi", 0, 0xFFFF).field, 0b0100)
        self.assertEqual(compare_family.evaluate("cmpli", 0, 0xFFFF).field, 0b1000)
        self.assertEqual(compare_family.evaluate("cmpi", 0xFFFF_8000, 0x8000).field, 0b0010)
        self.assertEqual(compare_family.evaluate("cmpli", 0x0000_8000, 0x8000).field, 0b0010)

    def test_bf_replaces_only_selected_cr_field(self):
        self.assertEqual(
            compare_family.evaluate("cmp", 0xFFFF_FFFF, 0, bf=0, so=1, old_cr=0x1234_5678).cr,
            0x9234_5678,
        )
        self.assertEqual(
            compare_family.evaluate("cmp", 0xFFFF_FFFF, 0, bf=3, so=1, old_cr=0x1234_5678).cr,
            0x1239_5678,
        )
        self.assertEqual(
            compare_family.evaluate("cmp", 0xFFFF_FFFF, 0, bf=7, so=1, old_cr=0x1234_5678).cr,
            0x1234_5679,
        )

    def test_xer_is_unchanged_and_so_is_current_value(self):
        result = compare_family.evaluate(
            "cmpl", 7, 7, bf=2, ca=1, ov=1, so=1, old_cr=0xABCD_EF01
        )
        self.assertEqual(result, compare_family.CompareResult(0xAB3D_EF01, 0b0011, 1, 1, 1))

    def test_invalid_fields_and_l1_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown"):
            compare_family.evaluate("bogus", 0, 0)
        with self.assertRaisesRegex(ValueError, "three-bit"):
            compare_family.encode("cmp", bf=8, ra=0, rhs=0)
        with self.assertRaisesRegex(ValueError, "five-bit"):
            compare_family.encode("cmp", bf=0, ra=0, rhs=32)
        with self.assertRaisesRegex(ValueError, "16-bit"):
            compare_family.evaluate("cmpi", 0, 0x1_0000)
        with self.assertRaisesRegex(ValueError, "L=0"):
            compare_family.encode("cmpli", bf=0, ra=0, rhs=0, l=1)

    def test_anchor_vectors_are_deterministic_and_cover_all_forms(self):
        first, second = compare_family.anchor_vectors(), compare_family.anchor_vectors()
        self.assertEqual(first, second)
        self.assertEqual({vector["family"] for vector in first}, set(compare_family.ENCODINGS))
        for vector in first:
            compare_family.evaluate(**vector)


if __name__ == "__main__":
    unittest.main()
