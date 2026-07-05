/* crt0.S - C Runtime Zero */
.section .text._start
.global _start

_start:
    /* Initialize Stack Pointer to top of DMEM */
    la sp, __stack_top

    /* Optional: Initialize global pointer (gp) here if needed */

    /* Jump to main() */
    jal ra, main

    /* Infinite loop if main unexpectedly returns */
end_loop:
    j end_loop
