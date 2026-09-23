ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); probe PT_LOAD FLAGS(5); }
MEMORY { BOOT (rwx) : ORIGIN = 0xfff00000, LENGTH = 64K }
SECTIONS
{
  .text.boot ORIGIN(BOOT) + 0x100 : { KEEP(*(.text.boot)) } > BOOT :text
  .imiss ORIGIN(BOOT) + 0x1000 : { KEEP(*(.exception.imiss)) } > BOOT :text
  .dlmiss ORIGIN(BOOT) + 0x1100 : { KEEP(*(.exception.dlmiss)) } > BOOT :text
  .dsmiss ORIGIN(BOOT) + 0x1200 : { KEEP(*(.exception.dsmiss)) } > BOOT :text
  .text ORIGIN(BOOT) + 0x2000 : { *(.text .text.*) } > BOOT :text
  .rodata : { *(.rodata .rodata.*) } > BOOT :text
  .data : { *(.data .data.*) } > BOOT :data
  .bss ALIGN(4) (NOLOAD) :
  {
    __bss_start = .;
    *(.bss .bss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > BOOT :data
  .tohost ORIGIN(BOOT) + 0x4000 : { KEEP(*(.tohost)) } > BOOT :data
  .pageprobe ORIGIN(BOOT) + 0x6000 : { KEEP(*(.pageprobe)) } > BOOT :probe
  __image_end = .;
  __stack_bottom = ORIGIN(BOOT) + LENGTH(BOOT) - 0x1000;
  __stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
  /DISCARD/ : { *(.eh_frame .eh_frame.*) *(.note .note.*) *(.comment) }
  ASSERT(_start == ORIGIN(BOOT) + 0x100, "reset entry moved")
  ASSERT(imiss_handler == ORIGIN(BOOT) + 0x1000, "I miss vector moved")
  ASSERT(dlmiss_handler == ORIGIN(BOOT) + 0x1100, "D load miss vector moved")
  ASSERT(dsmiss_handler == ORIGIN(BOOT) + 0x1200, "D store miss vector moved")
  ASSERT(page_probe == ORIGIN(BOOT) + 0x6000, "page probe moved")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= ORIGIN(BOOT) + 0x8000, "firmware overlaps physical data")
  ASSERT(__image_end <= __stack_bottom, "firmware overlaps stack")
}
