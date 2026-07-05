set BIT [file normalize [file dirname [info script]]]/vivado_build/snake_mayin.bit
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device -update_hw_probes false [current_hw_device]
set_property PROGRAM.FILE $BIT [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAM_DONE: [current_hw_device] <- $BIT"
close_hw_target
disconnect_hw_server
