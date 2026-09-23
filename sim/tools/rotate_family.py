#!/usr/bin/env python3
"""Independent 32-bit reference preparation for reviewed word-rotate forms."""

from __future__ import annotations

from dataclasses import dataclass

MASK32 = 0xFFFF_FFFF
PRIMARY_OPCODE = {"rlwimi": 20, "rlwinm": 21, "rlwnm": 23}


@dataclass(frozen=True)
class RotateResult:
    value: int
    ca: int
    ov: int
    so: int
    cr0: int


def _bit(value: int, name: str) -> int:
    if value not in (0, 1):
        raise ValueError(f"{name} must be 0 or 1")
    return value


def _five_bits(value: int, name: str) -> int:
    if not 0 <= value < 32:
        raise ValueError(f"{name} must be a five-bit value")
    return value


def ppc_mask(mb: int, me: int) -> int:
    """Return MASK(MB,ME), where architectural bit 0 is the numeric MSB."""
    mb, me = _five_bits(mb, "mb"), _five_bits(me, "me")
    result = 0
    index = mb
    while True:
        result |= 1 << (31 - index)
        if index == me:
            return result
        index = (index + 1) & 31


def rotate_left(value: int, amount: int) -> int:
    """Rotate a 32-bit value left by the numeric low five bits of amount."""
    value &= MASK32
    amount &= 31
    return value if amount == 0 else ((value << amount) | (value >> (32 - amount))) & MASK32


def evaluate(
    family: str,
    s: int,
    shift: int,
    mb: int,
    me: int,
    *,
    old_a: int = 0,
    rc: int = 0,
    ca: int = 0,
    ov: int = 0,
    so: int = 0,
    old_cr0: int = 0,
) -> RotateResult:
    """Evaluate one rotate form; shift is SH or the full rB value for rlwnm."""
    if family not in PRIMARY_OPCODE:
        raise ValueError(f"unknown word-rotate family: {family}")
    if family != "rlwnm":
        _five_bits(shift, "sh")
    rc, ca, ov, so = (_bit(value, name) for value, name in ((rc, "rc"), (ca, "ca"), (ov, "ov"), (so, "so")))
    if not 0 <= old_cr0 <= 0xF:
        raise ValueError("old_cr0 must be a nibble")

    mask = ppc_mask(mb, me)
    rotated = rotate_left(s, shift)
    if family == "rlwimi":
        value = (rotated & mask) | ((old_a & MASK32) & ~mask)
    else:
        value = rotated & mask
    value &= MASK32

    if rc:
        relation = 0b1000 if value & (1 << 31) else (0b0010 if value == 0 else 0b0100)
        cr0 = relation | so
    else:
        cr0 = old_cr0
    return RotateResult(value=value, ca=ca, ov=ov, so=so, cr0=cr0)


def encode(family: str, *, rc: int, rs: int, ra: int, sh_or_rb: int, mb: int, me: int) -> int:
    """Encode one reviewed M-form; sh_or_rb is SH or the rB register index."""
    if family not in PRIMARY_OPCODE:
        raise ValueError(f"unknown word-rotate family: {family}")
    rc = _bit(rc, "rc")
    rs, ra = _five_bits(rs, "rs"), _five_bits(ra, "ra")
    sh_or_rb = _five_bits(sh_or_rb, "sh_or_rb")
    mb, me = _five_bits(mb, "mb"), _five_bits(me, "me")
    return (
        (PRIMARY_OPCODE[family] << 26) | (rs << 21) | (ra << 16) |
        (sh_or_rb << 11) | (mb << 6) | (me << 1) | rc
    )


def anchor_vectors() -> tuple[dict[str, int | str], ...]:
    """Stable boundary vectors intended for later RTL/cosim adapters."""
    return (
        {"family": "rlwinm", "s": 0x1234_5678, "shift": 0, "mb": 0, "me": 31},
        {"family": "rlwinm", "s": 0x8000_0001, "shift": 31, "mb": 0, "me": 31},
        {"family": "rlwimi", "s": 0x1234_5678, "shift": 0, "mb": 8, "me": 15, "old_a": 0xAAAA_5555},
        {"family": "rlwimi", "s": 0x1234_5678, "shift": 0, "mb": 24, "me": 7, "old_a": 0xAABB_CCDD},
        {"family": "rlwnm", "s": 0x8000_0000, "shift": 0xFFFF_FFE1, "mb": 0, "me": 31},
    )
