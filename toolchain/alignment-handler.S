    .section .exception.alignment,"ax",@progbits
    .balign 4
    .globl alignment_handler
    .type alignment_handler,@function
alignment_handler:
    /* Preserve interrupted GPRs without changing CR, XER, LR or CTR. */
    mtspr 272,0
    mtspr 273,11
    mtspr 274,12
    lis 12,fault_dar@ha
    mfspr 11,19
    stw 11,fault_dar@l(12)
    lis 12,fault_dsisr@ha
    mfspr 11,18
    stw 11,fault_dsisr@l(12)
    lis 12,fault_pc@ha
    mfspr 11,26
    stw 11,fault_pc@l(12)
    addi 11,11,4
    mtspr 26,11
    lis 12,fault_msr@ha
    mfspr 11,27
    stw 11,fault_msr@l(12)
    lis 12,fault_count@ha
    lwz 11,fault_count@l(12)
    addi 11,11,1
    stw 11,fault_count@l(12)
    mfspr 0,272
    mfspr 11,273
    mfspr 12,274
    rfi
    .size alignment_handler,.-alignment_handler
    .section .note.GNU-stack,"",@progbits
