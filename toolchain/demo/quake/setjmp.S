/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* setjmp/longjmp for the SVR4 ABI, without lmw/stmw, which little-endian
 * mode does not allow. Layout of the buffer: LR, CR, r1, r2,
 * r13-r31 from byte 0, then f14-f31 from byte 104 with hard float. */
    .text
    .globl setjmp
    .type setjmp,@function
setjmp:
    mflr 0
    mfcr 5
    stw 0,0(3)
    stw 5,4(3)
    stw 1,8(3)
    stw 2,12(3)
    .irp r,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    stw \r,16+4*(\r-13)(3)
    .endr
#ifndef _SOFT_FLOAT
    stfd 14,104(3)
    stfd 15,112(3)
    stfd 16,120(3)
    stfd 17,128(3)
    stfd 18,136(3)
    stfd 19,144(3)
    stfd 20,152(3)
    stfd 21,160(3)
    stfd 22,168(3)
    stfd 23,176(3)
    stfd 24,184(3)
    stfd 25,192(3)
    stfd 26,200(3)
    stfd 27,208(3)
    stfd 28,216(3)
    stfd 29,224(3)
    stfd 30,232(3)
    stfd 31,240(3)
#endif
    li 3,0
    blr
    .size setjmp,.-setjmp

    .globl longjmp
    .type longjmp,@function
longjmp:
    lwz 0,0(3)
    lwz 5,4(3)
    mtlr 0
    mtcrf 0xff,5
    lwz 1,8(3)
    lwz 2,12(3)
#ifndef _SOFT_FLOAT
    lfd 14,104(3)
    lfd 15,112(3)
    lfd 16,120(3)
    lfd 17,128(3)
    lfd 18,136(3)
    lfd 19,144(3)
    lfd 20,152(3)
    lfd 21,160(3)
    lfd 22,168(3)
    lfd 23,176(3)
    lfd 24,184(3)
    lfd 25,192(3)
    lfd 26,200(3)
    lfd 27,208(3)
    lfd 28,216(3)
    lfd 29,224(3)
    lfd 30,232(3)
    lfd 31,240(3)
#endif
    mr. 0,4
    bne 1f
    li 0,1
1:  mr 5,3
    mr 3,0
    .irp r,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    lwz \r,16+4*(\r-13)(5)
    .endr
    blr
    .size longjmp,.-longjmp

    .section .note.GNU-stack,"",@progbits
