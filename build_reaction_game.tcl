#=============================================================================
#  build_reaction_game.tcl
#  反应力测试仪 (Zybo Z7 / Zynq-7020)  —— Vivado 2019.1 一键构建脚本
#
#  用法：
#    GUI   : Tools -> Run Tcl Script...  选择本文件
#    批处理: vivado -mode batch -source build_reaction_game.tcl -notrace
#
#  流程：建工程 -> 加 RTL -> Block Design(PS7 + 2x AXI GPIO + reaction_timer)
#        -> 连线/地址/中断 -> Wrapper -> 综合 -> 实现 -> 导出 XSA
#
#  目录约定（脚本按自身所在目录推导，可直接放到工程根目录运行）：
#    <root>/rtl/reaction_timer.v          必需
#    <root>/constraints/reaction_game.xdc 可选（无此文件则跳过 bitstream）
#    <root>/reaction_game/                Vivado 工程目录（脚本生成，会被重建）
#    <root>/xsa/reaction_game.xsa         导出结果
#=============================================================================

#----------------------------- 用户可调参数 ----------------------------------
set proj_name    "reaction_game"
set part_name    "xc7z020clg400-1"   ;# 需求指定器件；板卡 preset 可用时会被板卡器件覆盖
set use_board    1                   ;# 1=优先使用 Digilent Zybo Z7-20 board preset
                                     ;#   (DDR/MIO 参数才正确；注意板卡器件为 -2 速级)
                                     ;# 0=纯 part 模式，DDR 走 PS7 默认值(有启动风险)
set do_bitstream 1                   ;# 1=跑到 write_bitstream 并导出含 bit 的 XSA
set jobs         8                   ;# 并行编译线程数
set clean_rebuild 1                  ;# 1=删除旧工程目录重建
#-----------------------------------------------------------------------------

#----------------------------- 路径推导 --------------------------------------
if {[info exists ::argv0] && $::argv0 ne ""} {
    set root [file normalize [file dirname [file normalize $::argv0]]]
} else {
    set root [pwd]
}
# GUI 方式运行 [info script] 更可靠
if {[info script] ne ""} {
    set root [file normalize [file dirname [file normalize [info script]]]]
}
set rtl_file  [file join $root rtl reaction_timer.v]
set xdc_file  [file join $root constraints reaction_game.xdc]
set proj_dir  [file join $root $proj_name]
set xsa_dir   [file join $root xsa]
set xsa_file  [file join $xsa_dir "${proj_name}.xsa"]

if {![file exists $rtl_file]} {
    error "找不到 RTL 源文件: $rtl_file"
}
file mkdir $xsa_dir

puts "\n=============================================================="
puts " reaction_game build  |  root = $root"
puts "==============================================================\n"

#----------------------------- 1. 创建工程 -----------------------------------
if {$clean_rebuild && [file exists $proj_dir]} {
    puts "==> 删除旧工程目录 $proj_dir"
    file delete -force $proj_dir
}
if {[llength [get_projects -quiet]] > 0} {
    close_project -quiet
}

create_project $proj_name $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]

# 板卡 preset（决定 DDR/MIO 是否正确，强烈建议启用）
set ps_preset 0
if {$use_board} {
    set cands [get_board_parts -quiet *zybo-z7-20*]
    if {[llength $cands] > 0} {
        set bpart [lindex $cands end]
        set_property board_part $bpart [current_project]
        set ps_preset 1
        puts "==> 使用 board_part: $bpart  (工程器件: [get_property part [current_project]])"
    } else {
        puts "!!! 警告: 未安装 Digilent Zybo Z7-20 板卡文件, 回退到 part 模式"
        puts "!!!       此时 PS7 的 DDR 参数为通用默认值, 可能无法正常启动"
    }
}

#----------------------------- 2. 添加源文件 ---------------------------------
add_files -norecurse -fileset sources_1 $rtl_file
set_property file_type {Verilog} [get_files [file tail $rtl_file]]
puts "==> 已添加 RTL: $rtl_file"

set has_xdc 0
if {[file exists $xdc_file]} {
    add_files -norecurse -fileset constrs_1 $xdc_file
    set has_xdc 1
    puts "==> 已添加约束: $xdc_file"
} else {
    puts "!!! 警告: 未找到 $xdc_file"
    puts "!!!       综合仍会执行(用于检查 RTL)，但会跳过实现/bitstream"
}

update_compile_order -fileset sources_1

#----------------------------- 3. Block Design ------------------------------
create_bd_design "design_1"

# ---- 3.1 PS7 + Block Automation (DDR / FIXED_IO) ---------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0
set ps_cfg [format {make_external "FIXED_IO, DDR" apply_board_preset "%d" Master "Disable" Slave "Disable"} $ps_preset]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config $ps_cfg \
    [get_bd_cells processing_system7_0]

# ---- 3.2 PS 外设配置 -------------------------------------------------------
#  注意: MIO48/49 在 Zynq 上是 UART1 的固定映射（UART0 是 MIO46/47）。
#        Zybo Z7 的 Micro-USB 串口接的正是 UART1，因此这里使能 UART1。
set_property -dict [list \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_UART1_BAUD_RATE {115200} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
] [get_bd_cells processing_system7_0]
puts "==> PS7: UART1 @ MIO48/49 (115200), FCLK_CLK0 = 100MHz, IRQ_F2P 使能"

# ---- 3.3 AXI GPIO: 控制通道 ------------------------------------------------
#  说明: 一个 AXI GPIO 的单通道只有 32bit，而本设计需要
#        "32bit 计时值 + 状态位" 共 38bit，无法塞进一个双通道 IP，
#        因此拆为 axi_gpio_ctrl(双通道) + axi_gpio_time(32bit 输入)。
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_ctrl
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO_WIDTH {8} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {4} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_ctrl]

#  通道1 (输出, 0x4120_0000, 8bit):
#     bit0   = start      (上升沿清零并开始计时)
#     bit4:1 = stim_led   (激励目标灯, 由 PS 决定点哪颗)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice slice_start
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] \
    [get_bd_cells slice_start]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice slice_stim
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {4} CONFIG.DIN_TO {1}] \
    [get_bd_cells slice_stim]

#  通道2 (输入, 0x4120_0008, 4bit):
#     bit0    = armed
#     bit1    = btn_pressed
#     bit3:2  = btn_index
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat concat_status
set_property -dict [list CONFIG.NUM_PORTS {3}] [get_bd_cells concat_status]
set_property -dict [list CONFIG.IN0_WIDTH {1} CONFIG.IN1_WIDTH {1} CONFIG.IN2_WIDTH {2}] \
    [get_bd_cells concat_status]

# ---- 3.4 AXI GPIO: 计时值通道 ----------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_time
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_time]
#  0x4121_0000, 32bit 只读 = timer_value (单位: clk 周期)

# ---- 3.5 例化 reaction_timer (module reference) ----------------------------
#  注意: module reference 使用模块默认参数 CLK_FREQ_HZ=100MHz / DEBOUNCE_MS=20
#        若把 FCLK_CLK0 改成 125MHz, 需同步改模块参数, 否则计时换算错 25%
create_bd_cell -type module -reference reaction_timer reaction_timer_0

# ---- 3.6 外部端口 ----------------------------------------------------------
create_bd_port -dir I -from 3 -to 0 btn_in
create_bd_port -dir O -from 3 -to 0 led_out

# ---- 3.7 AXI 互联 (自动生成 interconnect / proc_sys_reset) -----------------
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/axi_gpio_ctrl/S_AXI} ddr_seg {Auto} intc_ip {Auto} master_apm {0}} \
    [get_bd_intf_pins axi_gpio_ctrl/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/axi_gpio_time/S_AXI} ddr_seg {Auto} intc_ip {Auto} master_apm {0}} \
    [get_bd_intf_pins axi_gpio_time/S_AXI]

# ---- 3.8 连线 --------------------------------------------------------------
# GPIO 通道1 -> start / stim_led
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o] \
                [get_bd_pins slice_start/Din] [get_bd_pins slice_stim/Din]
connect_bd_net [get_bd_pins slice_start/Dout] [get_bd_pins reaction_timer_0/start]
connect_bd_net [get_bd_pins slice_stim/Dout]  [get_bd_pins reaction_timer_0/stim_led]

# GPIO 通道2 <- 状态
connect_bd_net [get_bd_pins reaction_timer_0/armed]       [get_bd_pins concat_status/In0]
connect_bd_net [get_bd_pins reaction_timer_0/btn_pressed] [get_bd_pins concat_status/In1]
connect_bd_net [get_bd_pins reaction_timer_0/btn_index]   [get_bd_pins concat_status/In2]
connect_bd_net [get_bd_pins concat_status/dout]           [get_bd_pins axi_gpio_ctrl/gpio2_io_i]

# 32bit 计时值 -> axi_gpio_time
connect_bd_net [get_bd_pins reaction_timer_0/timer_value] [get_bd_pins axi_gpio_time/gpio_io_i]

# 按键 / LED
connect_bd_net [get_bd_ports btn_in]  [get_bd_pins reaction_timer_0/btn_in]
connect_bd_net [get_bd_ports led_out] [get_bd_pins reaction_timer_0/led_out]

# 时钟
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins reaction_timer_0/clk]

# 复位：复用 axi4 automation 生成的 proc_sys_reset
set rst_cell [get_bd_cells -quiet -filter {VLNV =~ "*proc_sys_reset*"}]
if {[llength $rst_cell] == 0} {
    error "未找到 proc_sys_reset, 请检查 AXI automation 是否执行成功"
}
connect_bd_net [get_bd_pins $rst_cell/peripheral_aresetn] [get_bd_pins reaction_timer_0/rst_n]

# 中断：用 btn_pressed(电平) 而不是 press_pulse(10ns 脉冲)，
#       避免 PS GIC 采不到；ISR 里写 start=1 即可在 PL 侧清零。
connect_bd_net [get_bd_pins reaction_timer_0/btn_pressed] [get_bd_pins processing_system7_0/IRQ_F2P]

# ---- 3.9 地址分配 ----------------------------------------------------------
assign_bd_address -offset 0x41200000 -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs axi_gpio_ctrl/S_AXI/Reg]
assign_bd_address -offset 0x41210000 -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs axi_gpio_time/S_AXI/Reg]

regenerate_bd_layout
validate_bd_design
save_bd_design
puts "==> Block Design 校验通过"

#----------------------------- 4. Wrapper -----------------------------------
set wrapper_files [make_wrapper -files [get_files design_1.bd] -top]
foreach wf $wrapper_files {
    add_files -norecurse -fileset sources_1 $wf
}
set_property top design_1_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "==> Wrapper: [get_property top [current_fileset]]"

#----------------------------- 5. 综合 --------------------------------------
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "综合失败, 请查看 $proj_dir/$proj_name.runs/synth_1/runme.log"
}
puts "==> 综合完成"

#----------------------------- 6. 实现 + 导出 XSA ---------------------------
if {$do_bitstream && $has_xdc} {
    launch_runs impl_1 -to_step write_bitstream -jobs $jobs
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "实现失败, 请查看 $proj_dir/$proj_name.runs/impl_1/runme.log"
    }
    open_run impl_1
    write_hw_platform -fixed -include_bit -force -file $xsa_file
    puts "==> XSA (含 bitstream): $xsa_file"
} else {
    if {$do_bitstream} {
        puts "!!! 无约束文件, 跳过实现/bitstream, 导出不含 bit 的 XSA"
    }
    open_run synth_1
    write_hw_platform -fixed -force -file $xsa_file
    puts "==> XSA (不含 bitstream): $xsa_file"
}

#----------------------------- 7. 汇总 --------------------------------------
puts "\n=============================================================="
puts " 构建完成"
puts " 工程   : $proj_dir"
puts " XSA    : $xsa_file"
puts ""
puts " PL 寄存器映射 (PS7 M_AXI_GP0 / Data 0x4000_0000 起)"
puts "   axi_gpio_ctrl  0x4120_0000  CH1 输出 8bit"
puts "        \[0\]    start       写1: 清零并使能计时 (下次启动前先写回0)"
puts "        \[4:1\]  stim_led    激励目标灯 LD3..LD0 选择"
puts "   axi_gpio_ctrl  0x4120_0008  CH2 输入 4bit"
puts "        \[0\]    armed       1=正在计时"
puts "        \[1\]    btn_pressed 1=已命中"
puts "        \[3:2\]  btn_index   命中键号 BTN0..BTN3"
puts "   axi_gpio_time  0x4121_0000  输入 32bit  timer_value (clk 周期)"
puts "        time_us = timer_value / 100   (100MHz)"
puts ""
puts " 下一步: 在 Xilinx SDK 2019.1 中 File -> New -> Application Project,"
puts "        使用 $proj_name.xsa 作为硬件平台, 选 Hello World 模板后替换为游戏代码"
puts "==============================================================\n"
