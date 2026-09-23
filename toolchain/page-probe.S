.section .pageprobe,"ax",@progbits
.globl page_probe
.type page_probe,@function
page_probe:
    addi 3,3,17
    blr
.size page_probe,.-page_probe
.section .note.GNU-stack,"",@progbits
