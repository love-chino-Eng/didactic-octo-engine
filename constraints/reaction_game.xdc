#=============================================================================
#  reaction_game.xdc
#  反应力测试仪 —— Zybo Z7-20 (XC7Z020CLG400) 引脚约束
#
#  引脚来源: Digilent 官方 Zybo-Z7-Master.xdc (Rev. B, 兼容 Z7-10 / Z7-20)
#            https://github.com/Digilent/digilent-xdc
#
#  顶层模块: design_1_wrapper  (Block Design 生成的 wrapper)
#  端口来源: Block Design 里创建的两个外部端口 btn_in[3:0] / led_out[3:0]
#  ★ 注意: XDC 中的端口名必须与"综合后的顶层端口名"完全一致,
#          不是 RTL 里的内部信号名, 也不是 BTN0/LD0 这类板卡丝印名。
#=============================================================================

#-----------------------------------------------------------------------------
# 0. 配置 bank 电压 (Zybo Z7 bank 0 = 3.3V, 消除 bitgen 相关 DRC 警告)
#-----------------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#-----------------------------------------------------------------------------
# 1. 系统时钟
#
#    ★ 本工程没有时钟引脚约束的原因:
#      PL 时钟由 PS 的 FCLK_CLK0 提供 (Block Design 内部连线, 100MHz),
#      FCLK 是 PS 内部时钟, 不经过任何 PL 引脚, 因此无需(也无法)约束引脚。
#      Xilinx 会自动从 PS7 IP 推导 create_clock, 无需手写。
#
#    ▼ 下面这段是 Zybo Z7 板上唯一的晶振 (125MHz, 单端, 引脚 K17)。
#      当前设计未使用, 仅作参考保留; 取消注释即可改为外部晶振驱动 PL
#      (注意: 那样 reaction_timer 的 CLK_FREQ_HZ 要改成 125_000_000)。
#-----------------------------------------------------------------------------
#set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { sysclk }]
#create_clock -add -name sys_clk_pin -period 8.000 -waveform {0 4.000} [get_ports { sysclk }]

#-----------------------------------------------------------------------------
# 2. 按键 BTN0 ~ BTN3  (板载, 按下为高电平, 高有效)
#    端口名: btn_in[0] ~ btn_in[3]  <-- 对应 BTN0 ~ BTN3
#-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { btn_in[0] }]; # BTN0  IO_L12N_T1_MRCC_35
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { btn_in[1] }]; # BTN1  IO_L24N_T3_34
set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { btn_in[2] }]; # BTN2  IO_L10P_T1_AD11P_35
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { btn_in[3] }]; # BTN3  IO_L7P_T1_34

#-----------------------------------------------------------------------------
# 3. LED LD0 ~ LD3  (板载, 输出高电平点亮)
#    端口名: led_out[0] ~ led_out[3]  <-- 对应 LD0 ~ LD3
#-----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { led_out[0] }]; # LD0  IO_L23P_T3_35
set_property -dict { PACKAGE_PIN M15   IOSTANDARD LVCMOS33 } [get_ports { led_out[1] }]; # LD1  IO_L23N_T3_35
set_property -dict { PACKAGE_PIN G14   IOSTANDARD LVCMOS33 } [get_ports { led_out[2] }]; # LD2  IO_0_35
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { led_out[3] }]; # LD3  IO_L3N_T0_DQS_AD1N_35

#-----------------------------------------------------------------------------
# 说明: DDR3 与 FIXED_IO (UART/GPIO/SD 等 MIO) 全部是 PS 的专用引脚,
#       由 Zynq 内部硬核直接驱动, 不占用 PL 的 I/O, 因此不需要任何引脚约束。
#       只要 FIXED_IO / DDR 在 Block Design 中已 make_external 即可。
#-----------------------------------------------------------------------------
