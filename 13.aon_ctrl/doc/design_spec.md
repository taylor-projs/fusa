# aon_ctrl 设计规格

## 1. 概述

`aon_ctrl` 是 AON (Always-On) 域的 L1/L2 FCHM (Fault Channel Monitor) 错误码
捕获 IP：单 `apb_clk` 时钟域的 APB3 从端寄存器面，**纯捕获状态面**（无配置
寄存器）。

- L1/L2 FCHM 在 `cf_wr` 有效拍把 `err_code` 锁存进各自只读状态寄存器。
- SW 经 APB3 读回捕获错误码；捕获事件置粘滞 `STA_CAP` 供 SW 轮询，W1C 清。
- 每个存储寄存器都是 `reg_wrap` 实例（存储 + 偶校验 + 自带粘滞 flt），奇偶
  故障聚合为 `reg_par_fault/_n` 双轨送 ESM。

## 2. 架构

| 模块 | 说明 |
|---|---|
| `aon_ctrl_top` | 集成顶层（薄壳）：APB3 从端 + FCHM 捕获输入 + ESM 双轨，只例化 regfile |
| `aon_ctrl_regfile` | 寄存器文件：APB3 译码 + 捕获 + 奇偶保护（`reg_wrap`）+ ID |

单时钟域（`apb_clk`），无 CDC、无复位同步器。公共单元 `reg_wrap` 引用
`common_modules/reg_wrap.sv` 单一源（规则 21）。

## 3. 寄存器地图

APB3，`paddr[7:0]`，32bit，零等待（`pready=1`）。

| 偏移 | 名称 | 类型 | 字段 |
|---|---|---|---|
| 0x00 | `L1_ERR_CODE` | RO | `[ECW-1:0]` L1 FCHM 捕获错误码（`cf_wr` 拍锁存） |
| 0x04 | `L2_ERR_CODE` | RO | `[ECW-1:0]` L2 FCHM 捕获错误码 |
| 0x08 | `STA_CAP` | RW1C | `[0]` L1_CAP / `[1]` L2_CAP 捕获粘滞（置位优先） |
| 0x0C | `STA_PAR` | RW1C/R | `[1:0]` PAR_FAULT_N/PAR_FAULT（写 1 只清自测锁存）/ `[4:2]` PERR2..PERR0（W1C，bit=2+组号） |
| 0x10 | `CFG_REGST` | W(带key) | `[3:0]` key=1010 / `[4]` REG_SELFTEST / `[5]` PAR_SELFTEST / `[11:8]` REGSEL（读回 0） |
| 0xFC | `ID` | RO | `32'hA0C0_1000 | IDX` |

## 4. 捕获语义

`cf_wr` 是 FCHM 侧的写使能脉冲：`cf_wr == 1` 的 `apb_clk` 拍，`err_code` 被
锁存进对应 `L*_ERR_CODE` 的 `reg_wrap`，同时置 `STA_CAP` 对应粘滞位。

- `L*_ERR_CODE` 只读（SW 无写路径，仅 FCHM 捕获写）。
- `STA_CAP` 置位优先于 W1C（同拍捕获事件压 W1C 清）。

## 5. 奇偶保护（FuSa）

| PERR 组号 | STA_PAR bit | 寄存器 |
|---|---|---|
| 0 | `[2]` | `L1_ERR_CODE`（`u_l1_err`） |
| 1 | `[3]` | `L2_ERR_CODE`（`u_l2_err`） |
| 2 | `[4]` | `STA_CAP`（`u_cap`） |

`PAR_FAULT = PERR0 | PERR1 | PERR2 | 自测锁存`，作为 `reg_par_fault/_n` 双轨
输出。每个 `reg_wrap` 的 `flt` 是粘滞电平（存储偶校验失配即置位），`STA_PAR`
组位 W1C 清对应 `flt`。`reg_wrap` 自带反相副本（flt_q_n），SEU 清 0 自愈回
SET（规则 11/12 家族标准）。

## 5.1 自测注错（CFG_REGST，规则 25）

`CFG_REGST`（写带 key=1010，读回 0）提供两条注错通路：

- **REG_SELFTEST**（`[4]=1` + `REGSEL` 选组）：对选中组（0=L1 / 1=L2 / 2=STA_CAP）
  的 `reg_wrap` 注入校验错（`selftest_key` 翻奇偶位，数据不破坏）→ 点亮对应
  PERR 组位 → 经 粘滞→`reg_par_fault` 出 ESM，W1C 清。
- **PAR_SELFTEST**（`[5]=1`）：只置自测锁存（Q/Q_n，heal-to-SET），产生
  "有 fault 无源" 签名（`STA_PAR[0]=1` 但无 PERR 组位），`STA_PAR` bit0 W1C 清。

## 6. 复位

`apb_rstn` 异步低有效。单时钟域直接使用，不做同步（规则 26，单域设计无
独立功能域复位需求）。复位后：`L*_ERR_CODE=0`、`STA_CAP=0`、奇偶故障清 0。

## 7. ESM 输出

| 信号 | 域 | 语义 |
|---|---|---|
| `reg_par_fault/_n` | `apb_clk` | 寄存器奇偶错双轨（`|PERR`），ESM 侧逐拍互补校验 |
