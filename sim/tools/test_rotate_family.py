#!/usr/bin/env python3
import json
import unittest

import isa_generate
import rotate_family


class RotateFamilyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads(isa_generate.ISA_PATH.read_text())
        cls.entries = [
            entry for entry in cls.spec["decode_entries"]
            if entry.get("semantic_class") == "word_rotate"
        ]

    def test_six_concrete_encodings_match_independent_encoder(self):
        self.assertEqual(len(self.entries), 6)
        for entry in self.entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            word = rotate_family.encode(entry["family"], rc=rc, rs=7, ra=13, sh_or_rb=31, mb=24, me=7)
            self.assertEqual(word & int(entry["mask"], 16), int(entry["value"], 16), entry["id"])
            self.assertEqual(entry["implementation"]["status"], "implemented")
        self.assertEqual(
            rotate_family.encode("rlwinm", rc=1, rs=7, ra=13, sh_or_rb=31, mb=24, me=7),
            0x54ED_FE0F,
        )

    def test_ppc_msb_numbering_and_wrapping_masks(self):
        hand_anchors = {
            (0, 31): 0xFFFF_FFFF,
            (0, 0): 0x8000_0000,
            (31, 31): 0x0000_0001,
            (8, 15): 0x00FF_0000,
            (24, 7): 0xFF00_00FF,
            (31, 0): 0x8000_0001,
        }
        for endpoints, expected in hand_anchors.items():
            self.assertEqual(rotate_family.ppc_mask(*endpoints), expected)

        # Independent bit-string interpretation: character zero is the numeric MSB.
        for mb in range(32):
            for me in range(32):
                selected = lambda bit: mb <= bit <= me if mb <= me else bit >= mb or bit <= me
                expected = int("".join("1" if selected(bit) else "0" for bit in range(32)), 2)
                self.assertEqual(rotate_family.ppc_mask(mb, me), expected, (mb, me))

    def test_rotation_zero_and_thirty_one(self):
        self.assertEqual(rotate_family.rotate_left(0x8000_0001, 0), 0x8000_0001)
        self.assertEqual(rotate_family.rotate_left(0x8000_0001, 31), 0xC000_0000)
        bits = f"{0x91A2_B3C4:032b}"
        for amount in range(32):
            expected = int(bits[amount:] + bits[:amount], 2)
            self.assertEqual(rotate_family.rotate_left(0x91A2_B3C4, amount), expected)

    def test_rlwimi_preserves_unmasked_destination(self):
        straight = rotate_family.evaluate("rlwimi", 0x1234_5678, 0, 8, 15, old_a=0xAAAA_5555)
        wrapped = rotate_family.evaluate("rlwimi", 0x1234_5678, 0, 24, 7, old_a=0xAABB_CCDD)
        self.assertEqual(straight.value, 0xAA34_5555)
        self.assertEqual(wrapped.value, 0x12BB_CC78)

    def test_rlwnm_uses_only_low_five_shift_bits(self):
        self.assertEqual(
            rotate_family.evaluate("rlwnm", 0x8000_0000, 0xFFFF_FFE1, 0, 31).value,
            0x0000_0001,
        )

    def test_cr0_uses_result_and_current_so_while_xer_is_unchanged(self):
        negative = rotate_family.evaluate("rlwinm", 0x8000_0000, 0, 0, 31, rc=1, ca=1, ov=1, so=1)
        zero = rotate_family.evaluate("rlwinm", 0, 31, 0, 31, rc=1, ca=1, ov=1, so=1)
        positive = rotate_family.evaluate("rlwinm", 1, 0, 0, 31, rc=1)
        self.assertEqual(negative, rotate_family.RotateResult(0x8000_0000, 1, 1, 1, 0b1001))
        self.assertEqual(zero, rotate_family.RotateResult(0, 1, 1, 1, 0b0011))
        self.assertEqual(positive.cr0, 0b0100)
        preserved = rotate_family.evaluate("rlwinm", 1, 0, 0, 31, rc=0, ca=1, ov=1, so=1, old_cr0=0b1010)
        self.assertEqual((preserved.ca, preserved.ov, preserved.so, preserved.cr0), (1, 1, 1, 0b1010))

    def test_invalid_fields_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "unknown"):
            rotate_family.evaluate("bogus", 0, 0, 0, 31)
        with self.assertRaisesRegex(ValueError, "mb"):
            rotate_family.ppc_mask(32, 0)
        with self.assertRaisesRegex(ValueError, "sh"):
            rotate_family.evaluate("rlwinm", 0, 32, 0, 31)
        with self.assertRaisesRegex(ValueError, "five-bit"):
            rotate_family.encode("rlwnm", rc=0, rs=0, ra=0, sh_or_rb=32, mb=0, me=31)

    def test_anchor_vectors_are_deterministic(self):
        first, second = rotate_family.anchor_vectors(), rotate_family.anchor_vectors()
        self.assertEqual(first, second)
        for vector in first:
            rotate_family.evaluate(**vector)


if __name__ == "__main__":
    unittest.main()
