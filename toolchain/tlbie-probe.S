.section .pageprobe,"ax",@progbits
.globl page_probe
.type page_probe,@function
page_probe:
    addi 3,3,17
    blr
.size page_probe,.-page_probe
.section .faultprobe,"ax",@progbits
.globl tlbie_data_probe
.type tlbie_data_probe,@function
tlbie_data_probe:
    lwz 3,0(3)
    blr
.size tlbie_data_probe,.-tlbie_data_probe
.section .note.GNU-stack,"",@progbits
