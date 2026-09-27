#!/usr/bin/env python3
"""Verify and print the reciprocal-square-root estimate constants."""

from decimal import Decimal, getcontext
from pathlib import Path
import re

getcontext().prec = 100
source = Path(__file__).with_name("ppc_fpu_arith.sv").read_text()
for odd in (0, 1):
    for index in range(16):
        midpoint_num = (33 + 2 * index) * (2 if odd else 1)
        midpoint_den = 32
        midpoint = Decimal(midpoint_num) / Decimal(midpoint_den)
        estimate = int((Decimal(1) / midpoint.sqrt()) * (1 << 53))
        # Integer inequalities establish the exact floor despite Decimal rounding.
        assert estimate**2 * midpoint_num <= (1 << 106) * midpoint_den
        assert (estimate + 1) ** 2 * midpoint_num > (1 << 106) * midpoint_den
        lower_num = (16 + index) * (2 if odd else 1)
        upper_num = (17 + index) * (2 if odd else 1)
        # Relative error is below 1/32 throughout each monotonic input bin.
        assert estimate**2 * lower_num * 32**2 > 31**2 * (1 << 106) * 16
        assert estimate**2 * upper_num * 32**2 < 33**2 * (1 << 106) * 16
        key = (odd << 4) | index
        pattern = rf"5'h{key:02x}: estimate_sig = 53'h([0-9a-f]{{14}});"
        match = re.search(pattern, source)
        assert match and int(match.group(1), 16) == estimate, f"table mismatch {key:02x}"
print("PASS frsqrte table=32 exact-floor=32 relative-bound=32")
