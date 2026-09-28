/* Alignment handler: record DAR/DSISR/SRR0, count, skip the instruction. */
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
    mfspr 11,272
    mfspr 12,273
    rfi
    .size alignment_handler,.-alignment_handler

    .section .note.GNU-stack,"",@progbits
