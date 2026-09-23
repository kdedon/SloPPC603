/* Fetch-fault firmware variant of link.ld, with the high ISI vector and isolated probes installed. */
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

  .text :
  {
    *(.text .text.*)
  } > BOOT :text

  /* Kept separate from .text.* so the ISI vector has a fixed address. */
  .isi ORIGIN(BOOT) + 0x400 :
  {
    KEEP(*(.exception.isi))
  } > BOOT :text

  .protection_probe ORIGIN(BOOT) + 0x800 :
  {
    KEEP(*(.probe.protection))
  } > BOOT :text
  .guarded_probe ORIGIN(BOOT) + 0x900 :
  {
    KEEP(*(.probe.guarded))
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
  ASSERT(isi_handler == ORIGIN(BOOT) + 0x400, "ISI handler moved")
  ASSERT(fetch_protection_probe == ORIGIN(BOOT) + 0x800, "protection probe moved")
  ASSERT(fetch_guarded_probe == ORIGIN(BOOT) + 0x900, "guarded probe moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= __stack_bottom,
         "bootstrap image overlaps reserved stack space")
}
