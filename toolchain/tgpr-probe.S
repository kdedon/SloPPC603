    .text
    .balign 4
    .globl tgpr_probe
    .type tgpr_probe,@function
tgpr_probe:
    mtspr 272,1
    mtspr 273,2
    li 0,0
    mtspr 275,0
    li 0,0x1111
    li 1,0x2222
    li 2,0x3333
    li 3,0x4444
    lis 4,2
    ori 4,4,0x40
    mtmsr 4
    isync
    /* Only r0-r3 are used while TGPR is selected. */
    cmpwi 0,0
    bne .Ltemp_fail
    cmpwi 1,0
    bne .Ltemp_fail
    cmpwi 2,0
    bne .Ltemp_fail
    cmpwi 3,0
    bne .Ltemp_fail
    li 0,11
    li 1,22
    li 2,33
.Lreturn_normal:
    lis 3,.Lnormal_one@ha
    addi 3,3,.Lnormal_one@l
    mtspr 26,3
    lis 3,2
    ori 3,3,0x40
    /* RFI must clear TGPR even with SRR1.WAY/TGPR-position bit set. */
    mtspr 27,3
    li 3,44
    rfi
.Ltemp_fail:
    li 0,1
    mtspr 275,0
    b .Lreturn_normal
.Lnormal_one:
    cmpwi 0,0x1111
    bne .Lnormal_fail
    cmpwi 1,0x2222
    bne .Lnormal_fail
    cmpwi 2,0x3333
    bne .Lnormal_fail
    cmpwi 3,0x4444
    bne .Lnormal_fail
    mfmsr 4
    cmpwi 4,0x40
    bne .Lnormal_fail
    mfspr 5,275
    cmpwi 5,0
    bne .Lnormal_fail
    lis 4,2
    ori 4,4,0x40
    mtmsr 4
    isync
    cmpwi 0,11
    bne .Ltemp_fail_two
    cmpwi 1,22
    bne .Ltemp_fail_two
    cmpwi 2,33
    bne .Ltemp_fail_two
    cmpwi 3,44
    bne .Ltemp_fail_two
    li 0,0x40
    mtmsr 0
    isync
    b .Lnormal_two
.Ltemp_fail_two:
    li 0,1
    mtspr 275,0
    li 0,0x40
    mtmsr 0
    isync
.Lnormal_two:
    cmpwi 0,0x1111
    bne .Lnormal_fail
    cmpwi 1,0x2222
    bne .Lnormal_fail
    cmpwi 2,0x3333
    bne .Lnormal_fail
    cmpwi 3,0x4444
    bne .Lnormal_fail
    mfspr 5,275
    cmpwi 5,0
    bne .Lnormal_fail
    li 3,1
    b .Lrestore
.Lnormal_fail:
    li 3,0
.Lrestore:
    mfspr 1,272
    mfspr 2,273
    blr
    .size tgpr_probe,.-tgpr_probe
    .section .note.GNU-stack,"",@progbits
