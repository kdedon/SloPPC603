#!/usr/bin/env python3
"""Independent 32-bit reference preparation for the reviewed ADD family."""

from __future__ import annotations

from dataclasses import dataclass

MASK32 = 0xFFFF_FFFF
MIN_SIGNED = -(1 << 31)
MAX_SIGNED = (1 << 31) - 1
XO = {"add": 266, "addc": 10, "adde": 138, "addme": 234, "addze": 202}


@dataclass(frozen=True)
class AddResult:
    value: int
    ca: int
    ov: int
    so: int
    cr0: int


def _bit(value: int, name: str) -> int:
    if value not in (0, 1):
        raise ValueError(f"{name} must be 0 or 1")
    return value


def _signed(value: int) -> int:
    value &= MASK32
    return value - (1 << 32) if value & (1 << 31) else value


def evaluate(
    family: str,
    a: int,
    b: int = 0,
    *,
    ca: int = 0,
    oe: int = 0,
    rc: int = 0,
    old_ov: int = 0,
    old_so: int = 0,
    old_cr0: int = 0,
) -> AddResult:
    """Evaluate one ADD-family form, including XER and CR0 side effects."""
    if family not in XO:
        raise ValueError(f"unknown ADD family: {family}")
    ca, oe, rc = _bit(ca, "ca"), _bit(oe, "oe"), _bit(rc, "rc")
    old_ov, old_so = _bit(old_ov, "old_ov"), _bit(old_so, "old_so")
    if not 0 <= old_cr0 <= 0xF:
        raise ValueError("old_cr0 must be a nibble")
    a &= MASK32
    b &= MASK32

    if family in ("add", "addc"):
        unsigned_total = a + b
        signed_total = _signed(a) + _signed(b)
    elif family == "adde":
        unsigned_total = a + b + ca
        signed_total = _signed(a) + _signed(b) + ca
    elif family == "addme":
        unsigned_total = a + MASK32 + ca
        signed_total = _signed(a) + ca - 1
    else:  # addze
        unsigned_total = a + ca
        signed_total = _signed(a) + ca

    value = unsigned_total & MASK32
    carry = int(unsigned_total > MASK32)
    new_ca = ca if family == "add" else carry
    overflow = int(signed_total < MIN_SIGNED or signed_total > MAX_SIGNED)
    new_ov = overflow if oe else old_ov
    new_so = (old_so | overflow) if oe else old_so
    if rc:
        relation = 0b1000 if value & (1 << 31) else (0b0010 if value == 0 else 0b0100)
        new_cr0 = relation | new_so
    else:
        new_cr0 = old_cr0
    return AddResult(value=value, ca=new_ca, ov=new_ov, so=new_so, cr0=new_cr0)


def encode(family: str, *, oe: int, rc: int, rd: int, ra: int, rb: int = 0) -> int:
    """Encode one reviewed XO form; reject nonzero reserved rB for addme/addze."""
    if family not in XO:
        raise ValueError(f"unknown ADD family: {family}")
    oe, rc = _bit(oe, "oe"), _bit(rc, "rc")
    for value, name in ((rd, "rd"), (ra, "ra"), (rb, "rb")):
        if not 0 <= value < 32:
            raise ValueError(f"{name} must be a five-bit register index")
    if family in ("addme", "addze") and rb != 0:
        raise ValueError(f"{family} rB field is reserved and must be zero")
    return (31 << 26) | (rd << 21) | (ra << 16) | (rb << 11) | (oe << 10) | (XO[family] << 1) | rc


def anchor_vectors() -> tuple[dict[str, int | str], ...]:
    """Stable boundary vectors intended for later RTL/cosim adapters."""
    return (
        {"family": "add", "a": 0xFFFF_FFFF, "b": 1, "ca": 0, "oe": 0, "rc": 0},
        {"family": "addc", "a": 0xFFFF_FFFF, "b": 1, "ca": 0, "oe": 0, "rc": 0},
        {"family": "adde", "a": 0xFFFF_FFFF, "b": 0, "ca": 1, "oe": 0, "rc": 0},
        {"family": "addme", "a": 0, "b": 0, "ca": 0, "oe": 0, "rc": 0},
        {"family": "addme", "a": 0, "b": 0, "ca": 1, "oe": 0, "rc": 0},
        {"family": "addze", "a": 0xFFFF_FFFF, "b": 0, "ca": 1, "oe": 0, "rc": 0},
        {"family": "add", "a": 0x7FFF_FFFF, "b": 1, "ca": 0, "oe": 1, "rc": 1},
        {"family": "addme", "a": 0x8000_0000, "b": 0, "ca": 0, "oe": 1, "rc": 1},
        {"family": "addze", "a": 0x7FFF_FFFF, "b": 0, "ca": 1, "oe": 1, "rc": 1},
    )
