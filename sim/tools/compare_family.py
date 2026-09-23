#!/usr/bin/env python3
"""Independent 32-bit reference preparation for reviewed compare forms."""

from __future__ import annotations

from dataclasses import dataclass

MASK32 = 0xFFFF_FFFF
ENCODINGS = {
    "cmp": ("X", 31, 0),
    "cmpi": ("D", 11, None),
    "cmpl": ("X", 31, 32),
    "cmpli": ("D", 10, None),
}


@dataclass(frozen=True)
class CompareResult:
    cr: int
    field: int
    ca: int
    ov: int
    so: int


def _bit(value: int, name: str) -> int:
    if value not in (0, 1):
        raise ValueError(f"{name} must be 0 or 1")
    return value


def _signed32(value: int) -> int:
    value &= MASK32
    return value - (1 << 32) if value & 0x8000_0000 else value


def evaluate(
    family: str,
    a: int,
    rhs: int,
    *,
    bf: int = 0,
    l: int = 0,
    ca: int = 0,
    ov: int = 0,
    so: int = 0,
    old_cr: int = 0,
) -> CompareResult:
    """Evaluate one reviewed L=0 compare and replace only CR field BF."""
    if family not in ENCODINGS:
        raise ValueError(f"unknown compare family: {family}")
    if not 0 <= bf < 8:
        raise ValueError("bf must be a three-bit field")
    if l != 0:
        raise ValueError("only the 32-bit L=0 form is legal on 603e")
    ca, ov, so = (_bit(value, name) for value, name in ((ca, "ca"), (ov, "ov"), (so, "so")))
    if not 0 <= old_cr <= MASK32:
        raise ValueError("old_cr must be a 32-bit value")

    a &= MASK32
    if family.endswith("i"):
        if not 0 <= rhs < (1 << 16):
            raise ValueError("immediate rhs must be a 16-bit encoded field")
        b = rhs - (1 << 16) if family == "cmpi" and rhs & 0x8000 else rhs
    else:
        b = rhs & MASK32

    if family in {"cmp", "cmpi"}:
        left = _signed32(a)
        right = _signed32(b)
    else:
        left = a
        right = b
    relation = 0b1000 if left < right else (0b0100 if left > right else 0b0010)
    field = relation | so
    shift = 28 - 4 * bf
    field_mask = 0xF << shift
    cr = (old_cr & ~field_mask) | (field << shift)
    return CompareResult(cr=cr, field=field, ca=ca, ov=ov, so=so)


def encode(family: str, *, bf: int, ra: int, rhs: int, l: int = 0) -> int:
    """Encode one reviewed compare, rejecting unavailable L=1 forms."""
    if family not in ENCODINGS:
        raise ValueError(f"unknown compare family: {family}")
    if not 0 <= bf < 8:
        raise ValueError("bf must be a three-bit field")
    if not 0 <= ra < 32:
        raise ValueError("ra must be a five-bit field")
    if l != 0:
        raise ValueError("only the 32-bit L=0 form is legal on 603e")
    form, opcode, xo = ENCODINGS[family]
    word = (opcode << 26) | (bf << 23) | (ra << 16)
    if form == "D":
        if not 0 <= rhs < (1 << 16):
            raise ValueError("immediate rhs must be a 16-bit encoded field")
        return word | rhs
    if not 0 <= rhs < 32:
        raise ValueError("register rhs must be a five-bit field")
    return word | (rhs << 11) | (xo << 1)


def anchor_vectors() -> tuple[dict[str, int | str], ...]:
    """Stable signed, unsigned, immediate, and BF vectors for later cosim."""
    return (
        {"family": "cmp", "a": 0xFFFF_FFFF, "rhs": 0, "bf": 0},
        {"family": "cmpl", "a": 0xFFFF_FFFF, "rhs": 0, "bf": 3, "so": 1},
        {"family": "cmpi", "a": 0, "rhs": 0xFFFF, "bf": 7},
        {"family": "cmpli", "a": 0, "rhs": 0xFFFF, "bf": 5, "old_cr": 0x1234_5678},
    )
