/* Page-hit firmware variant of link.ld, with the high vector installed. */
ENTRY(_start)

PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  probe PT_LOAD FLAGS(5);
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

  /* Kept separate from .text.* so the external-interrupt vector has a fixed address. */
  .interrupt ORIGIN(BOOT) + 0x500 :
  {
    KEEP(*(.exception.interrupt))
  } > BOOT :text

  .decrementer ORIGIN(BOOT) + 0x900 :
  {
    KEEP(*(.exception.decrementer))
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

  .tohost ORIGIN(BOOT) + 0x4000 :
  {
    KEEP(*(.tohost))
  } > BOOT :data

  .pageprobe ORIGIN(BOOT) + 0x6000 : { KEEP(*(.pageprobe)) } > BOOT :probe

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
  ASSERT(interrupt_handler == ORIGIN(BOOT) + 0x500, "interrupt handler moved")
  ASSERT(decrementer_handler == ORIGIN(BOOT) + 0x900, "decrementer handler moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= ORIGIN(BOOT) + 0x8000,
         "page firmware overlaps alias/fixture phase words")
  ASSERT(__image_end <= __stack_bottom,
         "bootstrap image overlaps reserved stack space")
}
