@echo off
echo ============================================
echo  RV32 Prototip-2 SoC Simulation
echo  (Wishbone B4 Bus + Periferaller)
echo ============================================

cd /d "%~dp0"

echo [1/3] Compiling SoC...
iverilog -o tb_rv32_soc.vvp -g2012 ^
  -I..\rtl ^
  -I..\rtl\periph ^
  tb_soc.v ^
  ..\rtl\rv32_soc.v ^
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
  ..\rtl\hazard_detection_unit.v ^
  ..\rtl\periph\wb_interconnect.v ^
  ..\rtl\periph\wb_dmem.v ^
  ..\rtl\periph\wb_slave_wrapper.v ^
  ..\rtl\periph\uart.v ^
  ..\rtl\periph\gpio.v ^
  ..\rtl\periph\timer.v ^
  ..\rtl\periph\spi.v

if errorlevel 1 (
    echo [ERROR] Derleme hatasi!
    pause
    exit /b 1
)

echo [2/3] Running SoC simulation...
vvp tb_rv32_soc.vvp

echo [3/3] Done!
pause
