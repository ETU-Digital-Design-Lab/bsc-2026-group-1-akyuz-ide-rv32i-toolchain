## basys3.xdc — Basys 3 (xc7a35tcpg236-1) Constraint File
## Target: basys3_top.v
## Reference: Digilent Basys 3 Master XDC
##
## NOTE: Verify all pin assignments below against the official Digilent
##       Basys 3 Master XDC before programming the board.

## =============================================================================
## Clock  (100 MHz on-board oscillator)
## =============================================================================
set_property PACKAGE_PIN W5  [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk100]

## =============================================================================
## Reset  (BTNC — active-HIGH CENTER pushbutton)
## =============================================================================
set_property PACKAGE_PIN U18 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]
set_property PACKAGE_PIN T18 [get_ports btn_u]
set_property IOSTANDARD LVCMOS33 [get_ports btn_u]
set_property PACKAGE_PIN W19 [get_ports btn_l]
set_property IOSTANDARD LVCMOS33 [get_ports btn_l]
set_property PACKAGE_PIN T17 [get_ports btn_r]
set_property IOSTANDARD LVCMOS33 [get_ports btn_r]
set_property PACKAGE_PIN U17 [get_ports btn_d]
set_property IOSTANDARD LVCMOS33 [get_ports btn_d]

## =============================================================================
## Switches SW0–SW15
## =============================================================================
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property PACKAGE_PIN W15 [get_ports {sw[4]}]
set_property PACKAGE_PIN V15 [get_ports {sw[5]}]
set_property PACKAGE_PIN W14 [get_ports {sw[6]}]
set_property PACKAGE_PIN W13 [get_ports {sw[7]}]
set_property PACKAGE_PIN V2  [get_ports {sw[8]}]
set_property PACKAGE_PIN T3  [get_ports {sw[9]}]
set_property PACKAGE_PIN T2  [get_ports {sw[10]}]
set_property PACKAGE_PIN R3  [get_ports {sw[11]}]
set_property PACKAGE_PIN W2  [get_ports {sw[12]}]
set_property PACKAGE_PIN U1  [get_ports {sw[13]}]
set_property PACKAGE_PIN T1  [get_ports {sw[14]}]
set_property PACKAGE_PIN R2  [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

## =============================================================================
## LEDs LD0–LD15
## =============================================================================
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property PACKAGE_PIN W18 [get_ports {led[4]}]
set_property PACKAGE_PIN U15 [get_ports {led[5]}]
set_property PACKAGE_PIN U14 [get_ports {led[6]}]
set_property PACKAGE_PIN V14 [get_ports {led[7]}]
set_property PACKAGE_PIN V13 [get_ports {led[8]}]
set_property PACKAGE_PIN V3  [get_ports {led[9]}]
set_property PACKAGE_PIN W3  [get_ports {led[10]}]
set_property PACKAGE_PIN U3  [get_ports {led[11]}]
set_property PACKAGE_PIN P3  [get_ports {led[12]}]
set_property PACKAGE_PIN N3  [get_ports {led[13]}]
set_property PACKAGE_PIN P1  [get_ports {led[14]}]
set_property PACKAGE_PIN L1  [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## =============================================================================
## 7-Segment Display (4 digits)
## =============================================================================
## Code convention: seg[6]=g(middle)  seg[5]=f(top-left)  seg[4]=e(bot-left)
##                  seg[3]=d(bottom)  seg[2]=c(bot-right) seg[1]=b(top-right) seg[0]=a(top)
## Basys3 pins:     CG=U7  CF=V5  CE=U5  CD=V8  CC=U8  CB=W6  CA=W7
set_property PACKAGE_PIN U7  [get_ports {seg[6]}]
set_property PACKAGE_PIN V5  [get_ports {seg[5]}]
set_property PACKAGE_PIN U5  [get_ports {seg[4]}]
set_property PACKAGE_PIN V8  [get_ports {seg[3]}]
set_property PACKAGE_PIN U8  [get_ports {seg[2]}]
set_property PACKAGE_PIN W6  [get_ports {seg[1]}]
set_property PACKAGE_PIN W7  [get_ports {seg[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

## Decimal point
set_property PACKAGE_PIN V7  [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

## Anodes AN0–AN3 (active-low, 4 digits)
set_property PACKAGE_PIN U2  [get_ports {an[0]}]
set_property PACKAGE_PIN U4  [get_ports {an[1]}]
set_property PACKAGE_PIN V4  [get_ports {an[2]}]
set_property PACKAGE_PIN W4  [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

## =============================================================================
## UART (USB-Serial CP2102)
## =============================================================================
set_property PACKAGE_PIN A18 [get_ports uart_txd_out]
set_property PACKAGE_PIN B18 [get_ports uart_rxd_in]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd_out]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd_in]
set_false_path -to   [get_ports uart_txd_out]
set_false_path -from [get_ports uart_rxd_in]

## =============================================================================
## VGA Connector (accent: resistor-DAC → 4-bit per channel)
## =============================================================================
set_property PACKAGE_PIN G19 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

set_property PACKAGE_PIN J17 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

set_property PACKAGE_PIN N18 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

## =============================================================================
## 50 MHz generated clock (100 MHz / 2 via toggle FF + BUFG)
## =============================================================================


## =============================================================================
## Bitstream settings
## =============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
