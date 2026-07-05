/* prototip3_linker.ld */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  IMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
  DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    *(.text._start)
    *(.text*)
  } > IMEM

  .rodata : {
    *(.rodata*)
  } > IMEM

  .data : {
    *(.data*)
    *(.sdata*)
  } > DMEM

  .bss : {
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    __bss_end = .;
  } > DMEM

  . = ALIGN(4);
  /* Place stack at the top of DMEM (4KB minus 4 bytes) */
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 4;
}
