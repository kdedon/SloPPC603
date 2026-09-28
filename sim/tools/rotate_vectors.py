#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Expected rlwinm/rlwnm IU results from the rotate_family model, for tb_rotate_execution."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

import rotate_family

SEED = 603


def vectors(count: int = 64) -> list[tuple[int, ...]]:
    """Rows of (a, b, mask, so, rc, value, cr0); b is SH or the full rB value."""
    rng = random.Random(SEED)
    rows = []
    for anchor in rotate_family.anchor_vectors():
        if anchor["family"] != "rlwimi":
            rows.append((anchor["family"], anchor["s"], anchor["shift"], anchor["mb"], anchor["me"], 1, 0))
    while len(rows) < count:
        family = rng.choice(("rlwinm", "rlwnm"))
        shift = rng.getrandbits(32) if family == "rlwnm" else rng.randrange(32)
        s = rng.choice((0, 0xFFFF_FFFF, 0x8000_0000, 1, rng.getrandbits(32)))
        rows.append((family, s, shift, rng.randrange(32), rng.randrange(32), rng.randrange(2), rng.randrange(2)))
    out = []
    for family, s, shift, mb, me, rc, so in rows:
        result = rotate_family.evaluate(family, s, shift, mb, me, rc=rc, so=so)
        # The IU packet carries CR0 only for Rc=1 and never CA/OV/SO for rotates.
        out.append((s, shift, rotate_family.ppc_mask(mb, me), so, rc, result.value, result.cr0 if rc else 0))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    rows = vectors()
    args.output.write_text("".join(
        f"{a:08x} {b:08x} {mask:08x} {so:x} {rc:x} {value:08x} {cr0:x}\n"
        for a, b, mask, so, rc, value, cr0 in rows))
    print(f"wrote {len(rows)} rotate vectors to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
