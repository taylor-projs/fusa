# 10.dup_ctrl — DCLS 控制器设计规格

> 版本: v1.0 (2026-11-05) · 状态: RTL 冻结候选, sim T1–T14 验证中
> 上游: `4.fusa_ips[资料]/1.duplication` (dcls_auto.py 生成物)
> 风格: 全仓统一 rtl-coding-style (GRLIB two-process / logic / 例化对齐 / 公共单元单一源)

---

## 1. 背景与动机

`dcls_auto.py` 对功能 RTL 生成 DCLS 顶层(func/shadow 复制 + 延迟对齐 + 比较器),
demo 实测 (`demo/test_dcls.v`, 9/9 PASS) 暴露两个交付缺口:

1. **err 非 sticky**: `err_fusadcls_<mod>` 是比较器 err 的打拍**电平**,
   func/shadow 失配消失后 err 跟着回 0。瞬时失配(如单粒子扰动后自恢复)
   软件可能永远读不到 —— 必须在 err 产生时**捕获并粘滞到寄存器端**,
   由软件 W1C 清除。
2. **FI 无控制**: `dcls_fault_injection[1:0]` 是裸端口, 比较器/报错通路
   的在线自检(注错)无法由软件发起, 也无法禁止 —— 需要**寄存器化 + 双保险门控**
   (4bit 编码使能 + 写 key)。

本设计(`dup_ctrl`)即补这两块: mbus 配置接口 + err 粘滞捕获 + FI 寄存器控制,
作为 DCLS 生成物与 mbus/ESM 之间的控制面。

## 2. 顶层结构

```
                       mbus (APB 桥侧)
      ce/wr/addr/wdata/par ──────────────►│
                                          ▼
   err_fusadcls_*  ──► sync_2dff ──► dup_ctrl_regfile ──► rdata
   (DCLS 功能域)       u_err_sync        (8 寄存器, 5×reg_wrap)
                          │                  │
                          │                  ├── fi_o (准静态) ──► [对端 DCLS 侧
                          │                  │                     sync_2dff 同步]
                          │                  │                     ▼
                          │                  │              dcls_fault_injection
                          │                  ├── esm_err / esm_err_n        (双轨)
                          │                  └── reg_par_fault / _n         (双轨)
                          └── STA_RAW (实时电平读出, 组合)
```

- `dup_ctrl_top` — 集成顶层: `sync_2dff`(err 摄入) + regfile 例化。
  参数 `IDX`(mbus 实例号) / `NUM_ERR`(1..32) / `ERR_SYNC_STAGE`(2|3, 默认 3)。
- `dup_ctrl_regfile` — 全部寄存器语义(见 §3/§5), 纯 mbus 单域。
- 复位: `rstn` 异步低有效直入(与 int_prot_top 同惯例, 片内不再加
  rst_sync —— 复位同步由 mbus 子系统顶层统一负责)。

## 3. 寄存器地图 (mbus, 32bit)

addr[15:8] = IDX(实例号), addr[7:0] = 偏移; `par` = `^{addr,wr,wdata}` 命令在途偶校验。

| 偏移 | 名称 | 属性 | 复位 | 说明 |
|---|---|---|---|---|
| 0x00 | CFG_EN | RW | `0xF` | [3:0] 监测使能, 4bit 编码(1111/0000)。非法码整写拒绝; 1bit 错纠回并**写回**; 2bit 平局默认**开**(fail-visible)。只门控 STA_ERR 新置位, STA_RAW 读出永不受门控 |
| 0x04 | CFG_INJ_EN | RW+key | `0x0` | [3:0] 注错(FI)使能, 4bit 编码, 平局默认**关**(fail-safe)。写需 [7:4]=`4'b1010`, 否则整写忽略 |
| 0x08 | CFG_FI | RW | `0x0` | [1:0] FI 模式(00/01/10)。存储面自由写; **输出** `fi = INJ_EN 开 ? CFG_FI : 00` —— key+编码双保险下模式值本身不再加 key |
| 0x10 | STA_ERR | RW1C | `0x0` | [NUM_ERR-1:0] DCLS err 粘滞。err_sync 电平置位, **置位优先于 W1C**(源在线清不掉, 撤源后可清); W1C 写本身即 wrap 重写(奇偶重算) |
| 0x14 | STA_RAW | RO | `0x0` | [NUM_ERR-1:0] 同步后 err 当前电平(组合读, 区分"正在报"与"报过已粘滞") |
| 0x18 | STA_PAR | RW1C/RO | `0x0` | [0] PAR_FAULT 电平, 写 1 只清自测锁存; [1] PAR_FAULT_N 反轨(RO); [6:2] PERR4..PERR0(W1C 清对应组); [7] 保留读 0 |
| 0x1C | CFG_REGST | W+key | — | [3:0] key=`1010`; [4] REG_SELFTEST 脉冲(对 [11:8] REGSEL 选中的组 0..4 注校验错, >4 忽略); [5] PAR_SELFTEST 脉冲(只置自测锁存 = "有 fault 无源" 签名)。读回 0 |
| 0xFC | ID | RO | `5AFE_2000\|IDX` | 实例识别 |

PERR 组号 ↔ STA_PAR bit = 2+组号: **0** CFG_EN / **1** CFG_INJ_EN / **2** CFG_FI /
**3** STA_ERR / **4** 命令在途奇偶粘滞(cmd wrap, W=1)。

## 4. CDC 策略

本模块自身为 mbus 单时钟域(`clk`); 与 DCLS 功能域的 CDC 分两条通路,
err 方向由本模块内的 `sync_2dff` 收敛, **fi 方向的同步放在对端(DCLS 侧)**:

| 信号 | 方向 | 策略 |
|---|---|---|
| err_i | DCLS 功能域 → mbus 域 | 电平输入, `u_err_sync = sync_2dff`(WIDTH=NUM_ERR, STAGES=ERR_SYNC_STAGE=3)同步。**集成约束**: err 电平在 mbus clk 域须 ≥2 拍可观测宽度 —— DCLS err 为打拍电平, 失配持续期间天然满足; 若功能时钟显著快于 mbus 时钟且失配可能单拍出现, 需源侧展宽(或在 DCLS 生成物 err 后加功能域 sticky, 本模块不代劳) |
| fi_o | mbus 域 → DCLS 功能域 | **准静态**输出, 本模块不做同步(放到对端): 集成者在 DCLS 侧例化 `sync_2dff`(功能时钟, WIDTH=2, 复位 00 fail-safe)同步后接 `dcls_fault_injection` —— fusa_comparator 的 FI 是组合输入, 不同步则翻转沿可能在其下游寄存器亚稳捕获 → 毛刺 err 反被 STA_ERR 粘滞(假报)。FI 为 2bit, 逐位同步不保多 bit 相干: 软件切换模式一律**经 00 中转**(00→01 / 01→00 / 00→10 / 10→00 均单比特翻转无毛刺; 禁止 01↔10 直切); 写后等待对端同步级数+1 个功能时钟再生效 |
| clk / rstn | — | rstn 异步低有效直入, 复位同步由 mbus 子系统顶层负责 |

esm_err / reg_par_fault 为 mbus 域输出, 与 int_prot 同按 ESM 侧约定消费。

## 5. 加固规格

1. **4bit 编码使能**(规则11): CFG_EN/CFG_INJ_EN 均 d=4 码(纠1检2), 最近邻纠 1bit 并
   **写回存储**(功能自愈); 平局方向: 监测=开(fail-visible)/注错=关(fail-safe),
   复位值即默认方向; 注错使能写带 key [7:4]=1010。
2. **寄存器奇偶**(reg_wrap × 5): 每数据寄存器 = 存储+偶校验+selftest_key 注错+
   flt 粘滞(双副本 SEU 自愈, W1C CPU 优先)。注错只翻 parity, 数据不动;
   **治愈 = 重写该寄存器**(parity 重算) —— STA_ERR 的 W1C 写自身就是 wrap 重写,
   但 wdata 全 0 且源离线时 sta_err_wr=0 不产生写, 治愈需源在线置位一次
   (TB T10 组3 覆盖此坑)。
3. **命令在途奇偶**(PERR4): ce 拍重组比对 par, 失配 = APB→mbus 通路在途损坏。
   fail-safe: 坏命令**写不落任何寄存器**(wr_ok 由 par_ok 门控), **读驱 0**
   (不交付错地址数据), 粘滞 PERR4 可 W1C。
4. **ESM 双轨**(规则13): `esm_err/_n`(DCLS 检错 = \|STA_ERR, 电平不可屏蔽)、
   `reg_par_fault/_n`(寄存器/通路奇偶), 互补两轨, ESM 侧做互补校验。
5. **无 Q/Q_n 内部状态副本的理由**(规则12的文档豁免): 本模块无可被扰动检出的
   内部计数器/状态机 —— 粘滞位在 wrap 内已双副本自愈(flt_q/flt_q_n),
   PAR_SELFTEST 锁存自带 q/q_n 反相副本, err 同步链由 sync_2dff 单元提供。
6. **PAR_SELFTEST 锁存**: q/q_n 反相副本逐拍比较, 失配自愈回 SET(正本被 SEU
   清除时重报不丢), W1C 走 STA_PAR bit0。用途: ESM 服务程序自检签名
   ("有 fault 无源" = 锁存通路完好)。

## 6. 与 dcls_auto 生成物的集成约束

| 本模块端口 | 生成物(test_dcls.v)侧 | 约束 |
|---|---|---|
| err_i[NUM_ERR-1:0] | 各 `err_fusadcls_<mod>` 按位拼接 | NUM_ERR = err 通道数; 见 §4 宽度约束 |
| — | DCLS 主比较时钟(`mclk` 类) | 供对端 fi 同步链使用(FI 变更生效需该时钟在跑) |
| — | DCLS 复位(异步低) | 对端 fi 同步链复位 |
| fi_o[1:0] | 对端 `sync_2dff` 同步后接 `dcls_fault_injection[1:0]` | 同步在对端; 模式切换经 00 中转, 见 §4 |
| — | `icg_mode` / scan 类 | 不入寄存器, 集成者接 DFT 信号或 tie 0 |
| — | `<mclk>_dcls_gate` 等 | 生成物内部时钟门控, 本模块不触碰 |

注: dcls_auto 生成物为多时钟 DCLS IP 时, err 通道应按"每比较时钟域一组"聚合
(生成物强制单一主比较时钟, 见 1.duplication 分析); 跨域异步 err 的对齐不在
本模块职责内。

## 7. 验证计划 (tb_dup_ctrl, T1–T14)

| # | 内容 | 关键点 |
|---|---|---|
| T1 | 复位默认值 + ID + 双轨全 0 | EN=F(开)/INJ_EN=0(关)/FI=0 |
| T2 | CFG_EN 编码切换 | 1111→0000→1111 读写回 |
| T3 | 拒写三连 | 非法 nibble / 无 key / key+非法 |
| T4 | err 异步→3 级同步→RAW | negedge+#3 非沿对齐驱动 |
| T5 | **sticky 核心** | 源撤销 RAW 回 0, STA_ERR/esm 保持 |
| T6 | W1C 语义 | 离线清成功; 在线清不掉(置位优先); 撤源后清 |
| T7 | EN 门控 | 关时只反映 RAW 不粘滞; 重开恢复 |
| T8 | FI 三重门 | 关时存储可写读但 fi_o=0; key 开跟随; 复关回 0 且存储不变 (FI 同步在对端, 不在 TB 范围) |
| T9 | ESM 双轨电平 | 全程互补监视(run_check) + 显式电平查 |
| T10 | REGST 逐组 0..4 | 注错→PERR→重写治愈+W1C; REGSEL>4 忽略; 组3 需源在线制造 wrap 写 |
| T11 | PAR_SELFTEST | 锁存→bit0(+反轨 bit1=0)→W1C |
| T12 | 命令在途坏 par | 拒写+读 0+PERR4+W1C |
| T13 | 静默类 | 未映射/错实例/写 ID/写 RAW 均静默 |
| T14 | 复位清除 | err 在线+已粘滞时复位全默认 |

运行: VM rocky-eda `~/work`, `bash sim/run_vcs.sh`(自检 grep TB PASS/FAIL,
SVA/$display 不进退出码)。
