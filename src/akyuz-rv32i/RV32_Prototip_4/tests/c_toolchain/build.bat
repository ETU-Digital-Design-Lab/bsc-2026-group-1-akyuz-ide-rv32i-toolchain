@echo off
set "GCC_BIN=C:\Users\Taha\Desktop\riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-w64-mingw32\bin"
set "PATH=%GCC_BIN%;%PATH%"

echo C kodlari derleniyor...
%GCC_BIN%\riscv64-unknown-elf-gcc.exe -march=rv32i -mabi=ilp32 -Os -Wall -ffreestanding -nostdlib -T prototip4_linker.ld -nostartfiles -Wl,--no-relax crt0.S main.c -o firmware.elf

if %errorlevel% neq 0 (
    echo.
    echo DERLEME HATASI!
    exit /b %errorlevel%
)

echo Makine makine koduna (Binary) cevriliyor...
%GCC_BIN%\riscv64-unknown-elf-objcopy.exe -j .text -j .rodata -O binary firmware.elf firmware.bin

if %errorlevel% neq 0 (
    echo.
    echo DONUSTURME HATASI!
    exit /b %errorlevel%
)

echo.
echo =========================================
echo HARIKA! firmware.bin basariyla olusturuldu.
echo =========================================
echo.
echo Simdi ayni pencereye sunu yazip calistir:
echo python upload.py COM12 firmware.bin
echo (Not: COM12 yerine Vivado'daki portunu yazmayi unutma)
