/* crt0.S - C Runtime Zero */
.section .text._start
.global _start

_start:
    /* Stack pointer = top of DMEM */
    la sp, __stack_top

    /* Copy .data: IMEM(LMA) -> DMEM(VMA) */
    la   a0, __data_start
    la   a1, __data_end
    la   a2, __data_load
1:
    bgeu a0, a1, 2f
    lw   a3, 0(a2)
    sw   a3, 0(a0)
    addi a0, a0, 4
    addi a2, a2, 4
    j    1b

2:
    /* Zero .bss */
    la   a0, __bss_start
    la   a1, __bss_end
3:
    bgeu a0, a1, 4f
    sw   x0, 0(a0)
    addi a0, a0, 4
    j    3b

4:
    /* Jump to main() */
    jal ra, main

end_loop:
    j end_loop
