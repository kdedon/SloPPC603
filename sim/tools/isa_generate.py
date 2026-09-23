#!/usr/bin/env python3
"""Validate bounded P03 ISA metadata and deterministically generate ISA_MATRIX.md."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
ISA_PATH = ROOT / "sim/spec/isa.json"
SOURCE_PATH = ROOT / "sim/spec/isa_sources.json"
TIMING_PATH = ROOT / "sim/spec/timing.json"
MATRIX_PATH = ROOT / "docs/references/ISA_MATRIX.md"


class MetadataError(ValueError):
    pass


def _number(value: Any, field: str) -> int:
    if not isinstance(value, str) or not value.startswith("0x"):
        raise MetadataError(f"{field} must be a 0x-prefixed string")
    try:
        result = int(value, 16)
    except ValueError as exc:
        raise MetadataError(f"{field} is not hexadecimal") from exc
    if not 0 <= result <= 0xFFFFFFFF:
        raise MetadataError(f"{field} exceeds 32 bits")
    return result


def patterns_overlap(left: dict[str, Any], right: dict[str, Any]) -> bool:
    lm, lv = _number(left["mask"], "mask"), _number(left["value"], "value")
    rm, rv = _number(right["mask"], "mask"), _number(right["value"], "value")
    return ((lv ^ rv) & lm & rm) == 0


def decode_matches(entry: dict[str, Any], word: int) -> bool:
    mask, value = _number(entry["mask"], "mask"), _number(entry["value"], "value")
    return word & mask == value


def find_overlaps(entries: list[dict[str, Any]]) -> list[tuple[str, str]]:
    return [
        (left["id"], right["id"])
        for index, left in enumerate(entries)
        for right in entries[index + 1:]
        if patterns_overlap(left, right)
    ]


def validate(spec: dict[str, Any], sources: dict[str, Any], timing: dict[str, Any]) -> None:
    required = {"schema_version", "variants", "functional_families", "instruction_forms", "decode_entries", "allowed_overlaps"}
    missing = required - spec.keys()
    if missing:
        raise MetadataError(f"missing top-level fields: {sorted(missing)}")
    if spec["schema_version"] != 1:
        raise MetadataError(f"unsupported ISA schema_version: {spec['schema_version']!r}")
    if sources.get("schema_version") != 1:
        raise MetadataError(f"unsupported ISA source schema_version: {sources.get('schema_version')!r}")

    family_tables = {item["table"] for item in spec["functional_families"]}
    expected_families = {f"A-{n}" for n in range(3, 31)}
    if family_tables != expected_families:
        raise MetadataError("functional-family inventory must cover A-3 through A-30 exactly")
    form_tables = {item["table"] for item in spec["instruction_forms"]}
    expected_forms = {f"A-{n}" for n in range(31, 46)}
    if form_tables != expected_forms:
        raise MetadataError("instruction-form inventory must cover A-31 through A-45 exactly")

    b3 = next((item for item in spec.get("appendix_b_exclusions", []) if item.get("table") == "B-3"), None)
    if b3 is None:
        raise MetadataError("missing Appendix B-3 membership and exception classification")
    grouped = [mnemonic for group in b3.get("exception_groups", []) for mnemonic in group.get("mnemonics", [])]
    if len(grouped) != len(set(grouped)) or set(grouped) != set(b3["mnemonics"]):
        raise MetadataError("B-3 exception groups must partition table membership exactly")
    exception_by_mnemonic = {
        mnemonic: group["exception"]
        for group in b3["exception_groups"]
        for mnemonic in group["mnemonics"]
    }
    if exception_by_mnemonic.get("tlbia") != "pending_editorial_reconciliation":
        raise MetadataError("B-3 tlbia must remain pending editorial reconciliation")
    for mnemonic in ("fsqrt", "fsqrts"):
        if exception_by_mnemonic.get(mnemonic) != "floating_point_unavailable":
            raise MetadataError(f"B-3 {mnemonic} must explicitly use EC603e floating-point unavailable")

    inventory = sources.get("appendix_a_mnemonic_inventory", [])
    if sources.get("observed_row_count") != 226 or len(inventory) != 226:
        raise MetadataError("Appendix A.1 inventory must contain 226 observed rows")
    if len({row["row_id"] for row in inventory}) != len(inventory):
        raise MetadataError("duplicate Appendix A inventory row id")
    inventory_counts = Counter(row["encoding_status"] for row in inventory)
    expected_inventory_counts = {
        "primary_opcode_only_pending_full_mask": 124,
        "reviewed_and_immediate_record": 2,
        "reviewed_integer_unary_2_Rc_forms": 3,
        "reviewed_cr_transfer_exact_forms": 2,
        "reviewed_cr_logical_exact_forms": 8,
        "reviewed_cr_state_transfer_exact_forms": 2,
        "reviewed_add_immediate_carry": 2,
        "reviewed_subtract_immediate": 1,
        "reviewed_subtract_family_4_OE_Rc_forms": 6,
        "reviewed_current_rtl_decode_entry": 6,
        "reviewed_add_family_4_OE_Rc_forms": 5,
        "reviewed_register_logical_2_Rc_forms": 8,
        "reviewed_rotate_family_2_Rc_forms": 3,
        "reviewed_shift_family_2_Rc_forms": 4,
        "reviewed_compare_family_32bit_L0": 4,
        "reviewed_control_memory_bounded_subset": 20,
        "reviewed_multiply_low_family": 2,
        "reviewed_multiply_high_family": 2,
        "reviewed_divwu_family": 1,
        "reviewed_divw_family": 1,
        "reviewed_lsu_update_exact_forms": 14,
        "reviewed_supervisor_opt_in_exact_form": 3,
        "reviewed_serialization_opt_in_exact_form": 3,
    }
    if dict(inventory_counts) != sources.get("inventory_status_counts") or dict(inventory_counts) != expected_inventory_counts:
        raise MetadataError("Appendix A inventory status counts do not match the bounded reviewed sets")
    rows_by_status = {
        status: {row["row_id"] for row in inventory if row["encoding_status"] == status}
        for status in expected_inventory_counts
    }
    if rows_by_status["reviewed_current_rtl_decode_entry"] != {"A1-004", "A1-007", "A1-153", "A1-154", "A1-225", "A1-226"}:
        raise MetadataError("current immediate-form source rows are not the reviewed six")
    if rows_by_status["reviewed_add_family_4_OE_Rc_forms"] != {"A1-001", "A1-002", "A1-003", "A1-008", "A1-009"}:
        raise MetadataError("ADD-family source rows are not the reviewed five")
    if rows_by_status["reviewed_subtract_family_4_OE_Rc_forms"] != {"A1-149", "A1-208", "A1-209", "A1-210", "A1-212", "A1-213"}:
        raise MetadataError("subtract source rows changed")
    if rows_by_status["reviewed_subtract_immediate"] != {"A1-211"}:
        raise MetadataError("SUBFIC source row changed")
    if rows_by_status["reviewed_add_immediate_carry"] != {"A1-005", "A1-006"}:
        raise MetadataError("ADDIC source rows changed")
    if rows_by_status["reviewed_and_immediate_record"] != {"A1-012", "A1-013"}:
        raise MetadataError("AND-immediate source rows changed")
    if rows_by_status["reviewed_integer_unary_2_Rc_forms"] != {"A1-023", "A1-046", "A1-047"}:
        raise MetadataError("integer-unary source rows are not the reviewed three")
    if rows_by_status["reviewed_cr_transfer_exact_forms"] != {"A1-125", "A1-132"}:
        raise MetadataError("CR-transfer source rows are not MFCR/MTCRF")
    if rows_by_status["reviewed_cr_logical_exact_forms"] != {
        "A1-024", "A1-025", "A1-026", "A1-027",
        "A1-028", "A1-029", "A1-030", "A1-031",
    }:
        raise MetadataError("CR-logical source rows are not the reviewed eight")
    if rows_by_status["reviewed_cr_state_transfer_exact_forms"] != {"A1-122", "A1-124"}:
        raise MetadataError("CR-state source rows are not MCRF/MCRXR")
    if rows_by_status["reviewed_multiply_low_family"] != {"A1-146", "A1-147"}:
        raise MetadataError("multiply-low source rows are not MULLI/MULLW")
    if rows_by_status["reviewed_multiply_high_family"] != {"A1-143", "A1-144"}:
        raise MetadataError("multiply-high source rows are not MULHW/MULHWU")
    if rows_by_status["reviewed_divwu_family"] != {"A1-041"}:
        raise MetadataError("DIVWU source row changed")
    if rows_by_status["reviewed_divw_family"] != {"A1-040"}:
        raise MetadataError("DIVW source row changed")
    expected_lsu_update_rows = {
        "A1-085", "A1-086", "A1-102", "A1-103", "A1-107", "A1-108",
        "A1-119", "A1-120", "A1-177", "A1-178", "A1-196", "A1-197",
        "A1-205", "A1-206",
    }
    if rows_by_status["reviewed_lsu_update_exact_forms"] != expected_lsu_update_rows:
        raise MetadataError("LSU-update source rows changed")
    if rows_by_status["reviewed_supervisor_opt_in_exact_form"] != {"A1-127", "A1-155", "A1-165"}:
        raise MetadataError("supervisor opt-in source rows are not MFMSR/RFI/SC")
    if rows_by_status["reviewed_serialization_opt_in_exact_form"] != {"A1-044", "A1-083", "A1-214"}:
        raise MetadataError("serialization opt-in source rows are not EIEIO/ISYNC/SYNC")
    expected_logical_rows = {"A1-010", "A1-011", "A1-045", "A1-148", "A1-150", "A1-151", "A1-152", "A1-224"}
    if rows_by_status["reviewed_register_logical_2_Rc_forms"] != expected_logical_rows:
        raise MetadataError("register-logical source rows are not the reviewed eight")
    if rows_by_status["reviewed_rotate_family_2_Rc_forms"] != {"A1-162", "A1-163", "A1-164"}:
        raise MetadataError("word-rotate source rows are not the reviewed three")
    if rows_by_status["reviewed_shift_family_2_Rc_forms"] != {"A1-169", "A1-172", "A1-173", "A1-175"}:
        raise MetadataError("word-shift source rows are not the reviewed four")
    if rows_by_status["reviewed_compare_family_32bit_L0"] != {"A1-018", "A1-019", "A1-020", "A1-021"}:
        raise MetadataError("compare source rows are not the reviewed four")

    reviewed_source = sources.get("reviewed_add_family", {})
    if reviewed_source.get("concrete_OE_Rc_forms") != 20:
        raise MetadataError("reviewed ADD-family source inventory must declare 20 concrete forms")
    profiles = {profile["id"]: profile for profile in spec.get("add_family_semantics", {}).get("profiles", [])}
    expected_profile_ids = {f"ADD-{family}" for family in ("add", "addc", "adde", "addme", "addze")}
    if set(profiles) != expected_profile_ids:
        raise MetadataError("ADD-family semantic profiles must cover add/addc/adde/addme/addze")
    reviewed_logical_source = sources.get("reviewed_logical_family", {})
    if reviewed_logical_source.get("concrete_Rc_forms") != 16:
        raise MetadataError("reviewed register-logical source inventory must declare 16 concrete forms")
    logical_profiles = {
        profile["id"]: profile
        for profile in spec.get("logical_family_semantics", {}).get("profiles", [])
    }
    logical_xo = {"and": 28, "andc": 60, "or": 444, "orc": 412, "xor": 316, "nand": 476, "nor": 124, "eqv": 284}
    if set(logical_profiles) != {f"LOGIC-{family}" for family in logical_xo}:
        raise MetadataError("register-logical semantic profiles must cover the reviewed eight families")
    reviewed_unary_source = sources.get("reviewed_integer_unary_family", {})
    if reviewed_unary_source.get("concrete_Rc_forms") != 6:
        raise MetadataError("reviewed integer-unary source inventory must declare six concrete forms")
    unary_profiles = {
        profile["id"]: profile
        for profile in spec.get("integer_unary_semantics", {}).get("profiles", [])
    }
    unary_xo = {"cntlzw": 26, "extsb": 954, "extsh": 922}
    if set(unary_profiles) != {f"UNARY-{family}" for family in unary_xo}:
        raise MetadataError("integer-unary semantic profiles must cover cntlzw/extsb/extsh")
    reviewed_cr_source = sources.get("reviewed_cr_transfer", {})
    if reviewed_cr_source.get("concrete_forms") != 2:
        raise MetadataError("reviewed CR-transfer source inventory must declare two concrete forms")
    cr_profiles = {
        profile["id"]: profile
        for profile in spec.get("cr_transfer_semantics", {}).get("profiles", [])
    }
    if set(cr_profiles) != {"CRXFER-mfcr", "CRXFER-mtcrf"}:
        raise MetadataError("CR-transfer profiles must cover MFCR and MTCRF exactly")
    reviewed_cr_logical_source = sources.get("reviewed_cr_logical_family", {})
    if reviewed_cr_logical_source.get("concrete_forms") != 8:
        raise MetadataError("reviewed CR-logical source inventory must declare eight forms")
    cr_logical_profiles = {
        profile["id"]: profile
        for profile in spec.get("cr_logical_semantics", {}).get("profiles", [])
    }
    cr_logical_xo = {
        "crand": 257, "crandc": 129, "creqv": 289, "crnand": 225,
        "crnor": 33, "cror": 449, "crorc": 417, "crxor": 193,
    }
    if set(cr_logical_profiles) != {f"CRLOGIC-{family}" for family in cr_logical_xo}:
        raise MetadataError("CR-logical profiles must cover the reviewed eight families")
    reviewed_cr_state_source = sources.get("reviewed_cr_state_transfer", {})
    if reviewed_cr_state_source.get("concrete_forms") != 2:
        raise MetadataError("reviewed CR-state source inventory must declare two forms")
    reviewed_multiply_source = sources.get("reviewed_multiply_low_family", {})
    if (reviewed_multiply_source.get("source_rows") != ["A1-146", "A1-147"] or
        reviewed_multiply_source.get("canonical_families") != ["mulli", "mullw"] or
        reviewed_multiply_source.get("concrete_forms") != 5):
        raise MetadataError("reviewed multiply-low source inventory must declare two rows and five forms")
    expected_multiply_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 366, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 377, "table": "A-3"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 389, "table": "A-34", "family": "mulli"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 396, "table": "A-41", "family": "mullw"},
    ]
    if reviewed_multiply_source.get("primary_encoding") != expected_multiply_primary:
        raise MetadataError("multiply-low primary source anchors changed")
    expected_multiply_secondary = [
        {"file": "MPC601UM.pdf", "pdf_page": 697, "printed_page": "10-143", "family": "mulli"},
        {"file": "MPC601UM.pdf", "pdf_page": 698, "printed_page": "10-144", "family": "mullw"},
        {"file": "MPC601UM.pdf", "pdf_page": 58, "printed_page": "2-12", "topic": "CR0 LT/GT/EQ and final XER.SO"},
        {"file": "MPC601UM.pdf", "pdf_page": 62, "printed_page": "2-16", "topic": "XER SO/OV/CA"},
    ]
    if reviewed_multiply_source.get("secondary_semantics") != expected_multiply_secondary:
        raise MetadataError("multiply-low secondary source anchors changed")
    expected_multiply_limits = [
        "The secondary MULLI pseudocode prints prod[0-48] and rD=prod[16-48], an internally inconsistent 49/33-bit range; the adjacent prose unambiguously specifies the low-order 32 bits of the signed register-by-SIMM product.",
        "The secondary 601 MULLW pseudocode uses 64-bit register slice notation although the 601 and 603e operands are 32-bit; the adjacent prose defines a 64-bit product of two 32-bit values and a low-order 32-bit result.",
        "Table 6-4 lists MULLI 2/3 and MULLW 2/3/4/5 execute-cycle possibilities without mapping operands to counts. The bounded IU selects the documented maximum 3/5-cycle reservations; lower silicon-selected timing remains unresolved.",
    ]
    if reviewed_multiply_source.get("source_limits") != expected_multiply_limits:
        raise MetadataError("multiply-low source transcription limits changed")
    reviewed_multiply_high_source = sources.get("reviewed_multiply_high_family", {})
    if (reviewed_multiply_high_source.get("source_rows") != ["A1-143", "A1-144"] or
        reviewed_multiply_high_source.get("canonical_families") != ["mulhw", "mulhwu"] or
        reviewed_multiply_high_source.get("concrete_forms") != 4):
        raise MetadataError("reviewed multiply-high source inventory must declare two rows and four forms")
    expected_multiply_high_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_pages": [365, 366], "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 377, "table": "A-3"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 396, "table": "A-41", "families": ["mulhw", "mulhwu"]},
    ]
    expected_multiply_high_secondary = [
        {"file": "MPC601UM.pdf", "pdf_page": 695, "printed_page": "10-141", "family": "mulhw"},
        {"file": "MPC601UM.pdf", "pdf_page": 696, "printed_page": "10-142", "family": "mulhwu"},
        {"file": "MPC601UM.pdf", "pdf_page": 58, "printed_page": "2-12", "topic": "CR0 LT/GT/EQ and current XER.SO"},
    ]
    expected_multiply_high_limits = [
        "The secondary 601 pseudocode uses 64-bit register slice notation and marks the non-result half of rD undefined; the adjacent prose unambiguously defines a 32-bit destination containing product bits 63:32.",
        "The secondary 601 descriptions state that MQ becomes undefined. MQ is not exposed by this bounded 603e scaffold, so that 601-specific microarchitectural side effect is not imported.",
        "Table 6-4 lists MULHW 2/3/4/5 and MULHWU 2/3/4/5/6 execute-cycle possibilities without mapping operands to counts. The bounded IU selects the documented maximum 5/6-cycle reservations; lower silicon-selected timing remains unresolved.",
    ]
    if (reviewed_multiply_high_source.get("primary_encoding") != expected_multiply_high_primary or
        reviewed_multiply_high_source.get("secondary_semantics") != expected_multiply_high_secondary or
        reviewed_multiply_high_source.get("source_limits") != expected_multiply_high_limits):
        raise MetadataError("multiply-high source anchors or transcription limits changed")
    reviewed_divwu_source = sources.get("reviewed_divwu_family", {})
    if (reviewed_divwu_source.get("source_rows") != ["A1-041"] or
        reviewed_divwu_source.get("canonical_family") != "divwu" or
        reviewed_divwu_source.get("concrete_OE_Rc_forms") != 4):
        raise MetadataError("reviewed DIVWU source inventory must declare one row and four forms")
    expected_divwu_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 362, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 377, "table": "A-3"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 396, "table": "A-41"},
    ]
    expected_divwu_secondary = [
        {"file": "MPC601UM.pdf", "pdf_page": 603, "printed_page": "10-49", "family": "divwu"},
        {"file": "MPC601UM.pdf", "pdf_page": 58, "printed_page": "2-12", "topic": "CR0 LT/GT/EQ and final XER.SO"},
        {"file": "MPC601UM.pdf", "pdf_page": 62, "printed_page": "2-16", "topic": "XER SO/OV/CA"},
    ]
    expected_divwu_limits = [
        "On a zero divisor the architecture leaves rD and, when Rc=1, CR0 LT/GT/EQ undefined. Only OE-enabled OV=1, sticky SO, and CR0.SO remain architecturally defined.",
        "The bounded scaffold chooses deterministic rD=0 and therefore CR0 LT/GT/EQ=EQ for a zero divisor. This is an implementation policy, not a required architectural value.",
        "The synthesizable quotient path uses a 16-step radix-4 restoring divider. The IU reserves 20 execute cycles by default for PID7v or 37 when configured for PID6 per TIM-T64-045; the algorithm is not claimed to match silicon internals.",
    ]
    if (reviewed_divwu_source.get("primary_encoding") != expected_divwu_primary or
        reviewed_divwu_source.get("secondary_semantics") != expected_divwu_secondary or
        reviewed_divwu_source.get("source_limits") != expected_divwu_limits):
        raise MetadataError("DIVWU source anchors or undefined-result limits changed")
    reviewed_divw_source = sources.get("reviewed_divw_family", {})
    if (reviewed_divw_source.get("source_rows") != ["A1-040"] or
        reviewed_divw_source.get("canonical_family") != "divw" or
        reviewed_divw_source.get("concrete_OE_Rc_forms") != 4):
        raise MetadataError("reviewed DIVW source inventory must declare one row and four forms")
    expected_divw_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 362, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 377, "table": "A-3"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 396, "table": "A-41"},
    ]
    expected_divw_secondary = [
        {"file": "MPC601UM.pdf", "pdf_page": 601, "printed_page": "10-47", "family": "divw"},
        {"file": "MPC601UM.pdf", "pdf_page": 58, "printed_page": "2-12", "topic": "CR0 LT/GT/EQ and final XER.SO"},
        {"file": "MPC601UM.pdf", "pdf_page": 62, "printed_page": "2-16", "topic": "XER SO/OV/CA"},
    ]
    expected_divw_limits = [
        "For a zero divisor or signed INT_MIN divided by -1, the architecture leaves rD and, when Rc=1, CR0 LT/GT/EQ undefined. Only OE-enabled OV=1, sticky SO, and CR0.SO remain architecturally defined.",
        "The bounded scaffold chooses deterministic rD=0 and therefore CR0 LT/GT/EQ=EQ for both exceptional classes. This is an implementation policy, not a required architectural value.",
        "The synthesizable quotient path detects both exceptional classes before a 16-step radix-4 restoring magnitude divide. The IU reserves 20 execute cycles by default for PID7v or 37 when configured for PID6 per TIM-T64-047; the algorithm is not claimed to match silicon internals.",
    ]
    if (reviewed_divw_source.get("primary_encoding") != expected_divw_primary or
        reviewed_divw_source.get("secondary_semantics") != expected_divw_secondary or
        reviewed_divw_source.get("source_limits") != expected_divw_limits):
        raise MetadataError("DIVW source anchors or undefined-result limits changed")
    reviewed_lsu_update = sources.get("reviewed_lsu_update", {})
    expected_lsu_rows = [
        "A1-085", "A1-086", "A1-102", "A1-103", "A1-107", "A1-108",
        "A1-119", "A1-120", "A1-177", "A1-178", "A1-196", "A1-197",
        "A1-205", "A1-206",
    ]
    expected_lsu_secondary = {
        "lbzu": (640, "10-86"), "lbzux": (641, "10-87"),
        "lhau": (652, "10-98"), "lhaux": (653, "10-99"),
        "lhzu": (657, "10-103"), "lhzux": (658, "10-104"),
        "lwzu": (668, "10-114"), "lwzux": (669, "10-115"),
        "stbu": (735, "10-181"), "stbux": (736, "10-182"),
        "sthu": (748, "10-194"), "sthux": (749, "10-195"),
        "stwu": (757, "10-203"), "stwux": (758, "10-204"),
    }
    observed_lsu_secondary = {
        item.get("mnemonic"): (item.get("pdf_page"), item.get("printed_page"))
        for item in reviewed_lsu_update.get("secondary_instruction_pages", [])
        if item.get("file") == "MPC601UM.pdf"
    }
    primary_summary = reviewed_lsu_update.get("primary_summary", [])
    if (reviewed_lsu_update.get("source_rows") != expected_lsu_rows or
        reviewed_lsu_update.get("concrete_forms") != 14 or
        observed_lsu_secondary != expected_lsu_secondary or
        not any(item.get("pdf_pages") == [107, 109] for item in primary_summary) or
        not any(item.get("pdf_pages") == [364, 367] and item.get("table") == "A-1"
                for item in primary_summary) or
        not any(item.get("pdf_pages") == [381, 382] and item.get("tables") == ["A-13", "A-14"]
                for item in primary_summary) or
        len(reviewed_lsu_update.get("source_limits", [])) != 3):
        raise MetadataError("LSU-update source anchors or limits changed")
    reviewed_rotate_source = sources.get("reviewed_rotate_family", {})
    if reviewed_rotate_source.get("concrete_Rc_forms") != 6:
        raise MetadataError("reviewed word-rotate source inventory must declare six concrete forms")
    rotate_conflict = reviewed_rotate_source.get("primary_functional_table_conflict", {})
    if rotate_conflict.get("observed_primary_opcodes") != {"rlwimi": 22, "rlwinm": 20, "rlwnm": 21}:
        raise MetadataError("Table A-6 word-rotate opcode conflict must remain explicit")
    rotate_profiles = {
        profile["id"]: profile
        for profile in spec.get("rotate_family_semantics", {}).get("profiles", [])
    }
    rotate_opcodes = {"rlwimi": 20, "rlwinm": 21, "rlwnm": 23}
    if set(rotate_profiles) != {f"ROTATE-{family}" for family in rotate_opcodes}:
        raise MetadataError("word-rotate semantic profiles must cover the reviewed three families")
    reviewed_shift_source = sources.get("reviewed_shift_family", {})
    if reviewed_shift_source.get("concrete_Rc_forms") != 8:
        raise MetadataError("reviewed word-shift source inventory must declare eight concrete forms")
    shift_profiles = {
        profile["id"]: profile
        for profile in spec.get("shift_family_semantics", {}).get("profiles", [])
    }
    shift_xo = {"slw": 24, "srw": 536, "sraw": 792, "srawi": 824}
    if set(shift_profiles) != {f"SHIFT-{family}" for family in shift_xo}:
        raise MetadataError("word-shift semantic profiles must cover the reviewed four families")
    reviewed_compare_source = sources.get("reviewed_compare_family", {})
    if reviewed_compare_source.get("concrete_32bit_L0_forms") != 4:
        raise MetadataError("reviewed compare source inventory must declare four L=0 forms")
    compare_profiles = {
        profile["id"]: profile
        for profile in spec.get("compare_family_semantics", {}).get("profiles", [])
    }
    compare_encodings = {
        "cmp": ("X", 31, 0, 0xFC6007FF, 0x7C000000),
        "cmpi": ("D", 11, None, 0xFC600000, 0x2C000000),
        "cmpl": ("X", 31, 32, 0xFC6007FF, 0x7C000040),
        "cmpli": ("D", 10, None, 0xFC600000, 0x28000000),
    }
    if set(compare_profiles) != {f"COMPARE-{family}" for family in compare_encodings}:
        raise MetadataError("compare semantic profiles must cover the reviewed four families")

    timing_ids = {row["id"] for row in timing.get("rows", [])}
    variants = {variant["id"] for variant in spec["variants"]}
    entries = spec["decode_entries"]
    ids = [entry.get("id") for entry in entries]
    if len(ids) != len(set(ids)):
        raise MetadataError("duplicate decode entry id")
    required_entry = {"id", "mnemonic", "form", "mask", "value", "primary_opcode", "unit", "operands", "writes", "privilege", "serialization", "reserved_bits", "modifiers", "timing_row", "variants", "implementation", "evidence"}
    for entry in entries:
        absent = required_entry - entry.keys()
        if absent:
            raise MetadataError(f"{entry.get('id', '<unknown>')}: missing fields {sorted(absent)}")
        mask, value = _number(entry["mask"], f"{entry['id']}.mask"), _number(entry["value"], f"{entry['id']}.value")
        if value & ~mask:
            raise MetadataError(f"{entry['id']}: value sets bits outside mask")
        if entry["timing_row"] not in timing_ids:
            raise MetadataError(f"{entry['id']}: unknown timing row {entry['timing_row']}")
        if set(entry["variants"]) != variants:
            raise MetadataError(f"{entry['id']}: variant map must cover every declared variant")
        if entry["implementation"].get("status") == "implemented" and "pending" in entry["form"]:
            raise MetadataError(f"{entry['id']}: implemented entry has pending form")
        if entry["primary_opcode"] != value >> 26:
            raise MetadataError(f"{entry['id']}: primary opcode disagrees with value")

    supervisor_base_ids = {"sc", "rfi", "mfmsr", "mfsrr0", "mfsrr1", "mtsrr0", "mtsrr1"}
    sprg_ids = {f"{direction}sprg{index}"
                for index in range(4) for direction in ("mf", "mt")}
    supervisor_ids = supervisor_base_ids | sprg_ids
    supervisor_entries = {entry["id"]: entry for entry in entries if entry["id"] in supervisor_ids}
    if set(supervisor_entries) != supervisor_ids:
        raise MetadataError("supervisor opt-in profile must contain fifteen exact forms")
    expected_supervisor_encoding = {
        "sc": (0xFFFFFFFF, 0x44000002, "TIM-T62-001", "user"),
        "rfi": (0xFFFFFFFF, 0x4C000064, "TIM-T62-002", "supervisor"),
        "mfmsr": (0xFC1FFFFF, 0x7C0000A6, "TIM-T62-004", "supervisor"),
        "mfsrr0": (0xFC1FFFFF, 0x7C1A02A6, "TIM-T62-008", "supervisor"),
        "mfsrr1": (0xFC1FFFFF, 0x7C1B02A6, "TIM-T62-008", "supervisor"),
        "mtsrr0": (0xFC1FFFFF, 0x7C1A03A6, "TIM-T62-011", "supervisor"),
        "mtsrr1": (0xFC1FFFFF, 0x7C1B03A6, "TIM-T62-011", "supervisor"),
    }
    for name, (mask, value, timing_row, privilege) in expected_supervisor_encoding.items():
        entry = supervisor_entries[name]
        if (_number(entry["mask"], "mask"), _number(entry["value"], "value")) != (mask, value):
            raise MetadataError(f"{name}: supervisor opt-in encoding changed")
        if entry["timing_row"] != timing_row or entry["privilege"] != privilege:
            raise MetadataError(f"{name}: supervisor timing or privilege changed")
        implementation = entry["implementation"]
        if (implementation.get("status") != "implemented_opt_in_supervisor" or
                implementation.get("feature_profile") != "ENABLE_SUPERVISOR_EXCEPTIONS" or
                implementation.get("validation") != "accepted_supervisor_integration_benches"):
            raise MetadataError(f"{name}: supervisor opt-in implementation contract changed")
    for index in range(4):
        spr = 272 + index
        for direction, xo, timing_row in (("mf", 339, "TIM-T62-010"),
                                          ("mt", 467, "TIM-T62-012")):
            name = f"{direction}sprg{index}"
            entry = supervisor_entries[name]
            expected_value = ((31 << 26) | ((spr & 31) << 16) |
                              ((spr >> 5) << 11) | (xo << 1))
            expected_operands = ["rD", f"SPRG{index}"] if direction == "mf" else ["rS"]
            expected_writes = ["rD"] if direction == "mf" else [f"SPRG{index}"]
            if ((_number(entry["mask"], "mask"), _number(entry["value"], "value")) !=
                    (0xFC1FFFFF, expected_value) or entry.get("spr") != spr or
                    entry["form"] != "XFX" or entry["privilege"] != "supervisor" or
                    entry["timing_row"] != timing_row or
                    entry["operands"] != expected_operands or entry["writes"] != expected_writes):
                raise MetadataError(f"{name}: SPRG selector, encoding, or effects changed")
            implementation = entry["implementation"]
            if (implementation.get("status") != "implemented_opt_in_supervisor" or
                    implementation.get("feature_profile") != "ENABLE_SUPERVISOR_EXCEPTIONS" or
                    implementation.get("validation") != "accepted_sprg_integration_benches"):
                raise MetadataError(f"{name}: SPRG implementation contract changed")
    supervisor_contract = spec.get("supervisor_integration_semantics", {})
    xer_contract = supervisor_contract.get("xer_scope", {})
    xer_required = {"selector": 1, "feature_profile": "ENABLE_SUPERVISOR_EXCEPTIONS",
                    "privilege": "user_or_supervisor", "read_opcodes": [339, 371],
                    "write_opcode": 467, "reserved_rc": 0, "defined_mask": "0xe000007f",
                    "reserved_policy": "read zero; writes ignored"}
    if any(xer_contract.get(key) != value for key, value in xer_required.items()):
        raise MetadataError("XER SPR access contract changed")
    sprg_contract = supervisor_contract.get("sprg_scope", {})
    if (supervisor_contract.get("concrete_forms") != 15 or
            set(supervisor_contract.get("forms", [])) != supervisor_ids or
            supervisor_contract.get("default") is not False or
            supervisor_contract.get("mfmsr_read_mask") != "0x0007ff73" or
            supervisor_contract.get("rfi_restore_mask") != "0x87c0ffff" or
            supervisor_contract.get("rfi_rejected_active_mask") != "0x0000bf33" or
            sprg_contract.get("selectors") != [272, 273, 274, 275] or
            sprg_contract.get("width_bits") != 32 or
            "accepted at retirement" not in sprg_contract.get("commit", "") or
            "hard-reset value zero" not in sprg_contract.get("hard_reset", "") or
            "no distinct soft-reset" not in sprg_contract.get("soft_reset_limit", "")):
        raise MetadataError("supervisor opt-in semantic contract changed")
    reviewed_supervisor = sources.get("reviewed_supervisor_integration", {})
    sprg_sources = reviewed_supervisor.get("sprg_sources", [])
    if (reviewed_supervisor.get("concrete_opt_in_forms") != 15 or
            set(reviewed_supervisor.get("exact_appendix_rows", [])) != {"A1-127", "A1-155", "A1-165"} or
            set(reviewed_supervisor.get("shared_selector_rows", [])) != {"A1-128", "A1-138"} or
            set(reviewed_supervisor.get("sprg_aliases", [])) != sprg_ids or
            reviewed_supervisor.get("sprg_selectors") != [272, 273, 274, 275] or
            len(sprg_sources) != 3 or
            sprg_sources[0].get("pdf_pages") != [177, 178] or
            sprg_sources[1].get("pdf_page") != 95 or
            sprg_sources[2].get("pdf_pages") != [568, 585]):
        raise MetadataError("reviewed supervisor source contract changed")

    serialization_ids = {"isync", "sync", "eieio"}
    serialization_entries = {
        entry["id"]: entry for entry in entries if entry["id"] in serialization_ids
    }
    expected_serialization_encoding = {
        "isync": (0x4C00012C, "TIM-T62-003", "context_sync_refetch"),
        "sync": (0x7C0004AC, "TIM-T62-014", "execution_sync"),
        "eieio": (0x7C0006AC, "TIM-T62-016", "memory_ordering"),
    }
    if set(serialization_entries) != serialization_ids:
        raise MetadataError("serialization opt-in profile must contain three exact forms")
    for name, (value, timing_row, serialization) in expected_serialization_encoding.items():
        entry = serialization_entries[name]
        if (_number(entry["mask"], "mask"), _number(entry["value"], "value")) != (0xFFFFFFFF, value):
            raise MetadataError(f"{name}: serialization opt-in encoding changed")
        if (entry["timing_row"] != timing_row or entry["serialization"] != serialization or
                entry["privilege"] != "user" or entry["writes"] or entry["operands"]):
            raise MetadataError(f"{name}: serialization opt-in contract changed")
        implementation = entry["implementation"]
        if (implementation.get("status") != "implemented_opt_in_serialization" or
                implementation.get("feature_profile") != "ENABLE_SUPERVISOR_EXCEPTIONS" or
                implementation.get("validation") != "accepted_serialization_integration_benches"):
            raise MetadataError(f"{name}: serialization implementation contract changed")
    serialization_contract = spec.get("serialization_integration_semantics", {})
    reviewed_serialization = sources.get("reviewed_serialization_integration", {})
    if (serialization_contract.get("concrete_forms") != 3 or
            set(serialization_contract.get("forms", [])) != serialization_ids or
            serialization_contract.get("default") is not False or
            reviewed_serialization.get("concrete_opt_in_forms") != 3 or
            set(reviewed_serialization.get("exact_appendix_rows", [])) != {"A1-044", "A1-083", "A1-214"}):
        raise MetadataError("reviewed serialization semantic/source contract changed")

    add_entries = [entry for entry in entries if entry.get("family") in {"add", "addc", "adde", "addme", "addze"}]
    if len(add_entries) != 20:
        raise MetadataError("ADD family must contain 20 concrete OE/Rc forms")
    expected_xo = {"add": 266, "addc": 10, "adde": 138, "addme": 234, "addze": 202}
    for family, xo in expected_xo.items():
        family_entries = [entry for entry in add_entries if entry["family"] == family]
        combinations = {(entry["modifiers"]["OE"], entry["modifiers"]["Rc"]) for entry in family_entries}
        if combinations != {(f"fixed_{oe}", f"fixed_{rc}") for oe in range(2) for rc in range(2)}:
            raise MetadataError(f"{family}: incomplete OE/Rc expansion")
        profile = profiles[f"ADD-{family}"]
        for entry in family_entries:
            if entry["semantic_profile"] != profile["id"] or entry["extended_opcode"] != xo:
                raise MetadataError(f"{entry['id']}: semantic profile or extended opcode mismatch")
            oe = int(entry["modifiers"]["OE"][-1])
            rc = int(entry["modifiers"]["Rc"][-1])
            expected_mask = 0xFC00FFFF if family in ("addme", "addze") else 0xFC0007FF
            if _number(entry["mask"], "mask") != expected_mask:
                raise MetadataError(f"{entry['id']}: mask does not enforce reviewed XO/reserved fields")
            expected_value = (31 << 26) | (oe << 10) | (xo << 1) | rc
            if _number(entry["value"], "value") != expected_value:
                raise MetadataError(f"{entry['id']}: value disagrees with reviewed XO/OE/Rc encoding")
            if entry["reserved_bits"] != profile["reserved_bits"]:
                raise MetadataError(f"{entry['id']}: reserved-bit policy differs from semantic profile")
            expected_writes = {"rD"}
            if family != "add":
                expected_writes.add("XER.CA")
            if oe:
                expected_writes.update(("XER.OV", "XER.SO"))
            if rc:
                expected_writes.add("CR0")
            if set(entry["writes"]) != expected_writes:
                raise MetadataError(f"{entry['id']}: writes disagree with ADD-family OE/Rc semantics")
            if entry["privilege"] != "user" or entry["serialization"] != "none":
                raise MetadataError(f"{entry['id']}: reviewed ADD forms are user-level and non-serializing")
            expected_variants = {
                "PID6-603e": "legal", "PID7v-603e": "legal", "EC603e": "legal",
                "603": "pending_reconciliation", "602": "pending_missing_primary",
            }
            if entry["variants"] != expected_variants:
                raise MetadataError(f"{entry['id']}: reviewed ADD-family variant status changed")
            expected_unit = "Integer/SRU" if family == "add" and not rc else "Integer"
            if entry["unit"] != expected_unit or entry["timing_row"] != profile["timing_row"]:
                raise MetadataError(f"{entry['id']}: unit or timing row disagrees with reviewed profile")

    subtract_profiles = {p["family"]: p for p in spec.get("subtract_family_semantics", {}).get("profiles", [])}
    if set(subtract_profiles) != {"subf", "neg", "subfc", "subfe", "subfme", "subfze"}:
        raise MetadataError("subtract profiles must cover six register subtract/negate families")
    for family, xo, timing_row in (("subf", 40, "TIM-T64-028"), ("neg", 104, "TIM-T64-031"), ("subfc", 8, "TIM-T64-021"), ("subfe", 136, "TIM-T64-033"), ("subfme", 232, "TIM-T64-037"), ("subfze", 200, "TIM-T64-035")):
        selected = [e for e in entries if e.get("family") == family]
        if len(selected) != 4 or {(e["modifiers"]["OE"], e["modifiers"]["Rc"]) for e in selected} != {(f"fixed_{oe}", f"fixed_{rc}") for oe in (0,1) for rc in (0,1)}:
            raise MetadataError("subtract family requires four OE/Rc forms")
        unary = family in ("neg", "subfme", "subfze")
        extended = family in ("subfe", "subfme", "subfze")
        reserved = [{"field":"rB", "bits":"15:11", "required":0, "incorrect_encoding":"boundedly_undefined"}] if unary else []
        operands = ["rA"] + ([] if unary else ["rB"]) + (["XER.CA"] if extended else [])
        expressions = {"subf":"u32(rB-rA)", "neg":"u32(-rA)", "subfc":"u32(rB-rA)", "subfe":"u32(rB-rA+XER.CA-1)", "subfme":"u32(-rA+XER.CA-2)", "subfze":"u32(-rA+XER.CA-1)"}
        carries = {"subf":"XER.CA unchanged", "neg":"XER.CA unchanged", "subfc":"XER.CA receives unsigned no-borrow (rB>=rA)", "subfe":"XER.CA receives unsigned no-borrow (rB>rA or rB==rA and CAin)", "subfme":"XER.CA is zero only if rA=0xffffffff and CAin=0", "subfze":"XER.CA is one only if rA=0 and CAin=1"}
        profile = subtract_profiles[family]
        for key, value in {"id":"SUB-"+family, "extended_opcode":xo, "operands":operands, "expression":expressions[family], "carry_in":"XER.CA" if extended else "none", "carry_out":carries[family], "reserved_bits":reserved, "timing_row":timing_row}.items():
            if profile.get(key) != value:
                raise MetadataError("subtract semantic profile changed")
        for entry in selected:
            oe, rc = (int(entry["modifiers"][k][-1]) for k in ("OE", "Rc"))
            writes = {"rD"} | ({"XER.CA"} if family in ("subfc", "subfe", "subfme", "subfze") else set()) | ({"XER.OV", "XER.SO"} if oe else set()) | ({"CR0"} if rc else set())
            if (_number(entry["mask"], "mask") != (0xFC00FFFF if unary else 0xFC0007FF) or
                _number(entry["value"], "value") != (31<<26)|(oe<<10)|(xo<<1)|rc or
                entry.get("extended_opcode") != xo or entry["reserved_bits"] != reserved or entry["form"] != "XO"):
                raise MetadataError("subtract encoding/reserved fields changed")
            if set(entry["writes"]) != writes or entry["operands"] != operands or entry.get("semantic_profile") != profile["id"]:
                raise MetadataError("subtract operand/flag semantics changed")
            if (entry["timing_row"] != timing_row or entry["unit"] != "Integer" or entry["variants"] != expected_variants or entry["privilege"] != "user" or entry["serialization"] != "none" or entry.get("semantic_class") != "subtract_negate"):
                raise MetadataError("subtract scope/timing changed")
            if entry["modifiers"]["AA"] != "absent" or entry["modifiers"]["LK"] != "absent":
                raise MetadataError("subtract modifiers changed")

    immediate_subtract = [e for e in entries if e.get("family") == "subfic"]
    if len(immediate_subtract) != 1:
        raise MetadataError("SUBFIC requires one D-form")
    entry = immediate_subtract[0]
    expected = {"id":"subfic", "mnemonic":"subfic", "semantic_class":"subtract_immediate", "semantic_profile":"SUBIMM-subfic", "form":"D", "mask":"0xfc000000", "value":"0x20000000", "primary_opcode":8, "operands":["rA", "SIMM"], "writes":["rD", "XER.CA"], "reserved_bits":[], "modifiers":{k:"absent" for k in ("OE", "Rc", "AA", "LK")}, "unit":"Integer", "timing_row":"TIM-T64-003", "privilege":"user", "serialization":"none", "variants":expected_variants}
    if any(entry.get(k) != v for k, v in expected.items()) or "extended_opcode" in entry:
        raise MetadataError("SUBFIC encoding/operand/flags changed")
    profile = spec.get("subtract_immediate_semantics", {})
    expected_profile = {"id":"SUBIMM-subfic", "expression":"u32(sext16(SIMM)-rA)", "carry_in":"none", "carry_out":"XER.CA receives unsigned no-borrow (u32(sext16(SIMM))>=rA)", "rA_zero":"real register", "preserved":["CR", "XER.OV", "XER.SO"], "timing_row":"TIM-T64-003"}
    if any(profile.get(k) != v for k, v in expected_profile.items()):
        raise MetadataError("SUBFIC semantic profile changed")

    immediate_add = [e for e in entries if e.get("family") == "addic"]
    if {e["id"] for e in immediate_add} != {"addic", "addic."}:
        raise MetadataError("ADDIC requires two D-forms")
    for entry in immediate_add:
        record = entry["id"] == "addic."
        op = 13 if record else 12
        expected = {"mnemonic":entry["id"], "semantic_class":"add_immediate_carry", "semantic_profile":"ADDIMM-addic", "form":"D", "mask":"0xfc000000", "value":f"0x{op<<26:08x}", "primary_opcode":op, "operands":["rA", "SIMM"], "writes":["rD", "XER.CA"]+(["CR0"] if record else []), "reserved_bits":[], "modifiers":{"OE":"absent", "Rc":f"fixed_{int(record)}", "AA":"absent", "LK":"absent"}, "unit":"Integer", "timing_row":"TIM-T64-007" if record else "TIM-T64-006", "privilege":"user", "serialization":"none", "variants":expected_variants}
        if any(entry.get(k) != v for k,v in expected.items()) or "extended_opcode" in entry:
            raise MetadataError("ADDIC encoding/operand/flags changed")
    profile = spec.get("add_immediate_semantics", {})
    expected = {"id":"ADDIMM-addic", "expression":"u32(rA+sext16(SIMM))", "carry_in":"none", "carry_out":"XER.CA receives unsigned carry of rA+u32(sext16(SIMM))", "rA_zero":"real register", "record":"primary13 only; CR0 from result and current SO", "preserved":["XER.OV", "XER.SO"]}
    if any(profile.get(k) != v for k,v in expected.items()):
        raise MetadataError("ADDIC semantic profile changed")

    and_immediate = [e for e in entries if e.get("semantic_class") == "logical_immediate_record"]
    if {e["id"] for e in and_immediate} != {"andi.", "andis."}:
        raise MetadataError("AND-immediate requires two D-forms")
    for entry in and_immediate:
        high = entry["id"] == "andis."
        op = 29 if high else 28
        expected = {"mnemonic":entry["id"], "family":"andis" if high else "andi", "semantic_profile":"ANDIMM", "form":"D", "mask":"0xfc000000", "value":f"0x{op<<26:08x}", "primary_opcode":op, "operands":["rS", "UIMM"], "writes":["rA", "CR0"], "reserved_bits":[], "modifiers":{"OE":"absent", "Rc":"fixed_1", "AA":"absent", "LK":"absent"}, "unit":"Integer", "timing_row":"TIM-T64-018" if high else "TIM-T64-017", "privilege":"user", "serialization":"none", "variants":expected_variants}
        if any(entry.get(k) != v for k,v in expected.items()) or "extended_opcode" in entry:
            raise MetadataError("AND-immediate encoding/operand/flags changed")
    profile = spec.get("and_immediate_semantics", {})
    expected = {"id":"ANDIMM", "expressions":{"andi.":"u32(rS & zext16(UIMM))", "andis.":"u32(rS & (UIMM<<16))"}, "record":"always; CR0 from result and current SO", "preserved":["XER", "CR1-CR7"], "rS_zero":"real register"}
    if any(profile.get(k) != v for k,v in expected.items()):
        raise MetadataError("AND-immediate semantic profile changed")
    conflict = profile.get("secondary_conflict", {})
    if (conflict.get("source") != "MPC601UM.pdf" or conflict.get("pdf_page") != 574 or conflict.get("observed_operator") != "+" or conflict.get("accepted_operator") != "AND" or not conflict.get("resolution")):
        raise MetadataError("ANDIS secondary conflict must remain explicit")

    logical_entries = [entry for entry in entries if entry.get("semantic_class") == "register_logical"]
    if len(logical_entries) != 16:
        raise MetadataError("register-logical family must contain 16 concrete Rc forms")
    expected_variants = {
        "PID6-603e": "legal", "PID7v-603e": "legal", "EC603e": "legal",
        "603": "pending_reconciliation", "602": "pending_missing_primary",
    }
    for family, xo in logical_xo.items():
        family_entries = [entry for entry in logical_entries if entry["family"] == family]
        if {entry["modifiers"]["Rc"] for entry in family_entries} != {"fixed_0", "fixed_1"}:
            raise MetadataError(f"{family}: incomplete Rc expansion")
        profile = logical_profiles[f"LOGIC-{family}"]
        for entry in family_entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            if entry["semantic_profile"] != profile["id"] or entry["extended_opcode"] != xo:
                raise MetadataError(f"{entry['id']}: logical semantic profile or extended opcode mismatch")
            if _number(entry["mask"], "mask") != 0xFC0007FF:
                raise MetadataError(f"{entry['id']}: logical mask must fix OPCD, XO, and Rc")
            expected_value = (31 << 26) | (xo << 1) | rc
            if _number(entry["value"], "value") != expected_value:
                raise MetadataError(f"{entry['id']}: value disagrees with reviewed XO/Rc encoding")
            if entry["reserved_bits"] or entry["modifiers"]["OE"] != "absent":
                raise MetadataError(f"{entry['id']}: reviewed logical X-form has no reserved operand field or OE")
            expected_writes = {"rA"} | ({"CR0"} if rc else set())
            if set(entry["writes"]) != expected_writes:
                raise MetadataError(f"{entry['id']}: writes disagree with logical Rc semantics")
            if entry["unit"] != "Integer" or entry["timing_row"] != profile["timing_row"]:
                raise MetadataError(f"{entry['id']}: unit or timing row disagrees with reviewed profile")
            if entry["privilege"] != "user" or entry["serialization"] != "none":
                raise MetadataError(f"{entry['id']}: reviewed logical forms are user-level and non-serializing")
            if entry["variants"] != expected_variants:
                raise MetadataError(f"{entry['id']}: reviewed logical-family variant status changed")
            expected_status = "implemented"
            if entry["implementation"].get("status") != expected_status:
                raise MetadataError(f"{entry['id']}: register-logical implementation status disagrees with Rc support")
            expected_validation = "accepted_core_logical_bench" if not rc else "accepted_core_record_logical_bench"
            if entry["implementation"].get("validation") != expected_validation:
                raise MetadataError(f"{entry['id']}: register-logical validation status changed")

    expected_unary_rows = ["A1-023", "A1-046", "A1-047"]
    if (reviewed_unary_source.get("source_rows") != expected_unary_rows or
        reviewed_unary_source.get("canonical_families") != ["cntlzw", "extsb", "extsh"]):
        raise MetadataError("integer-unary source provenance changed")
    expected_unary_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_pages": [362, 363], "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 378, "table": "A-5"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 391, "table": "A-36"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 94, "section": "2.3.1.1", "topic": "reserved fields"},
    ]
    if reviewed_unary_source.get("primary_encoding") != expected_unary_primary:
        raise MetadataError("integer-unary primary source anchors changed")
    unary_semantics = spec.get("integer_unary_semantics", {})
    if (unary_semantics.get("encoding_source") != {
            "file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf",
            "tables": ["A-1", "A-5", "A-36"], "pdf_pages": [362, 363, 378, 391]} or
        unary_semantics.get("reserved_field_source") != {
            "file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf",
            "pdf_page": 94, "section": "2.3.1.1"}):
        raise MetadataError("integer-unary encoding/reserved source anchors changed")
    unary_common = unary_semantics.get("common_effects", {})
    expected_unary_common = {
        "operand_layout": "X-form rS is the sole source and rA is the destination; rB is reserved and must be zero.",
        "XER": "All XER fields, including CA, OV, and SO, are unchanged.",
        "Rc_0": "CR0 is unchanged.",
        "Rc_1": "CR0.LT/GT/EQ are the signed 32-bit result compared with zero; CR0.SO copies the current unchanged XER.SO.",
    }
    if any(unary_common.get(key) != value for key, value in expected_unary_common.items()):
        raise MetadataError("integer-unary common operand/CR/XER semantics changed")
    unary_expressions = {
        "cntlzw": "count_leading_zeros_32(rS), yielding 0 through 32",
        "extsb": "sign_extend_8_to_32(rS[24:31])",
        "extsh": "sign_extend_16_to_32(rS[16:31])",
    }
    unary_timing = {"cntlzw": "TIM-T64-025", "extsb": "TIM-T64-052", "extsh": "TIM-T64-051"}
    unary_pages = {"cntlzw": 584, "extsb": 610, "extsh": 611}
    expected_unary_reserved = [{"field": "rB", "bits": "15:11", "required": 0, "incorrect_encoding": "boundedly_undefined"}]
    unary_entries = [entry for entry in entries if entry.get("semantic_class") == "integer_unary"]
    if len(unary_entries) != 6:
        raise MetadataError("integer-unary family must contain six concrete Rc forms")
    unary_statuses = {entry["implementation"].get("status") for entry in unary_entries}
    if unary_statuses != {"implemented"}:
        raise MetadataError("integer-unary family must contain six implemented forms")
    for family, xo in unary_xo.items():
        profile = unary_profiles[f"UNARY-{family}"]
        expected_profile = {
            "family": family,
            "extended_opcode": xo,
            "operands": ["rS"],
            "expression": unary_expressions[family],
            "reserved_bits": expected_unary_reserved,
            "timing_row": unary_timing[family],
        }
        if any(profile.get(key) != value for key, value in expected_profile.items()):
            raise MetadataError(f"{family}: integer-unary semantic profile changed")
        source = profile.get("semantic_source", {})
        if source.get("file") != "MPC601UM.pdf" or source.get("pdf_page") != unary_pages[family]:
            raise MetadataError(f"{family}: integer-unary semantic source changed")
        family_entries = [entry for entry in unary_entries if entry["family"] == family]
        if {entry["modifiers"]["Rc"] for entry in family_entries} != {"fixed_0", "fixed_1"}:
            raise MetadataError(f"{family}: incomplete Rc expansion")
        for entry in family_entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            if (entry.get("semantic_profile") != profile["id"] or
                entry.get("extended_opcode") != xo or entry["form"] != "X"):
                raise MetadataError(f"{entry['id']}: integer-unary profile/form/XO mismatch")
            if (_number(entry["mask"], "mask") != 0xFC00FFFF or
                _number(entry["value"], "value") != ((31 << 26) | (xo << 1) | rc)):
                raise MetadataError(f"{entry['id']}: integer-unary mask/value must fix OPCD, rB, XO and Rc")
            if entry["reserved_bits"] != expected_unary_reserved:
                raise MetadataError(f"{entry['id']}: integer-unary reserved-rB policy changed")
            if entry["operands"] != ["rS"] or entry["writes"] != (["rA"] + (["CR0"] if rc else [])):
                raise MetadataError(f"{entry['id']}: integer-unary operands/writes changed")
            if (entry["modifiers"] != {"OE": "absent", "Rc": f"fixed_{rc}", "AA": "absent", "LK": "absent"} or
                entry["unit"] != "Integer" or entry["timing_row"] != unary_timing[family] or
                entry["privilege"] != "user" or entry["serialization"] != "none" or
                entry["variants"] != expected_variants):
                raise MetadataError(f"{entry['id']}: integer-unary scope/timing/modifiers changed")
            implementation = entry["implementation"]
            expected_rtl = ["rtl/ppc_decode.sv", "rtl/ppc_dispatch.sv", "rtl/ppc_iu.sv", "rtl/ppc_core.sv", "rtl/ppc_completion.sv", "rtl/ppc_flags.sv"]
            if implementation != {"status": "implemented", "rtl": expected_rtl, "validation": "accepted_unarylogical_benches"}:
                raise MetadataError(f"{entry['id']}: integer-unary validation status changed")

    if (reviewed_cr_source.get("source_rows") != ["A1-125", "A1-132"] or
        reviewed_cr_source.get("canonical_families") != ["mfcr", "mtcrf"] or
        reviewed_cr_source.get("excluded_newer_forms") != ["mfocrf", "mtocrf"]):
        raise MetadataError("CR-transfer source scope/provenance changed")
    expected_cr_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 365, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 385, "table": "A-26"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 392, "table": "A-36", "family": "mfcr"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 395, "table": "A-38", "family": "mtcrf"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 94, "section": "2.3.1.1", "topic": "reserved fields"},
    ]
    if reviewed_cr_source.get("primary_encoding") != expected_cr_primary:
        raise MetadataError("CR-transfer primary source anchors changed")
    cr_semantics = spec.get("cr_transfer_semantics", {})
    if cr_semantics.get("scope") != "Reviewed MFCR and MTCRF only. Newer architecture MF-OCRF/MT-OCRF forms are outside this 603e inventory and are not aliases.":
        raise MetadataError("CR-transfer scope must exclude newer OCRF forms")
    if cr_semantics.get("secondary_editorial_note") != "601UM PDF 684 pseudocode names rS[32-63], an apparent 64-bit notation inconsistency in the 32-bit instruction description; its prose and the 32-bit 603e XFX diagram establish copying corresponding 32-bit source fields into CR.":
        raise MetadataError("MTCRF secondary source notation conflict changed")
    cr_entries = [entry for entry in entries if entry.get("semantic_class") == "cr_transfer"]
    if {entry["id"] for entry in cr_entries} != {"mfcr", "mtcrf"}:
        raise MetadataError("CR-transfer decode entries must be MFCR/MTCRF exactly")
    if {"mfocrf", "mtocrf"} & set(ids):
        raise MetadataError("newer OCRF forms must not enter the 603e decoder inventory")
    mfcr_reserved = [
        {"field": "rA", "bits": "20:16", "required": 0, "incorrect_encoding": "boundedly_undefined"},
        {"field": "rB", "bits": "15:11", "required": 0, "incorrect_encoding": "boundedly_undefined"},
    ]
    mtcrf_reserved = [
        {"field": "reserved", "bits": "20", "required": 0, "incorrect_encoding": "boundedly_undefined"},
        {"field": "reserved", "bits": "11", "required": 0, "incorrect_encoding": "boundedly_undefined"},
    ]
    cr_expected = {
        "mfcr": {"form": "X", "xo": 19, "mask": 0xFC1FFFFF, "value": 0x7C000026,
                 "operands": ["CR"], "writes": ["rD"], "reserved": mfcr_reserved,
                 "timing": "TIM-T63-010", "expression": "rD = CR[0:31]", "page": 676},
        "mtcrf": {"form": "XFX", "xo": 144, "mask": 0xFC100FFF, "value": 0x7C000120,
                  "operands": ["FXM", "rS"], "writes": ["CR[FXM-selected fields]"], "reserved": mtcrf_reserved,
                  "timing": "TIM-T63-011", "expression": "for i=0..7, if FXM[i]=1 then CR field i = rS field i; otherwise CR field i is unchanged", "page": 684},
    }
    cr_statuses = {entry["implementation"].get("status") for entry in cr_entries}
    if cr_statuses != {"implemented"}:
        raise MetadataError("CR-transfer family must contain two implemented forms")
    for family, expected in cr_expected.items():
        entry = next(entry for entry in cr_entries if entry["id"] == family)
        profile = cr_profiles[f"CRXFER-{family}"]
        for key, value in {"family": family, "form": expected["form"], "extended_opcode": expected["xo"],
                           "operands": expected["operands"], "expression": expected["expression"],
                           "writes": expected["writes"], "reserved_bits": expected["reserved"],
                           "timing_row": expected["timing"]}.items():
            if profile.get(key) != value:
                raise MetadataError(f"{family}: CR-transfer semantic profile changed")
        source = profile.get("semantic_source", {})
        if source.get("file") != "MPC601UM.pdf" or source.get("pdf_page") != expected["page"]:
            raise MetadataError(f"{family}: CR-transfer semantic source changed")
        if (entry.get("semantic_profile") != profile["id"] or entry["form"] != expected["form"] or
            entry.get("extended_opcode") != expected["xo"] or _number(entry["mask"], "mask") != expected["mask"] or
            _number(entry["value"], "value") != expected["value"]):
            raise MetadataError(f"{family}: CR-transfer form/XO/mask/value changed")
        if entry["reserved_bits"] != expected["reserved"]:
            raise MetadataError(f"{family}: CR-transfer reserved-bit policy changed")
        if entry["operands"] != expected["operands"] or entry["writes"] != expected["writes"]:
            raise MetadataError(f"{family}: CR-transfer operands/writes changed")
        if (entry["modifiers"] != {"OE": "absent", "Rc": "fixed_0", "AA": "absent", "LK": "absent"} or
            entry["unit"] != "SRU" or entry["timing_row"] != expected["timing"] or
            entry["privilege"] != "user" or entry["serialization"] != "none" or entry["variants"] != expected_variants):
            raise MetadataError(f"{family}: CR-transfer scope/timing/modifiers changed")
        implementation = entry["implementation"]
        expected_cr_rtl = ["rtl/ppc_decode.sv", "rtl/ppc_special.sv", "rtl/ppc_core.sv", "rtl/ppc_completion.sv", "rtl/ppc_flags.sv"]
        expected_implementation = {
            "status": "implemented", "rtl": expected_cr_rtl,
            "validation": "accepted_cr_transfer_benches",
            "scheduling": "serialized after draining older operations; no 603e timing acceptance",
        }
        if implementation != expected_implementation:
            raise MetadataError(f"{family}: CR-transfer validation marker changed")
    mtcrf_profile = cr_profiles["CRXFER-mtcrf"]
    if mtcrf_profile.get("field_mapping") != "FXM is instruction word bits 19:12 in MSB-first order; FXM[0] selects CR0 and FXM[7] selects CR7.":
        raise MetadataError("MTCRF FXM-to-CR field mapping changed")
    if mtcrf_profile.get("FXM_zero") != "No CR field is selected; CR is unchanged.":
        raise MetadataError("MTCRF zero-FXM preservation changed")

    cr_logical_families = list(cr_logical_xo)
    expected_cr_logical_rows = [f"A1-{row:03d}" for row in range(24, 32)]
    if (reviewed_cr_logical_source.get("source_rows") != expected_cr_logical_rows or
        reviewed_cr_logical_source.get("canonical_families") != cr_logical_families or
        reviewed_cr_logical_source.get("separate_state_transfer_forms") != ["mcrf", "mcrxr"]):
        raise MetadataError("CR-logical source scope/provenance changed")
    expected_cr_logical_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 362, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 394, "table": "A-37"},
    ]
    if reviewed_cr_logical_source.get("primary_encoding") != expected_cr_logical_primary:
        raise MetadataError("CR-logical primary source anchors changed")
    cr_logical_semantics = spec.get("cr_logical_semantics", {})
    if cr_logical_semantics.get("scope") != "Reviewed eight XL-form Boolean CR operations; MCRF and MCRXR are separately reviewed state-transfer forms.":
        raise MetadataError("CR-logical scope changed")
    if cr_logical_semantics.get("bit_numbering") != "crbD, crbA and crbB are architectural CR bit numbers 0 through 31; bit 0 is CR[31] in the HDL vector.":
        raise MetadataError("CR-logical bit numbering changed")
    if cr_logical_semantics.get("source_snapshot") != "Both input bits are read from the pre-instruction CR before the selected destination bit is replaced, including crbD/crbA/crbB aliases.":
        raise MetadataError("CR-logical old-source snapshot rule changed")
    if cr_logical_semantics.get("preserved") != ["all unselected CR bits", "GPR", "XER"]:
        raise MetadataError("CR-logical preservation contract changed")
    cr_logical_entries = [entry for entry in entries if entry.get("semantic_class") == "cr_logical"]
    if {entry["id"] for entry in cr_logical_entries} != set(cr_logical_xo):
        raise MetadataError("CR-logical decode entries must be the reviewed eight exactly")
    cr_logical_expression = {
        "crand": "a AND b", "crandc": "a AND NOT b",
        "creqv": "NOT (a XOR b)", "crnand": "NOT (a AND b)",
        "crnor": "NOT (a OR b)", "cror": "a OR b",
        "crorc": "a OR NOT b", "crxor": "a XOR b",
    }
    cr_logical_timing = {
        "crand": "TIM-T63-006", "crandc": "TIM-T63-003",
        "creqv": "TIM-T63-007", "crnand": "TIM-T63-005",
        "crnor": "TIM-T63-002", "cror": "TIM-T63-009",
        "crorc": "TIM-T63-008", "crxor": "TIM-T63-004",
    }
    cr_logical_pages = {family: 585 + index for index, family in enumerate(cr_logical_families)}
    expected_cr_logical_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_special.sv", "rtl/ppc_core.sv",
        "rtl/ppc_completion.sv", "rtl/ppc_flags.sv",
    ]
    for family, xo in cr_logical_xo.items():
        entry = next(entry for entry in cr_logical_entries if entry["id"] == family)
        profile = cr_logical_profiles[f"CRLOGIC-{family}"]
        expected_profile = {
            "family": family, "extended_opcode": xo,
            "operands": ["CR[crbA]", "CR[crbB]"],
            "expression": cr_logical_expression[family],
            "writes": ["CR[crbD]"], "timing_row": cr_logical_timing[family],
        }
        if any(profile.get(key) != value for key, value in expected_profile.items()):
            raise MetadataError(f"{family}: CR-logical semantic profile changed")
        source = profile.get("semantic_source", {})
        if source.get("file") != "MPC601UM.pdf" or source.get("pdf_page") != cr_logical_pages[family]:
            raise MetadataError(f"{family}: CR-logical semantic source changed")
        if (entry.get("semantic_profile") != profile["id"] or entry.get("form") != "XL" or
            entry.get("extended_opcode") != xo or _number(entry["mask"], "mask") != 0xFC0007FF or
            _number(entry["value"], "value") != ((19 << 26) | (xo << 1))):
            raise MetadataError(f"{family}: CR-logical form/XO/mask/value changed")
        if (entry["operands"] != expected_profile["operands"] or
            entry["writes"] != expected_profile["writes"] or entry["reserved_bits"]):
            raise MetadataError(f"{family}: CR-logical operands/writes/reserved fields changed")
        if (entry["modifiers"] != {"OE": "absent", "Rc": "fixed_0", "AA": "absent", "LK": "absent"} or
            entry["unit"] != "SRU" or entry["timing_row"] != cr_logical_timing[family] or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{family}: CR-logical scope/timing/modifiers changed")
        expected_implementation = {
            "status": "implemented", "rtl": expected_cr_logical_rtl,
            "validation": "accepted_cr_logical_benches",
            "scheduling": "serialized after draining older operations; no 603e timing acceptance",
        }
        if entry["implementation"] != expected_implementation:
            raise MetadataError(f"{family}: CR-logical validation marker changed")

    if (reviewed_cr_state_source.get("source_rows") != ["A1-122", "A1-124"] or
        reviewed_cr_state_source.get("canonical_families") != ["mcrf", "mcrxr"]):
        raise MetadataError("CR-state source scope/provenance changed")
    expected_cr_state_primary = [
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 365, "table": "A-1"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 395, "table": "A-37", "family": "mcrf"},
        {"file": "1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf", "pdf_page": 392, "table": "A-36", "family": "mcrxr"},
    ]
    if reviewed_cr_state_source.get("primary_encoding") != expected_cr_state_primary:
        raise MetadataError("CR-state primary source anchors changed")
    expected_cr_state_secondary = [
        {"file": "MPC601UM.pdf", "pdf_page": 673, "printed_page": "10-119", "family": "mcrf"},
        {"file": "MPC601UM.pdf", "pdf_page": 675, "printed_page": "10-121", "family": "mcrxr"},
        {"file": "MPC601UM.pdf", "pdf_pages": [61, 62], "printed_pages": ["2-15", "2-16"], "topic": "XER bit layout and reserved bits"},
    ]
    expected_cr_state_limits = [
        "The now-available primary MPCFPE.pdf section2.1.5/Table2-6, printed2-11/PDF73, defines XER SO/OV/CA and byte count (mask0xe000007f). MCRXR clears only SO/OV/CA; SPR1 remains user-accessible.",
        "MCRFS is a floating-point status operation, not an MCRF/MCRXR alias and is outside this slice.",
    ]
    if (reviewed_cr_state_source.get("secondary_semantics") != expected_cr_state_secondary or
        reviewed_cr_state_source.get("source_limits") != expected_cr_state_limits):
        raise MetadataError("CR-state secondary sources or provenance limits changed")
    cr_state_semantics = spec.get("cr_state_transfer_semantics", {})
    if cr_state_semantics.get("scope") != "Reviewed MCRF and MCRXR only. MCRFS and newer OCRF forms are not aliases and remain outside this bounded slice.":
        raise MetadataError("CR-state scope changed")
    expected_mcrf = {
        "id": "CRSTATE-mcrf",
        "expression": "CR field crfD = pre-instruction CR field crfS",
        "source_snapshot": "The complete pre-instruction source field is read before the destination field is replaced, including crfD=crfS.",
        "preserved": ["all unselected CR fields", "GPR", "XER"],
        "timing_row": "TIM-T63-001",
    }
    expected_mcrxr = {
        "id": "CRSTATE-mcrxr",
        "expression": "CR field crfD = {old XER.SO, old XER.OV, old XER.CA, 0}; XER.SO/OV/CA = 0",
        "atomic_ordering": "The CR value uses the pre-instruction XER bits; the selected CR write and three XER clears commit atomically.",
        "preserved": ["all unselected CR fields", "GPR", "XER bits 3 through 31"],
        "reserved_bit_3": "601UM Figure 2-7 and Table 2-8 show XER bit 3 reserved zero. The destination field low bit is therefore zero. This bounded state model preserves its backing xer[28] because only architected SO/OV/CA are writable.",
        "secondary_layout_note": "601UM PDF675 extracted pseudocode displays a single CR bit on the left, but the prose and affected-field list require the complete selected CR field.",
        "timing_row": "TIM-T63-012",
    }
    for key, value in expected_mcrf.items():
        if cr_state_semantics.get("mcrf", {}).get(key) != value:
            raise MetadataError("MCRF semantic profile changed")
    for key, value in expected_mcrxr.items():
        if cr_state_semantics.get("mcrxr", {}).get(key) != value:
            raise MetadataError("MCRXR semantic profile changed")
    if cr_state_semantics.get("mcrf", {}).get("semantic_source") != {
        "file": "MPC601UM.pdf", "pdf_page": 673, "printed_page": "10-119"
    } or cr_state_semantics.get("mcrxr", {}).get("semantic_source") != {
        "file": "MPC601UM.pdf", "pdf_page": 675, "printed_page": "10-121"
    }:
        raise MetadataError("CR-state semantic source locators changed")
    if cr_state_semantics.get("timing_note") != "603e timing row TIM-T63-012 prints 1& and carries dispatch plus completion serialization; TIM-T63-001 carries completion serialization. The current serialized lane is conservative and does not establish cycle timing.":
        raise MetadataError("CR-state timing boundary changed")
    cr_state_entries = [entry for entry in entries if entry.get("semantic_class") == "cr_state_transfer"]
    if {entry["id"] for entry in cr_state_entries} != {"mcrf", "mcrxr"}:
        raise MetadataError("CR-state entries must be MCRF/MCRXR exactly")
    cr_state_expected = {
        "mcrf": {
            "form": "XL", "primary": 19, "xo": 0, "mask": 0xFC63FFFF,
            "value": 0x4C000000, "operands": ["CR[crfS]"],
            "writes": ["CR[crfD]"], "timing": "TIM-T63-001",
            "reserved": [
                {"field": "reserved", "bits": "22:21", "required": 0, "incorrect_encoding": "boundedly_undefined"},
                {"field": "reserved", "bits": "17:16", "required": 0, "incorrect_encoding": "boundedly_undefined"},
                {"field": "reserved", "bits": "15:11", "required": 0, "incorrect_encoding": "boundedly_undefined"},
            ],
        },
        "mcrxr": {
            "form": "X", "primary": 31, "xo": 512, "mask": 0xFC7FFFFF,
            "value": 0x7C000400, "operands": ["XER.SO", "XER.OV", "XER.CA"],
            "writes": ["CR[crfD]", "XER.SO", "XER.OV", "XER.CA"],
            "timing": "TIM-T63-012",
            "reserved": [
                {"field": "reserved", "bits": "22:21", "required": 0, "incorrect_encoding": "boundedly_undefined"},
                {"field": "reserved", "bits": "20:16", "required": 0, "incorrect_encoding": "boundedly_undefined"},
                {"field": "reserved", "bits": "15:11", "required": 0, "incorrect_encoding": "boundedly_undefined"},
            ],
        },
    }
    expected_cr_state_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_special.sv", "rtl/ppc_core.sv",
        "rtl/ppc_completion.sv", "rtl/ppc_flags.sv",
    ]
    for family, expected in cr_state_expected.items():
        entry = next(entry for entry in cr_state_entries if entry["id"] == family)
        if (entry.get("semantic_profile") != f"CRSTATE-{family}" or entry["form"] != expected["form"] or
            entry["primary_opcode"] != expected["primary"] or entry.get("extended_opcode") != expected["xo"] or
            _number(entry["mask"], "mask") != expected["mask"] or
            _number(entry["value"], "value") != expected["value"]):
            raise MetadataError(f"{family}: CR-state form/opcode/mask/value changed")
        if (entry["operands"] != expected["operands"] or entry["writes"] != expected["writes"] or
            entry["reserved_bits"] != expected["reserved"]):
            raise MetadataError(f"{family}: CR-state operands/writes/reserved fields changed")
        if (entry["modifiers"] != {"OE": "absent", "Rc": "fixed_0", "AA": "absent", "LK": "absent"} or
            entry["unit"] != "SRU" or entry["timing_row"] != expected["timing"] or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{family}: CR-state scope/timing/modifiers changed")
        expected_implementation = {
            "status": "implemented", "rtl": expected_cr_state_rtl,
            "validation": "accepted_cr_state_benches",
            "scheduling": "serialized after draining older operations; no 603e timing acceptance",
        }
        if entry["implementation"] != expected_implementation:
            raise MetadataError(f"{family}: CR-state validation marker changed")

    multiply_semantics = spec.get("multiply_low_semantics", {})
    multiply_profiles = {
        profile["id"]: profile for profile in multiply_semantics.get("profiles", [])
    }
    if set(multiply_profiles) != {"MULLOW-mulli", "MULLOW-mullw"}:
        raise MetadataError("multiply-low profiles must cover MULLI and MULLW")
    if (multiply_semantics.get("ca_rule") != "MULLI and every MULLW form preserve XER.CA." or
        "MULLI 3" not in multiply_semantics.get("implementation_timing", "") or
        "MULLW 5" not in multiply_semantics.get("implementation_timing", "") or
        "accepted finish at E+N" not in multiply_semantics.get("implementation_timing", "") or
        "does not complete P08" not in multiply_semantics.get("implementation_timing", "")):
        raise MetadataError("multiply-low CA or bounded timing contract changed")
    multiply_entries = [entry for entry in entries if entry.get("semantic_class") == "multiply_low"]
    if {entry["id"] for entry in multiply_entries} != {
        "mulli", "mullw", "mullw.", "mullwo", "mullwo."
    }:
        raise MetadataError("multiply-low family must contain five concrete forms")
    expected_multiply_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_dispatch.sv", "rtl/ppc_iu.sv",
        "rtl/ppc_core.sv", "rtl/ppc_completion.sv", "rtl/ppc_flags.sv",
    ]
    for entry in multiply_entries:
        if entry["family"] == "mulli":
            expected = ("D", 7, None, 0xFC000000, 0x1C000000,
                        ["rA", "EXTS(SIMM16)"], ["rD"], "TIM-T64-002",
                        {"OE": "absent", "Rc": "absent", "AA": "absent", "LK": "absent"})
        else:
            oe = 1 if entry["id"] in {"mullwo", "mullwo."} else 0
            rc = 1 if entry["id"].endswith(".") else 0
            writes = ["rD"] + (["XER.OV", "XER.SO"] if oe else []) + (["CR0"] if rc else [])
            expected = ("XO", 31, 235, 0xFC0007FF,
                        (31 << 26) | (oe << 10) | (235 << 1) | rc,
                        ["rA", "rB"], writes, "TIM-T64-039",
                        {"OE": f"fixed_{oe}", "Rc": f"fixed_{rc}", "AA": "absent", "LK": "absent"})
        form, primary, xo, mask, value, operands, writes, timing_row, modifiers = expected
        if (entry["semantic_profile"] != f"MULLOW-{entry['family']}" or
            entry["form"] != form or entry["primary_opcode"] != primary or
            entry.get("extended_opcode") != xo or _number(entry["mask"], "mask") != mask or
            _number(entry["value"], "value") != value):
            raise MetadataError(f"{entry['id']}: multiply-low encoding changed")
        if (entry["operands"] != operands or entry["writes"] != writes or
            entry["modifiers"] != modifiers or entry["reserved_bits"]):
            raise MetadataError(f"{entry['id']}: multiply-low operands/writes/modifiers changed")
        if (entry["timing_row"] != timing_row or entry["unit"] != "Integer" or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{entry['id']}: multiply-low timing/scope changed")
        implementation = entry["implementation"]
        expected_latency = 3 if entry["family"] == "mulli" else 5
        if (implementation.get("status") != "implemented" or
            implementation.get("rtl") != expected_multiply_rtl or
            implementation.get("validation") != "accepted_multiply_low_benches" or
            implementation.get("timing") !=
            f"conservative_maximum_Table6-4_reservation; E+{expected_latency} accepted finish; lower operand-selected timing unresolved"):
            raise MetadataError(f"{entry['id']}: multiply-low implementation boundary changed")

    multiply_high_semantics = spec.get("multiply_high_semantics", {})
    multiply_high_profiles = {
        profile["id"]: profile for profile in multiply_high_semantics.get("profiles", [])
    }
    if set(multiply_high_profiles) != {"MULHIGH-mulhw", "MULHIGH-mulhwu"}:
        raise MetadataError("multiply-high profiles must cover MULHW and MULHWU")
    if ("reserved and must be zero" not in multiply_high_semantics.get("reserved_oe", "") or
        "signed interpretation" not in multiply_high_semantics.get("flag_rule", "") or
        "MULHW 5" not in multiply_high_semantics.get("implementation_timing", "") or
        "MULHWU 6" not in multiply_high_semantics.get("implementation_timing", "") or
        "accepted finish at E+N" not in multiply_high_semantics.get("implementation_timing", "") or
        "does not complete P08" not in multiply_high_semantics.get("implementation_timing", "")):
        raise MetadataError("multiply-high reserved-bit, flag, or timing contract changed")
    multiply_high_entries = [entry for entry in entries if entry.get("semantic_class") == "multiply_high"]
    if {entry["id"] for entry in multiply_high_entries} != {
        "mulhw", "mulhw.", "mulhwu", "mulhwu."
    }:
        raise MetadataError("multiply-high family must contain four concrete forms")
    expected_high_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_dispatch.sv", "rtl/ppc_iu.sv",
        "rtl/ppc_core.sv", "rtl/ppc_completion.sv", "rtl/ppc_flags.sv",
    ]
    expected_high_reserved = [{
        "field": "reserved_OE_position", "architectural_bit": "21", "word_bit": "10",
        "required": 0, "incorrect_encoding": "boundedly_undefined",
    }]
    for entry in multiply_high_entries:
        family = entry["family"]
        xo = 75 if family == "mulhw" else 11
        rc = 1 if entry["id"].endswith(".") else 0
        if (entry["semantic_profile"] != f"MULHIGH-{family}" or entry["form"] != "XO" or
            entry["primary_opcode"] != 31 or entry.get("extended_opcode") != xo or
            _number(entry["mask"], "mask") != 0xFC0007FF or
            _number(entry["value"], "value") != ((31 << 26) | (xo << 1) | rc)):
            raise MetadataError(f"{entry['id']}: multiply-high encoding changed")
        if (entry["operands"] != ["rA", "rB"] or
            entry["writes"] != (["rD"] + (["CR0"] if rc else [])) or
            entry["reserved_bits"] != expected_high_reserved or
            entry["modifiers"] != {"OE": "reserved_0", "Rc": f"fixed_{rc}", "AA": "absent", "LK": "absent"}):
            raise MetadataError(f"{entry['id']}: multiply-high operands/writes/reserved bit changed")
        profile = multiply_high_profiles[f"MULHIGH-{family}"]
        if (entry["timing_row"] != profile["timing_row"] or entry["unit"] != "Integer" or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{entry['id']}: multiply-high timing/scope changed")
        implementation = entry["implementation"]
        expected_latency = 5 if family == "mulhw" else 6
        if (implementation.get("status") != "implemented" or
            implementation.get("rtl") != expected_high_rtl or
            implementation.get("validation") != "accepted_multiply_high_benches" or
            implementation.get("timing") !=
            f"conservative_maximum_Table6-4_reservation; E+{expected_latency} accepted finish; lower operand-selected timing unresolved"):
            raise MetadataError(f"{entry['id']}: multiply-high implementation boundary changed")

    divwu_semantics = spec.get("divide_unsigned_semantics", {})
    if ("undefined" not in divwu_semantics.get("zero_divisor_architecture", "") or
        "returns rD=0" not in divwu_semantics.get("zero_divisor_local_policy", "") or
        "records EQ" not in divwu_semantics.get("zero_divisor_local_policy", "") or
        "detects rB=0" not in divwu_semantics.get("zero_divisor_local_policy", "") or
        "16-step radix-4" not in divwu_semantics.get("implementation_timing", "") or
        "20 execute cycles" not in divwu_semantics.get("implementation_timing", "") or
        "37 when configured" not in divwu_semantics.get("implementation_timing", "") or
        "does not complete all P08" not in divwu_semantics.get("implementation_timing", "")):
        raise MetadataError("DIVWU undefined-result policy or timing boundary changed")
    divwu_entries = [entry for entry in entries if entry.get("semantic_class") == "divide_unsigned"]
    if {entry["id"] for entry in divwu_entries} != {
        "divwu", "divwu.", "divwuo", "divwuo."
    }:
        raise MetadataError("DIVWU family must contain four concrete OE/Rc forms")
    expected_divwu_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_dispatch.sv", "rtl/ppc_divider.sv",
        "rtl/ppc_iu.sv", "rtl/ppc_core.sv", "rtl/ppc_completion.sv",
        "rtl/ppc_flags.sv",
    ]
    for entry in divwu_entries:
        oe = 1 if entry["id"] in {"divwuo", "divwuo."} else 0
        rc = 1 if entry["id"].endswith(".") else 0
        expected_writes = ["rD"] + (["XER.OV", "XER.SO"] if oe else []) + (["CR0"] if rc else [])
        if (entry.get("family") != "divwu" or entry.get("semantic_profile") != "DIVU-divwu" or
            entry["form"] != "XO" or entry["primary_opcode"] != 31 or
            entry.get("extended_opcode") != 459 or _number(entry["mask"], "mask") != 0xFC0007FF or
            _number(entry["value"], "value") != ((31 << 26) | (oe << 10) | (459 << 1) | rc)):
            raise MetadataError(f"{entry['id']}: DIVWU encoding changed")
        if (entry["operands"] != ["rA", "rB"] or entry["writes"] != expected_writes or
            entry["reserved_bits"] or
            entry["modifiers"] != {"OE": f"fixed_{oe}", "Rc": f"fixed_{rc}", "AA": "absent", "LK": "absent"}):
            raise MetadataError(f"{entry['id']}: DIVWU operands/writes/modifiers changed")
        if (entry["timing_row"] != "TIM-T64-045" or entry["unit"] != "Integer" or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{entry['id']}: DIVWU timing/scope changed")
        implementation = entry["implementation"]
        if (implementation.get("status") != "implemented" or
            implementation.get("rtl") != expected_divwu_rtl or
            implementation.get("validation") != "accepted_divwu_benches" or
            implementation.get("zero_divisor_policy") != "deterministic_zero_and_EQ_for_architecturally_undefined_result" or
            "radix4_restoring_16_steps" not in implementation.get("timing", "") or
            "PID7v_20_default_or_PID6_37" not in implementation.get("timing", "") or
            "accepted_finish_E_plus_N" not in implementation.get("timing", "")):
            raise MetadataError(f"{entry['id']}: DIVWU implementation boundary changed")

    divw_semantics = spec.get("divide_signed_semantics", {})
    if ("rA=INT_MIN" not in divw_semantics.get("exception_architecture", "") or
        "returns rD=0" not in divw_semantics.get("exception_local_policy", "") or
        "detects both" not in divw_semantics.get("exception_local_policy", "") or
        "16-step radix-4" not in divw_semantics.get("implementation_timing", "") or
        "20 execute cycles" not in divw_semantics.get("implementation_timing", "") or
        "37 when configured" not in divw_semantics.get("implementation_timing", "") or
        "does not complete all P08" not in divw_semantics.get("implementation_timing", "")):
        raise MetadataError("DIVW exceptional-result policy or timing boundary changed")
    divw_entries = [entry for entry in entries if entry.get("semantic_class") == "divide_signed"]
    if {entry["id"] for entry in divw_entries} != {
        "divw", "divw.", "divwo", "divwo."
    }:
        raise MetadataError("DIVW family must contain four concrete OE/Rc forms")
    expected_divw_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_dispatch.sv", "rtl/ppc_divider.sv",
        "rtl/ppc_iu.sv", "rtl/ppc_core.sv", "rtl/ppc_completion.sv",
        "rtl/ppc_flags.sv",
    ]
    for entry in divw_entries:
        oe = 1 if entry["id"] in {"divwo", "divwo."} else 0
        rc = 1 if entry["id"].endswith(".") else 0
        expected_writes = ["rD"] + (["XER.OV", "XER.SO"] if oe else []) + (["CR0"] if rc else [])
        if (entry.get("family") != "divw" or entry.get("semantic_profile") != "DIVS-divw" or
            entry["form"] != "XO" or entry["primary_opcode"] != 31 or
            entry.get("extended_opcode") != 491 or _number(entry["mask"], "mask") != 0xFC0007FF or
            _number(entry["value"], "value") != ((31 << 26) | (oe << 10) | (491 << 1) | rc)):
            raise MetadataError(f"{entry['id']}: DIVW encoding changed")
        if (entry["operands"] != ["rA", "rB"] or entry["writes"] != expected_writes or
            entry["reserved_bits"] or
            entry["modifiers"] != {"OE": f"fixed_{oe}", "Rc": f"fixed_{rc}", "AA": "absent", "LK": "absent"}):
            raise MetadataError(f"{entry['id']}: DIVW operands/writes/modifiers changed")
        if (entry["timing_row"] != "TIM-T64-047" or entry["unit"] != "Integer" or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{entry['id']}: DIVW timing/scope changed")
        implementation = entry["implementation"]
        if (implementation.get("status") != "implemented" or
            implementation.get("rtl") != expected_divw_rtl or
            implementation.get("validation") != "accepted_divw_benches" or
            implementation.get("exception_policy") != "deterministic_zero_and_EQ_for_architecturally_undefined_results" or
            "radix4_restoring_16_steps" not in implementation.get("timing", "") or
            "PID7v_20_default_or_PID6_37" not in implementation.get("timing", "") or
            "accepted_finish_E_plus_N" not in implementation.get("timing", "")):
            raise MetadataError(f"{entry['id']}: DIVW implementation boundary changed")

    lsu_update_semantics = spec.get("lsu_update_semantics", {})
    if (lsu_update_semantics.get("status") != "accepted_bounded_serialized_aligned_subset" or
        "rA!=0" not in lsu_update_semantics.get("legality", "") or
        "rA!=rD" not in lsu_update_semantics.get("legality", "") or
        "commit loaded rD and EA rA together" not in
          lsu_update_semantics.get("atomic_retirement", "") or
        "does not model the 603e two-destination rename/timing behavior" not in
          lsu_update_semantics.get("implementation_scheduling", "")):
        raise MetadataError("LSU-update legality, atomicity or scheduling boundary changed")
    lsu_update_encoding = {
        "lwzu": ("D", 33, None, "load", "word", False, "TIM-T66-048"),
        "lbzu": ("D", 35, None, "load", "byte", False, "TIM-T66-050"),
        "lhzu": ("D", 41, None, "load", "half", False, "TIM-T66-056"),
        "lhau": ("D", 43, None, "load", "half", True, "TIM-T66-058"),
        "stwu": ("D", 37, None, "store", "word", False, "TIM-T66-052"),
        "stbu": ("D", 39, None, "store", "byte", False, "TIM-T66-054"),
        "sthu": ("D", 45, None, "store", "half", False, "TIM-T66-060"),
        "lwzux": ("X", 31, 55, "load", "word", False, "TIM-T66-004"),
        "lbzux": ("X", 31, 119, "load", "byte", False, "TIM-T66-007"),
        "lhzux": ("X", 31, 311, "load", "half", False, "TIM-T66-018"),
        "lhaux": ("X", 31, 375, "load", "half", True, "TIM-T66-020"),
        "stwux": ("X", 31, 183, "store", "word", False, "TIM-T66-010"),
        "stbux": ("X", 31, 247, "store", "byte", False, "TIM-T66-013"),
        "sthux": ("X", 31, 439, "store", "half", False, "TIM-T66-023"),
    }
    lsu_update_entries = {
        entry["id"]: entry for entry in entries
        if entry.get("semantic_class") == "lsu_update"
    }
    if set(lsu_update_entries) != set(lsu_update_encoding):
        raise MetadataError("LSU-update family must contain the exact 14 selected forms")
    expected_update_rtl = [
        "rtl/ppc_decode.sv", "rtl/ppc_special.sv", "rtl/ppc_completion.sv",
        "rtl/ppc_regfile_gpr.sv", "rtl/ppc_core.sv",
    ]
    for name, (form, opcode, xo, kind, size, signed_load, timing_row) in lsu_update_encoding.items():
        entry = lsu_update_entries[name]
        expected_mask = 0xFC000000 if form == "D" else 0xFC0007FF
        expected_value = opcode << 26 if form == "D" else (31 << 26) | (xo << 1)
        expected_operands = (["rD", "rA_nonzero"] if kind == "load" else
                             ["rS", "rA_nonzero"]) + (["SIMM16"] if form == "D" else ["rB"])
        expected_writes = ["rD", "rA"] if kind == "load" else ["memory", "rA"]
        expected_constraints = [{"field": "rA", "rule": "nonzero", "incorrect_encoding": "invalid_form"}]
        if kind == "load":
            expected_constraints.append({"field": "rA/rD", "rule": "not_equal",
                                         "incorrect_encoding": "invalid_form"})
        expected_reserved = [] if form == "D" else [
            {"field": "Rc", "architectural_bits": "31", "word_bits": "0",
             "required": 0, "incorrect_encoding": "invalid_form"}
        ]
        if (entry["form"] != form or entry["primary_opcode"] != opcode or
            entry.get("extended_opcode") != xo or _number(entry["mask"], "mask") != expected_mask or
            _number(entry["value"], "value") != expected_value):
            raise MetadataError(f"{name}: LSU-update exact encoding changed")
        if (entry["operands"] != expected_operands or entry["writes"] != expected_writes or
            entry.get("field_constraints") != expected_constraints or
            entry["reserved_bits"] != expected_reserved):
            raise MetadataError(f"{name}: LSU-update operands, writes or invalid-form rules changed")
        expected_modifiers = {"OE": "absent", "Rc": "absent" if form == "D" else "fixed_0"}
        memory = entry.get("memory", {})
        if (entry["modifiers"] != expected_modifiers or memory.get("kind") != kind or
            memory.get("size") != size or
            memory.get("sign_extension") != ("signed" if signed_load else "zero_or_raw") or
            entry["unit"] != "LSU" or entry["timing_row"] != timing_row or
            entry["privilege"] != "user" or entry["serialization"] != "none" or
            entry["variants"] != expected_variants):
            raise MetadataError(f"{name}: LSU-update behavior, timing or scope changed")
        implementation = entry["implementation"]
        if (implementation.get("status") != "implemented" or
            implementation.get("rtl") != expected_update_rtl or
            implementation.get("validation") != "accepted_lsu_update_benches" or
            "no 603e LSU timing acceptance" not in implementation.get("scheduling", "")):
            raise MetadataError(f"{name}: LSU-update implementation boundary changed")

    rotate_entries = [entry for entry in entries if entry.get("semantic_class") == "word_rotate"]
    if len(rotate_entries) != 6:
        raise MetadataError("word-rotate family must contain six concrete Rc forms")
    for family, opcode in rotate_opcodes.items():
        family_entries = [entry for entry in rotate_entries if entry["family"] == family]
        if {entry["modifiers"]["Rc"] for entry in family_entries} != {"fixed_0", "fixed_1"}:
            raise MetadataError(f"{family}: incomplete Rc expansion")
        profile = rotate_profiles[f"ROTATE-{family}"]
        for entry in family_entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            if entry["semantic_profile"] != profile["id"] or entry["primary_opcode"] != opcode:
                raise MetadataError(f"{entry['id']}: rotate semantic profile or primary opcode mismatch")
            if _number(entry["mask"], "mask") != 0xFC000001:
                raise MetadataError(f"{entry['id']}: M-form mask must fix OPCD and Rc only")
            if _number(entry["value"], "value") != (opcode << 26) | rc:
                raise MetadataError(f"{entry['id']}: value disagrees with reviewed OPCD/Rc encoding")
            if entry["reserved_bits"] or entry["modifiers"]["OE"] != "absent":
                raise MetadataError(f"{entry['id']}: reviewed M-form has no reserved operand field or OE")
            if entry["operands"] != profile["operands"]:
                raise MetadataError(f"{entry['id']}: rotate operands disagree with semantic profile")
            expected_writes = {"rA"} | ({"CR0"} if rc else set())
            if set(entry["writes"]) != expected_writes:
                raise MetadataError(f"{entry['id']}: writes disagree with rotate Rc semantics")
            if entry["unit"] != "Integer" or entry["timing_row"] != profile["timing_row"]:
                raise MetadataError(f"{entry['id']}: unit or timing row disagrees with rotate profile")
            if entry["privilege"] != "user" or entry["serialization"] != "none":
                raise MetadataError(f"{entry['id']}: reviewed rotate forms are user-level and non-serializing")
            if entry["variants"] != expected_variants:
                raise MetadataError(f"{entry['id']}: reviewed rotate-family variant status changed")
            expected_status = "implemented"
            if entry["implementation"].get("status") != expected_status:
                raise MetadataError(f"{entry['id']}: word-rotate implementation status changed")

    shift_entries = [entry for entry in entries if entry.get("semantic_class") == "word_shift"]
    if len(shift_entries) != 8:
        raise MetadataError("word-shift family must contain eight concrete Rc forms")
    for family, xo in shift_xo.items():
        family_entries = [entry for entry in shift_entries if entry["family"] == family]
        if {entry["modifiers"]["Rc"] for entry in family_entries} != {"fixed_0", "fixed_1"}:
            raise MetadataError(f"{family}: incomplete Rc expansion")
        profile = shift_profiles[f"SHIFT-{family}"]
        for entry in family_entries:
            rc = int(entry["modifiers"]["Rc"][-1])
            if entry["semantic_profile"] != profile["id"] or entry["extended_opcode"] != xo:
                raise MetadataError(f"{entry['id']}: shift semantic profile or extended opcode mismatch")
            if _number(entry["mask"], "mask") != 0xFC0007FF:
                raise MetadataError(f"{entry['id']}: X-form shift mask must fix OPCD, XO, and Rc")
            if _number(entry["value"], "value") != ((31 << 26) | (xo << 1) | rc):
                raise MetadataError(f"{entry['id']}: value disagrees with reviewed XO/Rc encoding")
            if entry["reserved_bits"] or entry["modifiers"]["OE"] != "absent":
                raise MetadataError(f"{entry['id']}: reviewed shift form has no reserved operand field or OE")
            if entry["operands"] != profile["operands"]:
                raise MetadataError(f"{entry['id']}: shift operands disagree with semantic profile")
            expected_writes = {"rA"}
            if family in {"sraw", "srawi"}:
                expected_writes.add("XER.CA")
            if rc:
                expected_writes.add("CR0")
            if set(entry["writes"]) != expected_writes:
                raise MetadataError(f"{entry['id']}: writes disagree with shift Rc/CA semantics")
            if entry["unit"] != "Integer" or entry["timing_row"] != profile["timing_row"]:
                raise MetadataError(f"{entry['id']}: unit or timing row disagrees with shift profile")
            if entry["privilege"] != "user" or entry["serialization"] != "none":
                raise MetadataError(f"{entry['id']}: reviewed shift forms are user-level and non-serializing")
            if entry["variants"] != expected_variants:
                raise MetadataError(f"{entry['id']}: reviewed shift-family variant status changed")
            expected_status = "implemented"
            if entry["implementation"].get("status") != expected_status:
                raise MetadataError(f"{entry['id']}: word-shift implementation status changed")

    compare_entries = [entry for entry in entries if entry.get("semantic_class") == "compare_32bit"]
    if len(compare_entries) != 4:
        raise MetadataError("compare family must contain four concrete 32-bit forms")
    for entry in compare_entries:
        family = entry["family"]
        if family not in compare_encodings:
            raise MetadataError(f"{entry['id']}: unknown compare family")
        form, opcode, xo, mask, value = compare_encodings[family]
        profile = compare_profiles[f"COMPARE-{family}"]
        if entry["form"] != form or entry["primary_opcode"] != opcode:
            raise MetadataError(f"{entry['id']}: compare form or primary opcode mismatch")
        if xo is not None and entry.get("extended_opcode") != xo:
            raise MetadataError(f"{entry['id']}: compare extended opcode mismatch")
        if _number(entry["mask"], "mask") != mask or _number(entry["value"], "value") != value:
            raise MetadataError(f"{entry['id']}: compare mask/value does not enforce reserved bits and L=0")
        expected_reserved = [{"field": "reserved", "architectural_bits": "9", "word_bits": "22", "required": 0, "incorrect_encoding": "boundedly_undefined"}]
        if form == "X":
            expected_reserved.append({"field": "reserved", "architectural_bits": "31", "word_bits": "0", "required": 0, "incorrect_encoding": "boundedly_undefined"})
        if entry["reserved_bits"] != expected_reserved:
            raise MetadataError(f"{entry['id']}: compare reserved-bit policy changed")
        expected_l = [{"field": "L", "architectural_bit": "10", "word_bit": "21", "required": 0, "incorrect_encoding": "illegal_64_bit_form_on_32_bit_603e"}]
        if entry.get("field_constraints") != expected_l:
            raise MetadataError(f"{entry['id']}: compare L=0 legality constraint changed")
        if entry["operands"] != ["BF", "rA", profile["rhs"]] or entry["writes"] != ["CR[BF]"]:
            raise MetadataError(f"{entry['id']}: compare operands or selected-field write mismatch")
        if entry["unit"] != "Integer/SRU" or entry["timing_row"] != profile["timing_row"]:
            raise MetadataError(f"{entry['id']}: unit or timing row disagrees with compare profile")
        if entry["privilege"] != "user" or entry["serialization"] != "none":
            raise MetadataError(f"{entry['id']}: reviewed compare forms are user-level and non-serializing")
        if entry["variants"] != expected_variants or entry["implementation"].get("status") != "implemented":
            raise MetadataError(f"{entry['id']}: compare variant or implementation status changed")
    implemented_ids = {entry["id"] for entry in entries if entry["implementation"].get("status") == "implemented"}
    baseline_ids = {"addi", "addis", "ori", "oris", "xori", "xoris", "add"}
    logical_ids = {"and", "andc", "or", "orc", "xor", "nand", "nor", "eqv"}
    add_ids = {"add.", "addo", "addo.", "addc", "addc.", "addco", "addco."}
    adde_ids = {"adde", "adde.", "addeo", "addeo."}
    unary_ids = {family + suffix for family in ("addme", "addze") for suffix in ("", ".", "o", "o.")}
    rotate_ids = {"rlwinm", "rlwinm.", "rlwnm", "rlwnm."}
    control_ids = {"b", "bl", "ba", "bla", "bc", "bcl", "bca", "bcla", "bclr", "bclrl", "bcctr", "bcctrl", "mflr", "mfctr", "mtlr", "mtctr", "lbz", "lbzx", "lhz", "lhzx", "lha", "lhax", "lwz", "lwzx", "stb", "stbx", "sth", "sthx", "stw", "stwx", "cmp", "cmpl", "cmpi", "cmpli"}
    logical_shift_ids = {"slw", "slw.", "srw", "srw."}
    subtract_ids = {family+suffix for family in ("subf", "neg") for suffix in ("", ".", "o", "o.")}
    subunary_ids = {family+suffix for family in ("subfme", "subfze") for suffix in ("", ".", "o", "o.")}
    subextend_ids = {"subfe", "subfe.", "subfeo", "subfeo."}
    subcarry_ids = {"subfc", "subfc.", "subfco", "subfco."}
    insert_ids = {"rlwimi", "rlwimi."}
    arithmetic_shift_ids = {"sraw", "sraw.", "srawi", "srawi."}
    integer_unary_ids = {family + suffix for family in ("cntlzw", "extsb", "extsh") for suffix in ("", ".")}
    cr_logical_ids = set(cr_logical_xo)
    cr_state_ids = {"mcrf", "mcrxr"}
    multiply_ids = {"mulli", "mullw", "mullw.", "mullwo", "mullwo."}
    multiply_high_ids = {"mulhw", "mulhw.", "mulhwu", "mulhwu."}
    divwu_ids = {"divwu", "divwu.", "divwuo", "divwuo."}
    divw_ids = {"divw", "divw.", "divwo", "divwo."}
    lsu_update_ids = set(lsu_update_encoding)
    expected_implemented = baseline_ids | logical_ids | {name + "." for name in logical_ids} | add_ids | adde_ids | unary_ids | rotate_ids | control_ids | logical_shift_ids | arithmetic_shift_ids | insert_ids | subtract_ids | subcarry_ids | subextend_ids | subunary_ids | integer_unary_ids | {"subfic", "addic", "addic.", "andi.", "andis."}
    expected_implemented |= {"mfcr", "mtcrf"} | cr_logical_ids | cr_state_ids | multiply_ids | multiply_high_ids | divwu_ids | divw_ids | lsu_update_ids
    if implemented_ids != expected_implemented:
        raise MetadataError("implemented decoder subset must contain the expected 168 entries")
    for entry in entries:
        if entry["id"] in {"andi.", "andis."} and entry["implementation"].get("validation") != "accepted_andimmediate_benches":
            raise MetadataError("AND-immediate validation status changed")
        if entry["id"] in integer_unary_ids and entry["implementation"].get("validation") != "accepted_unarylogical_benches":
            raise MetadataError("integer-unary validation status changed")
        if entry["id"] in cr_logical_ids and entry["implementation"].get("validation") != "accepted_cr_logical_benches":
            raise MetadataError("CR-logical validation status changed")
        if entry["id"] in cr_state_ids and entry["implementation"].get("validation") != "accepted_cr_state_benches":
            raise MetadataError("CR-state validation status changed")
        if entry["id"] in multiply_ids and entry["implementation"].get("validation") != "accepted_multiply_low_benches":
            raise MetadataError("multiply-low validation status changed")
        if entry["id"] in multiply_high_ids and entry["implementation"].get("validation") != "accepted_multiply_high_benches":
            raise MetadataError("multiply-high validation status changed")
        if entry["id"] in divwu_ids and entry["implementation"].get("validation") != "accepted_divwu_benches":
            raise MetadataError("DIVWU validation status changed")
        if entry["id"] in divw_ids and entry["implementation"].get("validation") != "accepted_divw_benches":
            raise MetadataError("DIVW validation status changed")
        if entry["id"] in lsu_update_ids and entry["implementation"].get("validation") != "accepted_lsu_update_benches":
            raise MetadataError("LSU-update validation status changed")
        if entry["id"] in {"addic", "addic."} and entry["implementation"].get("validation") != "accepted_addimmediate_benches":
            raise MetadataError("ADDIC validation status changed")
        if entry["id"] == "subfic" and entry["implementation"].get("validation") != "accepted_subimmediate_benches":
            raise MetadataError("SUBFIC validation status changed")
        if entry["id"] in subunary_ids and entry["implementation"].get("validation") != "accepted_subunary_benches":
            raise MetadataError("unary subtract validation status changed")
        if entry["id"] in subextend_ids and entry["implementation"].get("validation") != "accepted_subextend_benches":
            raise MetadataError("SUBFE validation status changed")
        if entry["id"] in subcarry_ids and entry["implementation"].get("validation") != "accepted_subcarry_benches":
            raise MetadataError("SUBFC validation status changed")
        if entry["id"] in subtract_ids and entry["implementation"].get("validation") != "accepted_subtract_benches":
            raise MetadataError("subtract validation status changed")
        if entry["id"] in insert_ids and entry["implementation"].get("validation") != "accepted_insert_benches":
            raise MetadataError(f"{entry['id']}: insert validation status changed")
        if entry["id"] in arithmetic_shift_ids and entry["implementation"].get("validation") != "accepted_arithmetic_shift_benches":
            raise MetadataError(f"{entry['id']}: arithmetic-shift validation status changed")
        if entry["id"] in logical_shift_ids and entry["implementation"].get("validation") != "accepted_logical_shift_benches":
            raise MetadataError(f"{entry['id']}: logical-shift validation status changed")
        if entry["id"] in control_ids and entry["implementation"].get("validation") != "accepted_control_memory_benches":
            raise MetadataError(f"{entry['id']}: control/memory validation status changed")
        if entry.get("family") in {"bc", "bclr", "bcctr"}:
            expected_bo = [4, 5, 12, 13, 20] if entry["family"] == "bcctr" else [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20]
            if entry.get("allowed_bo") != expected_bo:
                raise MetadataError(f"{entry['id']}: reserved BO policy changed")
        if entry["id"] in rotate_ids and entry["implementation"].get("validation") != "accepted_core_rotate_bench":
            raise MetadataError(f"{entry['id']}: rotate validation status changed")
        if entry["id"] in unary_ids and entry["implementation"].get("validation") != "accepted_core_add_unary_bench":
            raise MetadataError(f"{entry['id']}: unary ADD validation status changed")
        if entry["id"] in adde_ids and entry["implementation"].get("validation") != "accepted_core_adde_bench":
            raise MetadataError(f"{entry['id']}: ADDE validation status changed")
        if entry["id"] in add_ids and entry["implementation"].get("validation") != "accepted_core_add_flags_bench":
            raise MetadataError(f"{entry['id']}: ADD/ADDC validation status changed")
        if entry["id"] in baseline_ids and entry["implementation"].get("validation") != "accepted_existing_subset":
            raise MetadataError(f"{entry['id']}: baseline validation status changed")

    allowed = {frozenset(item["entries"]): item for item in spec["allowed_overlaps"]}
    for pair, item in allowed.items():
        if len(pair) != 2 or not item.get("reason"):
            raise MetadataError("allowed overlap needs two distinct entries and a reason")
        if not pair <= set(ids):
            raise MetadataError(f"allowed overlap names unknown entries: {sorted(pair - set(ids))}")
    overlaps = {frozenset(pair) for pair in find_overlaps(entries)}
    for pair in overlaps - set(allowed):
        raise MetadataError(f"overlapping decode masks: {' and '.join(sorted(pair))}")
    for pair in set(allowed) - overlaps:
        raise MetadataError(f"stale allowed overlap: {' and '.join(sorted(pair))}")


def render(spec: dict[str, Any], sources: dict[str, Any]) -> str:
    entries = spec["decode_entries"]
    default_count = sum(entry["implementation"].get("status") == "implemented"
                        for entry in entries)
    supervisor_count = sum(entry["implementation"].get("status") ==
                           "implemented_opt_in_supervisor" for entry in entries)
    serialization_count = sum(entry["implementation"].get("status") ==
                              "implemented_opt_in_serialization" for entry in entries)
    lines = [
        "# ISA implementation and source inventory",
        "",
        "Generated by `sim/tools/isa_generate.py` from `sim/spec/isa.json` and `sim/spec/isa_sources.json`; do not edit by hand.",
        "",
        "## P03v boundary",
        "",
        f"This bounded preparation covers {len(entries)} reviewed decode entries: {default_count} implemented by default and {supervisor_count + serialization_count} available only with `ENABLE_SUPERVISOR_EXCEPTIONS=1`. The opt-in forms comprise {supervisor_count} supervisor forms plus ISYNC, SYNC, and EIEIO. This does not complete P03, the 603e exception architecture, or the cache/bus ordering architecture.",
        "",
        "Secondary 601UM and DingusPPC evidence is tagged only as an encoding/semantics cross-check. The 603e UM controls implementation-specific support, and neither secondary source is a timing oracle.",
        "",
        "## Reviewed decoder metadata",
        "",
        "| Mnemonic | State | Validation | Form | Mask | Value | Unit | Operands | Writes | OE/Rc | Privilege | Variants | Timing |",
        "|---|---|---|---|---:|---:|---|---|---|---|---|---|---|",
    ]
    for entry in entries:
        mods = entry["modifiers"]
        variants = ", ".join(f"{name}:{status}" for name, status in entry["variants"].items())
        validation = entry["implementation"].get("validation", "not_applicable_pending_implementation")
        lines.append(
            f"| `{entry['mnemonic']}` | `{entry['implementation']['status']}` | `{validation}` | {entry['form']} | `{entry['mask']}` | `{entry['value']}` | {entry['unit']} | "
            f"{', '.join(entry['operands'])} | {', '.join(entry['writes'])} | "
            f"{mods['OE']}/{mods['Rc']} | {entry['privilege']} | {variants} | `{entry['timing_row']}` |"
        )
    lines += [
        "",
        "All reviewed ADD forms are user-level and non-serializing. ADD, ADDC, ADDE, ADDME and ADDZE implement all OE/Rc combinations. `add` leaves XER.CA unchanged; `addc`, `adde`, `addme`, and `addze` update it. OE controls OV and sticky SO, while Rc updates CR0 from the signed result and final SO. `addme` and `addze` masks require reserved rB=0; section 2.3.1.1 classifies incorrectly set reserved fields as boundedly undefined rather than assigning them a legal form.",
        "",
        "The reviewed register-logical forms are user-level, non-serializing X-form operations with no OE field or reserved operand bits. They write rA, leave every XER field unchanged, and update CR0 only when Rc=1; CR0.SO copies the current XER.SO. All 16 use the Integer unit and their individual Table 6-4 timing rows.",
        "",
        "CNTLZW, EXTSB and EXTSH add six user-level, non-serializing X-form entries. Their masks require reserved rB=0 and fix the complete XO plus Rc. CNTLZW counts leading zeroes from PowerPC bit 0 and returns 32 for an all-zero source; EXTSB and EXTSH sign-extend the low byte and halfword. XER is unchanged, while Rc=1 records the final signed result and current XER.SO in CR0. Source rows A1-023/A1-046/A1-047, tagged 601UM PDF584/610/611 semantics, and timing rows TIM-T64-025/052/051 are reconciled.",
        "",
        "MFCR and MTCRF add two user-level processor-control transfers through the serialized SRU implementation lane. MFCR fixes both reserved five-bit fields and copies the complete CR to rD without changing CR or XER. MTCRF fixes word bits 20 and 11; its variable FXM in word bits 19:12 selects corresponding CR fields from rS in MSB-first order, preserving every unselected field and all XER state. The architectural instructions are non-serializing; serialized implementation scheduling is conservative and does not establish timing acceptance. Newer MFOCRF/MTOCRF forms are outside the 603e inventory.",
        "",
        "Primary A-1/A-26 plus X/XFX form tables establish masks `0xfc1fffff`/`0xfc100fff` and XO19/144. Tagged 601UM PDF676/684 supplies transfer semantics. Its MTCRF pseudocode uses rS[32-63] register notation; the prose and 32-bit 603e XFX diagram establish corresponding 32-bit source fields. Timing rows TIM-T63-010/011 identify the SRU lane and completion-serialization timing class.",
        "",
        "CRAND, CRANDC, CREQV, CRNAND, CRNOR, CROR, CRORC and CRXOR add eight user-level XL-form operations. They read both source bits from the pre-instruction CR and replace exactly CR[crbD], so source/destination aliases are well-defined. Every other CR bit, every GPR and all XER fields are preserved. Primary Table A-37 on PDF394 fixes primary19, the three five-bit CR selectors, XO and Rc=0; tagged 601UM PDFs585-592 supply the Boolean equations. The architectural forms are non-serializing; the current implementation uses the conservative serialized SRU lane and does not claim 603e timing.",
        "",
        "MCRF and MCRXR add two exact CR state-transfer forms. MCRF copies one complete pre-instruction CR field to another and handles source/destination aliases before replacement. MCRXR writes `{old XER.SO, old XER.OV, old XER.CA, 0}` to the selected CR field and clears SO/OV/CA in the same retirement; every other CR and XER bit and all GPRs are preserved. Primary Tables A-37/A-36 on PDF395/392 fix masks `0xfc63ffff`/`0xfc7fffff`; tagged 601UM PDFs673/675 supply semantics. Figure 2-7 and Table 2-8 on 601UM PDFs61-62 establish reserved XER bit 3 as zero. The primary 603e UM delegates the architectural XER layout to the unavailable Programming Environments Manual, so that provenance limit remains explicit. MCRFS and newer OCRF forms are outside this slice.",
        "",
        "MULLI and the four MULLW OE/Rc forms add signed low-word multiply. Both return the low 32 product bits; MULLW OE sets OV when the complete signed product cannot be represented in 32 bits and makes SO sticky, while Rc records the signed low word and final SO in CR0. Every form preserves CA. Primary A-1/A-3/A-34/A-41 and timing rows TIM-T64-002/039 fix the encodings and list 2/3 and 2/3/4/5 execute-cycle possibilities. The source does not map operands to those counts. The bounded IU therefore reserves the conservative documented maxima, with accepted finish at E+3 for MULLI and E+5 for MULLW. Lower silicon-selected timing remains unresolved, so this does not complete P08.",
        "",
        "MULHW and MULHWU add four XO-form entries with Rc variable and the OE-position bit reserved zero. They place signed or unsigned product bits 63:32 in rD, preserve every XER field, and use the signed interpretation of that 32-bit result when Rc writes CR0; thus unsigned multiplication may still record LT when result bit31 is one. Primary A-1/A-3/A-41 and timing rows TIM-T64-030/023 establish exact encoding and list 2/3/4/5 or 2/3/4/5/6 execute-cycle possibilities. The source does not map operands to those counts. The bounded IU reserves the conservative maxima, with accepted finish at E+5 for MULHW and E+6 for MULHWU. Lower silicon-selected timing remains unresolved, so this does not complete P08.",
        "",
        "DIVWU adds four XO459 OE/Rc forms with unsigned quotient semantics and no remainder destination. A zero divisor leaves rD and CR0 LT/GT/EQ architecturally undefined; OE-enabled OV=1, sticky SO, and CR0.SO remain defined. This scaffold detects the zero divisor before iteration and chooses deterministic rD=0/CR0 EQ for those undefined fields, a local policy rather than an ISA requirement. CA is preserved. Primary A-1/A-3/A-41, TIM-T64-045, and tagged 601UM PDF603 establish the contract. A synthesizable 16-step radix-4 divider feeds a nonpipelined IU reservation with PID7v 20-cycle default or configured PID6 37-cycle accepted finish; wider P08 multiply timing and silicon-internal equivalence remain open.",
        "",
        "DIVW adds four XO491 OE/Rc forms. Normal signed quotients truncate toward zero. A zero divisor and INT_MIN divided by -1 leave rD and CR0 LT/GT/EQ architecturally undefined; this scaffold detects both before magnitude iteration and chooses local-policy rD=0/CR0 EQ while retaining defined OE OV, sticky SO, CR0.SO, and CA preservation. Primary A-1/A-3/A-41, TIM-T64-047, and tagged 601UM PDF601 establish the contract. A synthesizable 16-step radix-4 divider feeds a nonpipelined IU reservation with PID7v 20-cycle default or configured PID6 37-cycle accepted finish; wider P08 multiply timing and silicon-internal equivalence remain open.",
        "",
        "LBZU/LBZUX, LHZU/LHZUX, LHAU/LHAUX, LWZU/LWZUX, STBU/STBUX, STHU/STHUX and STWU/STWUX add fourteen aligned integer LSU update forms. Every selected form requires rA nonzero; loads also require rA different from rD, and indexed bit 31 is reserved zero. Effective addresses use pre-instruction operands, so store rS=rA and indexed source aliases store the old source before updating the base. Successful loads retire loaded rD and effective-address rA together. Stores retire rA only after the acknowledged store; faults or accepted cuts suppress the base update. Primary UM section 2.3.4.3.3-.4 PDFs107-109, A-1 PDFs364-367, A-13/A-14 PDFs381-382, and tagged 601UM instruction pages establish the bounded contract.",
        "",
        "The implementation serializes each update operation from dispatch through accepted retirement. That conservative rule permits the second architectural GPR write without a second speculative rename allocation because there is no younger mapping to observe the old base. It does not model the 603e two-destination rename resource or its 2:1 LSU timing. The external interface remains one aligned word-addressed big-endian request plus one response acknowledgement. Caches, translation, exception vectors, little endian, split misalignment and other update families remain outside this milestone.",
        "",
        "The fifteen supervisor entries are a disabled-by-default integration profile. SC saves its next PC; the selected all-zero illegal instruction and privilege violations save their current PC; supported RFI restores the reviewed MSR subset and redirects to SRR0. MFMSR masks reserved bits with `0x0007ff73`, MFSRR0/1 and MTSRR0/1 select SPR26/27, and MFS/MTSPRG0..3 select SPR272..275. State changes occur only when the serialized completion entry is accepted at retirement. The faulting pseudo-operation is an internal accepted event token with its completion diagnostic bit cleared so the old halt path does not consume it; that token is not an architectural normal-completion claim. SRR1 and the internal redirect expose the selected cause and handler transfer.",
        "",
        "SPRG0..3 are four complete 32-bit supervisor storage registers. Each MFSpr alias reads one captured register and each MTSpr alias replaces exactly one register at accepted retirement; neither changes GPRs beyond the selected MFSpr destination nor changes CR, XER, LR, CTR, MSR, or SRRs. The core reset input applies the 603e hard-reset value of zero from Table 4-8. The scaffold exposes no separate soft-reset input and therefore does not implement Table 4-9 soft-reset preservation. Primary generic XFX encoding plus PEM section 2.3.8 and Tables 8-10/8-15 establish the selector, width, storage, and supervisor contract.",
        "",
        "The profile supports only PR and IP as restored controls that affect execution and rejects active return modes outside that set. MTMSR, TGPR bank effects, nested exception priority, asynchronous events, LSU/translation/FP exceptions, and a public architectural exception trace field remain open. The full-function RFI restore mask is an inference from 603e Table 4-5 plus section 4.2.4; it is not presented as an exact mask printed by the source.",
        "",
        "ISYNC, SYNC, and EIEIO are exact operand-free opt-in forms. All wait behind the empty completion queue and idle one-outstanding special/memory lane, then block younger dispatch through accepted retirement. ISYNC performs a keep-committing-pivot recovery to PC+4 at commit, clearing queued prefetched words and using the existing fetch obligation drain/refetch contract. SYNC and EIEIO have no register state effect. The serialized transport makes their local ordering conservative: all older requests have acknowledged before dispatch, and no younger request can appear before retirement.",
        "",
        "The 603e treats EIEIO as a no-op because it already performs cache-inhibited accesses in strict program order. This scaffold does not model WIMG attributes. Its SYNC cannot observe second-level caches, alternate bus masters, coherent storage, or cache-management effects, and ISYNC does not broadcast or make modified code coherent. These forms therefore establish ordering only over the implemented instruction/data transports, not full system memory synchronization or silicon timing.",
        "",
        "SUBF/NEG add eight XO-form OE/Rc entries. SUBF computes rB-rA; NEG computes -rA and requires reserved rB=0. Both preserve CA. OE replaces OV and makes SO sticky; Rc records the final signed result plus final SO. Primary Appendix A PDF366/367/377/396 establishes encoding; secondary 601UM PDF760/701 provides semantics. TIM-T64-028/031 retain their raw timing spellings, including open SUBF OE notation caveat TIM-U08.",
        "",
        "SUBFC adds four OE/Rc forms at XO8. It computes rB-rA and always replaces CA with unsigned no-borrow (rB>=rA), including equality; it does not read incoming CA. OV/SO and Rc follow the SUBF contract. Source A1-209, primary PDF367/377/396, secondary PDF761/62 and timing TIM-T64-021/PDF271 are reconciled.",
        "",
        "SUBFE adds four XO136 OE/Rc forms. It captures incoming CA and computes rB-rA+CA-1, replacing CA with no-borrow from the full operation. Signed overflow includes the borrow adjustment. Source A1-210, primary PDF368/377/396, secondary PDF762 and timing TIM-T64-033/PDF271 are reconciled.",
        "",
        "SUBFME/SUBFZE add eight XO232/200 OE/Rc forms with reserved rB=0. They capture CA and inject fixed B=ffffffff/0 into the extended subtract operation. Signed results are -rA+CA-2 and -rA+CA-1. Source A1-212/213, primary PDF368/377/396, secondary PDF764/765 and timing TIM-T64-037/035 are reconciled.",
        "",
        "SUBFIC adds one D-form at primary8. SIMM is signed16; rA0 is a real register. Only GPR and CA are written, with no incoming CA dependency or OE/Rc. All low16 bits are immediate data. Source A1-211, primary PDF368/377/390, secondary PDF763 and TIM-T64-003 are reconciled.",
        "",
        "ADDIC/ADDIC. add D-forms at primary12/13. SIMM is signed16 and rA0 is real. Both replace CA from unsigned carry and preserve OV/SO; only primary13 records the signed result with current SO in CR0. Low16 bits remain immediate data. Source A1-005/006, primary PDF361/377/389, secondary PDF566/567 and TIM-T64-006/007 are reconciled.",
        "",
        "ANDI./ANDIS. add primary28/29 D-forms, with unsigned low/high-half immediates, real rS0 and unconditional CR0 recording. XER is preserved. Primary PDF362/378/389, secondary PDF573/574 and TIM-T64-017/018 are reconciled. The secondary ANDIS pseudocode prints addition; prose and tagged DingusPPC corroboration establish AND, with the conflict retained explicitly.",
        "",
        "The six word-rotate entries are user-level, non-serializing M-form operations. RLWINM, RLWNM and RLWIMI implement both Rc forms. MB/ME use PowerPC MSB-first bit numbering and wrap when MB is greater than ME. `rlwimi` preserves the old rA bits outside the mask; `rlwnm` takes its shift count from the numeric low five bits of rB. XER is unchanged, while Rc=1 updates CR0 using the result and current XER.SO.",
        "",
        "Primary Table A-6 on PDF 379 prints conflicting opcodes 22/20/21 for `rlwimi`/`rlwinm`/`rlwnm`. The executable metadata uses 20/21/23 because primary Tables A-1 and A-43 agree on those values; 601UM and DingusPPC provide tagged secondary corroboration. The Table A-6 discrepancy remains an open editorial/errata item.",
        "",
        "The eight word-shift entries are user-level, non-serializing X-form operations with no reserved operand fields. SLW/SRW/SRAW/SRAWI implement both Rc forms. Register forms use the numeric low six bits rB[26:31]: logical shifts return zero and arithmetic shifts return all sign bits for counts 32 through 63. `sraw` and `srawi` replace XER.CA with one only for a negative source that discards at least one one-bit; `slw` and `srw` leave CA unchanged. All four preserve OV/SO, and Rc=1 records the result with current SO.",
        "",
        "601UM Table 3-9 supplies the six-bit register-count rule. Its `slw` per-instruction prose on PDF 721 prints bit 16, inconsistent with Table 3-9 and the analogous `srw`/`sraw` text using rB[26]; the reviewed semantics follow those internally consistent statements, with tagged DingusPPC corroboration.",
        "",
        "The four compare entries fix reserved architectural bit 9 to zero and L to zero. Register forms also fix architectural bit 31 to zero. BF remains a variable three-bit selector for one CR field; signed forms use 32-bit signed operands, immediate signed comparison sign-extends SIMM16, and logical forms compare unsigned values with UIMM16 zero-extended. The selected CR field receives LT/GT/EQ and current XER.SO while XER remains unchanged. L=1 is excluded as an illegal unavailable 64-bit form on the 32-bit 603e.",
        "",
        "All sixteen register-logical entries are implemented. The nonrecord bench checks 94 results and rejects eight high-XO-bit mutations. The record bench checks a surviving instruction stream and full GPR/CR/XER commitment, owner admission, dependencies, stalls and recovery, with 33 retirements including 14 record operations. A direct SO=0/1 fixture and focused whole-core recovery-edge tests supplement it. The prior seven entries retain their accepted baseline validation state. ADD/ADDC now provide architectural XER writers: the independent arithmetic corpus checks 75 arithmetic commits and all eight OE/Rc combinations; direct held-control and nonzero-XER recovery tests supplement it. ADDE adds committed-CA capture: its independent corpus checks 72 ADDE operations, all four OE/Rc forms and seven actual carry-seed chains, supplemented by capture/stall and recovery tests.",
        "",
        "`nop` is the constrained semantic alias `ori r0,r0,0`, not a second overlapping decode entry.",
        "",
        "## Source inventory coverage",
        "",
        f"Appendix A.1 contributes {sources['observed_row_count']} observed mnemonic rows on PDF pages 361-368. The inventory now reconciles the selected supervisor and serialization rows; 124 rows retain full-mask transcription pending. The generic SPR rows cover SPR8/9 in the default profile and exact SPR26/27 plus SPR272..275 aliases in the opt-in supervisor profile. Appendix A.3 contributes 28 functional-family tables; Appendix A.4 contributes 15 form tables.",
        "",
        "| Functional tables | Coverage |",
        "|---|---|",
    ]
    for item in spec["functional_families"]:
        pages = item["pdf_pages"]
        page_text = str(pages[0]) if pages[0] == pages[1] else f"{pages[0]}-{pages[1]}"
        lines.append(f"| {item['table']} {item['name']} | PDF {page_text}; unit tag {item['unit']} |")
    lines += ["", "| Form table | Status |", "|---|---|"]
    for item in spec["instruction_forms"]:
        lines.append(f"| {item['table']} {item['form']}-form | `{item['encoding_status']}` |")
    lines += ["", "## Appendix B variant limits", "", "| Table | Variant | Recorded status | Count/detail |", "|---|---|---|---|"]
    for item in spec["appendix_b_exclusions"]:
        detail = str(len(item["mnemonics"])) + " mnemonics" if "mnemonics" in item else f"SPR {item['spr_decimal']} {item['spr_name']}"
        lines.append(f"| {item['table']} | {item['variant']} | `{item['disposition']}` | {detail} |")
    lines += [
        "",
        "Table B-3 membership is not itself an exception classification. Its 53 floating-point rows, explicitly including `fsqrt` and `fsqrts`, take floating-point unavailable on EC603e under section 4.5.8. Its final `tlbia` row is anomalous: `tlbia` is not floating point, so its EC603e exception remains pending editorial reconciliation. For the ordinary 603e, Table B-1 and the program-exception rule classify these unavailable optional instructions as illegal; interactions with an ordinary 603e running with MSR[FP]=0 still require exception-priority review. The 64-bit architecture rows remain source inventory entries but are unavailable on 603e/EC603e.",
        "",
        "## Generator checks",
        "",
        f"The validator requires schema version 1, exact A-3..A-30 and A-31..A-45 coverage, {len(sources['inventory_status_counts'])} explicit Appendix A.1 inventory-status counts, complete reviewed-family profiles and modifier expansions, compare BF/reserved/L legality, explicit preservation of source conflicts, exact units and side effects, the exact {len(entries)}-entry implemented subset with validation state, valid timing references, full variant maps, masked values, and declared handling for every overlapping decode pattern. Any intentional decode alias must name both entries and give a reason.",
        "",
        "## Open P03 work",
        "",
    ]
    lines.extend(f"- {gap}" for gap in spec["open_gaps"])
    return "\n".join(lines) + "\n"


def load_all() -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    return tuple(json.loads(path.read_text()) for path in (ISA_PATH, SOURCE_PATH, TIMING_PATH))  # type: ignore[return-value]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="write the generated Markdown")
    parser.add_argument("--check", action="store_true", help="require generated Markdown to be current")
    args = parser.parse_args()
    spec, sources, timing = load_all()
    validate(spec, sources, timing)
    generated = render(spec, sources)
    if args.write:
        MATRIX_PATH.write_text(generated)
    if args.check and (not MATRIX_PATH.exists() or MATRIX_PATH.read_text() != generated):
        raise SystemExit(f"stale generated file: {MATRIX_PATH}")
    overlap_count = len(find_overlaps(spec["decode_entries"]))
    implemented_count = sum(entry["implementation"].get("status") == "implemented" for entry in spec["decode_entries"])
    opt_in_count = sum(entry["implementation"].get("status") == "implemented_opt_in_supervisor" for entry in spec["decode_entries"])
    serialization_count = sum(entry["implementation"].get("status") == "implemented_opt_in_serialization" for entry in spec["decode_entries"])
    print(
        f"ISA metadata valid: {len(spec['decode_entries'])} reviewed entries, {implemented_count} default implemented, "
        f"{opt_in_count} supervisor opt-in, {serialization_count} serialization opt-in, "
        f"{sources['observed_row_count']} source rows, {overlap_count} overlaps "
        f"({len(spec['allowed_overlaps'])} explicitly allowed)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
