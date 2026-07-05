# performance_test.s
# RV32I Performance Benchmark for Basys 3
# Calculates sum of 1 to 1000 and measures cycle count.

.section .text
.globl _start

_start:
    # Addresses
    # 0x00020010 : Cycle Counter (Read)
    # 0x00020008 : LED Register   (Write)
    
    lui  t0, 0x00020        # Base address for peripherals
    addi t0, t0, 0x010      # t0 = 0x00020010 (Cycle Count)

    lw   s0, 0(t0)          # s0 = start_cycles

    # --- Benchmark Start: Sum 1 to 1000 ---
    li   t1, 0              # sum = 0
    li   t2, 1              # i = 1
    li   t3, 1001           # limit = 1001
loop:
    add  t1, t1, t2         # sum = sum + i
    addi t2, t2, 1          # i = i + 1
    blt  t2, t3, loop       # if i < 1001 then loop
    # --- Benchmark End ---

    lw   s1, 0(t0)          # s1 = end_cycles
    sub  s2, s1, s0         # s2 = elapsed_cycles = end - start

    # Display results
    lui  t4, 0x00020
    addi t4, t4, 0x008      # t4 = 0x00020008 (LEDs)
    sw   s2, 0(t4)          # Show cycle count on LEDs

done:
    j    done               # Infinite loop
