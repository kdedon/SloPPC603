#!/usr/bin/env python3
"""Independent tests for the bounded MPC603e Tables 8-4 through 8-7 query."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

import bus_address  # noqa: E402


COUNTS = {
    "table_8_4_rows": 15,
    "table_8_4_byte_rows": 8,
    "table_8_4_halfword_rows": 4,
    "table_8_4_word_rows": 2,
    "table_8_4_doubleword_rows": 1,
    "table_8_5_start_cases": 8,
    "table_8_5_access_rows": 14,
    "table_8_5_aligned_cases": 2,
    "table_8_5_misaligned_cases": 6,
    "table_8_6_request_rows": 15,
    "table_8_6_data_beat_rows": 16,
    "table_8_6_byte_rows": 8,
    "table_8_6_halfword_rows": 4,
    "table_8_6_word_rows": 2,
    "table_8_6_doubleword_request_rows": 1,
    "table_8_7_start_cases": 8,
    "table_8_7_access_rows": 14,
    "table_8_7_aligned_cases": 2,
    "table_8_7_misaligned_cases": 6,
}

FOUR_BYTE_64 = {
    0: [(0, 4, "100", "000", [0, 1, 2, 3])],
    1: [(0, 3, "011", "001", [1, 2, 3]), (3, 1, "001", "100", [4])],
    2: [(0, 2, "010", "010", [2, 3]), (2, 2, "010", "100", [4, 5])],
    3: [(0, 1, "001", "011", [3]), (1, 3, "011", "100", [4, 5, 6])],
    4: [(0, 4, "100", "100", [4, 5, 6, 7])],
    5: [(0, 3, "011", "101", [5, 6, 7]), (3, 1, "001", "000", [0])],
    6: [(0, 2, "010", "110", [6, 7]), (2, 2, "010", "000", [0, 1])],
    7: [(0, 1, "001", "111", [7]), (1, 3, "011", "000", [0, 1, 2])],
}

FOUR_BYTE_32 = {
    0: [(0, 4, "100", "000", [0, 1, 2, 3])],
    1: [(0, 3, "011", "001", [1, 2, 3]), (3, 1, "001", "100", [0])],
    2: [(0, 2, "010", "010", [2, 3]), (2, 2, "010", "100", [0, 1])],
    3: [(0, 1, "001", "011", [3]), (1, 3, "011", "100", [0, 1, 2])],
    4: [(0, 4, "100", "100", [0, 1, 2, 3])],
    5: [(0, 3, "011", "101", [1, 2, 3]), (3, 1, "001", "000", [0])],
    6: [(0, 2, "010", "110", [2, 3]), (2, 2, "010", "000", [0, 1])],
    7: [(0, 1, "001", "111", [3]), (1, 3, "011", "000", [0, 1, 2])],
}


def chunks(result: dict) -> list[tuple[int, int, str, str, list[int]]]:
    start = result["request"]["address"]
    return [
        (
            access["address"] - start,
            access["transfer_size_bytes"],
            access["tsiz"],
            access["a29_31"],
            access["source_table_lane_marks"],
        )
        for access in result["accesses"]
    ]


class BusAddressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = bus_address.load_spec()

    def test_manifest_exact_counts_and_primary_pages(self) -> None:
        self.assertEqual(bus_address.validate(self.spec), COUNTS)
        self.assertEqual(self.spec["source"]["pdf_pages"], [323, 324, 325, 326, 327])
        self.assertTrue(self.spec["source"]["visually_checked"])
        self.assertEqual(
            [item["table"] for item in self.spec["tables_completed"]],
            ["8-4", "8-5", "8-6", "8-7"],
        )

    def test_every_aligned_64_bit_row_is_queryable(self) -> None:
        for row in self.spec["table_8_4_aligned_64"]:
            address = 0x1000 + int(row["a29_31"], 2)
            result = bus_address.query(address, row["transfer_size_bytes"], bus_width=64, spec=self.spec)
            self.assertEqual(result["access_count"], 1)
            access = result["accesses"][0]
            self.assertEqual(access["source_table"], "8-5" if row["transfer_size_bytes"] == 4 else "8-4")
            self.assertIn("8-4", access["source_table_rows"])
            self.assertEqual(access["address"], address)
            self.assertEqual(access["tsiz"], row["tsiz"])
            self.assertEqual(access["source_table_lane_marks"], row["source_table_lane_marks"])

    def test_all_four_byte_64_bit_decompositions(self) -> None:
        for offset, expected in FOUR_BYTE_64.items():
            result = bus_address.query(0x1000 + offset, 4, bus_width=64, spec=self.spec)
            self.assertEqual(chunks(result), expected, f"start offset {offset}")
            self.assertTrue(all(item["source_table"] == "8-5" for item in result["accesses"]))
        conflict = bus_address.query(0x1002, 4, bus_width=64, spec=self.spec)["accesses"][1]
        self.assertEqual(conflict["source_table_tsiz"], "011")
        self.assertEqual(conflict["tsiz"], "010")
        self.assertIn("provisional_normalization", conflict["tsiz_status"])

    def test_every_aligned_32_bit_row_and_physical_lane_is_queryable(self) -> None:
        expected_by_size = {
            1: {offset: [offset % 4] for offset in range(8)},
            2: {offset: [offset % 4, offset % 4 + 1] for offset in (0, 2, 4, 6)},
            4: {offset: [0, 1, 2, 3] for offset in (0, 4)},
            8: {0: [0, 1, 2, 3]},
        }
        signals = ["DH[0:7]", "DH[8:15]", "DH[16:23]", "DH[24:31]"]
        for size, offsets in expected_by_size.items():
            for offset, expected_lanes in offsets.items():
                result = bus_address.query(0x2000 + offset, size, bus_width=32, spec=self.spec)
                access = result["accesses"][0]
                self.assertEqual(access["source_table"], "8-6" if size != 4 else "8-7")
                self.assertIn("8-6", access["source_table_rows"])
                self.assertEqual(access["source_table_lane_marks"], expected_lanes)
                self.assertEqual(
                    access["source_table_active_data_signals"],
                    [signals[lane] for lane in expected_lanes],
                )
                self.assertNotIn("DL", "".join(access["source_table_active_data_signals"]))

    def test_all_four_byte_32_bit_decompositions_are_direct_table_8_7(self) -> None:
        for offset, expected in FOUR_BYTE_32.items():
            result = bus_address.query(0x3000 + offset, 4, bus_width=32, spec=self.spec)
            self.assertEqual(chunks(result), expected, f"start offset {offset}")
            self.assertIn("8-7", result["source_tables"])
            self.assertEqual(result["width_basis"], "direct_32_bit_table_rows")
            for access in result["accesses"]:
                self.assertEqual(access["source_table"], "8-7")
                self.assertEqual(access["data_beat_count"], 1)

    def test_raw_32_bit_lane_anomalies_and_normalizations_are_auditable(self) -> None:
        byte001 = bus_address.query(0x4001, 1, bus_width=32, spec=self.spec)["accesses"][0]
        self.assertEqual(byte001["source_table_lane_cells"], ["—", "A", "x", "—", "x", "x", "x", "x"])
        self.assertEqual(byte001["lane_cell_normalizations"][0]["source_conflict"], "T8-6-BYTE001-LANE2-SYMBOL")

        first001 = bus_address.query(0x4001, 4, bus_width=32, spec=self.spec)["accesses"][0]
        self.assertEqual(first001["source_table_lane_cells"][0], "")
        self.assertEqual(first001["lane_cell_normalizations"][0]["source_symbol"], "blank")

        second010 = bus_address.query(0x4002, 4, bus_width=32, spec=self.spec)["accesses"][1]
        self.assertEqual(second010["source_table_lane_cells"][:4], ["A", "A", "—", "x"])
        self.assertEqual(second010["lane_cell_normalizations"][0]["provisional_normalized_symbol"], "—")
        self.assertEqual(second010["source_table_lane_marks"], [0, 1])
        self.assertEqual(self.spec["source_conflicts"][0]["printed_tsiz"], "011")
        self.assertEqual(self.spec["source_conflicts"][0]["provisional_normalized_tsiz"], "010")

    def test_32_bit_doubleword_is_one_transaction_with_two_explicit_beats(self) -> None:
        result = bus_address.query(0x5000, 8, bus_width=32, spec=self.spec)
        self.assertEqual(result["access_count"], 1)
        access = result["accesses"][0]
        self.assertEqual(access["transfer_size_bytes"], 8)
        self.assertEqual(access["data_beat_count"], 2)
        beats = access["source_table_data_beats"]
        self.assertEqual([beat["sequence"] for beat in beats], ["first", "second"])
        self.assertEqual(
            [beat["source_table_row_label"] for beat in beats],
            ["Double word", "Second beat"],
        )
        self.assertEqual([beat["transfer_bytes"] for beat in beats], [4, 4])
        self.assertEqual([beat["source_table_data_bits"] for beat in beats], ["DH[0:31]", "DH[0:31]"])
        self.assertEqual([beat["a29_31"] for beat in beats], ["000", "000"])
        self.assertEqual([beat["tsiz"] for beat in beats], ["000", "000"])
        self.assertEqual([beat["source_table_lane_marks"] for beat in beats], [[0, 1, 2, 3]] * 2)
        self.assertTrue(all("address" not in beat for beat in beats))

    def test_query_makes_address_lane_and_endian_boundaries_explicit(self) -> None:
        result = bus_address.query(0x6003, 4, bus_width=32, spec=self.spec)
        self.assertEqual(result["address_domain"], "already_bus_side_32_bit_byte_address")
        self.assertIn("physical_data_bus_signal_groups", result["lane_result_scope"])
        self.assertIn("not_provided", result["operand_byte_to_lane_mapping"])
        self.assertEqual(result["endian_lane_steering"], "outside_scope")
        self.assertIn("cacheability", result["cpu_access_to_bus_prediction"])

    def test_crossing_flags_and_coherency_rule(self) -> None:
        ordinary = bus_address.query(0x00000003, 4, bus_width=64, spec=self.spec)
        self.assertTrue(ordinary["crosses_word_boundary"])
        self.assertFalse(ordinary["crosses_32_byte_boundary"])
        boundary = bus_address.query(0x0000001F, 4, bus_width=32, spec=self.spec)
        self.assertTrue(boundary["crosses_word_boundary"])
        self.assertTrue(boundary["crosses_32_byte_boundary"])
        self.assertIn("new address", boundary["coherency_boundary_action"])
        self.assertEqual([item["address"] for item in boundary["accesses"]], [0x1F, 0x20])

    def test_untranscribed_misaligned_sizes_are_scope_errors(self) -> None:
        for address, size, width in ((0x1001, 2, 32), (0x1001, 2, 64), (0x1001, 8, 32), (0x1001, 8, 64)):
            with self.subTest(address=address, size=size, width=width):
                with self.assertRaisesRegex(bus_address.ScopeError, "outside_selected_tables"):
                    bus_address.query(address, size, bus_width=width, spec=self.spec)

    def test_malformed_queries_are_rejected(self) -> None:
        invalid = [
            (-1, 4, 64),
            (0x1_0000_0000, 4, 64),
            (0xFFFFFFFF, 4, 64),
            (0x1000, 3, 64),
            (0x1000, True, 64),
            (0x1000, 4, 16),
            (0x1000, 4, 32.0),
            (0x1000, 4, True),
        ]
        for address, size, width in invalid:
            with self.subTest(address=address, size=size, width=width):
                with self.assertRaises(bus_address.AddressError):
                    bus_address.query(address, size, bus_width=width, spec=self.spec)

    def test_manifest_mutations_are_rejected_atomically(self) -> None:
        mutations = []
        for mutate in (
            lambda d: d["source"]["pdf_pages"].remove(327),
            lambda d: d["lane_signal_source"]["lane_to_data_signals"].update({"3": "DL[0:7]"}),
            lambda d: d["conventions"].update({"endian_scope": "infer little endian"}),
            lambda d: d["table_8_4_aligned_64"][0].update({"tsiz": "000"}),
            lambda d: d["table_8_5_four_byte_cases"][3]["accesses"][0].update({"source_table_lane_marks": [2]}),
            lambda d: d["table_8_6_aligned_32"][1]["source_table_lane_cells"].__setitem__(2, "—"),
            lambda d: d["table_8_6_aligned_32"][-1]["source_table_data_beats"][1].update({"a29_31": "100"}),
            lambda d: d["table_8_7_four_byte_cases"][2]["accesses"][1].update({"source_table_lane_marks": [0, 1, 2]}),
            lambda d: d["source_conflicts"].pop(),
            lambda d: d["expected_counts"].update({"table_8_6_data_beat_rows": 15}),
        ):
            changed = copy.deepcopy(self.spec)
            mutate(changed)
            mutations.append(changed)
        for index, mutated in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises(bus_address.AddressError):
                    bus_address.validate(mutated)

    def test_cli_query_is_deterministic_json(self) -> None:
        command = [
            sys.executable,
            str(HERE / "bus_address.py"),
            "query",
            "--address",
            "0x1003",
            "--size",
            "4",
            "--bus-width",
            "32",
        ]
        first = subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout
        second = subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout
        self.assertEqual(first, second)
        result = json.loads(first)
        self.assertEqual([item["address_hex"] for item in result["accesses"]], ["0x00001003", "0x00001004"])
        self.assertEqual(result["source_tables"], ["8-7"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
