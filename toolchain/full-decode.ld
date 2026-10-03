/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Full-decode firmware: link.ld with DSI, program, FP-unavailable and system-call vectors. */
ENTRY(_start)

PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}

MEMORY
{
  BOOT (rwx) : ORIGIN = 0xfff00000, LENGTH = 64K
}

SECTIONS
{
  .text.boot ORIGIN(BOOT) + 0x100 :
  {
    KEEP(*(.text.boot))
  } > BOOT :text

  .dsi ORIGIN(BOOT) + 0x300 :
  {
    KEEP(*(.exception.dsi))
  } > BOOT :text

  .program ORIGIN(BOOT) + 0x700 :
  {
    KEEP(*(.exception.program))
  } > BOOT :text

  .fp_unavailable ORIGIN(BOOT) + 0x800 :
  {
    KEEP(*(.exception.fp_unavailable))
  } > BOOT :text

  .syscall ORIGIN(BOOT) + 0xc00 :
  {
    KEEP(*(.exception.syscall))
  } > BOOT :text

  .text ORIGIN(BOOT) + 0x1000 :
  {
    *(.text .text.*)
  } > BOOT :text

  .rodata :
  {
    *(.rodata .rodata.*)
  } > BOOT :text

  .data :
  {
    *(.data .data.*)
  } > BOOT :data

  .bss ALIGN(4) (NOLOAD) :
  {
    __bss_start = .;
    *(.bss .bss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > BOOT :data

  .tohost ALIGN(0x1000) :
  {
    KEEP(*(.tohost))
  } > BOOT :data

  __image_end = .;
  __stack_bottom = ORIGIN(BOOT) + LENGTH(BOOT) - 0x1000;
  __stack_top = ORIGIN(BOOT) + LENGTH(BOOT);

  /DISCARD/ :
  {
    *(.eh_frame .eh_frame.*)
    *(.note .note.*)
    *(.comment)
  }

  ASSERT(_start == ORIGIN(BOOT) + 0x100, "reset entry moved")
  ASSERT(dsi_handler == ORIGIN(BOOT) + 0x300, "DSI handler moved")
  ASSERT(program_handler == ORIGIN(BOOT) + 0x700, "program handler moved")
  ASSERT(fp_unavailable_handler == ORIGIN(BOOT) + 0x800, "FP-unavailable handler moved")
  ASSERT(syscall_handler == ORIGIN(BOOT) + 0xc00, "system-call handler moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= ORIGIN(BOOT) + 0xe000, "firmware overlaps the stack")
}
