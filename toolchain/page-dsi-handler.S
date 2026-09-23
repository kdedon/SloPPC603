    .section .exception.dsi,"ax",@progbits
    .balign 4
    .globl page_dsi_handler
    .type page_dsi_handler,@function
page_dsi_handler:
    mtspr 272,0
    mtspr 273,11
    mtspr 274,12
    mfcr 0
    mtspr 275,0
    lis 12,fault_dar@ha
    mfspr 11,19
    stw 11,fault_dar@l(12)
    lis 12,fault_dsisr@ha
    mfspr 11,18
    stw 11,fault_dsisr@l(12)
    lis 12,fault_pc@ha
    mfspr 11,26
    stw 11,fault_pc@l(12)
    lis 12,fault_srr1@ha
    mfspr 11,27
    stw 11,fault_srr1@l(12)
    lis 12,fault_entry_msr@ha
    mfmsr 11
    stw 11,fault_entry_msr@l(12)
    lis 12,fault_count@ha
    lwz 11,fault_count@l(12)
    addi 11,11,1
    stw 11,fault_count@l(12)
    /* This direct physical read catches any escaped denied store before repair. */
    lis 12,denied_word@ha
    lis 11,0xfff0
    ori 11,11,0x8000
    lwz 11,0(11)
    stw 11,denied_word@l(12)
    /* Software fixes the pre-existing entry, then RFI retries SRR0. */
    lis 12,repair_rpa@ha
    lwz 11,repair_rpa@l(12)
    mtspr 982,11
    lis 11,0x1000
    ori 11,11,0x8000
    sync
    isync
    tlbld 11
    sync
    isync
    mfspr 0,275
    mtcrf 255,0
    mfspr 0,272
    mfspr 11,273
    mfspr 12,274
    rfi
    .size page_dsi_handler,.-page_dsi_handler
    .section .note.GNU-stack,"",@progbits
