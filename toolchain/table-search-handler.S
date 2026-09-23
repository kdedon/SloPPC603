    /* Bounded 603e software PTEG search. All vector/handler code uses only
       TGPR0..TGPR3; no LR, CTR, XER or normal GPR writes occur before RFI. */
    .section .exception.imiss,"ax",@progbits
    .globl imiss_handler
    .type imiss_handler,@function
imiss_handler:
    mfspr 1,980                 /* full faulting instruction EA */
    mfspr 2,981                 /* automatic ICMP, H=0 */
    li 3,1                      /* event type: instruction */
    b .Lsearch_entry
    .size imiss_handler,.-imiss_handler

    .section .exception.dlmiss,"ax",@progbits
    .globl dlmiss_handler
    .type dlmiss_handler,@function
dlmiss_handler:
    mfspr 1,976                 /* full faulting data EA */
    mfspr 2,977                 /* automatic DCMP, H=0 */
    li 3,0                      /* event type: data load */
    b .Lsearch_entry
    .size dlmiss_handler,.-dlmiss_handler

    .section .exception.dsmiss,"ax",@progbits
    .globl dsmiss_handler
    .type dsmiss_handler,@function
dsmiss_handler:
    mfspr 1,976
    mfspr 2,977
    li 3,2                      /* event type: data store or C=0 hit */
    b .Lsearch_entry
    .size dsmiss_handler,.-dsmiss_handler

    .text
.Lsearch_entry:
    /* Preserve the automatic miss inputs across the verification record and
       both eight-entry searches. SPRG0=EA, SPRG1=CMP, SPRG2=event type. */
    mtspr 272,1
    mtspr 273,2
    mtspr 274,3

    /* Eight-word record ABI: EA,CMP,HASH1,HASH2,SRR0,SRR1,MSR,sequence. */
    lis 2,miss_count@ha
    lwz 3,miss_count@l(2)
    cmpwi 3,4                   /* bounded four-record fixture */
    bge table_search_failure
    slwi 3,3,5
    lis 2,miss_records@ha
    addi 2,2,miss_records@l
    add 3,3,2
    mfspr 1,272
    stw 1,0(3)
    mfspr 2,273
    stw 2,4(3)
    mfspr 0,978
    stw 0,8(3)
    mfspr 0,979
    stw 0,12(3)
    mfspr 0,26
    stw 0,16(3)
    mfspr 0,27
    stw 0,20(3)
    mfmsr 0
    stw 0,24(3)
    lis 2,miss_count@ha
    lwz 1,miss_count@l(2)
    addi 1,1,1
    stw 1,miss_count@l(2)
    stw 1,28(3)

    /* Primary PTEG: compare all 32 PTE0 bits against automatic H=0 CMP. */
    mfspr 1,978                 /* current PTE0 physical address */
    li 2,8                      /* eight 8-byte PTEs */
    mfspr 3,273                 /* expected PTE0 */
.Lprimary_loop:
    lwz 0,0(1)
    cmpw 0,3
    beq .Lpte_found
    addi 1,1,8
    addi 2,2,-1
    cmpwi 2,0
    bne .Lprimary_loop

    /* Secondary PTEG: H is bit 6 of PTE0. Keep ICMP/DCMP H=0 for the
       bounded tlbli/tlbld fill contract; change only this local comparison. */
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
    lwz 0,4(1)                  /* PTE1 / future RPA */
    /* Unsupported RPA encodings remain a bounded diagnostic. Permission and
       guarded faults take the ordinary ISI/DSI path before any R/C write. */
    andi. 2,0,0x0e04            /* reserved RPA bits 20..22 and 29 */
    bne table_search_failure
    mfspr 2,274
    cmpwi 2,1
    bne .Lcheck_permission
    andi. 2,0,8                 /* instruction fetch may not use G=1 */
    bne .Lisi_guarded

.Lcheck_permission:
    /* Key 0 grants PP 0..2 read/write and PP 3 read-only. Key 1 denies
       PP 0, grants PP 1/3 read-only, and PP 2 read/write. SRR1[19] is KEY. */
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

    /* R-only: write PTE1 byte 2, preserving its RPN and low PP/WIMG byte. */
    ori 0,0,0x100
    srwi 2,0,8
    .globl table_search_r_write
table_search_r_write:
    stb 2,6(1)
    b .Lwrite_complete
.Lstore_update:
    /* Store: PTE1 halfword 1 holds R and C. Preserve its upper RPN half. */
    ori 0,0,0x180
    .globl table_search_rc_write
table_search_rc_write:
    sth 0,6(1)
.Lwrite_complete:
    /* The physical PTE update must complete before installing the new TLB
       translation. The serialized data lane retires the write; SYNC records
       the 603e-required ordering in software. */
    sync
    mtspr 982,0                 /* updated PTE1 to RPA */
    mfspr 1,272                 /* full original miss EA; set/API use page bits */
    mfspr 2,274
    cmpwi 2,1
    beq .Lfill_instruction
    tlbld 1
    b .Lreturn
.Lfill_instruction:
    tlbli 1
.Lreturn:
    mfspr 0,27
    mtcrf 128,0                 /* restore saved CR0 before RFI */
    rfi

.Lnot_found:
    mfspr 2,274
    cmpwi 2,1
    beq .Lisi_not_found
    lis 2,0x4000                /* DSISR[1]: PTE not found */
    b .Ldsi_convert
.Lprotection:
    mfspr 2,274
    cmpwi 2,1
    beq .Lisi_protection
    lis 2,0x0800                /* DSISR[4]: page protection */
    b .Ldsi_convert

.Lisi_not_found:
    lis 2,0x4000                /* SRR1[1]: PTE not found */
    b .Lisi_convert
.Lisi_protection:
    lis 2,0x0800                /* SRR1[4]: page protection */
    b .Lisi_convert
.Lisi_guarded:
    .globl table_search_guarded_cause
table_search_guarded_cause:
    lis 2,0x1000                /* SRR1[3]: guarded instruction fetch */
.Lisi_convert:
    /* The ordinary ISI sees saved MSR low 16 plus the cause. Preserve SRR0,
       restore CR0 while TGPR is active, then switch register banks. */
    mfspr 3,27
    andi. 1,3,0xffff
    or 1,1,2
    mtspr 27,1
    mfmsr 0
    xoris 0,0,0x0002           /* clear the asserted TGPR bit */
    mtcrf 128,3
    mtmsr 0
    b table_search_isi_vector   /* no register use after the bank switch */

.Ldsi_convert:
    /* Copy saved store status into DSISR[6], add the cause, and use the
       complete DMISS EA for DAR. The live profile is big-endian only. */
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
    b table_search_dsi_vector

    /* Unsupported or malformed fixture state remains a terminal diagnostic;
       absent/protected/guarded mappings enter the ordinary vectors. */
    .globl table_search_failure
    .type table_search_failure,@function
table_search_failure:
    lis 0,0x8dff
    ori 0,0,1
    lis 1,tohost@ha
    stw 0,tohost@l(1)
.Lfailure_halt:
    b .Lfailure_halt
    .size table_search_failure,.-table_search_failure

    /* Probe PCs retained for the compiled harness; these run after RFI in
       normal GPR mode and follow the ordinary C calling convention. */
    .globl miss_load,miss_load_pc
    .type miss_load,@function
miss_load:
miss_load_pc:
    lwz 3,0(3)
    blr
    .size miss_load,.-miss_load
    .globl miss_store,miss_store_pc
    .type miss_store,@function
miss_store:
miss_store_pc:
    stw 4,0(3)
    blr
    .size miss_store,.-miss_store
    .section .note.GNU-stack,"",@progbits
