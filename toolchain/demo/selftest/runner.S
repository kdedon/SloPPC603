/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Self-test case runner. st_enter(in, out, code) loads the whole register
 * state from in, enters code with rfi under in's MSR, and returns when the
 * case ends: every exception vector stores the register state to out and
 * resumes the caller. A case ends normally by branching to st_done, whose
 * sc the caller recognises by SRR0. With st_fp set, the FPRs and FPSCR are
 * part of the state too. Word offsets follow the field order in selftest.h. */
#define O_CR 128
#define O_XER 132
#define O_LR 136
#define O_CTR 140
#define O_VEC 144
#define O_SRR0 148
#define O_SRR1 152
#define O_MSR 156
#define O_DAR 160
#define O_DSISR 164
#define O_FPR 424
#define O_FPSCR 680
/* st_save: r1, r2, r13-r31 at 4 * n; LR, CR, MSR and out after them, then a
 * doubleword for the FPSCR. */
#define S_LR 128
#define S_CR 132
#define S_MSR 136
#define S_OUT 140
#define S_FPSCR 144

    .section .vectors,"ax",@progbits
    .globl _start
_start:                     /* 0x100: system reset */
    b _reset

    /* SPRG1 holds the case's r3, SPRG3 the MSR at entry; r3 the vector. */
    .macro vector off
    .org \off - 0x100
    mtsprg 1,3
    mfmsr 3
    mtsprg 3,3
    li 3,\off
    b st_trap
    .endm
    /* TLB misses enter with MSR[TGPR] set: r0-r3 are the shadow registers
     * until it is cleared, so the case's r3 is saved after. */
    .macro tlbvector off
    .org \off - 0x100
    mfmsr 3
    mtsprg 3,3
    rlwinm 3,3,0,15,13
    mtmsr 3
    isync
    mtsprg 1,3
    li 3,\off
    b st_trap
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
    tlbvector 0x1000
    tlbvector 0x1100
    tlbvector 0x1200
    vector 0x1300
    vector 0x1400
    vector 0x1500
    vector 0x1600

    .text
    .globl st_enter
    .type st_enter,@function
st_enter:
    lis 6,st_save@ha
    addi 6,6,st_save@l
    stw 1,4(6)
    stw 2,8(6)
    .irp n,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    stw \n,4*\n(6)
    .endr
    mflr 0
    stw 0,S_LR(6)
    mfcr 0
    stw 0,S_CR(6)
    mfmsr 0
    stw 0,S_MSR(6)
    stw 4,S_OUT(6)
    lis 7,st_fp@ha
    lwz 7,st_fp@l(7)
    cmpwi 7,0
    beq 1f
    /* The FPSCR from the word before it (mtfsf takes the low word), then
     * the FPRs, with MSR[FP] set until the rfi. */
    ori 7,0,0x2000
    mtmsr 7
    isync
    lfd 0,O_FPSCR-4(3)
    mtfsf 0xff,0
    .irp n,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lfd \n,O_FPR+8*\n(3)
    .endr
1:
    mtsrr0 5
    lwz 0,O_MSR(3)
    mtsrr1 0
    lwz 0,O_DAR(3)
    mtdar 0
    lwz 0,O_DSISR(3)
    mtdsisr 0
    lwz 0,O_CR(3)
    mtcr 0
    lwz 0,O_XER(3)
    mtxer 0
    lwz 0,O_LR(3)
    mtlr 0
    lwz 0,O_CTR(3)
    mtctr 0
    .irp n,0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lwz \n,4*\n(3)
    .endr
    lwz 3,12(3)
    rfi
    .size st_enter,.-st_enter

    .globl st_done
    .type st_done,@function
st_done:
    sc
    .size st_done,.-st_done

    /* The target of the absolute-branch cases. */
    .globl st_abs
    .type st_abs,@function
st_abs:
    addi 3,3,1
    b st_done
    .size st_abs,.-st_abs

    .type st_trap,@function
st_trap:
    mtsprg 2,4
    lis 4,st_save@ha
    addi 4,4,st_save@l
    lwz 4,S_OUT(4)
    stw 3,O_VEC(4)
    mfsprg 3,1
    stw 3,12(4)
    mfsprg 3,2
    stw 3,16(4)
    .irp n,0,1,2,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    stw \n,4*\n(4)
    .endr
    mfcr 3
    stw 3,O_CR(4)
    mfxer 3
    stw 3,O_XER(4)
    mflr 3
    stw 3,O_LR(4)
    mfctr 3
    stw 3,O_CTR(4)
    mfsrr0 3
    stw 3,O_SRR0(4)
    mfsrr1 3
    stw 3,O_SRR1(4)
    mfdar 3
    stw 3,O_DAR(4)
    mfdsisr 3
    stw 3,O_DSISR(4)
    lis 3,st_fp@ha
    lwz 3,st_fp@l(3)
    cmpwi 3,0
    beq 1f
    mfmsr 3
    ori 3,3,0x2000
    mtmsr 3
    isync
    .irp n,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    stfd \n,O_FPR+8*\n(4)
    .endr
    mffs 0
    lis 3,st_save@ha
    addi 3,3,st_save@l
    stfd 0,S_FPSCR(3)
    lwz 3,S_FPSCR+4(3)
    stw 3,O_FPSCR(4)
1:
    mfsprg 3,3
    stw 3,O_MSR(4)
    lis 4,st_save@ha
    addi 4,4,st_save@l
    lwz 1,4(4)
    lwz 2,8(4)
    .irp n,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lwz \n,4*\n(4)
    .endr
    lwz 0,S_CR(4)
    mtcr 0
    lwz 0,S_LR(4)
    mtsrr0 0
    lwz 0,S_MSR(4)
    mtsrr1 0
    rfi
    .size st_trap,.-st_trap

    .section .bss
    .align 3
st_save:
    .space 152

    .section .note.GNU-stack,"",@progbits
