/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
    /* Software table search plus machine-check, DSI, ISI, external and
       decrementer handlers for the MMU/event stress image. Miss handlers use
       only TGPR0..TGPR3 and SPRG0..2; the others run with EE=0 in real mode,
       save r3/r4 in SPRG0/1, and change neither CR, LR, CTR nor XER. */
    .section .exception.imiss,"ax",@progbits
    .globl imiss_handler
    .type imiss_handler,@function
imiss_handler:
    mfspr 1,980
    mfspr 2,981
    li 3,1
    b .Lsearch_entry
    .size imiss_handler,.-imiss_handler

    .section .exception.dlmiss,"ax",@progbits
    .globl dlmiss_handler
    .type dlmiss_handler,@function
dlmiss_handler:
    mfspr 1,976
    mfspr 2,977
    li 3,0
    b .Lsearch_entry
    .size dlmiss_handler,.-dlmiss_handler

    .section .exception.dsmiss,"ax",@progbits
    .globl dsmiss_handler
    .type dsmiss_handler,@function
dsmiss_handler:
    mfspr 1,976
    mfspr 2,977
    li 3,2
    b .Lsearch_entry
    .size dsmiss_handler,.-dsmiss_handler

    .text
.Lsearch_entry:
    /* SPRG0=EA, SPRG1=CMP, SPRG2=type (0 load, 1 fetch, 2 store/C=0). */
    mtspr 272,1
    mtspr 273,2
    mtspr 274,3

    /* Per-type count, then a 64-entry ring of {EA, SRR1, type, SRR0}. */
    slwi 3,3,2
    lis 2,miss_type_count@ha
    addi 2,2,miss_type_count@l
    add 2,2,3
    lwz 1,0(2)
    addi 1,1,1
    stw 1,0(2)
    lis 2,miss_total@ha
    lwz 3,miss_total@l(2)
    addi 1,3,1
    stw 1,miss_total@l(2)
    rlwinm 3,3,4,22,27
    lis 2,miss_log@ha
    addi 2,2,miss_log@l
    add 3,3,2
    mfspr 1,272
    stw 1,0(3)
    mfspr 1,27
    stw 1,4(3)
    mfspr 1,274
    stw 1,8(3)
    mfspr 1,26
    stw 1,12(3)

    mfspr 1,978
    li 2,8
    mfspr 3,273
.Lprimary_loop:
    lwz 0,0(1)
    cmpw 0,3
    beq .Lpte_found
    addi 1,1,8
    addi 2,2,-1
    cmpwi 2,0
    bne .Lprimary_loop

    /* Secondary PTEG compares H=1; ICMP/DCMP keep H=0 for the fill. */
    mfspr 1,979
    li 2,8
    mfspr 3,273
    ori 3,3,0x40
.Lsecondary_loop:
    lwz 0,0(1)
    cmpw 0,3
    beq .Lpte_found
    addi 1,1,8
    addi 2,2,-1
    cmpwi 2,0
    bne .Lsecondary_loop
    b .Lnot_found

.Lpte_found:
    lwz 0,4(1)
    andi. 2,0,0x0e04            /* reserved RPA bits 20..22 and 29 */
    bne stress_failure
    mfspr 2,274
    cmpwi 2,1
    bne .Lcheck_permission
    andi. 2,0,8                 /* fetch may not use G=1 */
    bne .Lisi_guarded
.Lcheck_permission:
    /* Key (SRR1[19]) 0: PP 3 read-only. Key 1: PP 0 none, 1/3 read-only. */
    mfspr 2,27
    andis. 2,2,0x0008
    bne .Lkey_one
    andi. 2,0,3
    cmpwi 2,3
    bne .Lpermission_granted
    b .Lread_only
.Lkey_one:
    andi. 2,0,3
    cmpwi 2,0
    beq .Lprotection
    cmpwi 2,2
    beq .Lpermission_granted
.Lread_only:
    mfspr 2,274
    cmpwi 2,2
    beq .Lprotection
.Lpermission_granted:
    mfspr 2,274
    cmpwi 2,2
    beq .Lstore_update
    ori 0,0,0x100               /* R */
    srwi 2,0,8
    stb 2,6(1)
    b .Lwrite_complete
.Lstore_update:
    ori 0,0,0x180               /* R and C */
    sth 0,6(1)
.Lwrite_complete:
    sync
    mtspr 982,0
    mfspr 1,272
    mfspr 2,274
    cmpwi 2,1
    beq .Lfill_instruction
    tlbld 1
    b .Lreturn
.Lfill_instruction:
    tlbli 1
.Lreturn:
    mfspr 0,27
    mtcrf 128,0
    rfi

.Lnot_found:
    lis 2,0x4000                /* SRR1[1] / DSISR[1]: no PTE */
    b .Lconvert
.Lprotection:
    lis 2,0x0800                /* SRR1[4] / DSISR[4]: protection */
    b .Lconvert
.Lisi_guarded:
    lis 2,0x1000                /* SRR1[3]: guarded fetch */
.Lconvert:
    mfspr 3,274
    cmpwi 3,1
    beq .Lisi_convert
    /* DSISR = cause | store bit (saved SRR1[15] -> DSISR[6]); DAR = DMISS. */
    mfspr 3,27
    rlwinm 1,3,9,6,6
    or 1,1,2
    mtspr 18,1
    mfspr 1,976
    mtspr 19,1
    andi. 1,3,0xffff
    mtspr 27,1
    mfmsr 0
    xoris 0,0,0x0002
    mtcrf 128,3
    mtmsr 0
    b dsi_handler
.Lisi_convert:
    mfspr 3,27
    andi. 1,3,0xffff
    or 1,1,2
    mtspr 27,1
    mfmsr 0
    xoris 0,0,0x0002
    mtcrf 128,3
    mtmsr 0
    b isi_handler

    .globl stress_failure
    .type stress_failure,@function
stress_failure:
    lis 0,0x8dff
    ori 0,0,1
    lis 1,tohost@ha
    stw 0,tohost@l(1)
.Lfailure_halt:
    b .Lfailure_halt
    .size stress_failure,.-stress_failure

    /* fault_log words: 0 DSI count, 1 DAR, 2 DSISR, 3 SRR0, 4 ISI count,
       5 ISI SRR0, 6 ISI SRR1. DSI skips the access; ISI returns to LR. */
    .section .exception.dsi,"ax",@progbits
    .globl dsi_handler
    .type dsi_handler,@function
dsi_handler:
    mtspr 272,3
    mtspr 273,4
    lis 4,fault_log@ha
    addi 4,4,fault_log@l
    lwz 3,0(4)
    addi 3,3,1
    stw 3,0(4)
    mfspr 3,19
    stw 3,4(4)
    mfspr 3,18
    stw 3,8(4)
    mfspr 3,26
    stw 3,12(4)
    addi 3,3,4
    mtspr 26,3
    mfspr 3,272
    mfspr 4,273
    rfi
    .size dsi_handler,.-dsi_handler

    .section .exception.isi,"ax",@progbits
    .globl isi_handler
    .type isi_handler,@function
isi_handler:
    mtspr 272,3
    mtspr 273,4
    lis 4,fault_log@ha
    addi 4,4,fault_log@l
    lwz 3,16(4)
    addi 3,3,1
    stw 3,16(4)
    mfspr 3,26
    stw 3,20(4)
    mfspr 3,27
    stw 3,24(4)
    mflr 3
    mtspr 26,3
    mfspr 3,272
    mfspr 4,273
    rfi
    .size isi_handler,.-isi_handler

    /* TEA machine check: count and retry at SRR0. SRR1[RI]=0 means the
       interrupted state is lost. CR is saved in SPRG3. */
    .section .exception.machine_check,"ax",@progbits
    .globl machine_check_handler
    .type machine_check_handler,@function
machine_check_handler:
    mtspr 272,3
    mtspr 273,4
    mfcr 3
    mtspr 275,3
    mfspr 3,27
    andi. 3,3,2
    beq- stress_failure
    lis 4,stress_mc_count@ha
    lwz 3,stress_mc_count@l(4)
    addi 3,3,1
    stw 3,stress_mc_count@l(4)
    mfspr 3,275
    mtcrf 255,3
    mfspr 3,272
    mfspr 4,273
    rfi
    .size machine_check_handler,.-machine_check_handler

    /* The bench drops its IRQ level on the physical irq_ack write. */
    .section .exception.interrupt,"ax",@progbits
    .globl interrupt_handler
    .type interrupt_handler,@function
interrupt_handler:
    mtspr 272,3
    mtspr 273,4
    lis 4,stress_ext_count@ha
    lwz 3,stress_ext_count@l(4)
    addi 3,3,1
    stw 3,stress_ext_count@l(4)
    lis 4,irq_ack@ha
    stw 3,irq_ack@l(4)
    mfspr 3,272
    mfspr 4,273
    rfi
    .size interrupt_handler,.-interrupt_handler

    /* Rearm DEC with 160..1152 ticks, varied by the event count. */
    .section .exception.decrementer,"ax",@progbits
    .globl decrementer_handler
    .type decrementer_handler,@function
decrementer_handler:
    mtspr 272,3
    mtspr 273,4
    lis 4,stress_dec_count@ha
    lwz 3,stress_dec_count@l(4)
    addi 3,3,1
    stw 3,stress_dec_count@l(4)
    rlwinm 3,3,5,22,26
    addi 3,3,160
    mtspr 22,3
    mfspr 3,272
    mfspr 4,273
    rfi
    .size decrementer_handler,.-decrementer_handler

    /* Probes with fixed PCs for SRR0 checks. A skipped load returns its
       unchanged address argument. */
    .text
    .globl stress_load,stress_load_pc
    .type stress_load,@function
stress_load:
stress_load_pc:
    lwz 3,0(3)
    blr
    .size stress_load,.-stress_load
    .globl stress_store,stress_store_pc
    .type stress_store,@function
stress_store:
stress_store_pc:
    stw 4,0(3)
    blr
    .size stress_store,.-stress_store
    /* Branch storm, copied so blob+0x100 is a page boundary: the first
       0x100 bytes end page Q0, the rest start page Q1. storm(r3, r4=count)
       crosses the boundary by fall-through, a conditional branch and bdnz,
       and returns through LR computed by the callee. */
    .section .text.storm,"ax",@progbits
    .balign 4
    .globl storm_blob
storm_blob:
    .space 0xc0
storm_entry:
    mflr 0
    mtctr 4
    li 5,0
storm_loop:
    addi 5,5,1
    andi. 6,5,3
    beq storm_even
    cmpwi 1,6,2
    beq 1,storm_two
    xor 3,3,5
    b storm_tail
storm_two:
    addi 3,3,0x11
    b storm_tail
    .org storm_blob+0xfc
storm_tail:
    add 3,3,5
storm_q1:
    rotlwi 3,3,3
    bl storm_sub
    bdnz storm_loop
    mtlr 0
    blr
storm_even:
    subf 3,5,3
    b storm_q1
storm_sub:
    mflr 8
    bl storm_skip
    addi 3,3,1000
storm_skip:
    mflr 7
    addi 7,7,24
    mtlr 7
    blr
    addi 3,3,2000
    xori 3,3,0x5a5a
    mtlr 8
    blr
    .org storm_blob+0x200
    .size storm_blob,.-storm_blob

    .section .note.GNU-stack,"",@progbits
