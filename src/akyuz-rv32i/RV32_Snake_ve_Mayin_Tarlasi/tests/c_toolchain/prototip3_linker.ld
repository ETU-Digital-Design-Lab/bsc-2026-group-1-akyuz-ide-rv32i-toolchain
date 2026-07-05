/* prototip3_linker.ld */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  IMEM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
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
    *(.srodata*)
  } > IMEM

  /* .data: calisma DMEM'de (VMA), ilk-deger goruntusu IMEM'de (LMA).
     crt0 acilista IMEM->DMEM kopyalar. */
  . = ALIGN(4);
  .data : {
    . = ALIGN(4);
    __data_start = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    __data_end = .;
  } > DMEM AT > IMEM
  __data_load = LOADADDR(.data);

  .bss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DMEM

  . = ALIGN(4);
  /* Place stack at the top of DMEM (4KB minus 4 bytes) */
  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM) - 4;
}
