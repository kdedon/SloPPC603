#!/usr/bin/env python3
"""Independent 32-bit reference preparation for register-logical instructions."""

from __future__ import annotations

from dataclasses import dataclass

MASK32 = 0xFFFF_FFFF
XO = {"and": 28, "andc": 60, "or": 444, "orc": 412, "xor": 316, "nand": 476, "nor": 124, "eqv": 284}


@dataclass(frozen=True)
class LogicalResult:
    value: int
    ca: int
    ov: int
    so: int
    cr0: int


def _bit(value: int, name: str) -> int:
    if value not in (0, 1):
        raise ValueError(f"{name} must be 0 or 1")
    return value


def evaluate(
    family: str,
    s: int,
    b: int,
    *,
    rc: int = 0,
    ca: int = 0,
    ov: int = 0,
    so: int = 0,
    old_cr0: int = 0,
) -> LogicalResult:
    """Evaluate a reviewed register-logical form and its architectural side effects."""
    if family not in XO:
        raise ValueError(f"unknown register-logical family: {family}")
    rc, ca, ov, so = (_bit(value, name) for value, name in ((rc, "rc"), (ca, "ca"), (ov, "ov"), (so, "so")))
    if not 0 <= old_cr0 <= 0xF:
        raise ValueError("old_cr0 must be a nibble")
    s, b = s & MASK32, b & MASK32

    if family == "and":
        value = s & b
    elif family == "andc":
        value = s & ~b
    elif family == "or":
        value = s | b
    elif family == "orc":
        value = s | ~b
    elif family == "xor":
        value = s ^ b
    elif family == "nand":
        value = ~(s & b)
    elif family == "nor":
        value = ~(s | b)
    else:  # eqv
        value = ~(s ^ b)
    value &= MASK32

    if rc:
        relation = 0b1000 if value & (1 << 31) else (0b0010 if value == 0 else 0b0100)
        cr0 = relation | so
    else:
        cr0 = old_cr0
    return LogicalResult(value=value, ca=ca, ov=ov, so=so, cr0=cr0)


def encode(family: str, *, rc: int, rs: int, ra: int, rb: int) -> int:
    """Encode one reviewed X-form register-logical instruction."""
    if family not in XO:
        raise ValueError(f"unknown register-logical family: {family}")
    rc = _bit(rc, "rc")
    for value, name in ((rs, "rs"), (ra, "ra"), (rb, "rb")):
        if not 0 <= value < 32:
            raise ValueError(f"{name} must be a five-bit register index")
    return (31 << 26) | (rs << 21) | (ra << 16) | (rb << 11) | (XO[family] << 1) | rc


def anchor_vectors() -> tuple[dict[str, int | str], ...]:
    """Stable vectors for all reviewed Boolean operations and CR0 relations."""
    return (
        {"family": "and", "s": 0xF0F0_F0F0, "b": 0x0FF0_00FF, "rc": 0},
        {"family": "andc", "s": 0xF0F0_F0F0, "b": 0x0FF0_00FF, "rc": 0},
        {"family": "or", "s": 0x8000_0000, "b": 0, "rc": 1, "so": 1},
        {"family": "orc", "s": 0, "b": 0xFFFF_FFFF, "rc": 1},
        {"family": "xor", "s": 0xAAAA_AAAA, "b": 0x5555_5555, "rc": 0},
        {"family": "nand", "s": MASK32, "b": MASK32, "rc": 1},
        {"family": "nor", "s": 0, "b": 0, "rc": 1},
        {"family": "eqv", "s": 0xAAAA_AAAA, "b": 0x5555_5555, "rc": 0},
    )
