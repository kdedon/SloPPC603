ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
MEMORY { BOOT (rwx) : ORIGIN = 0xfff00000, LENGTH = 64K }
SECTIONS
{
  .text.boot ORIGIN(BOOT) + 0x100 : { KEEP(*(.text.boot)) } > BOOT :text
  .machine_check ORIGIN(BOOT) + 0x200 : { KEEP(*(.exception.machine_check)) } > BOOT :text
  .dsi ORIGIN(BOOT) + 0x300 : { KEEP(*(.exception.dsi)) } > BOOT :text
  .isi ORIGIN(BOOT) + 0x400 : { KEEP(*(.exception.isi)) } > BOOT :text
  .interrupt ORIGIN(BOOT) + 0x500 : { KEEP(*(.exception.interrupt)) } > BOOT :text
  .decrementer ORIGIN(BOOT) + 0x900 : { KEEP(*(.exception.decrementer)) } > BOOT :text
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
  .tohost ORIGIN(BOOT) + 0x7000 : { KEEP(*(.tohost)) } > BOOT :data
  __image_end = .;
  __stack_bottom = ORIGIN(BOOT) + LENGTH(BOOT) - 0x1000;
  __stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
  __htab_base = 0xfff10000;
  /DISCARD/ : { *(.eh_frame .eh_frame.*) *(.note .note.*) *(.comment) }
  ASSERT(_start == ORIGIN(BOOT) + 0x100, "reset entry moved")
  ASSERT(machine_check_handler == ORIGIN(BOOT) + 0x200, "machine check vector moved")
  ASSERT(dsi_handler == ORIGIN(BOOT) + 0x300, "DSI vector moved")
  ASSERT(isi_handler == ORIGIN(BOOT) + 0x400, "ISI vector moved")
  ASSERT(interrupt_handler == ORIGIN(BOOT) + 0x500, "EXT vector moved")
  ASSERT(decrementer_handler == ORIGIN(BOOT) + 0x900, "DEC vector moved")
  ASSERT(imiss_handler == ORIGIN(BOOT) + 0x1000, "I miss vector moved")
  ASSERT(dlmiss_handler == ORIGIN(BOOT) + 0x1100, "D load miss vector moved")
  ASSERT(dsmiss_handler == ORIGIN(BOOT) + 0x1200, "D store miss vector moved")
  ASSERT(__bss_end <= ORIGIN(BOOT) + 0x7000, "firmware overlaps tohost")
  ASSERT((tohost & 3) == 0, "tohost is not word aligned")
  ASSERT(__image_end <= __stack_bottom, "firmware overlaps downward-growing stack")
  ASSERT(__stack_top == __htab_base, "stack top must meet HTAB without overlap")
}
