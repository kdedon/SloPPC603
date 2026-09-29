/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Demo system RAM: 256 KiB at the reset vector base. */
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0xfff00000, LENGTH = 256K
}

SECTIONS
{
  .vectors ORIGIN(RAM) + 0x100 :
  {
    KEEP(*(.vectors))
  } > RAM

  .text ALIGN(32) :
  {
    *(.text .text.*)
  } > RAM

  .rodata ALIGN(8) :
  {
    *(.rodata .rodata.*)
  } > RAM

  .data ALIGN(8) :
  {
    *(.data .data.* .sdata .sdata.*)
  } > RAM

  .bss ALIGN(8) (NOLOAD) :
  {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > RAM

  __heap_start = ALIGN(8);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  __heap_end = __stack_top - 0x8000;

  /DISCARD/ :
  {
    *(.eh_frame .eh_frame.*)
    *(.note .note.*)
    *(.comment)
  }

  ASSERT(_start == ORIGIN(RAM) + 0x100, "reset entry moved")
  ASSERT(__heap_start < __heap_end, "image leaves no heap")
}
