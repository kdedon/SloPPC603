/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Doom program start, in the program's byte order: exception vectors from
 * 0x200 (the reset stub owns 0x100) and the entry at 0xfff01500, which the
 * stub enters with r3 = 0 and plat_restart with r3 = 1. An exception exits
 * with 0xe0000000 plus its vector offset. */
#ifdef __LITTLE_ENDIAN__
#define EXIT_OFF 0x10
#else
#define EXIT_OFF 0x14
#endif

    .section .vectors,"ax",@progbits
    .macro vector off
    .org \off - 0x200
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

    .section .entry,"ax",@progbits
    .globl _entry
_entry:
    mr 31,3
    lis 1,__stack_top@ha
    addi 1,1,__stack_top@l
    li 0,0
    stwu 0,-16(1)
    lis 5,__data_load@ha
    addi 5,5,__data_load@l
    lis 6,__data_start@ha
    addi 6,6,__data_start@l
    lis 7,__data_end@ha
    addi 7,7,__data_end@l
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
    mr 3,31
    bl plat_main
    lis 4,0xf010
    stw 3,EXIT_OFF(4)
    sync
1:  b 1b

    .text
    .globl plat_restart
plat_restart:
    li 3,1
    b _entry

    /* Exceptions clear MSR[DR]; restore it so the exit store is inhibited. */
_trap:
    mfmsr 4
    ori 4,4,0x0010
    mtmsr 4
    isync
    oris 3,3,0xe000
    lis 4,0xf010
    stw 3,EXIT_OFF(4)
    sync
1:  b 1b

    .section .note.GNU-stack,"",@progbits
