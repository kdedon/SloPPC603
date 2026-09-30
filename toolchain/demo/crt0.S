/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Boot for the demo system. The processor resets with MSR[IP] set, so the
 * vectors sit at 0xfff00000 in RAM. Translation runs through BATs: RAM
 * cacheable for fetch and data, the peripheral window cache-inhibited and
 * guarded. Both caches are enabled. main's return
 * value goes to the exit register; an exception exits with 0xe0000000 plus
 * its vector offset. */
#define SPR_HID0 1008
#define IO_HI 0xf010

    .section .vectors,"ax",@progbits
    .globl _start
_start:                     /* 0x100: system reset */
    b _reset

    .macro vector off
    .org \off - 0x100
    li 3,\off
    b _trap
    .endm
    vector 0x200
    vector 0x300
    vector 0x400
    vector 0x500
    vector 0x600
    vector 0x700
    vector 0x800
    vector 0x900
    vector 0xa00
    vector 0xb00
    vector 0xc00
    vector 0xd00
    vector 0xe00
    vector 0xf00
    vector 0x1000
    vector 0x1100
    vector 0x1200
    vector 0x1300
    vector 0x1400

    .text
    .type _reset,@function
_reset:
    li 0,0
    /* Invalidate all BATs, then map RAM and the peripheral window. */
    mtspr 528,0
    mtspr 530,0
    mtspr 532,0
    mtspr 534,0
    mtspr 536,0
    mtspr 538,0
    mtspr 540,0
    mtspr 542,0
    isync
    /* DBAT0: 0xfff00000, 1 MiB, WIMG 0000, read/write. */
    lis 5,0xfff0
    ori 5,5,0x0002
    mtspr 537,5
    lis 5,0xfff0
    ori 5,5,0x001e
    mtspr 536,5
    /* IBAT0: the same RAM block; real-mode fetches are not cached. */
    lis 5,0xfff0
    ori 5,5,0x0002
    mtspr 529,5
    lis 5,0xfff0
    ori 5,5,0x001e
    mtspr 528,5
    /* DBAT1: 0xf0000000, 4 MiB, WIMG 0101 (inhibited, guarded): registers
     * and a framebuffer below them or of up to 2 MiB at 0xf0200000. */
    lis 5,0xf000
    ori 5,5,0x002a
    mtspr 539,5
    lis 5,0xf000
    ori 5,5,0x007e
    mtspr 538,5
    isync
    mfmsr 5
    ori 5,5,0x0030
    mtmsr 5
    isync

    /* Invalidate and enable the instruction cache, then the data cache. */
    li 5,0
    ori 5,5,0x8800
    mtspr SPR_HID0,5
    li 5,0
    ori 5,5,0x8000
    mtspr SPR_HID0,5
    isync
    sync
    ori 5,5,0x4400
    mtspr SPR_HID0,5
    li 5,0
    ori 5,5,0xc000
    mtspr SPR_HID0,5
    isync

    lis 1,__stack_top@ha
    addi 1,1,__stack_top@l
    stwu 0,-16(1)
    /* Copy initialised data from its load image when that is elsewhere, so a
     * reset restarts the program with fresh data. */
    lis 5,__data_load@ha
    addi 5,5,__data_load@l
    lis 6,__data_start@ha
    addi 6,6,__data_start@l
    lis 7,__data_end@ha
    addi 7,7,__data_end@l
    cmplw 5,6
    beq .Ldata_done
.Ldata:
    cmplw 6,7
    bge .Ldata_done
    lwz 8,0(5)
    stw 8,0(6)
    addi 5,5,4
    addi 6,6,4
    b .Ldata
.Ldata_done:
    lis 5,__bss_start@ha
    addi 5,5,__bss_start@l
    lis 6,__bss_end@ha
    addi 6,6,__bss_end@l
.Lbss:
    cmplw 5,6
    bge .Lbss_done
    stw 0,0(5)
    addi 5,5,4
    b .Lbss
.Lbss_done:
    bl main
    lis 4,IO_HI
    stw 3,0x14(4)
    sync
1:  b 1b
    .size _reset,.-_reset

    /* Exceptions clear MSR[DR]; restore it so the exit store is inhibited. */
    .type _trap,@function
_trap:
    mfmsr 4
    ori 4,4,0x0010
    mtmsr 4
    isync
    oris 3,3,0xe000
    lis 4,IO_HI
    stw 3,0x14(4)
    sync
1:  b 1b
    .size _trap,.-_trap

    .section .note.GNU-stack,"",@progbits
