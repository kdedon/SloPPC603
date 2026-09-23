#!/usr/bin/env python3
"""Read-only inventory parser for the local DingusPPC CSV vectors.

This module intentionally does not execute the C++ reference interpreter.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


KINDS = ("integer", "float", "disasm")
REQUIRED_FIELDS = {"integer": 5, "float": 5, "disasm": 3}
KNOWN_FIELDS = {
    "integer": {"rD", "rA", "rB", "XER", "CR"},
    "float": {"round", "frA", "frB", "frC", "frD", "FPSCR", "CR"},
    "disasm": set(),
}
MODEL_METADATA = {
    "MPC603EV": {"pid": "PID7v", "pvr": "0x00070101"},
    "MPC603E": {"pid": "PID6", "pvr": "0x00060101"},
}
ROUNDING_MODES = {"RTN", "RTZ", "RPI", "RNI", "VEN"}
HEX32 = re.compile(r"^0x[0-9A-Fa-f]{1,8}$")
HEX64 = re.compile(r"^0x[0-9A-Fa-f]{1,16}$")


@dataclass(frozen=True)
class ParsedRow:
    line_number: int
    raw_line: str
    fields: tuple[str, ...]


class ParseError(ValueError):
    """A CSV row does not match the observed reference grammar."""


def _is_ignored(raw: str) -> bool:
    return not raw.strip() or raw.startswith("#")


def parse_rows(path: Path, kind: str) -> list[ParsedRow]:
    if kind not in KINDS:
        raise ValueError(f"unknown vector kind: {kind}")
    rows: list[ParsedRow] = []
    errors: list[str] = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if _is_ignored(raw):
            continue
        fields = tuple(raw.split(","))
        if len(fields) < REQUIRED_FIELDS[kind]:
            errors.append(f"{path}:{line_number}: expected at least {REQUIRED_FIELDS[kind]} fields")
            continue
        if not fields[0].strip() or (kind == "disasm" and not fields[2].strip()):
            errors.append(f"{path}:{line_number}: mnemonic/text field is empty")
            continue
        if not HEX32.fullmatch(fields[1]) or (kind == "disasm" and not HEX32.fullmatch(fields[0])):
            errors.append(f"{path}:{line_number}: opcode/address is not a 32-bit hexadecimal value")
            continue
        if kind in ("integer", "float"):
            seen: set[str] = set()
            for field in fields[2:]:
                if "=" not in field:
                    errors.append(f"{path}:{line_number}: expected key=value field, got {field!r}")
                    break
                key, value = field.split("=", 1)
                if key not in KNOWN_FIELDS[kind] or not value:
                    errors.append(f"{path}:{line_number}: unknown or empty field {field!r}")
                    break
                if key in seen:
                    errors.append(f"{path}:{line_number}: duplicate field {key!r}")
                    break
                seen.add(key)
                if kind == "integer" and key in {"rD", "rA", "rB", "XER", "CR"} and not HEX32.fullmatch(value):
                    errors.append(f"{path}:{line_number}: {key} is not a 32-bit hexadecimal value")
                    break
                if kind == "float":
                    if key == "frD" and not HEX64.fullmatch(value):
                        errors.append(f"{path}:{line_number}: frD is not a 64-bit hexadecimal value")
                        break
                    if key in {"FPSCR", "CR"} and not HEX32.fullmatch(value):
                        errors.append(f"{path}:{line_number}: {key} is not a 32-bit hexadecimal value")
                        break
                    if key == "round" and value not in ROUNDING_MODES:
                        errors.append(f"{path}:{line_number}: unknown rounding mode {value!r}")
                        break
        rows.append(ParsedRow(line_number, raw, fields))
    if errors:
        raise ParseError("\n".join(errors))
    return rows


def _file_inventory(root: Path, filename: str, kind: str) -> dict:
    path = root / filename
    data = path.read_bytes()
    rows = parse_rows(path, kind)
    return {
        "path": filename,
        "sha256": hashlib.sha256(data).hexdigest(),
        "executable_rows": len(rows),
        "field_count_distribution": {
            str(count): number for count, number in sorted(Counter(len(row.fields) for row in rows).items())
        },
    }


def build_manifest(reference_root: Path, model: str = "MPC603EV") -> dict:
    if model not in MODEL_METADATA:
        raise ValueError(f"unsupported reference model {model!r}; choose MPC603EV or MPC603E")
    return {
        "schema": "dingusppc-csv-inventory-v1",
        "reference_model": {"name": model, **MODEL_METADATA[model]},
        "reference_root": str(reference_root),
        "vectors": {
            "integer": _file_inventory(reference_root, "ppcinttests.csv", "integer"),
            "float": _file_inventory(reference_root, "ppcfloattests.csv", "float"),
            "disasm": _file_inventory(reference_root, "ppcdisasmtest.csv", "disasm"),
        },
    }


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inventory DingusPPC CSV vectors without running the oracle")
    parser.add_argument("reference_root", type=Path, help="dingusppc/cpu/ppc/test directory")
    parser.add_argument("--model", default="MPC603EV")
    parser.add_argument("-o", "--output", type=Path, help="write JSON here instead of stdout")
    args = parser.parse_args(argv)
    try:
        manifest = build_manifest(args.reference_root, args.model)
    except (OSError, ParseError, ValueError) as error:
        parser.error(str(error))
    rendered = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
