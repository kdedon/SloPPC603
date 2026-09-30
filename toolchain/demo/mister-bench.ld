/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* MiSTer benchmark suite image: 256 KiB of RAM at the reset vector base. */
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0xfff00000, LENGTH = 256K
}

INCLUDE demo/mister-sections.ld
