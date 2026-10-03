/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Residuals firmware: link.ld with DSI, alignment, program, decrementer,
 * system-call, trace, data TLB miss and IABR vectors; text above 0x2000. */
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

  .alignment ORIGIN(BOOT) + 0x600 :
  {
    KEEP(*(.exception.alignment))
  } > BOOT :text

  .program ORIGIN(BOOT) + 0x700 :
  {
    KEEP(*(.exception.program))
  } > BOOT :text

  .decrementer ORIGIN(BOOT) + 0x900 :
  {
    KEEP(*(.exception.decrementer))
  } > BOOT :text

  .syscall ORIGIN(BOOT) + 0xc00 :
  {
    KEEP(*(.exception.syscall))
  } > BOOT :text

  .trace ORIGIN(BOOT) + 0xd00 :
  {
    KEEP(*(.exception.trace))
  } > BOOT :text

  .dtlb_load ORIGIN(BOOT) + 0x1100 :
  {
    KEEP(*(.exception.dtlb_load))
  } > BOOT :text

  .dtlb_store ORIGIN(BOOT) + 0x1200 :
  {
    KEEP(*(.exception.dtlb_store))
  } > BOOT :text

  .iabr ORIGIN(BOOT) + 0x1300 :
  {
    KEEP(*(.exception.iabr))
  } > BOOT :text

  .text ORIGIN(BOOT) + 0x2000 :
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
  ASSERT(dsi_handler == ORIGIN(BOOT) + 0x300, "dsi handler moved")
  ASSERT(alignment_handler == ORIGIN(BOOT) + 0x600, "alignment handler moved")
  ASSERT(program_handler == ORIGIN(BOOT) + 0x700, "program handler moved")
  ASSERT(decrementer_handler == ORIGIN(BOOT) + 0x900, "decrementer handler moved")
  ASSERT(syscall_handler == ORIGIN(BOOT) + 0xc00, "syscall handler moved")
  ASSERT(trace_handler == ORIGIN(BOOT) + 0xd00, "trace handler moved")
  ASSERT(dtlb_load_handler == ORIGIN(BOOT) + 0x1100, "dtlb_load handler moved")
  ASSERT(dtlb_store_handler == ORIGIN(BOOT) + 0x1200, "dtlb_store handler moved")
  ASSERT(iabr_handler == ORIGIN(BOOT) + 0x1300, "iabr handler moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= ORIGIN(BOOT) + 0xe000, "firmware overlaps the stack")
}
