/*============================================================================
 *  反应力测试仪 (Zybo Z7-20 / Zynq-7020)  --  裸寄存器直写版
 *
 *  本版本不使用 BSP 的 init_platform()/xil_printf()/XGpio 驱动/rand(),
 *  全部改为直接读写寄存器, 以规避 BSP 库函数在本环境下触发的异常。
 *  输出为纯 ASCII, 任何终端 (UTF-8 / GBK) 都能正常显示。
 *
 *  寄存器映射 (与 build_reaction_game.tcl 生成的 BD 一致):
 *    UART1         0xE0001000
 *    axi_gpio_ctrl 0x41200000  CH1(输出 0x00) : [0]=start  [4:1]=stim_led
 *                              CH2(输入 0x08) : [0]=armed  [1]=btn_pressed
 *                                               [3:2]=btn_index
 *    axi_gpio_time 0x41210000  [31:0] = timer_value (clk 周期)
 *
 *  PL 时钟 100MHz -> 1us = 100 个计数
 *===========================================================================*/

#include <xil_types.h>
#include <xil_io.h>

/*---------------------------------------------------------------------------
 * 硬件地址
 *-------------------------------------------------------------------------*/
#define UART1_BASE      0xE0001000u
#define UART_CR         0x00u
#define UART_MR         0x04u
#define UART_BAUDGEN    0x18u
#define UART_BAUDDIV    0x1Cu
#define UART_CH_STS     0x2Cu
#define UART_TX_FIFO    0x30u

#define GPIO_CTRL_BASE  0x41200000u
#define GPIO_CTRL_CH1   0x00u      /* 输出 */
#define GPIO_CTRL_CH2   0x08u      /* 输入 */
#define GPIO_TIME_BASE  0x41210000u

#define PL_CLK_MHZ      100u

/* 游戏参数 */
#define ROUNDS          3
#define RAND_MIN_MS     1000u
#define RAND_SPAN_MS    4000u      /* 1000 ~ 5000 ms */
#define PRESS_TIMEOUT   5000u      /* 亮灯后 5 秒未按 = 超时 */

/* 计分 */
#define SCORE_FAST      30
#define SCORE_GOOD      20
#define SCORE_OK        10
#define SCORE_SLOW      5
#define PENALTY_FALSE   (-10)
#define PENALTY_WRONG   (-5)

/*---------------------------------------------------------------------------
 * 关键: 关闭 D-Cache
 *   Zynq 启动代码会打开 MMU + D-Cache, 若外设区 (0xE0001000 / 0x41200000)
 *   被映射成可缓存, 则程序对这些寄存器的写会停留在 cache 里, 永远到不了硬件:
 *   表现为"程序在跑但 UART 一个字节都不发、GPIO 也不动"。
 *   关闭 D-Cache 后所有访问都是强序直写, 立刻生效。
 *-------------------------------------------------------------------------*/
static void disable_dcache(void)
{
    u32 ctl;
    __asm__ volatile ("mrc p15, 0, %0, c1, c0, 0" : "=r"(ctl));
    ctl &= ~(1u << 2);                      /* SCTLR.C = 0 : 关闭 D-Cache */
    __asm__ volatile ("mcr p15, 0, %0, c1, c0, 0" : : "r"(ctl));
    __asm__ volatile ("dsb");
    __asm__ volatile ("isb");
}

/*---------------------------------------------------------------------------
 * UART: 直接配置 115200-8-N-1 (参考时钟 100MHz: baudgen=124, bauddiv=6)
 *-------------------------------------------------------------------------*/
static void uart_init(void)
{
    Xil_Out32(UART1_BASE + UART_CR,      0x00000000u);   /* 关闭收发 */
    Xil_Out32(UART1_BASE + UART_MR,      0x00000020u);   /* 8 位, 无校验, 1 停止位 */
    Xil_Out32(UART1_BASE + UART_BAUDGEN, 124u);
    Xil_Out32(UART1_BASE + UART_BAUDDIV, 6u);
    Xil_Out32(UART1_BASE + UART_CR,      0x00000003u);   /* 复位 TX/RX 通路 */
    Xil_Out32(UART1_BASE + UART_CR,      0x0000010Cu);   /* TXEN|RXEN|RSTTO */
}

static void uart_putc(char c)
{
    u32 guard = 0;
    /* 等 TX FIFO 不满 (channel_sts bit4 = TXFULL) */
    while ((Xil_In32(UART1_BASE + UART_CH_STS) & 0x10u) && (guard++ < 2000000u))
        ;
    Xil_Out32(UART1_BASE + UART_TX_FIFO, (u32)(u8)c);
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

static void uart_putnum(u32 v)
{
    char b[11];
    int  i = 0;
    if (v == 0u) { uart_putc('0'); return; }
    while (v > 0u && i < 10) { b[i++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (i-- > 0) uart_putc(b[i]);
}

static void uart_put3(u32 v)          /* 固定 3 位, 前导补 0 */
{
    uart_putc((char)('0' + (v / 100u) % 10u));
    uart_putc((char)('0' + (v / 10u) % 10u));
    uart_putc((char)('0' + v % 10u));
}

/*---------------------------------------------------------------------------
 * 简单延时 (忙等)
 *-------------------------------------------------------------------------*/
static void delay_ms(u32 ms)
{
    volatile u32 i;
    while (ms--)
        for (i = 0; i < 9000u; i++)
            ;
}

/*---------------------------------------------------------------------------
 * 伪随机数 (32 位 xorshift, 不依赖 stdlib)
 *-------------------------------------------------------------------------*/
static u32 rng_state = 0xACE1u;

static u32 rng_next(void)
{
    u32 x = rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    rng_state = x;
    return x;
}

/*---------------------------------------------------------------------------
 * GPIO 访问
 *-------------------------------------------------------------------------*/
static void ctrl_write(u32 v) { Xil_Out32(GPIO_CTRL_BASE + GPIO_CTRL_CH1, v); }
static u32  ctrl_read(void)   { return Xil_In32(GPIO_CTRL_BASE + GPIO_CTRL_CH2); }
static u32  time_read(void)   { return Xil_In32(GPIO_TIME_BASE); }

#define BIT_ARMED   0x1u
#define BIT_PRESSED 0x2u
#define IDX_SHIFT   2u

/*---------------------------------------------------------------------------
 * 打印工具
 *-------------------------------------------------------------------------*/
static void print_time_ms(u32 cycles)
{
    u32 us = cycles / PL_CLK_MHZ;      /* 100MHz -> us */
    uart_putnum(us / 1000u);
    uart_putc('.');
    uart_put3(us % 1000u);
    uart_puts(" ms");
}

static void print_rules(void)
{
    uart_puts("\r\n\r\n==================================================\r\n");
    uart_puts("   Reaction Timer  (Zybo Z7-20 / Zynq-7020)\r\n");
    uart_puts("   PL counter @ 100 MHz,  UART @ 115200-8-N-1\r\n");
    uart_puts("==================================================\r\n\r\n");
    uart_puts("------------------ HOW TO PLAY -------------------\r\n");
    uart_puts(" Each LED has a matching button, press the SAME one:\r\n\r\n");
    uart_puts("      BTN0 --> LD0          BTN2 --> LD2\r\n");
    uart_puts("      BTN1 --> LD1          BTN3 --> LD3\r\n\r\n");
    uart_puts(" 1) When an LED lights up, press the button with\r\n");
    uart_puts("    the same number as fast as you can.\r\n");
    uart_puts(" 2) Pressing before the LED lights = FALSE START\r\n");
    uart_puts("    (-10 points, this round is void).\r\n");
    uart_puts(" 3) No press within 5 s after the LED = TIMEOUT.\r\n");
    uart_puts(" 4) Wrong button = -5 points.\r\n");
    uart_puts(" 5) 3 rounds, speed score:\r\n");
    uart_puts("      <=200 ms +30   <=300 ms +20\r\n");
    uart_puts("      <=500 ms +10   others   +5\r\n\r\n");
    uart_puts(" Tip: one short press is enough, holding it down\r\n");
    uart_puts("      will not score twice.\r\n");
    uart_puts("--------------------------------------------------\r\n");
}

/*---------------------------------------------------------------------------
 * 主程序
 *-------------------------------------------------------------------------*/
int main(void)
{
    static int   round;
    static int   score;
    static int   hits;
    static int   wrong;
    static int   timeouts;
    static int   falses;
    static u32   sum_us;
    static u32   valid;
    u32   seed;

    disable_dcache();       /* 必须先关 D-Cache, 否则 UART/GPIO 的写不生效 */
    uart_init();

    /* 用延时循环构造种子, 保证每次上电灯序不同 */
    {
        volatile u32 k;
        delay_ms(37u);
        seed = 0x12345u;
        for (k = 0; k < 50000u; k++)
            seed = seed * 1103515245u + 12345u;
        rng_state = seed | 1u;
    }

    print_rules();

    for (round = 5; round >= 1; round--) {
        uart_puts("  start in ");
        uart_putnum((u32)round);
        uart_puts(" s ...\r\n");
        delay_ms(1000u);
    }

    uart_puts("\r\n=== GAME START ===\r\n");

    for (round = 1; round <= ROUNDS; round++) {
        u32 target, wait_ms, elapsed;
        int false_start = 0;

        uart_puts("\r\n--- Round ");
        uart_putnum((u32)round);
        uart_puts(" / ");
        uart_putnum((u32)ROUNDS);
        uart_puts(" ---\r\n");

        /* --- 预启动: 计时器 armed 但灯全灭, 期间按键 = 抢跑 --- */
        ctrl_write(0u);                 /* stim=0 */
        ctrl_write(1u);                 /* start=1 -> 清计数并 armed */
        ctrl_write(0u);

        target  = rng_next() & 0x3u;                        /* 0..3 */
        wait_ms = RAND_MIN_MS + (rng_next() % RAND_SPAN_MS);

        uart_puts("  wait ");
        uart_putnum(wait_ms);
        uart_puts(" ms ...\r\n");

        /* 随机等待期, 同时监视抢跑 */
        elapsed = 0u;
        while (elapsed < wait_ms) {
            delay_ms(10u);
            elapsed += 10u;
            if (ctrl_read() & BIT_PRESSED) { false_start = 1; break; }
        }

        if (false_start) {
            u32 who = (ctrl_read() >> IDX_SHIFT) & 0x3u;
            uart_puts("  [FALSE START] you pressed BTN");
            uart_putnum(who);
            uart_puts(" before the LED!\r\n");
            uart_puts("  score -10, round void\r\n");
            score += PENALTY_FALSE;
            falses++;
            ctrl_write(0u);
            ctrl_write(1u);
            ctrl_write(0u);
            delay_ms(800u);
            continue;
        }

        /* --- 点亮目标灯, 同时 start 上升沿让 PL 从 0 重新计数 --- */
        {
            u32 stim = (1u << target) << 1;          /* 写进 [4:1] */
            ctrl_write(stim);
            ctrl_write(stim | 1u);
            ctrl_write(stim);
        }

        uart_puts("  >>> LED");
        uart_putnum(target);
        uart_puts(" ON  -- press BTN");
        uart_putnum(target);
        uart_puts(" now!\r\n");

        /* --- 等待玩家 --- */
        elapsed = 0u;
        while (!(ctrl_read() & BIT_PRESSED)) {
            delay_ms(1u);
            elapsed++;
            if (elapsed > PRESS_TIMEOUT) break;
        }

        if (!(ctrl_read() & BIT_PRESSED)) {
            uart_puts("  [TIMEOUT] no press within 5 s, round void\r\n");
            timeouts++;
            ctrl_write(0u);
            ctrl_write(1u);
            ctrl_write(0u);
            delay_ms(800u);
            continue;
        }

        /* --- 命中: 读硬件锁存值 --- */
        {
            u32 tv  = time_read();
            u32 idx = (ctrl_read() >> IDX_SHIFT) & 0x3u;

            uart_puts("  hit BTN");
            uart_putnum(idx);
            uart_puts("  (target BTN");
            uart_putnum(target);
            uart_puts(")\r\n  reaction: ");
            print_time_ms(tv);
            uart_puts("\r\n");

            if (idx != target) {
                uart_puts("  [WRONG] -5 points\r\n");
                score += PENALTY_WRONG;
                wrong++;
            } else {
                u32 us = tv / PL_CLK_MHZ;
                sum_us += us;
                valid++;
                hits++;
                if (us <= 200000u)      { score += SCORE_FAST; uart_puts("  [OK] +30\r\n"); }
                else if (us <= 300000u) { score += SCORE_GOOD; uart_puts("  [OK] +20\r\n"); }
                else if (us <= 500000u) { score += SCORE_OK;   uart_puts("  [OK] +10\r\n"); }
                else                    { score += SCORE_SLOW; uart_puts("  [SLOW] +5\r\n"); }
            }
        }

        ctrl_write(0u);
        ctrl_write(1u);
        ctrl_write(0u);
        delay_ms(500u);
    }

    /*------------------------- 统计 -------------------------*/
    uart_puts("\r\n==================================================\r\n");
    uart_puts("                  R E S U L T\r\n");
    uart_puts("--------------------------------------------------\r\n");
    uart_puts("  rounds        : ");
    uart_putnum((u32)ROUNDS);
    uart_puts("\r\n  hits          : ");
    uart_putnum((u32)hits);
    uart_puts("\r\n  wrong button  : ");
    uart_putnum((u32)wrong);
    uart_puts("\r\n  timeout       : ");
    uart_putnum((u32)timeouts);
    uart_puts("\r\n  false start   : ");
    uart_putnum((u32)falses);
    uart_puts("\r\n  total score   : ");
    uart_putnum((u32)(score < 0 ? 0 : score));
    uart_puts("\r\n");

    if (valid > 0u) {
        u32 avg = sum_us / valid;
        uart_puts("  average       : ");
        uart_putnum(avg / 1000u);
        uart_putc('.');
        uart_put3(avg % 1000u);
        uart_puts(" ms\r\n");
    } else {
        uart_puts("  average       : n/a\r\n");
    }
    uart_puts("==================================================\r\n");
    uart_puts(" Press PS-SRST to play again.\r\n\r\n");

    for (;;)
        ;

    return 0;
}
