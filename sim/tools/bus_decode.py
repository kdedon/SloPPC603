#!/usr/bin/env python3
"""Validate and query the source-backed MPC603e bus encoding manifest."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SPEC_PATH = ROOT / "sim/spec/bus_encodings.json"


class DecodeError(ValueError):
    """Raised when metadata or a query is invalid."""


def load_spec(path: Path = SPEC_PATH) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def _bits(value: str, width: int, field: str) -> str:
    if not isinstance(value, str) or len(value) != width or set(value) - {"0", "1"}:
        raise DecodeError(f"{field} must be exactly {width} binary digits")
    return value


def _pattern(value: str, width: int, field: str) -> str:
    if not isinstance(value, str) or len(value) != width or set(value) - {"0", "1", "X"}:
        raise DecodeError(f"{field} must be exactly {width} characters from 0, 1, X")
    return value


def pattern_matches(pattern: str, bits: str) -> bool:
    return all(expected == "X" or expected == actual for expected, actual in zip(pattern, bits))


def expand_pattern(pattern: str) -> list[str]:
    expanded = [""]
    for char in pattern:
        choices = "01" if char == "X" else char
        expanded = [prefix + choice for prefix in expanded for choice in choices]
    return expanded


def validate(spec: dict[str, Any]) -> dict[str, int]:
    if spec.get("schema_version") != 1:
        raise DecodeError(f"unsupported schema_version: {spec.get('schema_version')!r}")
    completed = {item["table"] for item in spec.get("tables_completed", [])}
    if completed != {"7-1", "7-2", "7-3", "7-5"}:
        raise DecodeError("tables_completed must be exactly 7-1, 7-2, 7-3, and 7-5")

    rows = spec.get("tt_commands", [])
    expanded: dict[str, dict[str, Any]] = {}
    allowed_actions = {
        "not_applicable", "kill_cancel_reservation", "flush_cancel_reservation",
        "clean_or_flush", "flush", "clean",
    }
    for row in rows:
        pattern = _pattern(row.get("pattern"), 5, "TT pattern")
        expected_dc = [index for index, char in enumerate(pattern) if char == "X"]
        if row.get("dont_care_bits") != expected_dc:
            raise DecodeError(f"{pattern}: dont_care_bits disagrees with X positions")
        if row.get("status") not in {"defined", "reserved"}:
            raise DecodeError(f"{pattern}: invalid TT status")
        if row.get("snoop_action") not in allowed_actions:
            raise DecodeError(f"{pattern}: invalid snoop action")
        if row["status"] == "reserved" and row.get("command") != "reserved":
            raise DecodeError(f"{pattern}: reserved encoding has a defined command")
        for code in expand_pattern(pattern):
            if code in expanded:
                raise DecodeError(f"overlapping TT patterns {expanded[code]['pattern']} and {pattern} at {code}")
            expanded[code] = row
    if set(expanded) != {f"{value:05b}" for value in range(32)}:
        missing = sorted({f"{value:05b}" for value in range(32)} - set(expanded))
        raise DecodeError(f"TT patterns do not cover all 32 codes; missing {missing}")

    overrides = spec.get("pid7v_abe_overrides", [])
    for override in overrides:
        pattern = _bits(override.get("pattern"), 5, "ABE override pattern")
        base = expanded[pattern]
        if base["status"] != "defined" or base["command"] != override.get("command"):
            raise DecodeError(f"{pattern}: ABE override disagrees with base command")
        if override.get("master", {}).get("generation") != "generated":
            raise DecodeError(f"{pattern}: ABE override must generate a transaction")
    if len({override["pattern"] for override in overrides}) != len(overrides):
        raise DecodeError("duplicate PID7v ABE override")

    combinations = spec.get("transfer_sizes", {}).get("listed_combinations", [])
    seen_sizes: set[tuple[str, str]] = set()
    for item in combinations:
        if item.get("tbst") not in {"asserted", "negated"}:
            raise DecodeError("TBST must use logical asserted/negated state")
        tsiz = _bits(item.get("tsiz"), 3, "TSIZ")
        key = (item["tbst"], tsiz)
        if key in seen_sizes:
            raise DecodeError(f"duplicate size combination: {key}")
        seen_sizes.add(key)
        if item.get("status") != "defined" or not 1 <= item.get("transfer_size_bytes", 0) <= 32:
            raise DecodeError(f"bad size entry: {key}")
    expected_sizes = {("asserted", "010")} | {("negated", f"{value:03b}") for value in range(8)}
    if seen_sizes != expected_sizes:
        raise DecodeError("Table 7-5 combinations are incomplete or contain unlisted values")

    counts = {
        "tt_pattern_rows": len(rows),
        "tt_expanded_codes": len(expanded),
        "tt_defined_expanded_codes": sum(row["status"] == "defined" for row in expanded.values()),
        "tt_reserved_expanded_codes": sum(row["status"] == "reserved" for row in expanded.values()),
        "generic_master_generated_commands": sum(
            row["master"]["generation"] == "generated" for row in rows
        ),
        "pid7v_abe_overrides": len(overrides),
        "listed_size_combinations": len(combinations),
    }
    if counts != spec.get("expected_counts"):
        raise DecodeError(f"count mismatch: computed {counts}, expected {spec.get('expected_counts')}")
    return counts


def decode_tt(
    bits: str,
    *,
    role: str = "bus",
    pid7v_abe: bool = False,
    spec: dict[str, Any] | None = None,
) -> dict[str, Any]:
    spec = load_spec() if spec is None else spec
    validate(spec)
    bits = _bits(bits, 5, "TT")
    if role not in {"bus", "master", "snoop"}:
        raise DecodeError("role must be bus, master, or snoop")
    if pid7v_abe and role != "master":
        raise DecodeError("pid7v_abe affects master generation only")
    matches = [row for row in spec["tt_commands"] if pattern_matches(row["pattern"], bits)]
    if len(matches) != 1:
        raise DecodeError(f"TT {bits} matched {len(matches)} patterns")
    row = matches[0]
    result: dict[str, Any] = {
        "input_bits": bits,
        "matched_pattern": row["pattern"],
        "dont_care_bits": row["dont_care_bits"],
        "encoding_status": row["status"],
        "command": row["command"],
        "manual_command": row["manual_command"],
        "bus_transaction": row["bus_transaction"],
        "role": role,
    }
    if role == "master":
        master = copy.deepcopy(row["master"])
        profile = "pid7v_abe" if pid7v_abe else "generic_603e"
        if pid7v_abe:
            override = next(
                (item for item in spec["pid7v_abe_overrides"] if item["pattern"] == bits),
                None,
            )
            if override is not None:
                master = copy.deepcopy(override["master"])
        generation = master["generation"]
        result.update(
            profile=profile,
            master=master,
            generation_status={
                "generated": "supported",
                "not_generated": "unsupported_by_profile",
                "reserved": "reserved_encoding",
            }[generation],
        )
    elif role == "snoop":
        result["action_on_hit"] = row["snoop_action"]
    return result


def decode_size(
    tbst: str,
    tsiz: str,
    *,
    bus_width: int,
    context: str = "memory",
    spec: dict[str, Any] | None = None,
) -> dict[str, Any]:
    spec = load_spec() if spec is None else spec
    validate(spec)
    if tbst not in {"asserted", "negated"}:
        raise DecodeError("TBST must be asserted or negated")
    tsiz = _bits(tsiz, 3, "TSIZ")
    if bus_width not in {32, 64}:
        raise DecodeError("bus_width must be 32 or 64")
    if context not in {"memory", "address_only", "external_control"}:
        raise DecodeError("context must be memory, address_only, or external_control")
    result: dict[str, Any] = {
        "tbst": tbst,
        "tsiz": tsiz,
        "bus_width": bus_width,
        "context": context,
    }
    overrides = spec["transfer_sizes"]["context_overrides"]
    if context == "address_only":
        result.update(status="not_applicable", meaning=overrides["address_only"])
        return result
    if context == "external_control":
        raw_tbst = "0" if tbst == "asserted" else "1"
        resource_bits = raw_tbst + tsiz
        result.update(
            status="defined_resource_id",
            meaning=overrides["external_control"],
            resource_id_bits=resource_bits,
            resource_id=int(resource_bits, 2),
        )
        return result

    item = next(
        (
            entry
            for entry in spec["transfer_sizes"]["listed_combinations"]
            if entry["tbst"] == tbst and entry["tsiz"] == tsiz
        ),
        None,
    )
    if item is None:
        result.update(
            status="unlisted",
            meaning="This TBST/TSIZ combination is absent from Table 7-5; do not infer a transfer size.",
            transfer_size_bytes=None,
            data_beats=None,
        )
        return result
    result.update(item)
    mode = spec["transfer_sizes"]["mode_rules"][str(bus_width)]
    result.update(
        address_alignment_status="not_checked",
        program_access_decomposition_status="not_checked",
    )
    if item["kind"] == "cache_line_burst":
        result.update(
            mode_status="defined_for_table_7_5_bus_transfer",
            data_beats=mode["cache_line_burst_beats"],
        )
    elif bus_width == 64:
        result.update(mode_status="defined_for_table_7_5_bus_transfer", data_beats=1)
    else:
        beats = mode["nonburst_beats_by_size"].get(str(item["transfer_size_bytes"]))
        if beats is None:
            result.update(
                mode_status="unresolved_without_alignment_tables",
                data_beats=None,
            )
        else:
            result.update(mode_status="defined_for_table_7_5_bus_transfer", data_beats=beats)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="validate the encoding manifest")

    tt_parser = subparsers.add_parser("tt", help="decode TT0..TT4")
    tt_parser.add_argument("bits", help="five bits in TT0..TT4 order")
    tt_parser.add_argument("--role", choices=("bus", "master", "snoop"), default="bus")
    tt_parser.add_argument("--pid7v-abe", action="store_true", help="apply PID7v HID0[ABE] master overrides")

    size_parser = subparsers.add_parser("size", help="decode logical TBST and TSIZ0..TSIZ2")
    size_parser.add_argument("--tbst", choices=("asserted", "negated"), required=True)
    size_parser.add_argument("--tsiz", required=True, help="three bits in TSIZ0..TSIZ2 order")
    size_parser.add_argument("--bus-width", type=int, choices=(32, 64), required=True)
    size_parser.add_argument(
        "--context",
        choices=("memory", "address_only", "external_control"),
        default="memory",
    )

    args = parser.parse_args()
    spec = load_spec()
    try:
        counts = validate(spec)
        if args.command == "validate":
            print(
                "bus encodings OK: "
                f"{counts['tt_pattern_rows']} TT rows / {counts['tt_expanded_codes']} codes; "
                f"{counts['tt_defined_expanded_codes']} defined / "
                f"{counts['tt_reserved_expanded_codes']} reserved; "
                f"{counts['listed_size_combinations']} size combinations"
            )
            return 0
        if args.command == "tt":
            result = decode_tt(args.bits, role=args.role, pid7v_abe=args.pid7v_abe, spec=spec)
        else:
            result = decode_size(
                args.tbst,
                args.tsiz,
                bus_width=args.bus_width,
                context=args.context,
                spec=spec,
            )
    except DecodeError as exc:
        parser.error(str(exc))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
