    .section .exception.dsi,"ax",@progbits
    .balign 4
    .globl dsi_handler
    .type dsi_handler,@function
dsi_handler:
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
    lis 12,fault_msr@ha
    mfspr 11,27
    stw 11,fault_msr@l(12)
    lis 12,fault_entry_msr@ha
    mfmsr 11
    stw 11,fault_entry_msr@l(12)
    lis 12,fault_count@ha
    lwz 11,fault_count@l(12)
    addi 11,11,1
    stw 11,fault_count@l(12)
    lis 12,repair@ha
    lwz 11,repair@l(12)
    cmpwi 11,0
    beq .Lskip
    /* Repair the active data alias and retry exactly the faulting instruction. */
    lis 11,0xfff0
    ori 11,11,2
    mtspr 539,11
    isync
    b .Lreturn
.Lskip:
    mfspr 11,26
    addi 11,11,4
    mtspr 26,11
.Lreturn:
    mfspr 0,275
    mtcrf 255,0
    mfspr 0,272
    mfspr 11,273
    mfspr 12,274
    rfi
    .size dsi_handler,.-dsi_handler
    .section .note.GNU-stack,"",@progbits
