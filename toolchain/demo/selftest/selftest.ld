/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Self-test image: 240 KiB at the reset vector base. The top 16 KiB of the
 * 256 KiB RAM, from 0xfff3c000, is the cases' scratch area (gen.py). */
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0xfff00000, LENGTH = 240K
}

INCLUDE demo/mister-sections.ld
