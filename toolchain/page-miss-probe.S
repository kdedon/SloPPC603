/* Reuse the fixed page/load probes; append the store at fff07008. */
#include "tlbie-probe.S"
.section .faultprobe,"ax",@progbits
.globl page_miss_store_probe
.type page_miss_store_probe,@function
page_miss_store_probe:
    stw 4,0(3)
    blr
.size page_miss_store_probe,.-page_miss_store_probe
.section .note.GNU-stack,"",@progbits
