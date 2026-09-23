    .section .exception.isi,"ax",@progbits
    .balign 4
    .globl isi_handler
    .type isi_handler,@function
isi_handler:
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
    .size isi_handler,.-isi_handler
    .section .probe.protection,"ax",@progbits
    .globl fetch_protection_probe
    .type fetch_protection_probe,@function
fetch_protection_probe:
    li 3,0x1234
    blr
    .size fetch_protection_probe,.-fetch_protection_probe
    .section .probe.guarded,"ax",@progbits
    .globl fetch_guarded_probe
    .type fetch_guarded_probe,@function
fetch_guarded_probe:
    li 3,0x5678
    blr
    .size fetch_guarded_probe,.-fetch_guarded_probe
    .section .note.GNU-stack,"",@progbits
