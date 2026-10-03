/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Full-decode firmware handlers. Each saves its scratch GPRs in SPRG0-3,
 * records SRR0/SRR1 (and DSISR/DAR for DSI) and resumes after the
 * faulting instruction. */
    .section .exception.dsi,"ax",@progbits
    .balign 4
    .globl dsi_handler
    .type dsi_handler,@function
dsi_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,dsi_dar@ha
    mfspr 11,19
    stw 11,dsi_dar@l(12)
    lis 12,dsi_dsisr@ha
    mfspr 11,18
    stw 11,dsi_dsisr@l(12)
    lis 12,dsi_srr0@ha
    mfspr 11,26
    stw 11,dsi_srr0@l(12)
    addi 11,11,4
    mtspr 26,11
    lis 12,dsi_count@ha
    lwz 11,dsi_count@l(12)
    addi 11,11,1
    stw 11,dsi_count@l(12)
    mfspr 11,272
    mfspr 12,273
    rfi
    .size dsi_handler,.-dsi_handler

/* Program: SRR1 bit 12 illegal, 13 privileged, 14 trap (0x00080000,
 * 0x00040000, 0x00020000); each cause has its own counter. */
    .section .exception.program,"ax",@progbits
    .balign 4
    .globl program_handler
    .type program_handler,@function
program_handler:
    mtspr 272,10
    mtspr 273,11
    mtspr 274,12
    mfcr 10
    mtspr 275,10
    lis 12,prog_srr0@ha
    mfspr 11,26
    stw 11,prog_srr0@l(12)
    lis 12,prog_srr1@ha
    mfspr 10,27
    stw 10,prog_srr1@l(12)
    addi 11,11,4
    mtspr 26,11
    lis 12,prog_illegal@ha
    addi 12,12,prog_illegal@l
    andis. 11,10,0x0008
    bne 1f
    lis 12,prog_priv@ha
    addi 12,12,prog_priv@l
    andis. 11,10,0x0004
    bne 1f
    lis 12,prog_trap@ha
    addi 12,12,prog_trap@l
    andis. 11,10,0x0002
    bne 1f
    lis 12,prog_other@ha
    addi 12,12,prog_other@l
1:  lwz 11,0(12)
    addi 11,11,1
    stw 11,0(12)
    mfspr 10,275
    mtcr 10
    mfspr 10,272
    mfspr 11,273
    mfspr 12,274
    rfi
    .size program_handler,.-program_handler

/* FP unavailable: emulates fmr frT,frB on the soft FPR file and skips
 * every other FP instruction. */
    .section .exception.fp_unavailable,"ax",@progbits
    .balign 4
    .globl fp_unavailable_handler
    .type fp_unavailable_handler,@function
fp_unavailable_handler:
    mtspr 272,9
    mtspr 273,10
    mtspr 274,11
    mtspr 275,12
    lis 12,fp_srr0@ha
    mfspr 11,26
    stw 11,fp_srr0@l(12)
    lis 12,fp_srr1@ha
    mfspr 10,27
    stw 10,fp_srr1@l(12)
    lis 12,fp_count@ha
    lwz 10,fp_count@l(12)
    addi 10,10,1
    stw 10,fp_count@l(12)
    lwz 10,0(11)
    addi 11,11,4
    mtspr 26,11
    /* fmr: primary 63, XO 72, Rc 0. */
    rlwinm 11,10,0,0,5
    lis 12,0xfc00
    cmpw 11,12
    bne 2f
    rlwinm 11,10,0,21,31
    cmpwi 11,0x90
    bne 2f
    lis 12,fp_emulated@ha
    lwz 11,fp_emulated@l(12)
    addi 11,11,1
    stw 11,fp_emulated@l(12)
    lis 12,soft_fpr@ha
    addi 12,12,soft_fpr@l
    rlwinm 11,10,24,24,28        /* frB * 8 */
    add 11,11,12
    lwz 9,0(11)
    lwz 11,4(11)
    rlwinm 10,10,14,24,28        /* frT * 8 */
    add 10,10,12
    stw 9,0(10)
    stw 11,4(10)
2:  mfspr 9,272
    mfspr 10,273
    mfspr 11,274
    mfspr 12,275
    rfi
    .size fp_unavailable_handler,.-fp_unavailable_handler

/* System call returns to supervisor state at the next instruction. */
    .section .exception.syscall,"ax",@progbits
    .balign 4
    .globl syscall_handler
    .type syscall_handler,@function
syscall_handler:
    mtspr 272,11
    mfspr 11,27
    rlwinm 11,11,0,18,16         /* clear MSR[PR] */
    mtspr 27,11
    mfspr 11,272
    rfi
    .size syscall_handler,.-syscall_handler
    .section .note.GNU-stack,"",@progbits
