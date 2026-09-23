    .section .exception.imiss,"ax",@progbits
    .globl imiss_handler
    .type imiss_handler,@function
imiss_handler:
    mfspr 1,980
    mfspr 2,981
    b .Lrecord_i
    .size imiss_handler,.-imiss_handler
    .section .exception.dlmiss,"ax",@progbits
    .globl dlmiss_handler
    .type dlmiss_handler,@function
dlmiss_handler:
    mfspr 1,976
    mfspr 2,977
    b .Lrecord_d
    .size dlmiss_handler,.-dlmiss_handler
    .section .exception.dsmiss,"ax",@progbits
    .globl dsmiss_handler
    .type dsmiss_handler,@function
dsmiss_handler:
    mfspr 1,976
    mfspr 2,977
    b .Lrecord_d
    .size dsmiss_handler,.-dsmiss_handler
    .text
.Lrecord_i:
    li 3,0
    b .Lrecord
.Lrecord_d:
    li 3,1
.Lrecord:
    /* Only TGPR0-3; preserve all normal GPRs, LR/CTR/XER. */
    mtspr 272,3
    mtspr 273,2
    lis 2,miss_count@ha
    lwz 3,miss_count@l(2)
    slwi 3,3,5
    lis 2,miss_records@ha
    addi 2,2,miss_records@l
    add 3,3,2
    mfspr 2,273
    stw 1,0(3)
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
    lwz 1,0(3)
    mfspr 0,272
    cmpwi 0,0
    beq .Lfill_i
    lis 2,0xeff0
    add 2,1,2
    ori 2,2,0x182
    mtspr 982,2
    tlbld 1
    b .Lreturn
.Lfill_i:
    lis 2,0xfff0
    ori 2,2,0x6182
    mtspr 982,2
    tlbli 1
.Lreturn:
    mfspr 0,27
    mtcrf 128,0
    rfi
    .globl miss_load,miss_load_pc
miss_load:
miss_load_pc:
    lwz 3,0(3)
    blr
    .globl miss_store,miss_store_pc
miss_store:
miss_store_pc:
    stw 4,0(3)
    blr
    .section .note.GNU-stack,"",@progbits
