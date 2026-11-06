connect
catch {bpremove all}
puts "==> BP_CLEARED"
targets -set -nocase -filter {name =~ "APU*"} -index 0
catch {stop}
catch {rst -system}
after 2000
source D:/vivado/reaction_test/sdk_ws/design_1_wrapper_hw_platform_1/ps7_init.tcl
ps7_init
ps7_post_config
puts "==> DDR_OK"
fpga D:/vivado/reaction_test/sdk_ws/design_1_wrapper_hw_platform_1/design_1_wrapper.bit
puts "==> FPGA_OK"
targets -set -nocase -filter {name =~ "ARM*#0"} -index 0
rst -processor
dow D:/vivado/reaction_test/sdk_ws/reaction_app/Debug/reaction_app.elf
puts "==> DOW_OK"
con
puts "==> RUNNING"
exit
