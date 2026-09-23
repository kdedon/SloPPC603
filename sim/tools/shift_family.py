#!/usr/bin/env python3
"""Independent 32-bit reference preparation for reviewed word-shift forms."""

from __future__ import annotations

from dataclasses import dataclass

MASK32 = 0xFFFF_FFFF
XO = {"slw": 24, "srw": 536, "sraw": 792, "srawi": 824}


@dataclass(frozen=True)
class ShiftResult:
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
    shift: int,
    *,
    rc: int = 0,
    ca: int = 0,
    ov: int = 0,
    so: int = 0,
    old_cr0: int = 0,
) -> ShiftResult:
    """Evaluate a shift; register forms consume the numeric low six bits of shift."""
    if family not in XO:
        raise ValueError(f"unknown word-shift family: {family}")
    rc, ca, ov, so = (_bit(value, name) for value, name in ((rc, "rc"), (ca, "ca"), (ov, "ov"), (so, "so")))
    if not 0 <= old_cr0 <= 0xF:
        raise ValueError("old_cr0 must be a nibble")
    if family == "srawi":
        if not 0 <= shift < 32:
            raise ValueError("srawi SH must be a five-bit value")
        count = shift
    else:
        count = shift & 0x3F
    s &= MASK32
    negative = bool(s & 0x8000_0000)

    if family == "slw":
        value = (s << count) & MASK32 if count < 32 else 0
        new_ca = ca
    elif family == "srw":
        value = s >> count if count < 32 else 0
        new_ca = ca
    else:
        if count >= 32:
            value = MASK32 if negative else 0
            discarded_one = negative
        else:
            signed_s = s - (1 << 32) if negative else s
            value = (signed_s >> count) & MASK32
            discarded_one = count > 0 and bool(s & ((1 << count) - 1))
        new_ca = int(negative and discarded_one)

    if rc:
        relation = 0b1000 if value & 0x8000_0000 else (0b0010 if value == 0 else 0b0100)
        cr0 = relation | so
    else:
        cr0 = old_cr0
    return ShiftResult(value=value, ca=new_ca, ov=ov, so=so, cr0=cr0)


def encode(family: str, *, rc: int, rs: int, ra: int, rb_or_sh: int) -> int:
    """Encode one reviewed X-form shift instruction."""
    if family not in XO:
        raise ValueError(f"unknown word-shift family: {family}")
    rc = _bit(rc, "rc")
    for value, name in ((rs, "rs"), (ra, "ra"), (rb_or_sh, "rb_or_sh")):
        if not 0 <= value < 32:
            raise ValueError(f"{name} must be a five-bit field")
    return (31 << 26) | (rs << 21) | (ra << 16) | (rb_or_sh << 11) | (XO[family] << 1) | rc


def anchor_vectors() -> tuple[dict[str, int | str], ...]:
    """Stable boundary vectors intended for later RTL/cosim adapters."""
    return (
        {"family": "slw", "s": 1, "shift": 31},
        {"family": "slw", "s": MASK32, "shift": 32},
        {"family": "srw", "s": 0x8000_0000, "shift": 31},
        {"family": "srw", "s": MASK32, "shift": 63},
        {"family": "sraw", "s": 0xF000_0008, "shift": 4},
        {"family": "sraw", "s": 0x8000_0000, "shift": 32},
        {"family": "srawi", "s": 0xF000_0008, "shift": 4, "rc": 1, "so": 1},
    )
