# NIC AXI4 总线 EDC 保护设计说明

## 1. 概述

本设计在 NIC 的每一条 AXI4 端口上插入一套 **EDC 生成 + 检查** 保护单元，
**EDC 通过 AXI user 位随事务在 NIC 的 SI 与 MI 之间搬运**：

- 主端口（SI）：请求通道（AW / W / AR）生成 EDC，随 `awuser/aruser/wuser`
  出发；响应通道（B / R）收到后重新计算并与随路 EDC 比对（`buser/ruser`）；
- 从端口（MI）：请求通道收到后比对随路 EDC；响应通道生成 EDC 随
  `buser/ruser` 返回；
- 一端生成、另一端检查，保护范围 = 源端站点寄存级 + NIC 内部通路 +
  目的端站点寄存级；
- 任一 1/2 bit 错误（数据位或校验位）都会检出；
- 支持逐站点、逐比特的**注错**（error injection），用于验证 ESM / 中断通路；
  注错使能为每站点 **4bit 编码**（`1111`=开 / `0000`=关，非法码拒绝写入，
  同 timeout 设计 SCMCNTRL.ENA 思路：任何 1bit 翻转 → 非法码 → 按关处理，
  fail-safe）；
- 错误按 **err / fault 双轨**上报，顶层真轨 OR / 反轨 AND 汇聚为
  `ESM_Err / ESM_Fault`（双轨输出，ESM 侧校验互补性），另有受
  `CFG_IRQEN` 门控的 `IRQ` 输出（单轨，冗余通知级）；
- **寄存器奇偶保护**（参照 hang_prot reg_wrap 设计）：cfg/sta 寄存器全部
  带 even-parity 存储 + 自愈粘滞 + 注错自测 + 在途负载奇偶检查
  （PERR13：mbus→AXI 配置链；PERR14：APB→mbus 命令链，失配拒写），
  逐源 PERR 状态 + `Reg_Par_Fault` 双轨 ESM 输出（独立事件）。

寄存器访问路径为 **APB3 → apb2mbus → mbus(24MHz) → 各 EDC_GEN_CHK 实例**，
每个实例内部自带 24MHz 的 cfg/sta 寄存器组，并完成 mbus(24MHz) ↔ AXI 时钟的跨域。

## 2. 架构

```
                     +-----------------------------------------------+
                     |        顶层 OR 汇聚 (mbus 域, 逐实例)          |
                     |   ESM_Err   <- |{esm_err  _<i>}  (中断级)     |
                     |   ESM_Fault <- |{esm_fault_<i>}  (fatal 级)   |
                     |   IRQ       <- |{irq     _<i>}                |
                     +-----------------------------------------------+
                        ^          ^           ^            ^
                        |          |           |            |
        esm_err / esm_fault / irq（每实例 3 根, mbus 域输出）
                        |          |           |            |
  +---------+    +---------+      +----------------+   +----------------+
  | APB_BUS |<-->| apb2mbus|<====>| EDC_GEN_CHK_<0>|<->| AXI_MST / NIC  |
  +---------+    +---------+      +----------------+   +----------------+
                       ||                ...
                       ||         +----------------+
                       ++========>| EDC_GEN_CHK_<n-1>|<->| AXI_SLV / NIC |
                                  +----------------+
                    Cfg_ctrl : CE / WR / Addr
                    Cfg_payload_i/o : wdata / rdata
                    mbus clock = 24 MHz
```

- `apb2mbus`：APB3 从端 → mbus 主端；mbus 侧时钟固定 24MHz，内部完成
  APB 时钟域 ↔ 24MHz 的请求/应答跨域。
- 每个 `EDC_GEN_CHK_<i>` 跨越一条 AXI4 端口，由参数 `SIDE` 决定角色：
  - `SIDE=0`（SI，主端口）：请求 GEN、响应 CHK；
  - `SIDE=1`（MI，从端口）：请求 CHK、响应 GEN；
  - 内部 **regfile**（24MHz）分 `cfg` 与 `sta` 两组；
  - `edc_gen`（AW/W/AR）与 `edc_chk`（B/R）工作在 AXI 侧时钟域，各自带
    `MODE` 在 GEN/CHK 间切换（`edc_gen .MODE(SIDE)`、`edc_chk .MODE(~SIDE)`）；
  - EDC 向量从/到 `awuser/aruser/wuser/buser/ruser` 切片；
  - regfile 与 gen/chk 之间是 **mbus → AXI** 的 cfg 下发 CDC、
    **AXI → mbus** 的 sta 回读同步。
- mbus 是**广播式**的：`ce / wr / addr / wdata` 同时送到所有实例，
  每个实例用参数 `IDX` 自行译码，未选中时 `rdata` 驱动 0；顶层把所有
  实例的 `rdata` 做**或逻辑**合并成一条 `mbus_rdata` 送回 apb2mbus。
  这样新增/删除实例不需要改动 apb2mbus，是纯分布式结构。
- 每个实例输出 3 根单 bit 信号（mbus 域）：
  - `esm_err`：任一站点 sticky err（含注错）→ 汇聚为顶层 `ESM_Err`（中断级）；
  - `esm_fault`：任一站点 sticky fault（organic）→ 汇聚为顶层 `ESM_Fault`（fatal 级）；
  - `irq = |(err_st & irqen)`：受 `CFG_IRQEN` 门控的实例级中断 → 汇聚为顶层 `IRQ`；
  - 顶层对三根信号各自**逐实例 OR**（mbus 域，与 `mbus_rdata` 的按位 OR
    汇聚在同一处完成，见 §9）。

## 3. 文件列表

| 文件 | 说明 |
| --- | --- |
| `rtl/nuclei300_edc_gen.sv` | Nuclei 原始原语（gen / chk / chk_fault_ej） |
| `rtl/global.v` | 原语 include 用的空占位 |
| `rtl/edc_site.sv` | 单站点保护单元（GEN/CHK 双模 + 1 级寄存 + 带注错的 chk + 转发） |
| `rtl/edc_gen.sv` | AW / W / AR 请求通道（13 站点），MODE 可配，EDC 随 user 位 |
| `rtl/edc_chk.sv` | B / R 响应通道（5 站点），MODE 可配，EDC 随 user 位 |
| `rtl/edc_regfile.sv` | 24MHz mbus 寄存器文件（cfg + sta + RW1C + 命令 toggle），纯 mbus 域 |
| `rtl/edc_reg_wrap.sv` | 寄存器奇偶保护单元（存储 + 偶校验 + 自测注错 + 自愈粘滞） |
| `rtl/edc_core.sv` | 单端口 IP：封装 edc_regfile + CDC + edc_gen + edc_chk + ESM（SIDE 参数） |
| `rtl/apb2mbus.sv` | APB3 → mbus 桥（含 APB ↔ 24MHz 异步握手） |
| `rtl/edc_top.sv` | 集成顶层（NM 个 master 口 + NS 个 slave 口，ESM 汇聚） |
| `doc/edc_regfile.md` | apb2mbus 交互时序图 + edc_regfile 寄存器逐条说明 |
| `doc/sil_analysis.md` | SIL2/SIL3 功能安全覆盖率分析（IEC 61508 route 1H，SFF 估计与差距清单） |
| `sim/tb_edc_top.v` | 集成 testbench（NM=1 / NS=1，4 个异步时钟） |
| `sim/run_sim.ps1` | iverilog 仿真脚本 |
| `sim/run_cov.ps1` | verilator 覆盖率脚本 |

## 4. EDC 编码

原语为缩短汉明码，最小距离 3：

- 可检出任意 1 bit、2 bit 错误（数据或校验位）；
- **不纠错**；
- ≥3 bit 的部分错误组合可能漏检。

校验位宽阶梯（gen / chk / chk_fault_ej 必须一致）：

| DW | EDCW |
| --- | --- |
| ≥ 58 | 7 |
| ≥ 27 | 6 |
| ≥ 12 | 5 |
| ≥ 5 | 4 |
| ≥ 2 | 3 |
| 1 | 1 |

单站点 `DW` 必须 ≤ 64（原语对 >64 只处理低 64 位），因此宽字段拆成多个站点。

注错位映射（每站点寄存器 `CFG_INJ_POS[s]` 为 64 bit，RTL 零扩展到原语的
`einj_pos[127:0]`）：

- bit `i`（`i < DW`）：翻转数据位 i；
- bit `DW+j`（`DW+j < 64`）：翻转校验位 j；
- `einj_force_err[128-DW-PW]`：强制 syndrome 报错（与 INJ_EN 配合使用）。

64 bit 数据站点（W wdata / R rdata）的 `DW+EDCW = 71 > 64`，只支持数据位
注错；该站点的“任意错误”注入用 `CFG_INJ_FORCE` 完成。

## 5. 站点划分

AXI 接口参数：**数据 64 bit、地址 40 bit**。一个 AXI4 端口共 **18 个站点**，
gen 13 个 + chk 5 个，分组与 EDC 向量一致：

```
axi_aweccp = {awaddr_hi_edc, awaddr_lo_edc, awattri0_edc, awattri1_edc, awid_edc}
axi_areccp = {araddr_hi_edc, araddr_lo_edc, arattri0_edc, arattri1_edc, arid_edc}
axi_weccp  = {wdata_edc, wmask_edc, wlast_edc}
axi_reccp  = {rdata_edc, rattri_edc, rid_edc}
axi_beccp  = {battri_edc, bid_edc}
```

| 站点号 | 通道 | 站点内容 | 位宽 DW | EDCW |
| --- | --- | --- | --- | --- |
| 0 | AW awaddr_hi | `awaddr[39:20]` | 20 | 5 |
| 1 | AW awaddr_lo | `awaddr[19:0]` | 20 | 5 |
| 2 | AW awattri0 | `{awlen[7:0], awsize[2:0]}` | 11 | 4 |
| 3 | AW awattri1 | `{awlock, awcache[3:0], awprot[2:0], awburst[1:0]}` | 10 | 4 |
| 4 | AW awid | `awid` | IDW | 3 |
| 5 | W wdata | `wdata` | 64 | 7 |
| 6 | W wmask | `wstrb` | 8 | 4 |
| 7 | W wlast | `wlast` | 1 | 1 |
| 8 | AR araddr_hi | `araddr[39:20]` | 20 | 5 |
| 9 | AR araddr_lo | `araddr[19:0]` | 20 | 5 |
| 10 | AR arattri0 | `{arlen[7:0], arsize[2:0]}` | 11 | 4 |
| 11 | AR arattri1 | `{arlock, arcache[3:0], arprot[2:0], arburst[1:0]}` | 10 | 4 |
| 12 | AR arid | `arid` | IDW | 3 |
| 13 | B battri | `bresp[1:0]` | 2 | 3 |
| 14 | B bid | `bid` | IDW | 3 |
| 15 | R rdata | `rdata` | 64 | 7 |
| 16 | R rattri | `{rresp[1:0], rlast}` | 3 | 3 |
| 17 | R rid | `rid` | IDW | 3 |

EDCW 列按 §4 阶梯计算（IDW=4 时）。chk 的 5 个站点刻意排在全局号高 5 位、
gen 的 13 个排在低 13 位，`site_err_g = {chk_site_err, gen_site_err}` 直接拼接。

`awqos / awregion / arqos / arregion` 不在上图保护范围内，为保持整条通道
固定 +1 拍，用与 `edc_site` 同条件的一级寄存器对齐转发（不参与 EDC）。

### 5.1 EDC 在 AXI user 位上的布局

EDC 向量经 AXI user 位在 SI↔MI 之间搬运（低位在右，与 §5 的拼接顺序一致）：

```
awuser/aruser (AWUW = 18 + EWID, IDW=4 时为 21):
   { awaddr_hi_edc[4:0], awaddr_lo_edc[4:0], awattri0_edc[3:0],
     awattri1_edc[3:0], awid_edc[EWID-1:0] }

wuser (WUW = 12):
   { wdata_edc[6:0], wmask_edc[3:0], wlast_edc[0] }

buser (BUW = 3 + EWID, IDW=4 时为 6):
   { battri_edc[2:0], bid_edc[EWID-1:0] }

ruser (RUW = 10 + EWID, IDW=4 时为 13):
   { rdata_edc[6:0], rattri_edc[2:0], rid_edc[EWID-1:0] }
```

其中 `EWID` 由 `IDW` 按 §4 阶梯得到（IDW=4 时 EWID=3）。GEN 侧把算出的
EDC 写进 user 位，CHK 侧从 user 位取随路 EDC 比对并原样透传。user 位只
在 NIC 内部接口（`mm_*` / `ss_*`）承载 EDC；外部接口的 user 位输入被
GEN 侧忽略。

## 6. 数据通路（edc_site）

每条通道固定 **+1 cycle** 延迟，valid/ready 语义完整保持。单站点引擎
`edc_site` **纯组合、不持有任何寄存器**，用参数 `MODE` 在 GEN/CHK 间切换；
valid/ready 由父级（`edc_gen` / `edc_chk`）按**通道**统一实现：

```
GEN (MODE=0): 父级装载拍 {payload, 新算 EDC} 同沿打入通道级寄存器记录
              o_edc = c_edc (组合算)              o_err 恒 0
CHK (MODE=1): 父级已寄存 {payload, 随路 EDC} -> 重算比对 + 注错
              o_edc = i_edc (透传)                o_err = 原始电平
              父级再门控: o_site_err[i] = o_err & 通道 vld
```

- 每条 AXI 通道只有**一个** valid FF（`aw_vld`/`w_vld`/`ar_vld` 或
  `b_vld`/`r_vld`）；通道内全部切片的 payload+EDC 在同一个寄存器记录里
  **同沿打拍**，不可能出现跨切片错拍；
- 通道级握手保持 1-deep skid 语义：`m_ready = s_ready || !vld`（空时组合
  接收、满时等下游），装载优先于 pop；
- CHK 模式：重算并与随路 EDC 比对，注错只作用在**检查分支的输入镜像**上，
  不修改已寄存 payload，转发数据无损；
- `o_err` 为未门控原始电平，父级仅在通道 `vld=1`（有有效拍驻留）时上报。

站点错误在 AXI 域按**电平**输出；`edc_core` 内部再转成粘滞状态
（站点有错时该拍持续为高，粘滞位置 1）。**只有 CHK 一侧报告错误**——
GEN 侧站点 `o_err` 恒 0，因此同一端口上响应站（13..17）在 SI 报错、
请求站（0..12）在 MI 报错。

> **历史结构与改造原因**：v1 每站点自持 1-deep skid（各自 `vld_q`），同一
> 通道的多个切片共享握手、仅首站点外接 `o_ready`/`o_valid`。正常情形各
> `vld_q` 恒等对齐；但任一 `vld_q` 单点翻转（SEU / 综合后不等价）会让该
> 切片与其他切片错一拍，拼出"各切片 EDC 自洽但跨切片混代"的事务——CHK
> 侧每切片自检自洽、**静默漏检**。v2 改为通道级单一 valid + 纯组合站点
> 引擎，整条通道的控制 FF 只剩一个 vld，从结构上消除该窗口。

## 7. mbus 协议与 apb2mbus

### 7.1 mbus 信号

| 信号 | 方向 | 说明 |
| --- | --- | --- |
| `ce` | M→S | 单拍片选（1 个 mbus 周期），读/写均有效 |
| `wr` | M→S | 1=写，0=读 |
| `addr[15:0]` | M→S | `[15:8]`=实例号，`[7:0]`=寄存器偏移 |
| `wdata[31:0]` | M→S | 写数据 |
| `par` | M→S | 命令负载偶校验 = `^{paddr, pwrite, pwdata}`，与 payload 3FF 同深度同步（在途检查，见 §7.2 与 §8.6 PERR14） |
| `rdata[31:0]` | S→M | 读数据，**与 ce 同拍有效**（组合读出） |

mbus 时钟 = 24MHz。所有实例共享 `ce/wr/addr/wdata`，各自按
`addr[15:8] == IDX` 译码；未选中实例 `rdata` 输出 0，顶层按位 OR 回选。

### 7.2 APB 访问时序（sysm_msync 式 toggle 握手）

CDC 结构与 `sysm_msync` 一致（APB 域 = memi，mbus 域 = memo）：

```
APB 域                                  mbus 域 (24MHz)
------                                  --------------
acc = psel & penable                    req_flag 3FF 同步 (s1/s2/s3)
ce_reg : acc 打拍, rdy 当拍清 0         payload (addr/wdata/wr) 3FF,
req_flag: acc 上升沿翻转 (toggle)           与 flag 链同深度对齐
                                         ce_flag : s2!=s3 的下一拍置 1 (单拍)
ack 4FF 同步 (s1..s4)                   ce 当拍: 采样 rdata, 翻转 ack_flag
rdy = s3 ^ s4  -> pready
rdat 2FF (s1/s2) -> prdata
```

1. APB access 相，`ce_reg` 检出 `acc` 上升沿 → 翻转 `req_flag`；
   payload 不在 APB 侧打拍，直接送 mbus 域 3FF（acc 相内稳定，
   回程 rdy 远晚于 3FF 采样完成）；
2. mbus 域 3FF 同步后，`s2 != s3` 边沿窗口的下一拍 `ce_flag` 置 1，
   此时 flag 链与 payload 链的第 3 级同沿更新，**ce 拍 payload 新鲜**；
3. ce 单拍当拍自完成（mbus 从端零等待）：采样 `rdata` 进 `rdat_cap`、
   翻转 `ack_flag`、`ce_flag` 自动回 0；
4. APB 域 ack 4FF + `s3^s4` 边沿检测得到单拍 `rdy` → `pready`；
   `prdata = rdat_s2`（比 rdy 早 2 拍稳定）；
5. `paddr[15:8] >= NP` 时不发起 mbus 传输，直接 `pready + pslverr`。

**命令在途奇偶**：`par = ^{paddr, pwrite, pwdata}` 在 APB 侧组合生成，
经与 payload 3FF **同深度**的独立链同步（同沿采样 → ce 拍 `par` 与
`addr/wr/wdata` 必为同一代）；每个 `edc_regfile` 在 ce 拍用收到的
`{addr, wr, wdata}` 重组比对，失配 = APB→mbus 同步链/广播通路在途
1 bit 损坏（**错位写/错实例读的来源**），动作 fail-safe：坏命令的写
不落任何寄存器（写使能与 `cmd_t` 翻转被 `par_ok` 门控）、读回 0、
置 PERR14（所有实例都检查，见 §8.6）。

与参考的两处适配（原因见 `apb2mbus.sv` 文件头）：

- 参考的 `memo_ce` 保持到下游 `rdy` 握手（自环约 2 拍）；本设计做成
  **单拍 ce**，否则 `edc_regfile` 同一笔写两次、`cmd_t` 双翻转，慢 AXI
  时钟下两个边沿合并成一个脉冲时 ack 与 cmd_t 永久错位；
- 读数据在 **ce 当拍**采样（参考在 ack toggle 下一拍，依赖下游锁存
  rdat；本设计 `rdata` 只在 ce 拍有效）。

读延迟约 4 个 mbus 周期 + 5 个 APB 周期，软件无需关心具体数值，
只看 `pready`。

## 8. edc_core 内部寄存器与 CDC

寄存器与 CDC 的分工：

- `edc_regfile`（本文件）：24MHz 域，实现下面 8.1 的 cfg/sta 寄存器、
  `sel` 实例译码、读 mux、RW1C 掩码累加、`cmd_t` 命令翻转与 `cmd_pend` 管理；
- `edc_core`：只做 CDC（§8.2~8.4）与 gen/chk 例化。

### 8.1 寄存器映射（每实例 256B，位于 edc_regfile）

| 偏移 | 名称 | 属性 | 说明 |
| --- | --- | --- | --- |
| 0x00/0x04/0x08 | CFG_INJ_EN[2:0] | RW 18×4b | 每站点 4bit 编码使能：`1111`=开/`0000`=关，非法码 nibble 拒绝写入；字 [2]=站点 12..17，[1]=6..11，[0]=0..5 |
| 0x0C | CFG_INJ_FORCE | RW [17:0] | 每站点强制报错 |
| 0x10 + 8·s | CFG_INJ_POS[s] | RW 64b | s=0..17，占 2 个 32b 字（0x10..0x9F） |
| 0xA0 | STA_ERR | RW1C [17:0] | err 轨粘滞（含注错） |
| 0xA4 | STA_FAULT | RW1C [17:0] | fault 轨粘滞（organic） |
| 0xA8 | CFG_IRQEN | RW [17:0] | err 轨中断使能 |
| 0xAC | STA_REGPAR | RW1C/R | 寄存器奇偶状态（§8.6） |
| 0xB0 | CFG_REGST | W (key=0xA) | 寄存器奇偶自测控制（§8.6），读回 0 |
| 0xFC | ID | RO | `32'hEDC0_1000 \| IDX` |

实例号：master 端口 `p` = `p`（0..NM-1），slave 端口 `q` = `NM+q`。
APB 地址 `paddr[15:8]` 选实例，`paddr[7:0]` 选寄存器（18 站点 INJ_POS × 8B
占到 0x9F，状态寄存器 0xA0 起）。

### 8.2 cfg 下发（mbus → AXI）

- cfg 寄存器（INJ_EN / INJ_FORCE / INJ_POS / IRQEN）在 24MHz 域；
- 任一 cfg 写 → 翻转 `cmd_t`（1 bit toggle）；
- AXI 域对 `cmd_t` 做 2FF + 边沿检测得到 `cmd_pulse`；
- **cfg 负载与 toggle 都在 AXI 域做 2FF**（同深度），`cmd_pulse` 当拍
  采样负载，保证拿到的是新值；
- 负载是**绝对量**（全量配置），中间丢一次 toggle 也只落后一拍，
  不会出现部分更新。

### 8.3 RW1C 清除（mbus → AXI）

- 写 `STA_ERR` / `STA_FAULT` 时，把写数据 OR 进 `clr_mask` 并翻转 `cmd_t`；
- AXI 域在 `cmd_pulse` 当拍执行 `sticky <= (sticky & ~clr) | site_err`，
  **置位优先**（同一拍又来新错不会丢）；
- AXI 域执行后翻转 `ack_t`，mbus 域同步到 ack 等于当前 `cmd_t` 时清
  `clr_mask` 与 pending。清动作在 ack 前到达的新写会继续并入 mask，
  不会丢。

### 8.4 sta 回读（AXI → mbus）

- `err_st` / `fault_st` / `irq` 为 AXI 域电平；
- mbus 域 2FF 同步后直接参与读 mux；
- RW1C 写后约 2~3 个 mbus 周期内读回值才反映清除（见 §12）。

### 8.5 双轨语义

```
err_st[s]   : 站点 s 出现 syndrome 错（含注错）       -> esm_err   (中断级)
fault_st[s] : 站点 s 出现 syndrome 错 且 !inj_en[s]  -> esm_fault (fatal 级)
irq         = |(err_st & irqen)
```

注错打开时无法区分注入错与真实错，因此 fault 轨在注错使能（4bit 编码
解码为开）的站点上主动屏蔽（与上一版 timeout 设计的双轨约定保持一致）。
**编码使能的 fail-safe 语义**：`inj_en` 任一 bit 翻转 → nibble 变非法码 →
解码为关 → 注错失效且 fault 轨解除屏蔽（不会永久屏蔽 organic fault），
同时影子寄存器奇偶（PERR7）会捕获该翻转。

在 SI/MI 拆分的架构下，GEN 侧站点 `site_err_g` 恒 0，只有 CHK 侧站点能
置位 `err_st/fault_st`：SI 实例只可能报响应站 13..17，MI 实例只可能报
请求站 0..12。注错也只在 CHK 侧站点生效。

### 8.6 寄存器奇偶保护（FuSa）

参照 hang_prot 的 reg_wrap 设计：**每个数据寄存器是存储 + 偶校验 +
自测注错 + 自愈粘滞的保护单元，检查与被保护的存储同域**。

```
edc_reg_wrap (每寄存器, mbus 域或 AXI 域):
   data_q / par_q 同沿载入  -> 任一单 bit 翻转 => (^data_q != par_q)
   flt_q / flt_q_n 反相副本  -> SEU 清除自愈回 SET (永不无声丢失)
   selftest_key 脉冲         -> 只翻校验位, data_q 永不污染 (自测注错)
```

保护对象与 PERR 编号（STA_REGPAR bit = 4 + 组号，共 15 组，PERR14
即 bit18）：

| PERR | 对象（域） | 说明 |
| --- | --- | --- |
| 0 | CFG_INJ_EN（mbus，18×4b） | 编码使能寄存器 |
| 1/2 | CFG_INJ_FORCE / CFG_IRQEN（mbus） | |
| 3 | CFG_INJ_POS（mbus，18×64b 整组） | |
| 4 | CLR_MASK（mbus） | RW1C 累积掩码 |
| 5/6 | STA_ERR / STA_FAULT 读回镜像（mbus，2FF 的 s2 级） | |
| 7..10 | inj_en_q / inj_force_q / irqen_q / inj_pos_q 影子（AXI） | |
| 11/12 | err_st / fault_st 粘滞（AXI） | |
| 13 | 在途负载奇偶（AXI 域检查，2FF 回读） | 跨域命令负载整体奇偶 |
| 14 | 命令在途奇偶（mbus 域，ce 拍检查；STA_REGPAR **bit18**） | APB→mbus 命令链在途损坏 |

- **命令在途奇偶（PERR14）**：`apb2mbus` 在 APB 侧对
  `{paddr, pwrite, pwdata}` 算 1 bit 偶校验，与 payload 3FF 同深度同步
  输出；每个实例 ce 拍用收到的 `{addr, wr, wdata}` 重组比对。这是
  PERR13（mbus→AXI 配置下发链）在 APB→mbus 命令链上的对应物，防
  「地址在途翻转 → 错位写 / 错实例读」（此前该通路 DC 仅 60–70%，
  属 SIL3 差距残余 #6，见 sil_analysis §4）。要点：
  - **所有实例都检查（不 gate sel）**：公共通路（apb2mbus 链/广播前）
    损坏 → 全实例置位；fanout 后局部损坏 → 仅该实例置位——置位模式
    本身即诊断信息；
  - **失配 fail-safe**：写使能（各 wrapper `wr`、`w1c_wr`、`regst_w`）
    与 `cmd_t` 翻转统一被 `par_ok` 门控，坏命令不落任何寄存器；读时
    `rdata` 驱 0，不交付错地址的数据；

- **在途奇偶（PERR13）**：`par_pay` = 全部跨域命令负载（en/force/irqen/
  pos/clr/par_w1c/par_st）的异或，作为 1bit 与负载同深度 2FF 进 AXI 域，
  `cmd_pulse` 拍与同步后的负载重组异或比对——多 bit 负载在同步链上的
  在途损坏被 1bit 奇偶检出（准静态假设之外的一层防线）；
- PERR14 为 mbus 本域粘滞（自愈双副本，同 PAR_FAULT 锁存风格），
  STA_REGPAR bit18 W1C 当拍清（不经 AXI 命令通道）；REGST 无法注入
  PERR14（源端无注入点），tb 用 force 翻转 apb2mbus 地址同步链 1 bit
  验证（用例 T13）；
- **双轨 ESM**：`esm_err/_n`、`esm_fault/_n`、`reg_par_fault/_n` 三对双轨
  输出（mbus 域）；顶层真轨 OR / 反轨 AND 汇聚，ESM 侧校验互补性，
  输出/汇聚通路自身 stuck-at 可检出。`irq` 为冗余通知级，保持单轨；
- **逐源清除**：STA_REGPAR (0xAC) W1C，mbus 域当拍清 + AXI 域经命令
  下发清（两域同步，不脱同步）；bit0 只清自测锁存；
- **自测**：CFG_REGST (0xB0) 带 key（[3:0]=0xA，防误触发），REG_SELFTEST
  按 REGSEL 注入指定组的校验错（0..6 本域，7..12 经命令在 AXI 域）；
  PAR_SELFTEST 只置锁存，形成"有 fault 无源"的 ESM 服务签名；
- **未保护项（取舍）**：2FF 首级（1 拍瞬态窗口）、irq 镜像（冗余级）、
  cmd_t/ack 等控制位（toggle 协议受 ack 追平约束）。APB 地址/命令链
  原为未保护项，本轮以 PERR14 命令在途奇偶覆盖（残余：偶校验不检
  2bit 共模翻转；`par_ok` 检查点之后的组合译码/写使能逻辑，需双份
  译码比较才能覆盖）。

## 9. 顶层集成（edc_top）

参数：`NM`（master 端口数）、`NS`（slave 端口数）、`IDW`（AXI ID 位宽），
实例总数 `NP = NM + NS`。另有 `EWID/AWUW/WUW/BUW/RUW` 宽度参数，由 `IDW`
按阶梯自动推导。主端口实例 `SIDE=0`（SI），从端口实例 `SIDE=1`（MI）。

端口命名（第一个字母是 IP 的 s/m 侧，第二个字母是端口类型）：

| 前缀 | 含义 |
| --- | --- |
| `sm_axi_*` | master 端口 s 侧（接外部 master） |
| `mm_axi_*` | master 端口 m 侧（接 NIC） |
| `ss_axi_*` | slave 端口 s 侧（接 NIC） |
| `ms_axi_*` | slave 端口 m 侧（接外部 slave） |

时钟：`apb_clk`、`mbus_clk`（24MHz）、`m_clk[NM]`、`s_clk[NS]`，
每端口独立异步。

顶层只做四件事：

1. 例化 `apb2mbus`；
2. generate 展开 `edc_core`，把 `ce / wr / addr / wdata` **广播**给
   所有实例（不再在顶层做实例译码，译码在 `edc_regfile` 内按 `IDX` 完成）；
3. mbus 读回：`mb_rdata = |{ip_rdata[0], ..., ip_rdata[NP-1]}`，未选中实例
   输出 0，因此或逻辑等价于选择器，且新增实例不需要改 apb2mbus；
4. ESM 汇聚：`esm_err / esm_fault / reg_par_fault` 真轨逐位 OR、
   反轨逐位 AND（双轨），`irq` 单轨 OR。ESM 侧校验两轨互补性，
   失配 = 汇聚通路自身故障。

```verilog
// 每个实例: wire sel = ce && (addr[15:8] == IDX[7:0]);
//           assign rdata = sel ? rdata_mux : 32'b0;
always @* begin
   rd_or = 32'b0;
   for (k = 0; k < NP; k = k + 1) rd_or = rd_or | ip_rdata[k*32 +: 32];
end
```

## 10. 验证

### 10.1 激励

`sim/tb_edc_top.v`，NM=1 / NS=1 / IDW=4，四个异步时钟：
APB 20ns、mbus 42ns（≈24MHz）、master AXI 13ns、slave AXI 17ns。

| 用例 | 内容 |
| --- | --- |
| T1 | 两个实例的 ID 读回 |
| T2 | AW 端到端（SI gen → fabric → MI chk → 外部 slave），校验 `mm_awuser` 非 0、字段完整、无误报 |
| T3 | AR 端到端，校验 `mm_aruser` 非 0 |
| T4 | W + B/R 端到端（MI gen → fabric → SI chk），校验 `mm_wuser` 非 0、两实例 ERR 干净 |
| T5 | MI 请求 CHK 站点 5（W wdata）注错：数据不污染、ERR 置位、FAULT 保持 0、IRQ、RW1C |
| T6 | SI 响应 CHK 站点 15（R rdata）强制错（INJ_EN=0）：ERR + FAULT 双轨置位，ESM_Fault |
| T7 | 越界实例号 → `pslverr` |
| T8 | user 位传输检查：翻转 W user 位（wlast_edc）→ MI 站点 7 报错，数据不污染 |
| T9 | 64 轮随机流量 + 随机注错（SI 响应站 13..17、MI 请求站 0..12），端到端字段逐通道比对 |
| T10 | 分布式结构检查：每个 `ce` 广播到全部实例，未选中实例 `sel=0` 且 `rdata=0`，OR 后读回与实例号一致；ESM 双轨互补性监视 |
| T11 | 寄存器奇偶自测：mbus 域 PERR0 注错（双轨 ESM 置位 + 恢复 + W1C）、AXI 域 PERR7 注错（命令下发 + 跨域 W1C）、PAR_SELFTEST 锁存、错误 key 拒绝 |
| T12 | 在途负载奇偶：force 翻转 AXI 同步链 1 bit → PERR13 置位 + 恢复 + W1C |
| T13 | 命令在途奇偶：force 翻转 apb2mbus 地址同步链（写偏移位 → 错址、读实例位 → 错实例）→ PERR14 + 双轨 ESM 置位、坏写被门控（IRQEN/INJ_POS 完好）、坏读回 0、W1C 恢复 |

tb 在 `mm_*`（mport m 侧）与 `ss_*`（sport s 侧）之间例化 `tb_relay_cdc`
（toggle 握手 + 稳定负载）模拟 NIC 内部 fabric，user 位全程随事务搬运，
与真实 NIC 跨时钟 CDC 语义一致。

结果：**全部检查 PASS**（含 T9 的 64×5 条端到端字段比对、T11/T12 的
寄存器奇偶 / 在途奇偶用例、T13 的命令在途奇偶用例）。

### 10.2 波形

`sim/run_sim.ps1`（iverilog）跑完后自动把 VCD 转成 **FST**（`vcd2fst`），
输出在 `sim/obj/tb_edc_top.fst`（约 130KB，VCD 的 1/10），直接用
`gtkwave tb_edc_top.fst` 打开。tb 内波形用 `NO_DUMP` 宏包裹，
覆盖率编译（verilator）加 `+define+NO_DUMP` 关闭波形。

### 10.3 覆盖率（verilator）

```
line      :  97.1% ( 271/ 279)
toggle    :  63.4% (31937/50412)
branch    :  73.1% ( 269/ 368)
expr      :  65.4% (  794/1214)
```

（含 edc_reg_wrap / 编码使能 / 奇偶保护 / 命令在途奇偶 PERR14 后的
数字；`edc_site` 复用为双模
站点，tb 加入 NIC fabric relay 后分支/表达式分母随之变大。）

toggle 覆盖率的缺口主要是 18×64b 注错寄存器阵列（每位翻转需要逐位
写 1）以及各站点 EDC 生成网络的悬空位，属于“枚举型”目标而非功能
风险；line/branch 已覆盖全部数据通路与 CDC 分支（含 GEN/CHK 双模与
fabric relay 的握手分支、奇偶保护与自测分支）。

SIL2/SIL3 视角的覆盖率目标与定向用例缺口（36 站点全集、非法
nibble 全遍历、MBU/亚稳/双轨破坏注入等）见 `doc/sil_analysis.md`
§5。

## 11. 集成约束

1. `edc_core` 每个实例的 AXI 侧时钟由所在端口提供，mbus 侧统一 24MHz；
2. cfg 写只应在业务流量配置阶段（或 APB 空闲时）进行，多 bit 负载的
   准静态假设依赖这一点；
3. `NP ≤ 256`（`addr[15:8]` 限制）；单站点 `DW ≤ 64`（原语限制），
   因此 `IDW ≤ 64`，实际 AXI4 常见 4/8；数据位宽 64、地址位宽 40 固定
   按本版分组；
4. 每通道固定 +1 cycle，不改变 AXI 事务序；`awready` / `wready` /
   `arready` 的回压完全透传；
5. 每个实例 18 个 `edc_site`（每通道各组并行，固定 +1 拍）+ 18×64b 注错
   寄存器阵列，实例数多时注意 APB 访问串行带来的配置时间。
6. EDC 经 AXI user 位传输，NIC 内部通路（`mm_*` ↔ `ss_*`）必须把
   `awuser/aruser/wuser/buser/ruser` 作为事务的一部分完整搬运（不得
   丢弃或改写），否则 CHK 侧必然报 organic fault。
7. ESM 双轨：`ESM_Err/_n`、`ESM_Fault/_n`、`Reg_Par_Fault/_n` 的反轨
   为 AND 汇聚；ESM 侧必须校验互补性（真轨 != ~反轨 即汇聚通路故障），
   不能只接真轨。

## 12. 已知限制

- **多 bit CDC 为准静态**：cfg 负载通过 2FF 跨域，依赖“改配置时 AXI
  侧无并发更新”的前提；若需完全动态，可改为每站点独立握手。
- **RW1C 窗口**：写清与 AXI 域实际清除之间有数个周期，期间读回仍可能
  为 1；且若被清的错误 beat 仍驻留在寄存器中，下一拍会再次置位
  （真实错误本身仍然存在，属预期行为）。
- **注错期间的真实错误**：注错使能（编码开）时 fault 轨被屏蔽，无法区分。
- **64bit 数据站的校验位注错**：wdata / rdata 站点 `DW+EDCW=71 > 64`，
  `CFG_INJ_POS` 只能翻转数据位；需要注入“校验位错/任意错”时用
  `CFG_INJ_FORCE`（该站点整站强制报错）。
- **GEN 侧不报错**：错误只在 CHK 侧站点粘滞；一条被保护的链路，其错误
  只能在对端（检查侧）观察到，本端（生成侧）状态恒 0，属预期行为。
- 原语只检出不纠错，≥3 bit 的特定错误组合可能漏检。
- **寄存器奇偶的共模**：数据位与校验位同拍同翻（2bit）奇偶不检；
  由周期性 REG_SELFTEST / PAR_SELFTEST + 软件读回兜底（检测窗口 =
  自测周期）。
- **同步器亚稳采样**：AXI→mbus 的 PERR 2FF 首拍亚稳可能偶发假 PERR
  （安全方向，W1C 即清）；属 2FF 固有特性。
- **命令奇偶覆盖 pwdata**：PERR14 的校验对象含 `pwdata`，而 APB 协议
  只保证**写**访问相内 PWDATA 稳定；读访问相内 master 若翻转 PWDATA，
  会造成假 PERR14（安全方向失效，W1C 即清）。集成方应保证 PWDATA
  在整个 access 相内稳定（绝大多数 master 为寄存器驱动，天然满足）。
- **PERR14 残余**：偶校验不检 2bit 共模翻转；`par_ok` 检查点之后的
  组合译码/写使能逻辑不在覆盖内（需双份译码比较，见 sil_analysis §4）。

## 13. 本轮调试记录（已修复）

1. **APB 读回取错数据源**：`apb2mbus` 在 APB 域同步的是组合 `rdata`
   （只在 mbus 单拍 ce 时有效），应同步 mbus 域锁存值 `rdata_cap`。
   现象：所有寄存器读回为 0。
2. **cfg 负载与 toggle 同步深度不匹配**：负载原先在源域（24MHz）做
   2FF，toggle 在目的域（AXI，更快）做 2FF，导致 toggle 先到、旧的
   配置被载入。修复：负载与 toggle 都在 AXI 域做 2FF。现象：注错
   使能后不生效、ERR_STAT 不置位。
3. **chk 的 INJ_POS 切片少了 128 bit**（当时为 128b/站点布局）：
   `inj_pos_q[8*128-1:6*128]` 应为 `[9*128-1:6*128]`（3 个站点）。
   现象：站点 8 的注错位错位。本版改为 64b/站点后切片按
   `inj_pos_q[18*64-1:13*64]` 显式对齐。
4. **照搬 sysm_msync 的 ce 电平会双写 regfile**（本轮重写 apb2mbus 时
   分析避免，未实际触发）：参考的 `memo_ce` 保持到下游 rdy 握手、
   rdy 自环下约 2 拍，`edc_regfile` 会对同一地址写两次、`cmd_t` 双翻转；
   AXI 时钟慢于 mbus 时两个边沿在 2FF+边沿检测下可能合并成一个脉冲，
   ack 少翻一次，`ack_sync[1] == cmd_t` 永不相等 → `clr_mask` 卡死、
   之后每条命令都重复携带陈旧清除掩码。对策：ce 做成单拍
   （零等待当拍自完成），见 §7.2。

5. **SI/MI 拆分 + user 位传输**（本轮）：`edc_chguard` 改为双模 `edc_site`
   （`MODE` 0=GEN/1=CHK），`edc_gen/edc_chk` 各带 `MODE`，`edc_core`
   增加 `SIDE`，顶层按端口类型绑定 `SIDE=0/1`；EDC 向量从/到 AXI user 位
   切片，tb 新增 `tb_relay_cdc` 模拟 NIC fabric 跨时钟搬运。原先 tb 直接
   驱动 `mm_*`/`ss_*` 的方式改为外部只驱动 `sm_*`/`ms_*`，中间由 fabric
   串起，从而验证“SI gen → MI chk、MI gen → SI chk”的完整闭环。

6. **寄存器奇偶保护 + 双轨 ESM + 编码使能**（本轮，参照 hang_prot
   reg_wrap）：cfg/sta 镜像与 AXI 影子/sticky 全部换成 edc_reg_wrap
   （存储+偶校验+自愈粘滞+自测注错）；新增 STA_REGPAR (0xAC) / CFG_REGST
   (0xB0，key=0xA)、在途负载奇偶 PERR13；esm_err/esm_fault/
   reg_par_fault 改双轨输出（顶层真轨 OR / 反轨 AND）；注错使能改
   每站点 4bit 编码（1111/0000，非法码 fail-safe 关），INJ_EN 扩为
   0x00/0x04/0x08 三个字，后续寄存器整体 +8 平移。本轮调试中踩的坑：
   ① STA_REGPAR 读回拼接顺序（保留位应放在 PERR 与 fault 对之间）；
   ② tb 自测写值忘编 key（0xA）；③ 期望值没扣除反轨 bit1 的常 1。
   均已修复，T11/T12 全 PASS。

7. **命令在途奇偶 PERR14**（本轮，闭环 SIL3 差距残余 #6 的 APB 地址
   通路）：apb2mbus 增加与 payload 3FF 同深度的 `par` 链（源端组合
   生成 `^{paddr, pwrite, pwdata}`）；每个 edc_regfile ce 拍重组比对，
   失配 → 全部写使能与 cmd_t 翻转被 `par_ok` 门控（fail-safe 拒写）、
   rdata 驱 0、置 PERR14（mbus 本域自愈双副本粘滞，STA_REGPAR bit18
   W1C 当拍清）。要点：PERR 位号公式 4+n 对 n=14 自然落在 bit18，
   既有 PERR0..13 位位置不变，软件兼容；检查不 gate sel（公共通路
   损坏全实例置位、局部损坏单实例置位，置位模式即诊断信息）。
   tb 新增 T13（force apb2mbus 地址同步链 1 bit：写偏移位验证门控、
   读实例位验证错实例读回 0），全 PASS；本轮覆盖率 line 96.7→97.1%。
