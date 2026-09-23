    .section .exception.dsi,"ax",@progbits
    .globl table_search_dsi_vector
    .type table_search_dsi_vector,@function
table_search_dsi_vector:
    /* TGPR is already clear. Preserve the interrupted normal r0-r3 first. */
    mtspr 272,0
    mtspr 273,1
    mtspr 274,2
    mtspr 275,3
    li 0,0
    b .Lordinary_fault
    .size table_search_dsi_vector,.-table_search_dsi_vector

    .section .exception.isi,"ax",@progbits
    .globl table_search_isi_vector
    .type table_search_isi_vector,@function
table_search_isi_vector:
    mtspr 272,0
    mtspr 273,1
    mtspr 274,2
    mtspr 275,3
    li 0,1
    b .Lordinary_fault
    .size table_search_isi_vector,.-table_search_isi_vector

    .text
.Lordinary_fault:
    /* Only r0-r3 are touched, and no link/CTR/XER state is changed. */
    lis 1,fault_kind_scratch@ha
    stw 0,fault_kind_scratch@l(1)
    mfcr 0
    lis 1,fault_cr_scratch@ha
    stw 0,fault_cr_scratch@l(1)

    lis 1,fault_count@ha
    lwz 2,fault_count@l(1)
    cmplwi 2,16
    bge .Lordinary_overflow
    slwi 3,2,4
    slwi 0,2,3
    add 3,3,0                    /* 24 bytes per record. */
    lis 1,fault_records@ha
    addi 1,1,fault_records@l
    add 3,3,1
    lis 1,case_marker@ha
    lwz 0,case_marker@l(1)
    stw 0,0(3)
    mfspr 0,26
    stw 0,4(3)
    mfspr 0,27
    stw 0,8(3)
    mfspr 0,19
    stw 0,12(3)
    mfspr 0,18
    stw 0,16(3)
    mfmsr 0
    stw 0,20(3)
    addi 2,2,1
    lis 1,fault_count@ha
    stw 2,fault_count@l(1)

    lis 1,fault_kind_scratch@ha
    lwz 0,fault_kind_scratch@l(1)
    cmpwi 0,0
    bne .Lresume_instruction
    /* A denied data instruction is skipped; its memory write never occurs. */
    mfspr 1,26
    addi 1,1,4                 /* ADDI rA=0 means zero, not GPR0. */
    mtspr 26,1
    b .Lordinary_return
.Lresume_instruction:
    /* The page remains unmapped or guarded. Return to the caller's LR. */
    mflr 0
    mtspr 26,0
.Lordinary_return:
    lis 1,fault_cr_scratch@ha
    lwz 0,fault_cr_scratch@l(1)
    mtcrf 255,0
    mfspr 3,275
    mfspr 2,274
    mfspr 1,273
    mfspr 0,272
    rfi

.Lordinary_overflow:
    lis 0,0x8dff
    ori 0,0,2
    lis 1,tohost@ha
    stw 0,tohost@l(1)
.Lordinary_halt:
    b .Lordinary_halt

    .section .text.faultprobes,"ax",@progbits
    .globl fault_load_byte
    .globl fault_load_byte_pc
    .type fault_load_byte,@function
fault_load_byte:
fault_load_byte_pc:
    lbz 3,0(3)
    blr
    .size fault_load_byte,.-fault_load_byte
    .section .note.GNU-stack,"",@progbits
