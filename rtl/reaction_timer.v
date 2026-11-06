`timescale 1ns / 1ps
`default_nettype none
//=============================================================================
//  Module      : reaction_timer
//  Project     : 反应力测试仪 (Zybo Z7-20 / XC7Z020)
//  Description : PL 端反应计时与按键消抖核心
//                - 4 路按键两级同步 + 20ms 计数消抖
//                - start 上升沿清零并使能计数
//                - 任意按键按下 -> 锁存周期数 / 按键编号 / 按下标志
//                - LED 在等待期显示激励目标, 命中后锁定为按键反馈
//  Clock       : clk = 100MHz (可用 CLK_FREQ_HZ 参数改为 125MHz)
//  Timing      : timer_value 单位 = 1 个 clk 周期 (100MHz -> 10ns)
//                32bit 最大 4.29e9 周期, 约 42.95s 后回绕
//                time_us = timer_value / 100 (100MHz)
//                time_us = timer_value / 125 (125MHz)
//  Reset       : rst_n 低有效, 异步复位
//=============================================================================
module reaction_timer #(
    parameter integer CLK_FREQ_HZ = 100_000_000,  // 系统时钟频率
    parameter integer DEBOUNCE_MS = 20,           // 消抖时间(ms)
    parameter integer DEBOUNCE_EN = 1             // 1=启用片内消抖, 0=按键已外部消抖
)(
    input  wire        clk,
    input  wire        rst_n,

    // 按键输入 (异步, 高有效)
    input  wire [3:0]  btn_in,

    // 启动/清零: 上升沿有效. 建议接到"目标 LED 点亮"的时刻
    input  wire        start,

    // 激励目标灯: 由随机延时模块驱动, 计数期间原样透传到 led_out
    // 若暂不使用, 顶层接 4'b0000 即可 (等待期 LED 全灭)
    input  wire [3:0]  stim_led,

    // LED 输出 (高有效)
    output reg  [3:0]  led_out,

    // 结果寄存器
    output reg  [31:0] timer_value,   // 反应时间, 单位: clk 周期
    output reg  [1:0]  btn_index,     // 命中按键编号 0~3
    output reg         btn_pressed,   // 命中标志, 持续到下个 start

    // 状态输出
    output wire        armed,         // 1 = 正在计时, 0 = 空闲/已命中
    output wire        press_pulse    // 单周期脉冲, 可用于 PS 中断
);

    //------------------------------------------------------------------
    // 参数换算
    //------------------------------------------------------------------
    localparam integer DB_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS; // 100MHz/20ms = 2,000,000
    localparam integer DB_W      = (DB_CYCLES <= 2) ? 1 : $clog2(DB_CYCLES); // 21bit

    //------------------------------------------------------------------
    // 4 路按键: 两级同步器 + 计数消抖
    // 计数到 DB_CYCLES 个周期电平仍与当前稳定值不同, 才更新稳定值
    //------------------------------------------------------------------
    wire [3:0] btn_db;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_debounce
            reg            meta_q;
            reg            sync_q;
            reg [DB_W-1:0] db_cnt;
            reg            stable_q;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    meta_q   <= 1'b0;
                    sync_q   <= 1'b0;
                    db_cnt   <= {DB_W{1'b0}};
                    stable_q <= 1'b0;
                end else begin
                    meta_q <= btn_in[gi];
                    sync_q <= meta_q;

                    if (DEBOUNCE_EN == 0) begin
                        stable_q <= sync_q;
                        db_cnt   <= {DB_W{1'b0}};
                    end else if (sync_q == stable_q) begin
                        db_cnt <= {DB_W{1'b0}};
                    end else if (db_cnt == (DB_CYCLES - 1)) begin
                        stable_q <= sync_q;
                        db_cnt   <= {DB_W{1'b0}};
                    end else begin
                        db_cnt <= db_cnt + 1'b1;
                    end
                end
            end

            assign btn_db[gi] = stable_q;
        end
    endgenerate

    //------------------------------------------------------------------
    // 上升沿检测 (消抖后的按键 -> 按下事件)
    //------------------------------------------------------------------
    reg [3:0] btn_db_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_db_d <= 4'b0000;
        else        btn_db_d <= btn_db;
    end

    wire [3:0] press_vec = btn_db & ~btn_db_d;
    wire       press_any = |press_vec;

    // 多键同时按下时按 BTN0 > BTN1 > BTN2 > BTN3 优先级编码
    reg [1:0] press_idx;

    always @* begin
        casez (press_vec)
            4'b???1: press_idx = 2'd0;
            4'b??10: press_idx = 2'd1;
            4'b?100: press_idx = 2'd2;
            4'b1000: press_idx = 2'd3;
            default: press_idx = 2'd0;
        endcase
    end

    // start 上升沿 -> 单周期 start_pulse (防止 start 长时间为高反复清零)
    reg start_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_d <= 1'b0;
        else        start_d <= start;
    end

    wire start_pulse = start & ~start_d;

    //------------------------------------------------------------------
    // 主状态机: 空闲/FROZEN  <->  计时(armed)
    //------------------------------------------------------------------
    reg        armed_r;
    reg [31:0] cnt_r;
    reg        press_pulse_r;

    assign armed       = armed_r;
    assign press_pulse = press_pulse_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            armed_r       <= 1'b0;
            cnt_r         <= 32'd0;
            timer_value   <= 32'd0;
            btn_index     <= 2'd0;
            btn_pressed   <= 1'b0;
            press_pulse_r <= 1'b0;
            led_out       <= 4'b0000;
        end else begin
            press_pulse_r <= 1'b0;   // 默认单周期

            if (start_pulse) begin
                // 清零并使能计数
                armed_r     <= 1'b1;
                cnt_r       <= 32'd0;
                timer_value <= 32'd0;
                btn_index   <= 2'd0;
                btn_pressed <= 1'b0;
                led_out     <= 4'b0000;
            end else if (armed_r) begin
                cnt_r   <= cnt_r + 32'd1;
                led_out <= stim_led;          // 等待期: 显示目标灯
                if (press_any) begin
                    armed_r       <= 1'b0;    // 停止计数, 冻结 cnt_r
                    timer_value   <= cnt_r;   // 锁存按下瞬间的周期数
                    btn_index     <= press_idx;
                    btn_pressed   <= 1'b1;
                    press_pulse_r <= 1'b1;
                    led_out       <= (4'b0001 << press_idx); // 命中反馈
                end
            end else begin
                // 空闲/已命中: 保持结果, LED 显示命中键或全灭
                led_out <= btn_pressed ? (4'b0001 << btn_index) : 4'b0000;
            end
        end
    end

endmodule

`default_nettype wire
