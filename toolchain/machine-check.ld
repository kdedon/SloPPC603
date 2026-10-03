/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Machine-check/trace/IABR firmware: link.ld with fixed 0x200, 0xD00 and
 * 0x1300 vectors, a line-aligned routine that straddles the TEA window and a
 * mode word the bench writes. */
ENTRY(_start)

PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  routine PT_LOAD FLAGS(5);
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

  .machine_check ORIGIN(BOOT) + 0x200 :
  {
    KEEP(*(.exception.machine_check))
  } > BOOT :text

  .trace ORIGIN(BOOT) + 0xd00 :
  {
    KEEP(*(.exception.trace))
  } > BOOT :text

  .iabr ORIGIN(BOOT) + 0x1300 :
  {
    KEEP(*(.exception.iabr))
  } > BOOT :text

  .text ORIGIN(BOOT) + 0x1400 :
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

  /* The bench's TEA window starts at the third doubleword of this line. */
  .bad_routine ORIGIN(BOOT) + 0xdfe0 :
  {
    KEEP(*(.routine.bad))
  } > BOOT :routine

  __stack_bottom = ORIGIN(BOOT) + LENGTH(BOOT) - 0x1000;
  __stack_top = ORIGIN(BOOT) + LENGTH(BOOT);

  /DISCARD/ :
  {
    *(.eh_frame .eh_frame.*)
    *(.note .note.*)
    *(.comment)
  }

  ASSERT(_start == ORIGIN(BOOT) + 0x100, "reset entry moved")
  ASSERT(machine_check_handler == ORIGIN(BOOT) + 0x200, "machine check handler moved")
  ASSERT(trace_handler == ORIGIN(BOOT) + 0xd00, "trace handler moved")
  ASSERT(iabr_handler == ORIGIN(BOOT) + 0x1300, "IABR handler moved")
  ASSERT(bad_routine == ORIGIN(BOOT) + 0xdfe0, "TEA routine moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= ORIGIN(BOOT) + 0xc000,
         "firmware overlaps the mode word and TEA window")
}
