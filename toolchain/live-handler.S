    .section .exception.syscall,"ax",@progbits
    .balign 4
    .globl syscall_handler
    .type syscall_handler,@function
syscall_handler:
    mtspr 272,11
    mtspr 273,12
    lis 12,handler_msr@ha
    mfmsr 11
    stw 11,handler_msr@l(12)
    lis 12,handler_srr1@ha
    mfspr 11,27
    stw 11,handler_srr1@l(12)
    lis 12,handler_count@ha
    lwz 11,handler_count@l(12)
    addi 11,11,1
    stw 11,handler_count@l(12)
    mfspr 11,272
    mfspr 12,273
    rfi
    .size syscall_handler,.-syscall_handler
    .section .note.GNU-stack,"",@progbits
