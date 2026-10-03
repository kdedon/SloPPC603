/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* MiSTer image sections, after a RAM region. The data section's load image
 * follows its run address, and start-up copies it, so a reset restores the
 * data. */
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

  /* Constant tables of the hard-float libgcc helpers (PIC). */
  .got2 ALIGN(8) :
  {
    *(.got2)
  } > RAM

  .data ALIGN(8) : AT(ADDR(.data) + SIZEOF(.data))
  {
    __data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(8);
    __data_end = .;
  } > RAM
  __data_load = LOADADDR(.data);

  .bss __data_load + SIZEOF(.data) (NOLOAD) :
  {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > RAM

  __heap_start = ALIGN(8);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
  /* Stack reservation; an image may set its own with --defsym. */
  __stack_size = DEFINED(__stack_size) ? __stack_size : 0x8000;
  __heap_end = __stack_top - __stack_size;

  /DISCARD/ :
  {
    *(.eh_frame .eh_frame.*)
    *(.note .note.*)
    *(.comment)
  }

  ASSERT(_start == ORIGIN(RAM) + 0x100, "reset entry moved")
  ASSERT(__heap_start < __heap_end, "image leaves no heap")
  ASSERT(__data_load == __data_end, "load image does not follow the data section")
}
