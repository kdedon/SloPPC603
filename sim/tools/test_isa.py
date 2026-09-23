#!/usr/bin/env python3
import copy
import subprocess
import unittest

import isa_generate


class IsaMetadataTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec, cls.sources, cls.timing = isa_generate.load_all()

    def test_metadata_and_generated_matrix_are_valid(self):
        isa_generate.validate(self.spec, self.sources, self.timing)
        self.assertEqual(
            isa_generate.MATRIX_PATH.read_text(),
            isa_generate.render(self.spec, self.sources),
        )

    def test_xer_defined_bits_and_user_aliases(self):
        contract = self.spec["supervisor_integration_semantics"]["xer_scope"]
        self.assertEqual(int(contract["defined_mask"], 16), (7 << 29) | 127)
        self.assertEqual(contract["privilege"], "user_or_supervisor")
        self.assertEqual(contract["read_opcodes"], [339, 371])

    def test_xer_contract_corruptions_are_rejected(self):
        for key, value in [("defined_mask", "0xe0000000"), ("privilege", "supervisor"),
                           ("read_opcodes", [339]), ("reserved_rc", 1)]:
            with self.subTest(key=key):
                broken = copy.deepcopy(self.spec)
                broken["supervisor_integration_semantics"]["xer_scope"][key] = value
                with self.assertRaisesRegex(isa_generate.MetadataError, "XER SPR access contract"):
                    isa_generate.validate(broken, self.sources, self.timing)

    def test_overlap_is_rejected_unless_explicitly_allowed(self):
        broken = copy.deepcopy(self.spec)
        alias = copy.deepcopy(broken["decode_entries"][0])
        alias["id"] = "addi-collision"
        alias["implementation"] = {"status": "pending", "reason": "test-only collision"}
        broken["decode_entries"].append(alias)
        with self.assertRaisesRegex(isa_generate.MetadataError, "overlapping decode masks"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken["allowed_overlaps"] = [{"entries": ["addi", "addi-collision"], "reason": "test-only exact alias"}]
        isa_generate.validate(broken, self.sources, self.timing)

    def test_invalid_schema_required_field_mask_and_timing_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        broken["schema_version"] = 2
        with self.assertRaisesRegex(isa_generate.MetadataError, "schema_version"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        del broken["decode_entries"][0]["primary_opcode"]
        with self.assertRaisesRegex(isa_generate.MetadataError, "primary_opcode"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["decode_entries"][0]["value"] = "0x38000001"
        with self.assertRaisesRegex(isa_generate.MetadataError, "outside mask"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["decode_entries"][0]["timing_row"] = "TIM-NOT-REAL"
        with self.assertRaisesRegex(isa_generate.MetadataError, "unknown timing row"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_current_rtl_subset_agrees_with_masks(self):
        result = subprocess.run(
            ["python3", str(isa_generate.ROOT / "sim/tools/isa_check_rtl.py")],
            cwd=isa_generate.ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            result.stdout,
            "PASS: 26048 compiled decoder probes, 935 accepted by metadata and RTL\n",
        )

    def test_add_family_expands_to_twenty_with_twenty_implemented_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("family") in {"add", "addc", "adde", "addme", "addze"}
        ]
        self.assertEqual(len(entries), 20)
        self.assertEqual({entry["family"] for entry in entries}, {"add", "addc", "adde", "addme", "addze"})
        self.assertEqual(
            {entry["id"] for entry in entries if entry["implementation"]["status"] == "implemented"},
            {"add", "add.", "addo", "addo.", "addc", "addc.", "addco", "addco.", "adde", "adde.", "addeo", "addeo.", "addme", "addme.", "addmeo", "addmeo.", "addze", "addze.", "addzeo", "addzeo."},
        )

    def test_register_logical_family_has_sixteen_implemented_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("semantic_class") == "register_logical"
        ]
        self.assertEqual(len(entries), 16)
        self.assertEqual(
            {entry["family"] for entry in entries},
            {"and", "andc", "or", "orc", "xor", "nand", "nor", "eqv"},
        )
        self.assertEqual(
            {entry["family"] for entry in entries if entry["implementation"]["status"] == "implemented"},
            {"and", "andc", "or", "orc", "xor", "nand", "nor", "eqv"},
        )
        self.assertTrue(all(
            entry["implementation"]["status"] == "implemented"
            for entry in entries
        ))

    def test_integer_unary_family_has_six_reserved_rb_rc_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("semantic_class") == "integer_unary"
        ]
        self.assertEqual(
            {entry["id"] for entry in entries},
            {"cntlzw", "cntlzw.", "extsb", "extsb.", "extsh", "extsh."},
        )
        expected = {
            "cntlzw": (26, "TIM-T64-025"),
            "extsb": (954, "TIM-T64-052"),
            "extsh": (922, "TIM-T64-051"),
        }
        for entry in entries:
            family = entry["family"]
            xo, timing = expected[family]
            rc = entry["id"].endswith(".")
            self.assertEqual(entry["mask"], "0xfc00ffff")
            self.assertEqual(int(entry["value"], 16), (31 << 26) | (xo << 1) | rc)
            self.assertEqual(entry["operands"], ["rS"])
            self.assertEqual(entry["writes"], ["rA"] + (["CR0"] if rc else []))
            self.assertEqual(entry["timing_row"], timing)
            self.assertEqual(entry["reserved_bits"][0]["field"], "rB")
            self.assertEqual(entry["reserved_bits"][0]["required"], 0)
            self.assertEqual(entry["implementation"]["status"], "implemented")
            self.assertEqual(entry["implementation"]["validation"], "accepted_unarylogical_benches")
            word = int(entry["value"], 16) | (17 << 21) | (9 << 16)
            self.assertTrue(isa_generate.decode_matches(entry, word))
            self.assertFalse(isa_generate.decode_matches(entry, word | (1 << 11)))
            self.assertFalse(isa_generate.decode_matches(entry, word ^ 1))

    def test_invalid_integer_unary_mask_xo_reserved_policy_and_effects_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cntlzw")
        entry["mask"] = "0xfc0007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "integer-unary mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "extsb.")
        entry["value"] = "0x7c000735"
        with self.assertRaisesRegex(isa_generate.MetadataError, "integer-unary mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "extsh")
        entry["reserved_bits"] = []
        with self.assertRaisesRegex(isa_generate.MetadataError, "reserved-rB policy"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "extsh.")
        entry["writes"].append("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        profile = next(item for item in broken["integer_unary_semantics"]["profiles"] if item["family"] == "cntlzw")
        profile["expression"] = "count_trailing_zeros_32(rS)"
        with self.assertRaisesRegex(isa_generate.MetadataError, "semantic profile"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "extsb")
        entry["timing_row"] = "TIM-T64-051"
        with self.assertRaisesRegex(isa_generate.MetadataError, "scope/timing/modifiers"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cntlzw.")
        entry["implementation"] = {"status": "pending", "reason": "test mutation"}
        with self.assertRaisesRegex(isa_generate.MetadataError, "six implemented forms"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_cr_transfer_masks_fields_and_profiles(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "cr_transfer"}
        self.assertEqual(set(entries), {"mfcr", "mtcrf"})
        mfcr = entries["mfcr"]
        self.assertEqual((mfcr["mask"], mfcr["value"]), ("0xfc1fffff", "0x7c000026"))
        for rd in (0, 1, 17, 31):
            word = int(mfcr["value"], 16) | (rd << 21)
            self.assertTrue(isa_generate.decode_matches(mfcr, word))
            self.assertFalse(isa_generate.decode_matches(mfcr, word | (1 << 20)))
            self.assertFalse(isa_generate.decode_matches(mfcr, word | (1 << 11)))
            self.assertFalse(isa_generate.decode_matches(mfcr, word | 1))
        mtcrf = entries["mtcrf"]
        self.assertEqual((mtcrf["mask"], mtcrf["value"]), ("0xfc100fff", "0x7c000120"))
        for rs, fxm in ((0, 0), (31, 0xff), (9, 0x81), (17, 0x3c)):
            word = int(mtcrf["value"], 16) | (rs << 21) | (fxm << 12)
            self.assertTrue(isa_generate.decode_matches(mtcrf, word))
            self.assertFalse(isa_generate.decode_matches(mtcrf, word | (1 << 20)))
            self.assertFalse(isa_generate.decode_matches(mtcrf, word | (1 << 11)))
            self.assertFalse(isa_generate.decode_matches(mtcrf, word | 1))
        self.assertTrue(all(entry["implementation"]["status"] == "implemented" for entry in entries.values()))
        self.assertTrue(all(entry["implementation"]["validation"] == "accepted_cr_transfer_benches" for entry in entries.values()))
        profile = next(item for item in self.spec["cr_transfer_semantics"]["profiles"]
                       if item["id"] == "CRXFER-mtcrf")
        self.assertIn("FXM[0] selects CR0", profile["field_mapping"])
        self.assertEqual(profile["FXM_zero"], "No CR field is selected; CR is unchanged.")
        self.assertEqual(self.spec["cr_transfer_semantics"]["profiles"][0]["preserved"], ["CR", "XER"])

    def test_invalid_cr_transfer_encoding_mapping_and_effects_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mfcr")
        entry["mask"] = "0xfc0007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "form/XO/mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mtcrf")
        entry["reserved_bits"] = entry["reserved_bits"][:1]
        with self.assertRaisesRegex(isa_generate.MetadataError, "reserved-bit policy"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        profile = next(item for item in broken["cr_transfer_semantics"]["profiles"] if item["id"] == "CRXFER-mtcrf")
        profile["field_mapping"] = "FXM[0] selects CR7"
        with self.assertRaisesRegex(isa_generate.MetadataError, "FXM-to-CR field mapping"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mfcr")
        entry["writes"] = ["CR"]
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mtcrf")
        entry["timing_row"] = "TIM-T63-010"
        with self.assertRaisesRegex(isa_generate.MetadataError, "scope/timing/modifiers"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        profile = next(item for item in broken["cr_transfer_semantics"]["profiles"] if item["id"] == "CRXFER-mtcrf")
        profile["FXM_zero"] = "CR0 is cleared"
        with self.assertRaisesRegex(isa_generate.MetadataError, "zero-FXM preservation"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mfcr")
        entry["implementation"] = {"status": "pending", "reason": "test mutation"}
        with self.assertRaisesRegex(isa_generate.MetadataError, "two implemented forms"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_cr_logical_exact_encodings_equations_and_effects(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "cr_logical"}
        expected = {
            "crand": (257, "a AND b"), "crandc": (129, "a AND NOT b"),
            "creqv": (289, "NOT (a XOR b)"), "crnand": (225, "NOT (a AND b)"),
            "crnor": (33, "NOT (a OR b)"), "cror": (449, "a OR b"),
            "crorc": (417, "a OR NOT b"), "crxor": (193, "a XOR b"),
        }
        self.assertEqual(set(entries), set(expected))
        profiles = {profile["family"]: profile
                    for profile in self.spec["cr_logical_semantics"]["profiles"]}
        for name, (xo, expression) in expected.items():
            entry = entries[name]
            self.assertEqual((entry["mask"], int(entry["value"], 16)),
                             ("0xfc0007ff", (19 << 26) | (xo << 1)))
            self.assertEqual(entry["operands"], ["CR[crbA]", "CR[crbB]"])
            self.assertEqual(entry["writes"], ["CR[crbD]"])
            self.assertEqual(entry["implementation"]["validation"],
                             "accepted_cr_logical_benches")
            self.assertEqual(profiles[name]["expression"], expression)
            for d, a, b in ((0, 0, 0), (31, 31, 31), (17, 0, 9), (3, 29, 3)):
                word = int(entry["value"], 16) | (d << 21) | (a << 16) | (b << 11)
                self.assertTrue(isa_generate.decode_matches(entry, word))
                self.assertFalse(isa_generate.decode_matches(entry, word | 1))
        self.assertIn("pre-instruction CR", self.spec["cr_logical_semantics"]["source_snapshot"])
        self.assertEqual(self.spec["cr_logical_semantics"]["preserved"],
                         ["all unselected CR bits", "GPR", "XER"])

    def test_invalid_cr_logical_encoding_equation_and_effects_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cror")
        entry["value"] = "0x4c000380"
        with self.assertRaisesRegex(isa_generate.MetadataError, "form/XO/mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "crand")
        entry["writes"] = ["CR"]
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/reserved"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        profile = next(item for item in broken["cr_logical_semantics"]["profiles"]
                       if item["id"] == "CRLOGIC-crandc")
        profile["expression"] = "a AND b"
        with self.assertRaisesRegex(isa_generate.MetadataError, "semantic profile"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "crxor")
        entry["implementation"]["validation"] = "unreviewed"
        with self.assertRaisesRegex(isa_generate.MetadataError, "validation marker"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_cr_state_transfer_encodings_reserved_fields_and_effects(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "cr_state_transfer"}
        self.assertEqual(set(entries), {"mcrf", "mcrxr"})
        self.assertEqual((entries["mcrf"]["mask"], entries["mcrf"]["value"]),
                         ("0xfc63ffff", "0x4c000000"))
        self.assertEqual((entries["mcrxr"]["mask"], entries["mcrxr"]["value"]),
                         ("0xfc7fffff", "0x7c000400"))
        for dest, source in ((0, 0), (7, 7), (3, 5)):
            word = int(entries["mcrf"]["value"], 16) | (dest << 23) | (source << 18)
            self.assertTrue(isa_generate.decode_matches(entries["mcrf"], word))
            for reserved in (1 << 22, 1 << 17, 1 << 11, 1):
                self.assertFalse(isa_generate.decode_matches(entries["mcrf"], word | reserved))
        for dest in (0, 3, 7):
            word = int(entries["mcrxr"]["value"], 16) | (dest << 23)
            self.assertTrue(isa_generate.decode_matches(entries["mcrxr"], word))
            for reserved in (1 << 22, 1 << 20, 1 << 11, 1):
                self.assertFalse(isa_generate.decode_matches(entries["mcrxr"], word | reserved))
        semantics = self.spec["cr_state_transfer_semantics"]
        self.assertIn("pre-instruction", semantics["mcrf"]["source_snapshot"])
        self.assertIn("commit atomically", semantics["mcrxr"]["atomic_ordering"])
        self.assertIn("reserved zero", semantics["mcrxr"]["reserved_bit_3"])
        self.assertEqual(entries["mcrxr"]["writes"],
                         ["CR[crfD]", "XER.SO", "XER.OV", "XER.CA"])
        self.assertTrue(all(entry["implementation"]["validation"] ==
                            "accepted_cr_state_benches" for entry in entries.values()))

    def test_invalid_cr_state_encoding_atomic_effects_and_provenance_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mcrf")
        entry["mask"] = "0xfc6007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "form/opcode/mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mcrxr")
        entry["writes"].remove("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/reserved"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["cr_state_transfer_semantics"]["mcrxr"]["atomic_ordering"] = "clear first"
        with self.assertRaisesRegex(isa_generate.MetadataError, "MCRXR semantic profile"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["cr_state_transfer_semantics"]["mcrxr"]["reserved_bit_3"] = "software value"
        with self.assertRaisesRegex(isa_generate.MetadataError, "MCRXR semantic profile"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.sources)
        broken["reviewed_cr_state_transfer"]["primary_encoding"][1]["pdf_page"] = 394
        with self.assertRaisesRegex(isa_generate.MetadataError, "primary source anchors"):
            isa_generate.validate(self.spec, broken, self.timing)

    def test_invalid_register_logical_encoding_is_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "orc.")
        entry["value"] = "0x7c00033b"
        with self.assertRaisesRegex(isa_generate.MetadataError, "XO/Rc encoding"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_word_rotate_family_has_six_implemented_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("semantic_class") == "word_rotate"
        ]
        self.assertEqual(len(entries), 6)
        self.assertEqual({entry["family"] for entry in entries}, {"rlwimi", "rlwinm", "rlwnm"})
        self.assertEqual({entry["id"] for entry in entries if entry["implementation"]["status"] == "implemented"}, {"rlwinm", "rlwinm.", "rlwnm", "rlwnm.", "rlwimi", "rlwimi."})

    def test_invalid_word_rotate_mask_is_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "rlwnm.")
        entry["mask"] = "0xfc0007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "M-form mask"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_word_shift_family_expands_to_eight_implemented_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("semantic_class") == "word_shift"
        ]
        self.assertEqual(len(entries), 8)
        self.assertEqual({entry["family"] for entry in entries}, {"slw", "srw", "sraw", "srawi"})
        self.assertEqual({entry["id"] for entry in entries if entry["implementation"]["status"] == "implemented"}, {"slw", "slw.", "srw", "srw.", "sraw", "sraw.", "srawi", "srawi."})

    def test_invalid_word_shift_side_effect_is_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "sraw")
        entry["writes"].remove("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "shift Rc/CA semantics"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_compare_family_has_four_implemented_l0_forms(self):
        entries = [
            entry for entry in self.spec["decode_entries"]
            if entry.get("semantic_class") == "compare_32bit"
        ]
        self.assertEqual(len(entries), 4)
        self.assertEqual({entry["family"] for entry in entries}, {"cmp", "cmpi", "cmpl", "cmpli"})
        self.assertTrue(all(entry["implementation"]["status"] == "implemented" for entry in entries))
        self.assertTrue(all(entry["field_constraints"][0]["required"] == 0 for entry in entries))

    def test_invalid_compare_mask_reserved_policy_and_l_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cmp")
        entry["mask"] = "0xfc0007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "compare mask/value"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cmpli")
        entry["reserved_bits"] = []
        with self.assertRaisesRegex(isa_generate.MetadataError, "reserved-bit policy"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "cmpi")
        entry["field_constraints"][0]["required"] = 1
        with self.assertRaisesRegex(isa_generate.MetadataError, "L=0 legality"):
            isa_generate.validate(broken, self.sources, self.timing)

    def test_source_inventory_is_bounded_and_complete(self):
        rows = self.sources["appendix_a_mnemonic_inventory"]
        self.assertEqual(len(rows), 226)
        self.assertEqual({row["pdf_page"] for row in rows}, set(range(361, 369)))
        self.assertEqual(self.sources["inventory_status_counts"]["primary_opcode_only_pending_full_mask"], 124)
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_supervisor_opt_in_exact_form"},
            {"A1-127", "A1-155", "A1-165"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_serialization_opt_in_exact_form"},
            {"A1-044", "A1-083", "A1-214"},
        )
        for mnemonic in ("addi", "addis", "ori", "oris", "xori", "xoris"):
            row = next(row for row in rows if row["source_spelling"].split()[0] == mnemonic)
            self.assertEqual(row["encoding_status"], "reviewed_current_rtl_decode_entry")
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_integer_unary_2_Rc_forms"},
            {"A1-023", "A1-046", "A1-047"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_cr_transfer_exact_forms"},
            {"A1-125", "A1-132"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_cr_logical_exact_forms"},
            {f"A1-{row:03d}" for row in range(24, 32)},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_cr_state_transfer_exact_forms"},
            {"A1-122", "A1-124"},
        )

    def test_supervisor_profile_is_explicitly_opt_in(self):
        rows = self.sources["appendix_a_mnemonic_inventory"]
        base = {"sc", "rfi", "mfmsr", "mfsrr0", "mfsrr1", "mtsrr0", "mtsrr1"}
        sprg = {f"{direction}sprg{index}"
                for index in range(4) for direction in ("mf", "mt")}
        expected = base | sprg
        entries = {
            entry["id"]: entry for entry in self.spec["decode_entries"]
            if entry["implementation"]["status"] == "implemented_opt_in_supervisor"
        }
        self.assertEqual(set(entries), expected)
        self.assertTrue(all(
            entry["implementation"]["feature_profile"] == "ENABLE_SUPERVISOR_EXCEPTIONS" and
            entry["implementation"]["validation"] == "accepted_supervisor_integration_benches"
            for name, entry in entries.items() if name in base
        ))
        self.assertTrue(all(
            entry["implementation"]["feature_profile"] == "ENABLE_SUPERVISOR_EXCEPTIONS" and
            entry["implementation"]["validation"] == "accepted_sprg_integration_benches"
            for name, entry in entries.items() if name in sprg
        ))
        default_ids = {
            entry["id"] for entry in self.spec["decode_entries"]
            if entry["implementation"]["status"] == "implemented"
        }
        self.assertEqual(len(default_ids), 168)
        self.assertTrue(default_ids.isdisjoint(expected))
        self.assertEqual(self.spec["supervisor_integration_semantics"]["concrete_forms"], 15)
        self.assertEqual(
            self.spec["supervisor_integration_semantics"]["sprg_scope"]["selectors"],
            [272, 273, 274, 275],
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_multiply_low_family"},
            {"A1-146", "A1-147"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_multiply_high_family"},
            {"A1-143", "A1-144"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_divwu_family"},
            {"A1-041"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_divw_family"},
            {"A1-040"},
        )
        self.assertEqual(
            {row["row_id"] for row in rows if row["encoding_status"] == "reviewed_lsu_update_exact_forms"},
            {"A1-085", "A1-086", "A1-102", "A1-103", "A1-107", "A1-108",
             "A1-119", "A1-120", "A1-177", "A1-178", "A1-196", "A1-197",
             "A1-205", "A1-206"},
        )

    def test_sprg_aliases_have_exact_swapped_selectors_and_effects(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "sprg_integration"}
        self.assertEqual(len(entries), 8)
        for index in range(4):
            spr = 272 + index
            for direction, xo, timing in (("mf", 339, "TIM-T62-010"),
                                           ("mt", 467, "TIM-T62-012")):
                name = f"{direction}sprg{index}"
                entry = entries[name]
                value = ((31 << 26) | ((spr & 31) << 16) |
                         ((spr >> 5) << 11) | (xo << 1))
                self.assertEqual((entry["mask"], int(entry["value"], 16)),
                                 ("0xfc1fffff", value))
                self.assertEqual((entry["spr"], entry["privilege"], entry["timing_row"]),
                                 (spr, "supervisor", timing))
                self.assertEqual(entry["writes"],
                                 ["rD"] if direction == "mf" else [f"SPRG{index}"])
        reviewed = self.sources["reviewed_supervisor_integration"]
        self.assertEqual(reviewed["sprg_selectors"], [272, 273, 274, 275])
        self.assertEqual(reviewed["sprg_sources"][0]["pdf_pages"], [177, 178])
        self.assertEqual(reviewed["sprg_sources"][1]["pdf_page"], 95)
        self.assertEqual(reviewed["sprg_sources"][2]["pdf_pages"], [568, 585])

    def test_invalid_sprg_selector_effect_and_source_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        next(entry for entry in broken["decode_entries"]
             if entry["id"] == "mtsprg2")["value"] = "0x7c1242a6"
        with self.assertRaisesRegex(isa_generate.MetadataError, "SPRG selector"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        next(entry for entry in broken["decode_entries"]
             if entry["id"] == "mfsprg1")["writes"] = ["SPRG1"]
        with self.assertRaisesRegex(isa_generate.MetadataError, "SPRG selector"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_supervisor_integration"]["sprg_sources"][2]["pdf_pages"] = [568, 584]
        with self.assertRaisesRegex(isa_generate.MetadataError, "reviewed supervisor source"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_serialization_profile_is_exact_and_opt_in(self):
        expected = {"isync", "sync", "eieio"}
        entries = {
            entry["id"]: entry for entry in self.spec["decode_entries"]
            if entry["implementation"]["status"] == "implemented_opt_in_serialization"
        }
        self.assertEqual(set(entries), expected)
        self.assertEqual(
            {name: (entry["mask"], entry["value"]) for name, entry in entries.items()},
            {
                "isync": ("0xffffffff", "0x4c00012c"),
                "sync": ("0xffffffff", "0x7c0004ac"),
                "eieio": ("0xffffffff", "0x7c0006ac"),
            },
        )
        self.assertTrue(all(
            entry["implementation"]["feature_profile"] == "ENABLE_SUPERVISOR_EXCEPTIONS" and
            entry["implementation"]["validation"] == "accepted_serialization_integration_benches" and
            not entry["writes"] and not entry["operands"]
            for entry in entries.values()
        ))

    def test_multiply_low_exact_encodings_effects_and_timing_boundary(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "multiply_low"}
        self.assertEqual(set(entries), {"mulli", "mullw", "mullw.", "mullwo", "mullwo."})
        self.assertEqual((entries["mulli"]["mask"], entries["mulli"]["value"]),
                         ("0xfc000000", "0x1c000000"))
        self.assertEqual(entries["mulli"]["operands"], ["rA", "EXTS(SIMM16)"])
        self.assertEqual(entries["mulli"]["writes"], ["rD"])
        for name, oe, rc in (("mullw", 0, 0), ("mullw.", 0, 1),
                             ("mullwo", 1, 0), ("mullwo.", 1, 1)):
            entry = entries[name]
            self.assertEqual((entry["mask"], int(entry["value"], 16)),
                             ("0xfc0007ff", (31 << 26) | (oe << 10) | (235 << 1) | rc))
            self.assertNotIn("XER.CA", entry["writes"])
            self.assertEqual(entry["implementation"]["validation"],
                             "accepted_multiply_low_benches")
        semantics = self.spec["multiply_low_semantics"]
        self.assertIn("complete signed product", semantics["profiles"][1]["overflow"])
        self.assertIn("MULLI 3", semantics["implementation_timing"])
        self.assertIn("MULLW 5", semantics["implementation_timing"])
        self.assertIn("accepted finish at E+N", semantics["implementation_timing"])
        self.assertIn("does not complete P08", semantics["implementation_timing"])

    def test_invalid_multiply_encoding_effects_and_sources_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mullwo.")
        entry["writes"].append("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/modifiers"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mulli")
        entry["mask"] = "0xfc0007ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "multiply-low encoding"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["multiply_low_semantics"]["implementation_timing"] = "cycle exact"
        with self.assertRaisesRegex(isa_generate.MetadataError, "bounded timing contract"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_multiply_low_family"]["primary_encoding"][2]["pdf_page"] = 391
        with self.assertRaisesRegex(isa_generate.MetadataError, "primary source anchors"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_multiply_high_exact_encodings_reserved_oe_and_result_contract(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "multiply_high"}
        self.assertEqual(set(entries), {"mulhw", "mulhw.", "mulhwu", "mulhwu."})
        for family, xo in (("mulhw", 75), ("mulhwu", 11)):
            for rc in (0, 1):
                entry = entries[family + ("." if rc else "")]
                self.assertEqual(entry["form"], "XO")
                self.assertEqual((entry["mask"], int(entry["value"], 16)),
                                 ("0xfc0007ff", (31 << 26) | (xo << 1) | rc))
                self.assertEqual(entry["modifiers"]["OE"], "reserved_0")
                self.assertEqual(entry["reserved_bits"][0]["word_bit"], "10")
                self.assertNotIn("XER.CA", entry["writes"])
                self.assertNotIn("XER.OV", entry["writes"])
                self.assertEqual(entry["implementation"]["validation"],
                                 "accepted_multiply_high_benches")
        semantics = self.spec["multiply_high_semantics"]
        self.assertIn("signed interpretation", semantics["flag_rule"])
        self.assertIn("MULHW 5", semantics["implementation_timing"])
        self.assertIn("MULHWU 6", semantics["implementation_timing"])
        self.assertIn("accepted finish at E+N", semantics["implementation_timing"])
        self.assertIn("does not complete P08", semantics["implementation_timing"])

    def test_invalid_multiply_high_reserved_bit_effects_and_sources_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mulhwu.")
        entry["mask"] = "0xfc0003ff"
        with self.assertRaisesRegex(isa_generate.MetadataError, "multiply-high encoding"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "mulhw")
        entry["writes"].append("XER.OV")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/reserved bit"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["multiply_high_semantics"]["flag_rule"] = "unsigned CR comparison"
        with self.assertRaisesRegex(isa_generate.MetadataError, "reserved-bit, flag, or timing"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_multiply_high_family"]["primary_encoding"][2]["pdf_page"] = 395
        with self.assertRaisesRegex(isa_generate.MetadataError, "source anchors"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_divwu_exact_forms_flags_and_explicit_zero_policy(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "divide_unsigned"}
        self.assertEqual(set(entries), {"divwu", "divwu.", "divwuo", "divwuo."})
        for name, oe, rc in (("divwu", 0, 0), ("divwu.", 0, 1),
                             ("divwuo", 1, 0), ("divwuo.", 1, 1)):
            entry = entries[name]
            self.assertEqual((entry["form"], entry["extended_opcode"]), ("XO", 459))
            self.assertEqual((entry["mask"], int(entry["value"], 16)),
                             ("0xfc0007ff", (31 << 26) | (oe << 10) | (459 << 1) | rc))
            self.assertNotIn("XER.CA", entry["writes"])
            self.assertEqual(entry["implementation"]["validation"], "accepted_divwu_benches")
            self.assertIn("architecturally_undefined", entry["implementation"]["zero_divisor_policy"])
            self.assertIn("rtl/ppc_divider.sv", entry["implementation"]["rtl"])
            self.assertIn("radix4_restoring_16_steps", entry["implementation"]["timing"])
        semantics = self.spec["divide_unsigned_semantics"]
        self.assertIn("undefined", semantics["zero_divisor_architecture"])
        self.assertIn("local policy", semantics["zero_divisor_local_policy"])
        self.assertIn("detects rB=0", semantics["zero_divisor_local_policy"])
        self.assertIn("16-step radix-4", semantics["implementation_timing"])
        self.assertIn("20 execute cycles", semantics["implementation_timing"])
        self.assertIn("37 when configured", semantics["implementation_timing"])
        self.assertIn("does not complete all P08", semantics["implementation_timing"])

    def test_invalid_divwu_encoding_policy_and_sources_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "divwuo.")
        entry["extended_opcode"] = 491
        with self.assertRaisesRegex(isa_generate.MetadataError, "DIVWU encoding"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "divwu")
        entry["writes"].append("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/modifiers"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["divide_unsigned_semantics"]["zero_divisor_local_policy"] = "host division"
        with self.assertRaisesRegex(isa_generate.MetadataError, "undefined-result policy"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_divwu_family"]["primary_encoding"][2]["pdf_page"] = 395
        with self.assertRaisesRegex(isa_generate.MetadataError, "source anchors"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_divw_exact_forms_flags_and_exception_policy(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "divide_signed"}
        self.assertEqual(set(entries), {"divw", "divw.", "divwo", "divwo."})
        for name, oe, rc in (("divw", 0, 0), ("divw.", 0, 1),
                             ("divwo", 1, 0), ("divwo.", 1, 1)):
            entry = entries[name]
            self.assertEqual((entry["form"], entry["extended_opcode"]), ("XO", 491))
            self.assertEqual((entry["mask"], int(entry["value"], 16)),
                             ("0xfc0007ff", (31 << 26) | (oe << 10) | (491 << 1) | rc))
            self.assertNotIn("XER.CA", entry["writes"])
            self.assertEqual(entry["implementation"]["validation"], "accepted_divw_benches")
            self.assertIn("architecturally_undefined", entry["implementation"]["exception_policy"])
            self.assertIn("rtl/ppc_divider.sv", entry["implementation"]["rtl"])
            self.assertIn("radix4_restoring_16_steps", entry["implementation"]["timing"])
        semantics = self.spec["divide_signed_semantics"]
        self.assertIn("truncated toward zero", semantics["normal_result"])
        self.assertIn("INT_MIN", semantics["exception_architecture"])
        self.assertIn("detects both", semantics["exception_local_policy"])
        self.assertIn("16-step radix-4", semantics["implementation_timing"])
        self.assertIn("20 execute cycles", semantics["implementation_timing"])
        self.assertIn("37 when configured", semantics["implementation_timing"])
        self.assertIn("does not complete all P08", semantics["implementation_timing"])

    def test_invalid_divw_encoding_policy_and_sources_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "divwo.")
        entry["extended_opcode"] = 459
        with self.assertRaisesRegex(isa_generate.MetadataError, "DIVW encoding"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        entry = next(item for item in broken["decode_entries"] if item["id"] == "divw")
        entry["writes"].append("XER.CA")
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands/writes/modifiers"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        broken["divide_signed_semantics"]["exception_local_policy"] = "evaluate signed division"
        with self.assertRaisesRegex(isa_generate.MetadataError, "exceptional-result policy"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_divw_family"]["primary_encoding"][2]["pdf_page"] = 395
        with self.assertRaisesRegex(isa_generate.MetadataError, "source anchors"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_lsu_update_exact_forms_legality_and_atomic_effects(self):
        entries = {entry["id"]: entry for entry in self.spec["decode_entries"]
                   if entry.get("semantic_class") == "lsu_update"}
        self.assertEqual(set(entries), {
            "lbzu", "lbzux", "lhzu", "lhzux", "lhau", "lhaux", "lwzu", "lwzux",
            "stbu", "stbux", "sthu", "sthux", "stwu", "stwux",
        })
        for name, entry in entries.items():
            self.assertEqual(entry["implementation"]["validation"],
                             "accepted_lsu_update_benches")
            self.assertEqual(entry["field_constraints"][0]["rule"], "nonzero")
            self.assertIn("rA", entry["writes"])
            if entry["memory"]["kind"] == "load":
                self.assertEqual(entry["writes"], ["rD", "rA"])
                self.assertEqual(entry["field_constraints"][1]["rule"], "not_equal")
            else:
                self.assertEqual(entry["writes"], ["memory", "rA"])
            if entry["form"] == "X":
                self.assertEqual(entry["reserved_bits"][0]["required"], 0)
        semantics = self.spec["lsu_update_semantics"]
        self.assertIn("together", semantics["atomic_retirement"])
        self.assertIn("second speculative rename allocation",
                      semantics["implementation_scheduling"])

    def test_invalid_lsu_update_metadata_and_sources_are_rejected(self):
        broken = copy.deepcopy(self.spec)
        next(item for item in broken["decode_entries"]
             if item["id"] == "lwzux")["mask"] = "0xfc0007fe"
        with self.assertRaisesRegex(isa_generate.MetadataError, "exact encoding"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        next(item for item in broken["decode_entries"]
             if item["id"] == "lbzu")["field_constraints"] = []
        with self.assertRaisesRegex(isa_generate.MetadataError, "invalid-form rules"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken = copy.deepcopy(self.spec)
        next(item for item in broken["decode_entries"]
             if item["id"] == "stwu")["writes"] = ["memory"]
        with self.assertRaisesRegex(isa_generate.MetadataError, "operands, writes"):
            isa_generate.validate(broken, self.sources, self.timing)
        broken_sources = copy.deepcopy(self.sources)
        broken_sources["reviewed_lsu_update"]["secondary_instruction_pages"][0]["pdf_page"] = 1
        with self.assertRaisesRegex(isa_generate.MetadataError, "source anchors"):
            isa_generate.validate(self.spec, broken_sources, self.timing)

    def test_b3_exception_groups_do_not_treat_tlbia_as_floating_point(self):
        b3 = next(item for item in self.spec["appendix_b_exclusions"] if item["table"] == "B-3")
        exceptions = {
            mnemonic: group["exception"]
            for group in b3["exception_groups"]
            for mnemonic in group["mnemonics"]
        }
        self.assertEqual(exceptions["tlbia"], "pending_editorial_reconciliation")
        self.assertEqual(exceptions["fsqrt"], "floating_point_unavailable")
        self.assertEqual(exceptions["fsqrts"], "floating_point_unavailable")


if __name__ == "__main__":
    unittest.main()
