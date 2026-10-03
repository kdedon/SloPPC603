/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Machine check, trace and IABR handlers plus the traced sequences. Handlers
 * save r10-r12 and CR in SPRG0-3. A machine check in bad_routine's line
 * returns to LR with r3 = 0x0badf00d; any other skips the faulting access. */
    .section .exception.machine_check,"ax",@progbits
    .balign 4
    .globl machine_check_handler
    .type machine_check_handler,@function
machine_check_handler:
    mtspr 272,11
    mtspr 273,12
    mfcr 11
    mtspr 275,11
    lis 12,mc_count@ha
    lwz 11,mc_count@l(12)
    addi 11,11,1
    stw 11,mc_count@l(12)
    lis 12,mc_srr0@ha
    mfspr 11,26
    stw 11,mc_srr0@l(12)
    lis 12,mc_srr1@ha
    mfspr 11,27
    stw 11,mc_srr1@l(12)
    lis 12,mc_msr@ha
    mfmsr 11
    stw 11,mc_msr@l(12)
    mfspr 11,26
    rlwinm 11,11,0,0,26
    lis 12,bad_routine@ha
    addi 12,12,bad_routine@l
    cmpw 11,12
    bne 1f
    mflr 11
    mtspr 26,11
    lis 3,0x0bad
    ori 3,3,0xf00d
    b 2f
1:  mfspr 11,26
    addi 11,11,4
    mtspr 26,11
2:  mfspr 11,275
    mtcrf 0xff,11
    mfspr 11,272
    mfspr 12,273
    rfi
    .size machine_check_handler,.-machine_check_handler

    .section .exception.trace,"ax",@progbits
    .balign 4
    .globl trace_handler
    .type trace_handler,@function
trace_handler:
    mtspr 272,11
    mtspr 273,12
    mtspr 274,10
    lis 12,trace_count@ha
    lwz 11,trace_count@l(12)
    addi 10,11,1
    stw 10,trace_count@l(12)
    rlwinm 11,11,2,26,29
    lis 12,trace_log@ha
    addi 12,12,trace_log@l
    mfspr 10,26
    stwx 10,12,11
    lis 12,trace_srr1@ha
    mfspr 10,27
    stw 10,trace_srr1@l(12)
    mfspr 10,274
    mfspr 11,272
    mfspr 12,273
    rfi
    .size trace_handler,.-trace_handler

    .section .exception.iabr,"ax",@progbits
    .balign 4
    .globl iabr_handler
    .type iabr_handler,@function
iabr_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,iabr_count@ha
    lwz 11,iabr_count@l(12)
    addi 11,11,1
    stw 11,iabr_count@l(12)
    lis 12,iabr_srr0@ha
    mfspr 11,26
    stw 11,iabr_srr0@l(12)
    li 11,0
    mtspr 1010,11
    mfspr 11,272
    mfspr 12,273
    rfi
    .size iabr_handler,.-iabr_handler

    .section .routine.bad,"ax",@progbits
    .balign 32
    .globl bad_routine
    .type bad_routine,@function
bad_routine:
    li 3,1
    li 3,2
    li 3,3
    li 3,4
    li 3,5
    blr
    .size bad_routine,.-bad_routine

    .text
    /* Single step entered through SRR1/RFI; returns 3. */
    .balign 4
    .globl trace_run
    .type trace_run,@function
trace_run:
    mfmsr 5
    ori 6,5,0x400
    mtspr 27,6
    lis 7,trace_body@ha
    addi 7,7,trace_body@l
    mtspr 26,7
    rfi
    .globl trace_body
trace_body:
    li 8,1
    addi 8,8,1
    b 1f
    nop
1:  addi 8,8,1
    mtmsr 5
    .globl trace_after
trace_after:
    mr 3,8
    blr
    .size trace_run,.-trace_run

    /* Branch trace over a not-taken and a taken branch. */
    .balign 4
    .globl branch_run
    .type branch_run,@function
branch_run:
    mfmsr 5
    ori 6,5,0x200
    mtmsr 6
    cmpw 5,5
    bne 1f
    .globl branch_taken
branch_taken:
    b 2f
1:  nop
    .globl branch_target
branch_target:
2:  mtmsr 5
    li 3,0
    blr
    .size branch_run,.-branch_run

    .balign 4
    .globl iabr_target
    .type iabr_target,@function
iabr_target:
    li 3,7
    blr
    .size iabr_target,.-iabr_target
