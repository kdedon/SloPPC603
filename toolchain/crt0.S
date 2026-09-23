    .section .text.boot,"ax",@progbits
    .balign 4
    .globl _start
    .type _start,@function
_start:
    .long 0x60000000
    lis 1,__stack_top@ha
    addi 1,1,__stack_top@l
    li 0,0
    stwu 0,-16(1)

    lis 5,__bss_start@ha
    addi 5,5,__bss_start@l
    lis 6,__bss_end@ha
    addi 6,6,__bss_end@l
.Lbss_loop:
    cmplw 5,6
    bge .Lbss_done
    stw 0,0(5)
    addi 5,5,4
    b .Lbss_loop
.Lbss_done:
    lis 4,tohost@ha
    stw 0,tohost@l(4)
#if defined(ENABLE_ALIGNMENT_SMOKE) || defined(ENABLE_FETCH_SMOKE) || defined(ENABLE_LIVE_SMOKE) || defined(ENABLE_IRQ_SMOKE) || defined(ENABLE_TIMER_SMOKE) || defined(ENABLE_RUNTIME_BAT_SMOKE) || defined(ENABLE_DSI_SMOKE) || defined(ENABLE_SEGMENT_SMOKE) || defined(ENABLE_PAGE_SMOKE) || defined(ENABLE_TLBIE_SMOKE) || defined(ENABLE_TLBLOAD_SMOKE) || defined(ENABLE_PAGE_DSI_SMOKE) || defined(ENABLE_PAGE_ISI_SMOKE)
    /* Select high exception vectors using the currently supported RFI path. */
    lis 5,.Lsupervisor_ready@ha
    addi 5,5,.Lsupervisor_ready@l
    mtspr 26,5
    li 5,0x40
    mtspr 27,5
    rfi
.Lsupervisor_ready:
#endif
    bl main
    lis 4,tohost@ha
    stw 3,tohost@l(4)
1:
    b 1b
    .size _start,.-_start

    .section .note.GNU-stack,"",@progbits
