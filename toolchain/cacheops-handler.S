/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Cache-operation firmware handlers. Each saves r11/r12 in SPRG0/1. DSI and
 * alignment record DAR, DSISR and SRR0, then resume after the instruction;
 * alignment first emulates dcbz by zeroing the 32-byte block at DAR. */
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

    .section .exception.interrupt,"ax",@progbits
    .balign 4
    .globl interrupt_handler
    .type interrupt_handler,@function
interrupt_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,irq_count@ha
    lwz 11,irq_count@l(12)
    addi 11,11,1
    stw 11,irq_count@l(12)
    mfspr 11,272
    mfspr 12,273
    rfi
    .size interrupt_handler,.-interrupt_handler

    .section .exception.alignment,"ax",@progbits
    .balign 4
    .globl alignment_handler
    .type alignment_handler,@function
alignment_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,align_dar@ha
    mfspr 11,19
    stw 11,align_dar@l(12)
    lis 12,align_dsisr@ha
    mfspr 11,18
    stw 11,align_dsisr@l(12)
    lis 12,align_srr0@ha
    mfspr 11,26
    stw 11,align_srr0@l(12)
    addi 11,11,4
    mtspr 26,11
    lis 12,align_count@ha
    lwz 11,align_count@l(12)
    addi 11,11,1
    stw 11,align_count@l(12)
    /* Emulated dcbz: the block is identity mapped. */
    mfspr 11,19
    rlwinm 11,11,0,0,26
    li 12,0
    stw 12,0(11)
    stw 12,4(11)
    stw 12,8(11)
    stw 12,12(11)
    stw 12,16(11)
    stw 12,20(11)
    stw 12,24(11)
    stw 12,28(11)
    mfspr 11,272
    mfspr 12,273
    rfi
    .size alignment_handler,.-alignment_handler

    .section .exception.decrementer,"ax",@progbits
    .balign 4
    .globl decrementer_handler
    .type decrementer_handler,@function
decrementer_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,dec_count@ha
    lwz 11,dec_count@l(12)
    addi 11,11,1
    stw 11,dec_count@l(12)
    li 11,3000
    mtspr 22,11
    mfspr 11,272
    mfspr 12,273
    rfi
    .size decrementer_handler,.-decrementer_handler
    .section .note.GNU-stack,"",@progbits
