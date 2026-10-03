/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Residuals firmware handlers. Each appends {vector, SRR0, SRR1, MSR} to
 * trap_log. Ordinary handlers run with TGPR clear and save r4-r6 and CR in
 * SPRG0-3; the data TLB miss handlers run on the temporary r0-r3 and
 * change no CR field. */
    .macro LOG_ENTRY vec
    mtspr 272,4
    mtspr 273,5
    mtspr 274,6
    mfcr 4
    mtspr 275,4
    lis 5,log_n@ha
    lwz 6,log_n@l(5)
    addi 4,6,1
    stw 4,log_n@l(5)
    slwi 6,6,4
    lis 5,trap_log@ha
    addi 5,5,trap_log@l
    add 5,5,6
    li 4,\vec
    stw 4,0(5)
    mfspr 4,26
    stw 4,4(5)
    mfspr 4,27
    stw 4,8(5)
    mfmsr 4
    stw 4,12(5)
    .endm

    .macro RETURN
    mfspr 4,275
    mtcr 4
    mfspr 4,272
    mfspr 5,273
    mfspr 6,274
    rfi
    .endm

    .macro SKIP
    mfspr 4,26
    addi 4,4,4
    mtspr 26,4
    .endm

    .section .exception.dsi,"ax",@progbits
    .globl dsi_handler
    .type dsi_handler,@function
dsi_handler:
    LOG_ENTRY 0x300
    lis 5,dsi_dsisr@ha
    mfspr 4,18
    stw 4,dsi_dsisr@l(5)
    lis 5,dsi_dar@ha
    mfspr 4,19
    stw 4,dsi_dar@l(5)
    SKIP
    RETURN
    .size dsi_handler,.-dsi_handler

    .section .exception.alignment,"ax",@progbits
    .globl alignment_handler
    .type alignment_handler,@function
alignment_handler:
    LOG_ENTRY 0x600
    SKIP
    RETURN
    .size alignment_handler,.-alignment_handler

    .section .exception.program,"ax",@progbits
    .globl program_handler
    .type program_handler,@function
program_handler:
    LOG_ENTRY 0x700
    SKIP
    RETURN
    .size program_handler,.-program_handler

/* Reload DEC far from the next transition; SRR0 is the next instruction. */
    .section .exception.decrementer,"ax",@progbits
    .globl decrementer_handler
    .type decrementer_handler,@function
decrementer_handler:
    LOG_ENTRY 0x900
    lis 4,0x7fff
    ori 4,4,0xffff
    mtspr 22,4
    RETURN
    .size decrementer_handler,.-decrementer_handler

/* Return to supervisor state at the next instruction. */
    .section .exception.syscall,"ax",@progbits
    .globl syscall_handler
    .type syscall_handler,@function
syscall_handler:
    LOG_ENTRY 0xc00
    mfspr 4,27
    rlwinm 4,4,0,18,16
    mtspr 27,4
    RETURN
    .size syscall_handler,.-syscall_handler

/* Clear SE and BE so the traced code resumes untraced. */
    .section .exception.trace,"ax",@progbits
    .globl trace_handler
    .type trace_handler,@function
trace_handler:
    LOG_ENTRY 0xd00
    mfspr 4,27
    rlwinm 4,4,0,23,20
    mtspr 27,4
    RETURN
    .size trace_handler,.-trace_handler

    .macro MISS vec
    lis 1,log_n@ha
    lwz 2,log_n@l(1)
    addi 3,2,1
    stw 3,log_n@l(1)
    slwi 2,2,4
    lis 1,trap_log@ha
    addi 1,1,trap_log@l
    add 1,1,2
    li 3,\vec
    stw 3,0(1)
    mfspr 3,26
    stw 3,4(1)
    mfspr 3,27
    stw 3,8(1)
    mfmsr 3
    stw 3,12(1)
    lis 1,miss_hash1@ha
    mfspr 3,978
    stw 3,miss_hash1@l(1)
    lis 1,miss_dmiss@ha
    mfspr 3,976
    stw 3,miss_dmiss@l(1)
    mfspr 3,26
    addi 3,3,4
    mtspr 26,3
    rfi
    .endm

/* Data TLB misses are recorded and skipped; rfi clears TGPR. */
    .section .exception.dtlb_load,"ax",@progbits
    .globl dtlb_load_handler
    .type dtlb_load_handler,@function
dtlb_load_handler:
    MISS 0x1100
    .size dtlb_load_handler,.-dtlb_load_handler

    .section .exception.dtlb_store,"ax",@progbits
    .globl dtlb_store_handler
    .type dtlb_store_handler,@function
dtlb_store_handler:
    MISS 0x1200
    .size dtlb_store_handler,.-dtlb_store_handler

/* Clear IABR and re-execute the breakpointed instruction. */
    .section .exception.iabr,"ax",@progbits
    .globl iabr_handler
    .type iabr_handler,@function
iabr_handler:
    LOG_ENTRY 0x1300
    li 4,0
    mtspr 1010,4
    RETURN
    .size iabr_handler,.-iabr_handler
    .section .note.GNU-stack,"",@progbits
