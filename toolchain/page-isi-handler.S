    .section .exception.isi,"ax",@progbits
    .balign 4
    .globl page_isi_handler
    .type page_isi_handler,@function
page_isi_handler:
    mtspr 272,0
    mtspr 273,11
    mtspr 274,12
    mfcr 0
    mtspr 275,0
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
    cmpwi 11,2
    beq .Lclear_n
    /* PP and G repair: replace way 0 from software-seeded ICMP/RPA. */
    lis 12,repair_rpa@ha
    lwz 11,repair_rpa@l(12)
    mtspr 982,11
    lis 11,0x2000
    sync
    isync
    tlbli 11
    sync
    isync
    b .Lreturn
.Lclear_n:
    /* N is a segment attribute, not a TLB entry property. */
    lis 11,0x4000
    ori 11,11,0x5678
    mtsr 2,11
    isync
.Lreturn:
    mfspr 0,275
    mtcrf 255,0
    mfspr 0,272
    mfspr 11,273
    mfspr 12,274
    rfi
    .size page_isi_handler,.-page_isi_handler
    .section .note.GNU-stack,"",@progbits
