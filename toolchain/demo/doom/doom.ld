/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Doom image: code, constants and the data section's load image in the
 * 1 MiB image window; data, BSS, heap and stack in the data window below the
 * IWAD at 0x01800000. 0x100 is left for the reset stub (stub.S). */
ENTRY(_entry)

MEMORY
{
  IMG (rx) : ORIGIN = 0xfff00000, LENGTH = 1M
  DATA (rw) : ORIGIN = 0x00000000, LENGTH = 24M
}

SECTIONS
{
  .vectors ORIGIN(IMG) + 0x200 : { KEEP(*(.vectors)) } > IMG
  .entry ORIGIN(IMG) + 0x1500 : { KEEP(*(.entry)) } > IMG
  .text ALIGN(32) : { *(.text .text.*) } > IMG
  .rodata ALIGN(8) : { *(.rodata .rodata.*) } > IMG
  .got2 ALIGN(8) : { *(.got2) } > IMG

  .data ORIGIN(DATA) + 0x100 : ALIGN(8)
  {
    __data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(8);
    __data_end = .;
  } > DATA AT> IMG
  __data_load = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(8)
  {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > DATA

  .noinit (NOLOAD) : ALIGN(8) { *(.noinit) } > DATA

  __heap_start = ALIGN(16);
  __stack_top = ORIGIN(DATA) + LENGTH(DATA);
  __heap_end = __stack_top - 0x40000;

  /DISCARD/ : { *(.eh_frame .eh_frame.* .note .note.* .comment) }

  ASSERT(_entry == 0xfff01500, "entry moved")
  ASSERT(__heap_end - __heap_start >= 0x00c00000, "less than 12 MiB of heap")
}
