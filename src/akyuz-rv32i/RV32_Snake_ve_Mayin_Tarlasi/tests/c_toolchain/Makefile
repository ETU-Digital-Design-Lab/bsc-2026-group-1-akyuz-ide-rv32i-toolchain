# Makefile for RV32_Prototip_3

# Standard RISC-V GCC (can be 64-bit or 32-bit toolchain, target is forced below)
PREFIX ?= riscv64-unknown-elf-
CC = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump

# Force 32-bit compilation suitable for our RV32I core
CFLAGS = -march=rv32i -mabi=ilp32 -Os -Wall -ffreestanding -nostdlib
# --build-id=none: .note.gnu.build-id (alloc) bolumu _start'i 0x0'dan kaydirmasin diye
LDFLAGS = -T prototip3_linker.ld -nostartfiles -Wl,--no-relax -Wl,--build-id=none

# RV32I has no hardware mul/div; pull __divsi3/__modsi3/__umodsi3 from libgcc
LIBGCC = $(shell $(CC) $(CFLAGS) -print-libgcc-file-name)

all: firmware.bin firmware.hex firmware.lst

firmware.elf: crt0.S main.c prototip3_linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S main.c $(LIBGCC) -o firmware.elf

firmware.bin: firmware.elf
	$(OBJCOPY) -j .text -j .rodata -j .data -O binary firmware.elf firmware.bin

firmware.hex: firmware.elf
	$(OBJCOPY) -O verilog firmware.elf firmware.hex

firmware.lst: firmware.elf
	$(OBJDUMP) -D firmware.elf > firmware.lst

clean:
	rm -f *.elf *.bin *.hex *.lst
