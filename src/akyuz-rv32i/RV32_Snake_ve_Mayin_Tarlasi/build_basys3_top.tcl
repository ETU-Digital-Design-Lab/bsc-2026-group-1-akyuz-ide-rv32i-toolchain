set ROOT  [file normalize [file dirname [info script]]]
set RTL   $ROOT/rtl
set HEX   $ROOT/tests/snake_mayin.hex
set FONT  $RTL/font8x16.hex
set OUT   $ROOT/vivado_build
file mkdir $OUT

read_verilog [glob $RTL/*.v]
read_xdc $RTL/basys3_soc_cam.xdc

synth_design -top basys3_soc_cam_top -part xc7a35tcpg236-1 \
    -generic IMEM_FILE=$HEX -generic FONT_FILE=$FONT

opt_design
place_design
route_design

report_timing_summary -file $OUT/timing.rpt
report_utilization     -file $OUT/util.rpt

write_bitstream -force $OUT/snake_mayin.bit
puts "BUILD_DONE -> $OUT/snake_mayin.bit"
