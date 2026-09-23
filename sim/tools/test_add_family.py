#!/usr/bin/env python3
import json
import unittest

import add_family
import isa_generate


class AddFamilyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads(isa_generate.ISA_PATH.read_text())
        cls.entries = [entry for entry in cls.spec["decode_entries"] if entry.get("family") in add_family.XO]

    def test_twenty_concrete_encodings_match_independent_encoder(self):
        self.assertEqual(len(self.entries), 20)
        for entry in self.entries:
            oe = int(entry["modifiers"]["OE"][-1])
            rc = int(entry["modifiers"]["Rc"][-1])
            rb = 0 if entry["family"] in ("addme", "addze") else 9
            word = add_family.encode(entry["family"], oe=oe, rc=rc, rd=7, ra=8, rb=rb)
            mask, value = int(entry["mask"], 16), int(entry["value"], 16)
            self.assertEqual(word & mask, value, entry["id"])
        self.assertEqual(sum(entry["implementation"]["status"] == "implemented" for entry in self.entries), 20)

    def test_reserved_rb_is_part_of_mask_and_nonzero_is_rejected(self):
        for family in ("addme", "addze"):
            family_entries = [entry for entry in self.entries if entry["family"] == family]
            self.assertTrue(all(int(entry["mask"], 16) & 0x0000_F800 == 0x0000_F800 for entry in family_entries))
            self.assertTrue(all(entry["reserved_bits"][0]["incorrect_encoding"] == "boundedly_undefined" for entry in family_entries))
            with self.assertRaisesRegex(ValueError, "reserved"):
                add_family.encode(family, oe=0, rc=0, rd=1, ra=2, rb=1)

    def test_carry_and_carry_in_anchors(self):
        self.assertEqual(add_family.evaluate("add", 0xFFFF_FFFF, 1, ca=0).ca, 0)  # unchanged
        self.assertEqual(add_family.evaluate("addc", 0xFFFF_FFFF, 1).ca, 1)
        self.assertEqual(add_family.evaluate("adde", 0xFFFF_FFFF, 0, ca=1), add_family.AddResult(0, 1, 0, 0, 0))
        addme_without_carry = add_family.evaluate("addme", 0, ca=0)
        self.assertEqual((addme_without_carry.value, addme_without_carry.ca), (0xFFFF_FFFF, 0))
        addme_with_carry = add_family.evaluate("addme", 0, ca=1)
        self.assertEqual((addme_with_carry.value, addme_with_carry.ca), (0, 1))
        self.assertEqual(add_family.evaluate("addme", 1, ca=0).ca, 1)
        self.assertEqual(add_family.evaluate("addme", 0x1234_5678, ca=1).ca, 1)
        self.assertEqual(add_family.evaluate("addze", 0xFFFF_FFFF, ca=1).ca, 1)

    def test_signed_overflow_sticky_so_and_oe_preservation(self):
        positive = add_family.evaluate("add", 0x7FFF_FFFF, 1, oe=1)
        negative = add_family.evaluate("add", 0x8000_0000, 0xFFFF_FFFF, oe=1)
        self.assertEqual((positive.value, positive.ov, positive.so), (0x8000_0000, 1, 1))
        self.assertEqual((negative.value, negative.ov, negative.so), (0x7FFF_FFFF, 1, 1))
        sticky = add_family.evaluate("add", 1, 1, oe=1, old_so=1, old_ov=1)
        self.assertEqual((sticky.ov, sticky.so), (0, 1))
        disabled = add_family.evaluate("addc", 1, 1, oe=0, old_ov=1, old_so=1)
        self.assertEqual((disabled.ov, disabled.so), (1, 1))
        self.assertEqual(add_family.evaluate("adde", 0x7FFF_FFFF, 0, ca=1, oe=1).ov, 1)
        addme_overflow = add_family.evaluate("addme", 0x8000_0000, ca=0, oe=1)
        self.assertEqual((addme_overflow.value, addme_overflow.ov), (0x7FFF_FFFF, 1))
        self.assertEqual(add_family.evaluate("addze", 0x7FFF_FFFF, ca=1, oe=1).ov, 1)

    def test_cr0_uses_signed_result_and_final_so(self):
        self.assertEqual(add_family.evaluate("add", 0x7FFF_FFFF, 1, oe=1, rc=1).cr0, 0b1001)
        self.assertEqual(add_family.evaluate("add", 1, 0xFFFF_FFFF, rc=1).cr0, 0b0010)
        self.assertEqual(add_family.evaluate("add", 1, 1, rc=1, old_so=1).cr0, 0b0101)
        self.assertEqual(add_family.evaluate("add", 1, 1, rc=0, old_cr0=0b1010).cr0, 0b1010)

    def test_anchor_vectors_are_deterministic_and_cover_every_family(self):
        first, second = add_family.anchor_vectors(), add_family.anchor_vectors()
        self.assertEqual(first, second)
        self.assertEqual({vector["family"] for vector in first}, set(add_family.XO))
        for vector in first:
            add_family.evaluate(**vector)


if __name__ == "__main__":
    unittest.main()
