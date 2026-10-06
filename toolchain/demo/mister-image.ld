/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Loadable MiSTer image: the 1 MiB DDR3 program window at the reset vector
 * base. The top 4 KiB stay out so the stack top fits in 32 bits. */
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0xfff00000, LENGTH = 1020K
}

INCLUDE demo/mister-sections.ld
