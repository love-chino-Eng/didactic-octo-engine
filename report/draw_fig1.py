# -*- coding: utf-8 -*-
"""绘制报告用的系统总体框图（图 1）。"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from matplotlib import font_manager as fm

FONT = r"C:/Windows/Fonts/simhei.ttf"
fm.fontManager.addfont(FONT)
CN = fm.FontProperties(fname=FONT).get_name()
plt.rcParams["font.family"] = CN
plt.rcParams["axes.unicode_minus"] = False

fig, ax = plt.subplots(figsize=(10.5, 7.0))
ax.set_xlim(0, 100)
ax.set_ylim(0, 68)
ax.axis("off")


def box(x, y, w, h, title, body="", fc="#FFFFFF", ec="#333333", ls="solid", lw=1.2, ts=11, bs=9.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.5,rounding_size=1.2",
                                linewidth=lw, edgecolor=ec, facecolor=fc, linestyle=ls))
    if body:
        ax.text(x + w / 2, y + h - 2.2, title, ha="center", va="top",
                fontsize=ts, fontweight="bold")
        ax.text(x + w / 2, y + (h - 4.4) / 2, body, ha="center", va="center",
                fontsize=bs, linespacing=1.5)
    else:
        ax.text(x + w / 2, y + h / 2, title, ha="center", va="center",
                fontsize=ts, fontweight="bold")


def arrow(x1, y1, x2, y2, text="", both=False, ls="solid", color="#333333"):
    st = "<|-|>" if both else "-|>"
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=st, mutation_scale=13,
                                 linewidth=1.2, color=color, linestyle=ls))
    if text:
        ax.text((x1 + x2) / 2 + 1.2, (y1 + y2) / 2, text, ha="left", va="center",
                fontsize=9, color="#222222",
                bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none", alpha=0.9))


# ---- 外框：PS / PL ----
ax.add_patch(FancyBboxPatch((2, 12), 46, 48, boxstyle="round,pad=0.8,rounding_size=1.5",
                            linewidth=1.4, edgecolor="#7f8c8d", facecolor="#F7F9FA", linestyle="--"))
ax.text(4, 58.5, "Zynq-7020  PS（ARM Cortex-A9）", fontsize=10.5, color="#555555")
ax.add_patch(FancyBboxPatch((52, 12), 46, 48, boxstyle="round,pad=0.8,rounding_size=1.5",
                            linewidth=1.4, edgecolor="#7f8c8d", facecolor="#F7F9FA", linestyle="--"))
ax.text(54, 58.5, "Zynq-7020  PL（可编程逻辑）", fontsize=10.5, color="#555555")

# ---- PS 内部 ----
box(6, 46, 36, 10, "应用程序 main.c", "预启动 / 随机延时 / 判决 / 计分 / 串口打印", fc="#EAF2FB", bs=9)
box(6, 24, 20, 8, "UART1 控制器", "115200-8-N-1", fc="#FFFFFF", ts=10, bs=8.5)
box(30, 24, 14, 8, "DDR3 / OCM", "程序与数据", fc="#FFFFFF", ts=10, bs=8.5)

# ---- AXI GPIO 桥（横跨 PS 与 PL）----
box(10, 36, 60, 6, "AXI GPIO：0x41200000（CH1 输出 / CH2 输入）  +  0x41210000（timer_value 32bit）",
    "", fc="#EDF7ED", ts=9.5)

# ---- PL 内部 ----
box(56, 46, 38, 10, "reaction_timer 状态机", "start 清零 → 32 位计数 → 锁存 / LED 驱动", fc="#FDF3E7", bs=9)
box(54, 24, 34, 8, "按键消抖 + 边沿检测 / 优先编码", "4×（两级同步 + 20 ms 计数）", fc="#FFFFFF", ts=10, bs=8.5)

# ---- 外部设备 ----
box(4, 2, 26, 7, "PC 串口终端（PuTTY）", "Micro-USB（JTAG/UART 共用）", fc="#F2F2F2", ts=10, bs=8.5)
box(36, 2, 24, 7, "板载按键 BTN0~3", "K18 / P16 / K19 / Y16", fc="#F2F2F2", ts=10, bs=8.5)
box(66, 2, 28, 7, "板载 LED LD0~3", "M14 / M15 / G14 / D18", fc="#F2F2F2", ts=10, bs=8.5)

# ---- 连线 ----
arrow(28, 46, 28, 42.2, "AXI 读写", both=True)
arrow(64, 46, 64, 42.2, "")
arrow(16, 34, 16, 38, "")
arrow(16, 24, 16, 9.2, "")
arrow(60, 9.2, 60, 24, "按键电平")
arrow(92, 44, 92, 9.2, "LED 驱动")

ax.text(50, 66.5, "图 1  反应力测试仪系统总体框图", ha="center", va="center", fontsize=11)
plt.tight_layout()
fig.savefig(r"D:/vivado/reaction_test/report/fig1_block.png", dpi=300, bbox_inches="tight",
            facecolor="white")
print("saved fig1")
