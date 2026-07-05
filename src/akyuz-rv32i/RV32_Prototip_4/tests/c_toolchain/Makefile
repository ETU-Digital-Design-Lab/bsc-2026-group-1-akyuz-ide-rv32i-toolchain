# Makefile for RV32_Prototip_4

# Standard RISC-V GCC (can be 64-bit or 32-bit toolchain, target is forced below)
PREFIX ?= riscv64-unknown-elf-
CC = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

# Force 32-bit compilation suitable for our RV32I core
CFLAGS = -march=rv32i -mabi=ilp32 -Os -Wall -ffreestanding -nostdlib
LDFLAGS = -T prototip4_linker.ld -nostartfiles -Wl,--no-relax

all: firmware.bin firmware.hex firmware.lst

firmware.elf: crt0.S main.c prototip4_linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S main.c -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -j .text -j .rodata -O binary firmware.elf firmware.bin

firmware.hex: firmware.elf
	$(OBJCOPY) -O verilog firmware.elf firmware.hex

firmware.lst: firmware.elf
	$(OBJDUMP) -D firmware.elf > firmware.lst

clean:
	rm -f *.elf *.bin *.hex *.lst
