#!/usr/bin/env python3
"""Validate and query the bounded MPC603e Tables 8-4 through 8-7 contract."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = ROOT / "sim/spec/bus_addressing.json"
MAX_ADDRESS = 0xFFFFFFFF


class AddressError(ValueError):
    """Raised for malformed queries or inconsistent metadata."""


class ScopeError(AddressError):
    """Raised when a valid query is outside the selected table rows."""


def load_spec(path: Path = SPEC_PATH) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def _bits(value: Any, width: int, field: str) -> str:
    if not isinstance(value, str) or len(value) != width or set(value) - {"0", "1"}:
        raise AddressError(f"{field} must be exactly {width} binary digits")
    return value


def _expected_aligned_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    tsiz = {1: "001", 2: "010", 4: "100", 8: "000"}
    for size in (1, 2, 4, 8):
        for offset in range(0, 8, size):
            rows.append(
                {
                    "transfer_size_bytes": size,
                    "tsiz": tsiz[size],
                    "a29_31": f"{offset:03b}",
                    "source_table_lane_marks": list(range(offset, offset + size)),
                }
            )
    return rows


def _expected_four_byte_case(offset: int) -> dict[str, Any]:
    tsiz = {1: "001", 2: "010", 3: "011", 4: "100"}
    if offset % 4 == 0:
        return {
            "start_a29_31": f"{offset:03b}",
            "alignment": "aligned",
            "accesses": [
                {
                    "sequence": "only",
                    "address_delta_bytes": 0,
                    "transfer_size_bytes": 4,
                    "tsiz": "100",
                    "a29_31": f"{offset:03b}",
                    "source_table_lane_marks": list(range(offset, offset + 4)),
                }
            ],
        }
    within_word = offset % 4
    first_size = 4 - within_word
    second_size = within_word
    second_offset = ((offset // 4) * 4 + 4) % 8
    result = {
        "start_a29_31": f"{offset:03b}",
        "alignment": "misaligned",
        "accesses": [
            {
                "sequence": "first",
                "address_delta_bytes": 0,
                "transfer_size_bytes": first_size,
                "tsiz": tsiz[first_size],
                "a29_31": f"{offset:03b}",
                "source_table_lane_marks": list(range(offset, offset + first_size)),
            },
            {
                "sequence": "second",
                "address_delta_bytes": first_size,
                "transfer_size_bytes": second_size,
                "tsiz": tsiz[second_size],
                "a29_31": f"{second_offset:03b}",
                "source_table_lane_marks": list(range(second_offset, second_offset + second_size)),
            },
        ],
    }
    if offset == 2:
        result["accesses"][1].update(
            {
                "source_table_tsiz": "011",
                "tsiz_status": "provisional_normalization_of_probable_manual_editorial_error",
                "source_conflict": "T8-5-OFFSET010-SECOND-TSIZ",
            }
        )
    return result


def _lane_cells(marks: list[int], *, width: int = 64) -> list[str]:
    """Return the ordinary table symbols; source anomalies are applied below."""
    return [
        "A" if lane in marks else ("—" if lane < width // 8 else "x")
        for lane in range(8)
    ]


def _expected_aligned_32_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    tsiz = {1: "001", 2: "010", 4: "100"}
    for size in (1, 2, 4):
        for offset in range(0, 8, size):
            marks = list(range(offset % 4, offset % 4 + size))
            cells = _lane_cells(marks, width=32)
            normalizations: list[dict[str, Any]] = []
            if size == 1 and offset == 1:
                cells[2] = "x"
                normalizations.append(
                    {
                        "lane": 2,
                        "source_symbol": "x",
                        "provisional_normalized_symbol": "—",
                        "source_conflict": "T8-6-BYTE001-LANE2-SYMBOL",
                    }
                )
            rows.append(
                {
                    "transfer_size_bytes": size,
                    "tsiz": tsiz[size],
                    "a29_31": f"{offset:03b}",
                    "data_beat_count": 1,
                    "source_table_lane_marks": marks,
                    "source_table_lane_cells": cells,
                    **(
                        {"lane_cell_normalizations": normalizations}
                        if normalizations
                        else {}
                    ),
                }
            )
    beat = {
        "tsiz": "000",
        "a29_31": "000",
        "transfer_bytes": 4,
        "source_table_data_bits": "DH[0:31]",
        "source_table_lane_marks": [0, 1, 2, 3],
        "source_table_lane_cells": ["A", "A", "A", "A", "x", "x", "x", "x"],
    }
    rows.append(
        {
            "transfer_size_bytes": 8,
            "tsiz": "000",
            "a29_31": "000",
            "data_beat_count": 2,
            "source_table_lane_marks": [0, 1, 2, 3],
            "source_table_lane_cells": beat["source_table_lane_cells"],
            "source_table_data_beats": [
                {
                    "sequence": "first",
                    "source_table_row_label": "Double word",
                    **copy.deepcopy(beat),
                },
                {
                    "sequence": "second",
                    "source_table_row_label": "Second beat",
                    **copy.deepcopy(beat),
                },
            ],
        }
    )
    return rows


def _expected_four_byte_32_case(offset: int) -> dict[str, Any]:
    """Reconstruct Table 8-7 independently of the stored metadata."""
    tsiz = {1: "001", 2: "010", 3: "011", 4: "100"}
    if offset % 4 == 0:
        chunks = [("only", 0, 4, offset)]
        alignment = "aligned"
    else:
        first_size = 4 - (offset % 4)
        chunks = [
            ("first", 0, first_size, offset),
            ("second", first_size, 4 - first_size, ((offset // 4) * 4 + 4) % 8),
        ]
        alignment = "misaligned"

    accesses = []
    for sequence, delta, size, a_offset in chunks:
        marks = list(range(a_offset % 4, a_offset % 4 + size))
        cells = _lane_cells(marks, width=32)
        normalizations: list[dict[str, Any]] = []
        if offset == 1 and sequence == "first":
            cells[0] = ""
            normalizations.append(
                {
                    "lane": 0,
                    "source_symbol": "blank",
                    "provisional_normalized_symbol": "—",
                    "source_conflict": "T8-7-OFFSET001-FIRST-LANE0-SYMBOL",
                }
            )
        if offset == 2 and sequence == "second":
            cells[3] = "x"
            normalizations.append(
                {
                    "lane": 3,
                    "source_symbol": "x",
                    "provisional_normalized_symbol": "—",
                    "source_conflict": "T8-7-OFFSET010-SECOND-LANE3-SYMBOL",
                }
            )
        accesses.append(
            {
                "sequence": sequence,
                "address_delta_bytes": delta,
                "transfer_size_bytes": size,
                "tsiz": tsiz[size],
                "a29_31": f"{a_offset:03b}",
                "data_beat_count": 1,
                "source_table_lane_marks": marks,
                "source_table_lane_cells": cells,
                **(
                    {"lane_cell_normalizations": normalizations}
                    if normalizations
                    else {}
                ),
            }
        )
    return {
        "start_a29_31": f"{offset:03b}",
        "alignment": alignment,
        "accesses": accesses,
    }


def _active_data_signals(lanes: list[int]) -> list[str]:
    signals = [
        "DH[0:7]",
        "DH[8:15]",
        "DH[16:23]",
        "DH[24:31]",
        "DL[0:7]",
        "DL[8:15]",
        "DL[16:23]",
        "DL[24:31]",
    ]
    return [signals[lane] for lane in lanes]


def validate(spec: dict[str, Any]) -> dict[str, int]:
    if spec.get("schema_version") != 1:
        raise AddressError(f"unsupported schema_version: {spec.get('schema_version')!r}")
    if spec.get("contract") != (
        "MPC603e Tables 8-4 through 8-7 address, size, and physical data-lane decomposition"
    ):
        raise AddressError("contract must name the bounded Tables 8-4 through 8-7 scope")
    if spec.get("source") != {
        "id": "UM",
        "path": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf",
        "sections": ["8.3.2.4", "8.3.2.5"],
        "pdf_pages": [323, 324, 325, 326, 327],
        "printed_pages": ["8-15", "8-16", "8-17", "8-18", "8-19"],
        "visually_checked": True,
    }:
        raise AddressError("primary source provenance must identify the visually checked pages")
    if spec.get("lane_signal_source") != {
        "section": "7.2.7.1, Table 7-7; 8.6.1",
        "pdf_pages": [295, 346],
        "printed_pages": ["7-19", "8-38"],
        "lane_to_data_signals": {
            "0": "DH[0:7]",
            "1": "DH[8:15]",
            "2": "DH[16:23]",
            "3": "DH[24:31]",
            "4": "DL[0:7]",
            "5": "DL[8:15]",
            "6": "DL[16:23]",
            "7": "DL[24:31]",
        },
        "scope": "physical signal groups only; operand byte order and endian steering are not specified by this mapping",
    }:
        raise AddressError("physical lane-to-signal provenance or scope differs from Tables 7-7/8.6.1")
    conventions = spec.get("conventions", {})
    for field in (
        "bit_numbering",
        "address",
        "table_lane_marks",
        "physical_lanes",
        "endian_scope",
        "decomposition",
        "doubleword_32",
        "scope_rejection",
    ):
        if not isinstance(conventions.get(field), str) or not conventions[field]:
            raise AddressError(f"conventions.{field} must be a nonempty scope statement")
    if "already bus-side" not in conventions["address"]:
        raise AddressError("address convention must retain the already bus-side input boundary")
    if "do not assign operand-byte significance" not in conventions["endian_scope"]:
        raise AddressError("endian scope must reject an inferred operand-byte mapping")
    completed = spec.get("tables_completed", [])
    if [item.get("table") for item in completed] != ["8-4", "8-5", "8-6", "8-7"]:
        raise AddressError("tables_completed must list exactly 8-4 through 8-7 in order")
    if completed[2:] != [
        {
            "table": "8-6",
            "title": "Aligned Data Transfers (32-Bit Bus Mode)",
            "pdf_page": 326,
            "printed_page": "8-18",
            "coverage": "all 15 aligned request rows, all 16 data-beat rows, and all rendered lane cells",
        },
        {
            "table": "8-7",
            "title": "Misaligned 32-Bit Data Bus Transfer (Four-Byte Examples)",
            "pdf_page": 327,
            "printed_page": "8-19",
            "coverage": "all eight starting A[29:31] values, all 14 resulting access rows, and all rendered lane cells",
        },
    ]:
        raise AddressError("Table 8-6/8-7 completion provenance or coverage differs")

    conflicts = spec.get("source_conflicts", [])
    if conflicts != [
        {
            "id": "T8-5-OFFSET010-SECOND-TSIZ",
            "location": "Table 8-5, start A[29:31]=010, second access",
            "printed_tsiz": "011",
            "lane_implied_transfer_size_bytes": 2,
            "printed_lane_marks": [4, 5],
            "provisional_normalized_tsiz": "010",
            "basis": "Table 8-1 maps two bytes to TSIZ=010; the row marks two lanes; the mirrored start A[29:31]=110 second access prints TSIZ=010; and the corresponding Table 8-7 row prints TSIZ=010.",
            "status": "probable_manual_editorial_error_preserved_and_normalization_explicit",
        },
        {
            "id": "T8-6-BYTE001-LANE2-SYMBOL",
            "location": "Table 8-6, byte A[29:31]=001, lane 2",
            "printed_symbol": "x",
            "provisional_normalized_symbol": "—",
            "basis": "The note defines x as a lane not used in 32-bit mode, but lane 2 is part of DH[0:31] and is marked A for byte A[29:31]=010; the remaining unused cells in lanes 0 through 3 print an em dash.",
            "query_effect": "none; active lanes are taken only from printed A marks",
            "status": "probable_manual_editorial_error_preserved_and_normalization_explicit",
        },
        {
            "id": "T8-7-OFFSET001-FIRST-LANE0-SYMBOL",
            "location": "Table 8-7, start A[29:31]=001, first access, lane 0",
            "printed_symbol": "blank",
            "provisional_normalized_symbol": "—",
            "basis": "The note defines A, em dash, and x but no blank; lane 0 is outside this three-byte access and corresponding unused cells in lanes 0 through 3 print an em dash.",
            "query_effect": "none; active lanes are taken only from printed A marks",
            "status": "probable_manual_editorial_omission_preserved_and_normalization_explicit",
        },
        {
            "id": "T8-7-OFFSET010-SECOND-LANE3-SYMBOL",
            "location": "Table 8-7, start A[29:31]=010, second access, lane 3",
            "printed_symbol": "x",
            "provisional_normalized_symbol": "—",
            "basis": "The note defines x as a lane not used in 32-bit mode, but lane 3 is part of DH[0:31] and other unused cells in lanes 0 through 3 print an em dash.",
            "query_effect": "none; active lanes are taken only from printed A marks",
            "status": "probable_manual_editorial_error_preserved_and_normalization_explicit",
        },
    ]:
        raise AddressError("the rendered Table 8-5 through 8-7 conflicts must be preserved exactly")

    tsiz = spec.get("tsiz_by_bytes", {})
    if tsiz != {"1": "001", "2": "010", "3": "011", "4": "100", "8": "000"}:
        raise AddressError("TSIZ size mapping disagrees with selected table rows")

    width_applicability = spec.get("width_applicability", {})
    if width_applicability.get("32") != {
        "aligned_rows": "direct_table_8_6",
        "four_byte_rows": "direct_table_8_7",
        "lane_marks": "physical lanes 0 through 3 and DH signal slices returned without operand-byte/endian mapping",
        "doubleword": "one data transaction with two Table 8-6 beats; source A/TSIZ/lane fields retained per beat without inferred second address",
    }:
        raise AddressError("32-bit width applicability must retain direct tables and endian limits")

    aligned = spec.get("table_8_4_aligned_64", [])
    if aligned != _expected_aligned_rows():
        raise AddressError("Table 8-4 rows differ from the exact aligned expansion")
    for row in aligned:
        _bits(row["tsiz"], 3, "TSIZ")
        _bits(row["a29_31"], 3, "A[29:31]")

    cases = spec.get("table_8_5_four_byte_cases", [])
    starts = [case.get("start_a29_31") for case in cases]
    if starts != [f"{offset:03b}" for offset in range(8)]:
        raise AddressError("Table 8-5 cases must cover A[29:31]=000 through 111 in order")
    for offset, case in enumerate(cases):
        if case != _expected_four_byte_case(offset):
            raise AddressError(f"Table 8-5 case {offset:03b} differs from the rendered row")
        if sum(access["transfer_size_bytes"] for access in case["accesses"]) != 4:
            raise AddressError(f"Table 8-5 case {offset:03b} does not total four bytes")

    aligned32 = spec.get("table_8_6_aligned_32", [])
    if aligned32 != _expected_aligned_32_rows():
        raise AddressError("Table 8-6 rows differ from the exact rendered expansion")
    for row in aligned32:
        _bits(row["tsiz"], 3, "TSIZ")
        _bits(row["a29_31"], 3, "A[29:31]")
        if row["source_table_lane_marks"] != [
            index for index, symbol in enumerate(row["source_table_lane_cells"])
            if symbol == "A"
        ]:
            raise AddressError("Table 8-6 active lane marks disagree with raw A cells")

    cases32 = spec.get("table_8_7_four_byte_cases", [])
    starts32 = [case.get("start_a29_31") for case in cases32]
    if starts32 != [f"{offset:03b}" for offset in range(8)]:
        raise AddressError("Table 8-7 cases must cover A[29:31]=000 through 111 in order")
    for offset, case in enumerate(cases32):
        if case != _expected_four_byte_32_case(offset):
            raise AddressError(f"Table 8-7 case {offset:03b} differs from the rendered row")
        if sum(access["transfer_size_bytes"] for access in case["accesses"]) != 4:
            raise AddressError(f"Table 8-7 case {offset:03b} does not total four bytes")

    counts = {
        "table_8_4_rows": len(aligned),
        "table_8_4_byte_rows": sum(row["transfer_size_bytes"] == 1 for row in aligned),
        "table_8_4_halfword_rows": sum(row["transfer_size_bytes"] == 2 for row in aligned),
        "table_8_4_word_rows": sum(row["transfer_size_bytes"] == 4 for row in aligned),
        "table_8_4_doubleword_rows": sum(row["transfer_size_bytes"] == 8 for row in aligned),
        "table_8_5_start_cases": len(cases),
        "table_8_5_access_rows": sum(len(case["accesses"]) for case in cases),
        "table_8_5_aligned_cases": sum(case["alignment"] == "aligned" for case in cases),
        "table_8_5_misaligned_cases": sum(case["alignment"] == "misaligned" for case in cases),
        "table_8_6_request_rows": len(aligned32),
        "table_8_6_data_beat_rows": sum(row["data_beat_count"] for row in aligned32),
        "table_8_6_byte_rows": sum(row["transfer_size_bytes"] == 1 for row in aligned32),
        "table_8_6_halfword_rows": sum(row["transfer_size_bytes"] == 2 for row in aligned32),
        "table_8_6_word_rows": sum(row["transfer_size_bytes"] == 4 for row in aligned32),
        "table_8_6_doubleword_request_rows": sum(row["transfer_size_bytes"] == 8 for row in aligned32),
        "table_8_7_start_cases": len(cases32),
        "table_8_7_access_rows": sum(len(case["accesses"]) for case in cases32),
        "table_8_7_aligned_cases": sum(case["alignment"] == "aligned" for case in cases32),
        "table_8_7_misaligned_cases": sum(case["alignment"] == "misaligned" for case in cases32),
    }
    if counts != spec.get("expected_counts"):
        raise AddressError(f"count mismatch: computed {counts}, expected {spec.get('expected_counts')}")
    return counts


def _check_query(address: int, size: int, bus_width: int) -> None:
    if not isinstance(address, int) or isinstance(address, bool) or not 0 <= address <= MAX_ADDRESS:
        raise AddressError("address must be a 32-bit unsigned byte address")
    if not isinstance(size, int) or isinstance(size, bool) or size not in {1, 2, 4, 8}:
        raise AddressError("size must be 1, 2, 4, or 8 bytes")
    if not isinstance(bus_width, int) or isinstance(bus_width, bool) or bus_width not in {32, 64}:
        raise AddressError("bus_width must be 32 or 64")
    if address + size - 1 > MAX_ADDRESS:
        raise AddressError("query wraps beyond the 32-bit physical address space")


def query(
    address: int,
    size: int,
    *,
    bus_width: int,
    spec: dict[str, Any] | None = None,
) -> dict[str, Any]:
    spec = load_spec() if spec is None else spec
    validate(spec)
    _check_query(address, size, bus_width)
    offset = address & 7

    source_tables: list[str]
    if size == 4:
        table_key = (
            "table_8_5_four_byte_cases"
            if bus_width == 64
            else "table_8_7_four_byte_cases"
        )
        case = next(
            item for item in spec[table_key]
            if item["start_a29_31"] == f"{offset:03b}"
        )
        source_tables = ["8-5" if bus_width == 64 else "8-7"]
        if case["alignment"] == "aligned":
            source_tables.insert(0, "8-4" if bus_width == 64 else "8-6")
        width_basis = f"direct_{bus_width}_bit_table_rows"
    else:
        if address % size:
            raise ScopeError(
                "outside_selected_tables: Tables 8-4/8-6 cover aligned transfers and Tables 8-5/8-7 expand only four-byte misalignment"
            )
        table_key = "table_8_4_aligned_64" if bus_width == 64 else "table_8_6_aligned_32"
        row = next(
            (
                item for item in spec[table_key]
                if item["transfer_size_bytes"] == size and item["a29_31"] == f"{offset:03b}"
            ),
            None,
        )
        if row is None:
            raise ScopeError(f"outside_selected_tables: no matching Table {'8-4' if bus_width == 64 else '8-6'} row")
        case = {
            "alignment": "aligned",
            "accesses": [
                {
                    "sequence": "only",
                    "address_delta_bytes": 0,
                    **copy.deepcopy(row),
                }
            ],
        }
        source_tables = ["8-4" if bus_width == 64 else "8-6"]
        width_basis = f"direct_{bus_width}_bit_table_row"

    accesses: list[dict[str, Any]] = []
    access_source_table = "8-5" if bus_width == 64 and size == 4 else (
        "8-7" if bus_width == 32 and size == 4 else (
            "8-4" if bus_width == 64 else "8-6"
        )
    )
    for item in case["accesses"]:
        access_address = address + item["address_delta_bytes"]
        access = {
            "sequence": item["sequence"],
            "address": access_address,
            "address_hex": f"0x{access_address:08x}",
            "a29_31": item["a29_31"],
            "transfer_size_bytes": item["transfer_size_bytes"],
            "tsiz": item["tsiz"],
            "data_beat_count": item.get("data_beat_count", 1),
            "source_table": access_source_table,
            "source_table_rows": source_tables if case["alignment"] == "aligned" else [access_source_table],
        }
        if "source_table_tsiz" in item:
            access["source_table_tsiz"] = item["source_table_tsiz"]
            access["tsiz_status"] = item["tsiz_status"]
            access["source_conflict"] = item["source_conflict"]
        access["source_table_lane_marks"] = item["source_table_lane_marks"]
        access["source_table_active_data_signals"] = _active_data_signals(
            item["source_table_lane_marks"]
        )
        if "source_table_lane_cells" in item:
            access["source_table_lane_cells"] = item["source_table_lane_cells"]
        if "lane_cell_normalizations" in item:
            access["lane_cell_normalizations"] = item["lane_cell_normalizations"]
        if "source_table_data_beats" in item:
            access["source_table_data_beats"] = [
                {
                    **beat,
                    "source_table_active_data_signals": _active_data_signals(
                        beat["source_table_lane_marks"]
                    ),
                }
                for beat in item["source_table_data_beats"]
            ]
        accesses.append(access)

    crosses_word = address // 4 != (address + size - 1) // 4
    crosses_coherency = address // 32 != (address + size - 1) // 32
    result: dict[str, Any] = {
        "request": {
            "address": address,
            "address_hex": f"0x{address:08x}",
            "a29_31": f"{offset:03b}",
            "transfer_size_bytes": size,
            "bus_width": bus_width,
        },
        "status": (
            "defined_with_explicit_source_conflict"
            if any(
                "source_conflict" in access or "lane_cell_normalizations" in access
                for access in accesses
            )
            else "defined_by_selected_tables"
        ),
        "interpretation": "selected_nonburst_bus_decomposition_only",
        "address_domain": "already_bus_side_32_bit_byte_address",
        "cpu_access_to_bus_prediction": "not_provided_requires_cacheability_and_memory_hierarchy_context",
        "alignment": case["alignment"],
        "access_count": len(accesses),
        "accesses": accesses,
        "crosses_word_boundary": crosses_word,
        "crosses_32_byte_boundary": crosses_coherency,
        "coherency_boundary_action": (
            spec["coherency_boundary_rule"]["rule"] if crosses_coherency else "not_applicable"
        ),
        "source_tables": source_tables,
        "width_basis": width_basis,
        "lane_result_scope": "physical_data_bus_signal_groups_marked_active_by_the_selected_source_table",
        "operand_byte_to_lane_mapping": "not_provided_requires_an_explicit_endian_and_access_semantics_contract",
        "endian_lane_steering": "outside_scope",
    }
    return result


def _address(text: str) -> int:
    try:
        return int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("address must be decimal or 0x-prefixed hexadecimal") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="validate the selected-table manifest")
    query_parser = subparsers.add_parser("query", help="query an exact selected-table case")
    query_parser.add_argument("--address", required=True, type=_address)
    query_parser.add_argument("--size", required=True, type=int, choices=(1, 2, 4, 8))
    query_parser.add_argument("--bus-width", required=True, type=int, choices=(32, 64))
    args = parser.parse_args()

    spec = load_spec()
    try:
        counts = validate(spec)
        if args.command == "validate":
            print(
                "bus addressing OK: "
                f"64-bit {counts['table_8_4_rows']} aligned rows and "
                f"{counts['table_8_5_start_cases']} four-byte starts / "
                f"{counts['table_8_5_access_rows']} accesses; "
                f"32-bit {counts['table_8_6_request_rows']} aligned requests / "
                f"{counts['table_8_6_data_beat_rows']} beats and "
                f"{counts['table_8_7_start_cases']} four-byte starts / "
                f"{counts['table_8_7_access_rows']} accesses"
            )
            return 0
        result = query(args.address, args.size, bus_width=args.bus_width, spec=spec)
    except AddressError as exc:
        parser.error(str(exc))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
