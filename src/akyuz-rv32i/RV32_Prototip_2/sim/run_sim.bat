@echo off
echo ============================================
echo  RV32 Prototip-2 Simulation (Wishbone B4)
echo ============================================

cd /d "%~dp0"

echo [1/3] Compiling...
iverilog -o tb_rv32_core.vvp -g2012 ^
  -I..\rtl ^
  ..\tests\tb_rv32_core.v ^
  ..\rtl\rv32_core_pipelined.v ^
  ..\rtl\rv32_control.v ^
  ..\rtl\alu.v ^
  ..\rtl\regfile.v ^
  ..\rtl\pc.v ^
  ..\rtl\if_id_reg.v ^
  ..\rtl\id_ex_reg.v ^
  ..\rtl\ex_mem_reg.v ^
  ..\rtl\mem_wb_reg.v ^
  ..\rtl\forwarding_unit.v ^
  ..\rtl\hazard_detection_unit.v

if errorlevel 1 (
    echo [ERROR] Derleme hatasi!
    pause
    exit /b 1
)

echo [2/3] Running simulation...
vvp tb_rv32_core.vvp

echo [3/3] Done! VCD file: tb_rv32_core.vcd
pause
