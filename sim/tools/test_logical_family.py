#!/usr/bin/env python3
import json
import unittest

import isa_generate
import logical_family


class LogicalFamilyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads(isa_generate.ISA_PATH.read_text())
        cls.entries = [
            entry for entry in cls.spec["decode_entries"]
            if entry.get("semantic_class") == "register_logical"
        ]

    def test_sixteen_concrete_encodings_match_independent_encoder(self):
        self.assertEqual(len(self.entries), 16)
        for entry in self.entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            word = logical_family.encode(entry["family"], rc=rc, rs=7, ra=13, rb=29)
            self.assertEqual(word & int(entry["mask"], 16), int(entry["value"], 16), entry["id"])
            expected_status = "implemented"
            self.assertEqual(entry["implementation"]["status"], expected_status)
            self.assertEqual(
                entry["implementation"]["validation"],
                "accepted_core_record_logical_bench" if rc else "accepted_core_logical_bench",
            )

    def test_all_eight_boolean_functions(self):
        # Constants were calculated independently from the bit truth tables.
        expected = {
            "and": 0x00F0_050A,
            "andc": 0xF000_50A0,
            "or": 0xFFF0_F5FA,
            "orc": 0xF0FF_5FAF,
            "xor": 0xFF00_F0F0,
            "nand": 0xFF0F_FAF5,
            "nor": 0x000F_0A05,
            "eqv": 0x00FF_0F0F,
        }
        for family, value in expected.items():
            self.assertEqual(logical_family.evaluate(family, 0xF0F0_55AA, 0x0FF0_A55A).value, value)

    def test_literal_instruction_anchor_fixes_rs_ra_layout(self):
        self.assertEqual(
            logical_family.encode("and", rc=1, rs=7, ra=13, rb=29),
            0x7CED_E839,
        )

    def test_complement_results_are_limited_to_32_bits(self):
        self.assertEqual(logical_family.evaluate("nand", 0, 0).value, 0xFFFF_FFFF)
        self.assertEqual(logical_family.evaluate("nor", 0, 0).value, 0xFFFF_FFFF)
        self.assertEqual(logical_family.evaluate("eqv", 0, 0).value, 0xFFFF_FFFF)
        self.assertEqual(logical_family.evaluate("andc", 0xFFFF_FFFF, 0).value, 0xFFFF_FFFF)
        self.assertEqual(logical_family.evaluate("orc", 0, 0xFFFF_FFFF).value, 0)

    def test_xer_is_unchanged_and_cr0_uses_current_so(self):
        result = logical_family.evaluate("xor", 1, 1, rc=1, ca=1, ov=1, so=1)
        self.assertEqual(result, logical_family.LogicalResult(0, 1, 1, 1, 0b0011))
        negative = logical_family.evaluate("or", 0x8000_0000, 0, rc=1, so=1)
        positive = logical_family.evaluate("or", 1, 0, rc=1, so=0)
        self.assertEqual((negative.cr0, positive.cr0), (0b1001, 0b0100))
        preserved = logical_family.evaluate("and", 1, 1, rc=0, ca=1, ov=1, so=1, old_cr0=0b1010)
        self.assertEqual((preserved.ca, preserved.ov, preserved.so, preserved.cr0), (1, 1, 1, 0b1010))

    def test_encoder_rejects_invalid_fields(self):
        with self.assertRaisesRegex(ValueError, "unknown"):
            logical_family.encode("bogus", rc=0, rs=0, ra=0, rb=0)
        with self.assertRaisesRegex(ValueError, "five-bit"):
            logical_family.encode("and", rc=0, rs=32, ra=0, rb=0)
        with self.assertRaisesRegex(ValueError, "rc"):
            logical_family.encode("and", rc=2, rs=0, ra=0, rb=0)

    def test_anchor_vectors_are_deterministic_and_cover_every_family(self):
        first, second = logical_family.anchor_vectors(), logical_family.anchor_vectors()
        self.assertEqual(first, second)
        self.assertEqual({vector["family"] for vector in first}, set(logical_family.XO))
        for vector in first:
            logical_family.evaluate(**vector)


if __name__ == "__main__":
    unittest.main()
