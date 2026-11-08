#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cmm_win_calc - CMM 通道表征计算器 (characterization calculator)

输入要监控的 dut 时钟频率, 一条命令给出该通道全部寄存器编程参数:
    PSC 分频档 / 期望计数 E / 检测精度 / WIN_LO / WIN_HI (及实际带宽百分比)
    / NDEAD / 检测延迟 / 带写 key 的寄存器写值

用法:
    python cmm_win_calc.py 200                # dut = 200 MHz, 其余全默认
    python cmm_win_calc.py 1000 --tol 3       # 1 GHz, 收紧到 ±3%
    python cmm_win_calc.py 20 --psc 3         # 强制 PSC (覆盖自动选择)
    python cmm_win_calc.py 48 --ref 25 --nwin 16384

权威公式 (doc/cmm_timing_sw_guide.md §2):
    E         = N_WIN * f_dut / (f_ref * 2^(PSC+1))          期望计数/窗
    PSC 选档  = 最小 PSC 满足两条:
                  (a) 奈奎斯特: f_dut / 2^(PSC+1) <= f_ref/4   (2FF+边沿检测)
                  (b) 饱和保护: E*(1+tol) <= SAT * 2^CNT_W      (计数器/寄存器 12bit)
    WIN_LO/HI = round(E * (1 -+ tol))                         频带下/上界 [counts]
    实际带宽  = (E-LO)/E, (HI-E)/E                            (取整后与名义 tol 的差)
    频点边界  : 名义 f_lo = LO*Δf, f_hi = HI*Δf (Δf=1 LSB); 计入 ±3 LSB 测量误差:
                保证报警 f ≤ (LO-3)Δf 或 f ≥ (HI+3)Δf (差 3 个 count 也一定越界)
                可能误报 f ≤ (LO+3)Δf 或 f ≥ (HI-3)Δf (好频率最多被多算/少算 3 个 count)
    精度      : 1 LSB = f_ref * 2^(PSC+1) / N_WIN             (一个 count 的频率当量)
                总误差 = 3 LSB (非整数 E 抖动 ±1 + CDC ±1 + 窗界丢边 ≤1)
                相对精度 = 3/E
    NDEAD     = ceil(2 * 2^(PSC+1) * f_ref / (f_dut*(1-tol)))  2x 最慢合法边沿间隔

注意:
    * PSC 是**综合期**参数 DUT_PSC[4*i+:4], 运行期寄存器改不了 -- 若算出的
      PSC 与当前例化不符, 必须改 RTL 参数重新综合, 只改 LO/HI 无效。
    * SAT 默认 0.8 (比文档硬约束 2^CNT_W 再留 20% 余量, 复现设计默认
      20 MHz@PSC=3 档); --sat 1.0 退回文档硬约束。
"""
import argparse
import math

WKEY = 0x5  # 写 key, wdata[31:28]


def pick_psc(f_dut, f_ref, n_win, tol, cnt_w, sat):
    """最小 PSC 同时满足奈奎斯特 + 饱和保护; 返回 (psc, why)."""
    psc = max(0, math.ceil(math.log2(4.0 * f_dut / f_ref)) - 1)
    hard = (1 << cnt_w)          # 4096
    guard = sat * hard
    while True:
        e = n_win * f_dut / (f_ref * (1 << (psc + 1)))
        nyq_ok = f_dut / (1 << (psc + 1)) <= f_ref / 4.0
        sat_ok = e * (1 + tol) <= guard
        if nyq_ok and sat_ok:
            return psc, e
        if psc >= 15:
            return psc, e
        psc += 1


def main():
    ap = argparse.ArgumentParser(description="CMM 通道表征计算器")
    ap.add_argument("fdut", type=float, help="被监控 dut 时钟频率 [MHz]")
    ap.add_argument("--ref", type=float, default=24.0, help="参考时钟频率 [MHz] (默认 24)")
    ap.add_argument("--nwin", type=int, default=32768, help="窗口长度 [ref cycles] (默认 32768)")
    ap.add_argument("--tol", type=float, default=5.0, help="频带宽度 ±%% (默认 5)")
    ap.add_argument("--cntw", type=int, default=12, help="计数器位宽 (默认 12, 勿改)")
    ap.add_argument("--sat", type=float, default=0.8, help="饱和保护系数 x 2^CNT_W (默认 0.8)")
    ap.add_argument("--psc", type=int, default=None, help="强制 PSC 档 (0..15, 覆盖自动选择)")
    ap.add_argument("--ch", type=int, default=0, help="通道号 i, 仅影响打印的寄存器地址 (默认 0)")
    ap.add_argument("--ndeb", type=int, default=3, help="FAIL_FREQ debounce [windows] (默认 3)")
    ap.add_argument("--reftol", type=float, default=0.0,
                    help="参考时钟容差 ±%% (默认 0): E 反比于 f_ref, ref 容差 1:1 折算进计数")
    a = ap.parse_args()

    f_dut, f_ref, n_win, tol = a.fdut, a.ref, a.nwin, a.tol / 100.0
    rt = a.reftol / 100.0
    if rt >= 0.5:
        raise SystemExit("--reftol 必须 < 50 (1-rt 会除零/变负)")
    # 饱和检查用合成容差: HI 实际最高到 E*(1+tol)/(1-rt)
    tol_sat = (1 + tol) / (1 - rt) - 1 if rt > 0 else tol

    if a.psc is not None:
        psc = max(0, min(15, a.psc))
    else:
        psc, _ = pick_psc(f_dut, f_ref, n_win, tol_sat, a.cntw, a.sat)
    div = 1 << (psc + 1)
    e = n_win * f_dut / (f_ref * div)

    if rt > 0:
        # 带宽吸收 ref 容差: LO 被 ref 快角(计数偏低)压低, HI 被 ref 慢角抬高
        lo = round(e * (1 - tol) / (1 + rt))
        hi = round(e * (1 + tol) / (1 - rt))
    else:
        lo = round(e * (1 - tol))
        hi = round(e * (1 + tol))
    lo_pct = (e - lo) / e * 100
    hi_pct = (hi - e) / e * 100

    lsb_hz = f_ref * 1e6 * div / n_win          # 1 count 的频率当量
    tot_hz = 3 * lsb_hz                          # 总误差 3 LSB
    prec_pct = 3.0 / e * 100
    f_lo = lo * lsb_hz / 1e6                     # 报警触发的实际频率
    f_hi = hi * lsb_hz / 1e6

    # 最慢合法边沿间隔 [ref cyc]: NDEAD 计的是 ref 拍, 按 ref 快角放大
    interval = div * f_ref * (1 + rt) / (f_dut * (1 - tol))
    ndead = math.ceil(2 * interval)
    win_ms = n_win / (f_ref * 1e6) * 1e3
    dead_us = ndead / (f_ref * 1e6) * 1e6
    lat_ms = a.ndeb * win_ms

    print(f"dut = {f_dut:g} MHz, ref = {f_ref:g} MHz, N_WIN = {n_win}, tol = ±{tol*100:g}%")
    print(f"-" * 62)
    print(f"PSC 档位      : {psc}  (dut/{div:g}, 方波 {f_dut/div:g} MHz"
          f" <= f_ref/4 = {f_ref/4:g} MHz)")
    print(f"  !! PSC 是综合期参数 DUT_PSC[4*{a.ch}+:4], 例化不符须改 RTL 重综合")
    print(f"期望计数 E    : {e:.2f} counts/窗 (窗口 {win_ms:.3f} ms)")
    print(f"检测精度      : 1 LSB = {lsb_hz/1e3:.2f} kHz,  总误差 3 LSB = ±{tot_hz/1e3:.2f} kHz"
          f" (±{prec_pct:.3f}%)")
    print(f"WIN_LO        : {lo:5d}   (E*(1-tol)={e*(1-tol):.2f}, 实际 -{lo_pct:.3f}%)")
    print(f"WIN_HI        : {hi:5d}   (E*(1+tol)={e*(1+tol):.2f}, 实际 +{hi_pct:.3f}%)")
    print(f"频点左右边界 (配置 LO/HI 后的报警触发频率, Δf=1 LSB={lsb_hz/1e3:.2f} kHz):")
    print(f"    名义边界  : f < {f_lo:.4f} MHz  或  f > {f_hi:.4f} MHz   (LO*Δf / HI*Δf)")
    print(f"    保证报警  : f ≤ {(lo-3)*lsb_hz/1e6:.4f} MHz  或  f ≥ {(hi+3)*lsb_hz/1e6:.4f} MHz")
    print(f"    可能误报  : f ≤ {(lo+3)*lsb_hz/1e6:.4f} MHz  或  f ≥ {(hi-3)*lsb_hz/1e6:.4f} MHz")
    print(f"    (±3 LSB=±{tot_hz/1e3:.2f} kHz 测量误差 => 边界各有 ±3Δf 不确定区;"
          f" 且需 N_DEB={a.ndeb} 个连续坏窗)")
    if rt > 0:
        g_lo = (1 - rt) * lo / e
        g_hi = (1 + rt) * hi / e
        print(f"[ref 容差 ±{rt*100:g}%] E 反比于 f_ref (ref 快=>计数少), 带宽已吸收 ref 漂移角:")
        print(f"    不误报     : ref 在容差内漂 + dut 在名义 ±{tol*100:g}% 内 -> 不报警")
        print(f"    ref 标称   : dut 超出 {lo/e*100-100:.1f}% / +{hi/e*100-100:.1f}% 即报警")
        print(f"    保证检测   : dut < {g_lo*100-100:.1f}% 或 > {g_hi*100-100:.1f}%"
              f" (ref 最不利角, 容差叠加两次)")
        print(f"    中间带     : 报不报取决于 ref 实际方向; 全通道同比例偏 = ref 漂移签名 (SW 流程 M1)")
        if rt >= tol:
            print(f"    [注意] ref 容差 >= dut 检测门限: |dut 漂移| 小于约"
                  f" {(rt-tol)*100:.0f}% 在任何 ref 状态下都不可见")
    print(f"NDEAD         : {ndead}  (2x 最慢合法边沿 {interval:.1f} ref cyc;"
          f" DEAD 延迟 {dead_us:.2f} us)")
    print(f"FAIL_FREQ 延迟: ≈ {a.ndeb} 窗 = {lat_ms:.2f} ms (+≤1 窗量化)")
    if prec_pct > tol * 100 * 0.5:
        print(f"[警告] 精度 ±{prec_pct:.2f}% 已超过带宽的一半, 会吃掉裕量:"
              f" 增大 N_WIN 或加宽 tol")
    if hi >= (1 << a.cntw):
        print(f"[错误] WIN_HI {hi} 溢出 {a.cntw} 位计数器 ({(1<<a.cntw)-1}), 加大 PSC 或 tol 减小")
    print(f"-" * 62)
    base = 0x40 + 12 * a.ch
    kv = WKEY << 28
    print(f"寄存器写值 (key=0x{WKEY:X} << 28, 通道 {a.ch}):")
    print(f"    wr 0x{base:02X} (CH{a.ch}_LO)   = 0x{kv|lo:08X}")
    print(f"    wr 0x{base+4:02X} (CH{a.ch}_HI)   = 0x{kv|hi:08X}")
    print(f"    wr 0x{base+8:02X} (CH{a.ch}_DEAD) = 0x{kv|ndead:08X}")
    print(f"    (写前轮询 GSTAT[6]==0; 每通道 ENLO/ENHI nibble = 0xF)")


if __name__ == "__main__":
    main()
