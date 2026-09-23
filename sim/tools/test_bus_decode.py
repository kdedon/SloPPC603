#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))
import bus_decode  # noqa: E402


class BusDecodeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = bus_decode.load_spec()

    def test_manifest_is_complete_for_selected_tables(self) -> None:
        counts = bus_decode.validate(self.spec)
        self.assertEqual(
            counts,
            {
                "tt_pattern_rows": 26,
                "tt_expanded_codes": 32,
                "tt_defined_expanded_codes": 19,
                "tt_reserved_expanded_codes": 13,
                "generic_master_generated_commands": 10,
                "pid7v_abe_overrides": 3,
                "listed_size_combinations": 9,
            },
        )

    def test_read_command_and_snoop_action(self) -> None:
        master = bus_decode.decode_tt("01010", role="master", spec=self.spec)
        self.assertEqual(master["command"], "read")
        self.assertEqual(master["generation_status"], "supported")
        self.assertEqual(master["master"]["transaction"], "single_beat_read")
        snoop = bus_decode.decode_tt("01010", role="snoop", spec=self.spec)
        self.assertEqual(snoop["action_on_hit"], "clean_or_flush")
        self.assertEqual(snoop["bus_transaction"], "single_beat_read_or_burst")

    def test_defined_bus_command_can_be_unsupported_for_master_generation(self) -> None:
        result = bus_decode.decode_tt("00000", role="master", spec=self.spec)
        self.assertEqual(result["encoding_status"], "defined")
        self.assertEqual(result["command"], "clean_block")
        self.assertEqual(result["generation_status"], "unsupported_by_profile")
        self.assertEqual(result["master"]["generation"], "not_generated")

    def test_pid7v_abe_overrides_generation_without_changing_bus_command(self) -> None:
        expected = {
            "00000": ("clean_block", ["dcbst"]),
            "00100": ("flush_block", ["dcbf"]),
            "01100": ("kill_block", ["dcbz", "dcbi"]),
        }
        for bits, (command, sources) in expected.items():
            with self.subTest(bits=bits):
                result = bus_decode.decode_tt(
                    bits, role="master", pid7v_abe=True, spec=self.spec
                )
                self.assertEqual(result["command"], command)
                self.assertEqual(result["profile"], "pid7v_abe")
                self.assertEqual(result["generation_status"], "supported")
                self.assertEqual(result["master"]["sources"], sources)

    def test_reserved_exact_and_dont_care_patterns_remain_distinct(self) -> None:
        exact = bus_decode.decode_tt("00101", role="master", spec=self.spec)
        self.assertEqual(exact["encoding_status"], "reserved")
        self.assertEqual(exact["matched_pattern"], "00101")
        self.assertEqual(exact["generation_status"], "reserved_encoding")
        wildcard = bus_decode.decode_tt("11001", role="master", spec=self.spec)
        self.assertEqual(wildcard["encoding_status"], "reserved")
        self.assertEqual(wildcard["matched_pattern"], "1XX01")
        self.assertEqual(wildcard["dont_care_bits"], [1, 2])

    def test_source_backed_snoop_actions(self) -> None:
        expected = {
            "01100": "kill_cancel_reservation",
            "00010": "flush_cancel_reservation",
            "00110": "kill_cancel_reservation",
            "01110": "flush",
            "01011": "clean",
        }
        for bits, action in expected.items():
            with self.subTest(bits=bits):
                self.assertEqual(
                    bus_decode.decode_tt(bits, role="snoop", spec=self.spec)["action_on_hit"],
                    action,
                )

    def test_all_table_7_5_combinations_decode(self) -> None:
        for item in self.spec["transfer_sizes"]["listed_combinations"]:
            with self.subTest(tbst=item["tbst"], tsiz=item["tsiz"]):
                result = bus_decode.decode_size(
                    item["tbst"], item["tsiz"], bus_width=64, spec=self.spec
                )
                self.assertEqual(result["status"], "defined")
                self.assertEqual(result["transfer_size_bytes"], item["transfer_size_bytes"])

    def test_bus_width_changes_burst_and_doubleword_beat_counts(self) -> None:
        burst64 = bus_decode.decode_size("asserted", "010", bus_width=64, spec=self.spec)
        burst32 = bus_decode.decode_size("asserted", "010", bus_width=32, spec=self.spec)
        self.assertEqual((burst64["transfer_size_bytes"], burst64["data_beats"]), (32, 4))
        self.assertEqual((burst32["transfer_size_bytes"], burst32["data_beats"]), (32, 8))
        size64 = bus_decode.decode_size("negated", "000", bus_width=64, spec=self.spec)
        size32 = bus_decode.decode_size("negated", "000", bus_width=32, spec=self.spec)
        self.assertEqual(size64["data_beats"], 1)
        self.assertEqual(size32["data_beats"], 2)
        for result in (burst64, burst32, size64, size32):
            self.assertEqual(result["address_alignment_status"], "not_checked")
            self.assertEqual(result["program_access_decomposition_status"], "not_checked")
            self.assertEqual(result["mode_status"], "defined_for_table_7_5_bus_transfer")

    def test_unresolved_32bit_size_is_not_guessed(self) -> None:
        result = bus_decode.decode_size("negated", "101", bus_width=32, spec=self.spec)
        self.assertEqual(result["transfer_size_bytes"], 5)
        self.assertEqual(result["mode_status"], "unresolved_without_alignment_tables")
        self.assertIsNone(result["data_beats"])

    def test_unlisted_asserted_tbst_combination_is_not_reserved_or_defined(self) -> None:
        result = bus_decode.decode_size("asserted", "011", bus_width=64, spec=self.spec)
        self.assertEqual(result["status"], "unlisted")
        self.assertIsNone(result["transfer_size_bytes"])

    def test_address_only_and_external_control_override_size_meaning(self) -> None:
        address_only = bus_decode.decode_size(
            "negated", "111", bus_width=64, context="address_only", spec=self.spec
        )
        self.assertEqual(address_only["status"], "not_applicable")
        external = bus_decode.decode_size(
            "asserted", "101", bus_width=64, context="external_control", spec=self.spec
        )
        self.assertEqual(external["status"], "defined_resource_id")
        self.assertEqual(external["resource_id_bits"], "0101")
        self.assertEqual(external["resource_id"], 5)

    def test_invalid_queries_and_overlapping_metadata_are_rejected(self) -> None:
        for bits in ("0101", "0101X", "abcde"):
            with self.subTest(bits=bits), self.assertRaises(bus_decode.DecodeError):
                bus_decode.decode_tt(bits, spec=self.spec)
        with self.assertRaises(bus_decode.DecodeError):
            bus_decode.decode_size("low", "010", bus_width=64, spec=self.spec)
        with self.assertRaises(bus_decode.DecodeError):
            bus_decode.decode_size("asserted", "01X", bus_width=64, spec=self.spec)
        with self.assertRaises(bus_decode.DecodeError):
            bus_decode.decode_size("negated", "010", bus_width=16, spec=self.spec)

        broken = copy.deepcopy(self.spec)
        duplicate = copy.deepcopy(broken["tt_commands"][0])
        duplicate["pattern"] = "XXXXX"
        duplicate["dont_care_bits"] = [0, 1, 2, 3, 4]
        broken["tt_commands"].append(duplicate)
        with self.assertRaisesRegex(bus_decode.DecodeError, "overlapping TT patterns"):
            bus_decode.validate(broken)

    def test_cli_is_deterministic_and_machine_readable(self) -> None:
        command = [
            sys.executable,
            str(bus_decode.ROOT / "sim/tools/bus_decode.py"),
            "tt",
            "10010",
            "--role",
            "master",
        ]
        first = subprocess.run(command, cwd=bus_decode.ROOT, text=True, capture_output=True)
        second = subprocess.run(command, cwd=bus_decode.ROOT, text=True, capture_output=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        decoded = json.loads(first.stdout)
        self.assertEqual(decoded["command"], "write_with_flush_atomic")
        self.assertEqual(decoded["master"]["sources"], ["stwcx."])


if __name__ == "__main__":
    unittest.main()
