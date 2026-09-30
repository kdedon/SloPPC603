/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* MiSTer demo image: 128 KiB of RAM at the reset vector base. The data
 * section runs from a copy made at start-up, so a reset restores it. */
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0xfff00000, LENGTH = 128K
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

  __data_load = ALIGN(8);
  /* Run address: past the load image, which must stay below it. */
  .data ORIGIN(RAM) + 0x10000 : AT(__data_load)
  {
    __data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(8);
    __data_end = .;
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
  ASSERT(__data_load + SIZEOF(.data) <= ADDR(.data), "load image overlaps the data section")
}
