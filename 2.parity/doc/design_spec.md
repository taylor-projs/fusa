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
  带 even-parity 存储 + 自愈粘滞 + 注错自测 + 在途奇偶检查
  （PERR13：mbus 侧跨域写锁存通道；PERR14：APB→mbus 命令链，失配拒写），
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
- 每个 `EDC_GEN_CHK_<i>`（即 `edc_core`）旁路挂在一条 AXI4 接口上，
  **单 AXI 接口、不切断业务通路**：五通道 payload/valid/ready 全输入
  tap（零延迟，不驱动总线握手），只有 EDC 随路 user 位的方向随部署
  角色 `SIDE` 变化：
  - `SIDE=0`（NIC 入口 / master 侧）：请求通道（AW/W/AR）**GEN** ——
    本 IP 对 tap 到的 payload 组合重算 EDC，经 `awuser_o/wuser_o/
    aruser_o` **输出**驱动总线 user（与 payload 同拍同沿被下游采样，
    不插拍）；响应通道（B/R）**CHK**（`buser/ruser` 输入比对）；
  - `SIDE=1`（NIC 出口 / slave 侧）：请求通道 **CHK**；响应通道
    **GEN**（`buser_o/ruser_o` 输出驱动总线 user）；
  - `SIDE=2`（观测，默认）：全通道 CHK，`user_o` 恒 0（纯挂线监控）。
  - 进 NIC 前 `SIDE=0`、NIC 后 `SIDE=1`：req 在入口生成、出口检查，
    rsp 在出口生成、入口检查，req/rsp 全部在途路径都受保护；同一 IP
    两种配置即可覆盖 NIC 前后两个接口；
  - GEN 方向注错**只翻 EDC 位**（永不破坏 payload），本地不置位，
    由链路对端 CHK 检出上报（对端表现为 err+fault，organic）；
  - 内部 **regfile**（24MHz）分 `cfg` 与 `sta` 两组；
  - GEN 引擎（`edc_site` MODE=0 组合级）与 CHK 引擎（`edc_chk_req` /
    `edc_chk_rsp` tap 检查器）工作在 AXI 侧时钟域，按 `SIDE` 经
    generate 装配（每 SIDE 下 18 站点 cfg 均有消费者，寄存器面不变）；
  - EDC 向量从/到 `awuser/aruser/wuser/buser/ruser` 切片；
  - regfile 与引擎之间是 **mbus → AXI** 的 cfg 下发 CDC（ia 式
    锁存 + req_t/req_edge 一次一条握手，见 §8.2）、**AXI → mbus**
    的 sta 回读 2FF 同步。
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
| `rtl/edc_site.sv` | 单站点保护单元（纯组合 GEN/CHK 双模 + 带注错；GEN 注错只翻 EDC 位） |
| `rtl/edc_gen.sv` | AW / W / AR 请求通道内联引擎（13 站点，+1 拍，TB 参考端点用库） |
| `rtl/edc_chk_req.sv` | AW / W / AR 请求通道 tap 检查器（13 站点，零延迟挂线） |
| `rtl/edc_chk_rsp.sv` | B / R 响应通道 tap 检查器（5 站点，零延迟挂线） |
| `rtl/edc_regfile.sv` | 24MHz mbus 寄存器文件（cfg + sta + RW1C + 命令 toggle），纯 mbus 域 |
|`$ROOT/../common_modules/reg_wrap.sv` | 寄存器奇偶保护单元（存储 + 偶校验 + 自测注错 + 自愈粘滞） |
| `rtl/edc_core.sv` | 单 AXI 接口旁路 IP：edc_regfile + CDC + GEN/CHK 引擎按 SIDE 装配 + ESM（SIDE 参数：0=NIC 入口 1=NIC 出口 2=观测） |
| `$ROOT/../6.apb2mbus/rtl/apb2mbus.sv` | APB3 → mbus 桥（含 APB ↔ 24MHz 异步握手，统一引用 6.apb2mbus） |
| `rtl/edc_top.sv` | fault 聚合器（独立 mbus 叶端：per-core sticky/RAW + 输入轨互补校验 + ESM 双轨） |
| `doc/edc_regfile.md` | apb2mbus 交互时序图 + edc_regfile 寄存器逐条说明 |
| `doc/sil_analysis.md` | SIL2/SIL3 功能安全覆盖率分析（IEC 61508 route 1H，SFF 估计与差距清单） |
| `sim/tb_edc_top.v` | 观测模式集成 testbench（SIDE=2 双核 + 聚合器，含 apb2mbus 桥） |
| `sim/tb_edc_side.v` | 部署角色 testbench（u_ms SIDE=0 + u_sl SIDE=1 背靠背 + 聚合器，S1~S12） |
| `sim/run_vcs.sh` | VCS 双 TB 编译仿真 + 自检 + 合并覆盖率（top/side/verdi/cov） |
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
不落任何寄存器（各 wrapper 写使能与 `req_t` 翻转/锁存装载被 `par_ok`
门控）、读回 0、置 PERR14（所有实例都检查，见 §8.6）。

与参考的两处适配（原因见 `apb2mbus.sv` 文件头）：

- 参考的 `memo_ce` 保持到下游 `rdy` 握手（自环约 2 拍）；本设计做成
  **单拍 ce**，否则 `edc_regfile` 同一笔写两次、`req_t` 双翻转，慢
  mod 时钟下两个边沿经 2FF+边沿检测合并成一个 `req_edge` 时 ack 与
  req_t 永久错位（`cdc_busy` 卡死、后续跨域写全部忙丢）；
- 读数据在 **ce 当拍**采样（参考在 ack toggle 下一拍，依赖下游锁存
  rdat；本设计 `rdata` 只在 ce 拍有效）。

读延迟约 4 个 mbus 周期 + 5 个 APB 周期，软件无需关心具体数值，
只看 `pready`。

## 8. edc_core 内部寄存器与 CDC

寄存器与 CDC 的分工（2026-11-08 双域钦定）：

- `edc_regfile`：**双时钟域模块**（mbus 24MHz + mod_clk=axi_clk），
  全部 CDC 收编在内——8.1 的 cfg/sta 寄存器、`sel` 实例译码、读 mux、
  跨域写锁存 `{wsel_q, wdata_q}` 与 `req_t` 握手管理（mbus 域），
  以及 req 边沿检测/影子装载/sticky 置位清除/ack 回转（mod 域）；
  结构与 `ia_bus_timeo_regfile` 相同（一次一条 toggle 握手，
  2026-11-08 二次钦定）；
- `edc_core`：只例化 regfile 与 gen/chk 站点引擎（引擎随 `axi_rstn`
  复位；regfile mod 域不复位于 axi_rstn，见 §8.7）。

### 8.1 寄存器映射（每实例 256B，位于 edc_regfile）

| 偏移 | 名称 | 属性 | 说明 |
| --- | --- | --- | --- |
| 0x00/0x04/0x08 | CFG_INJ_EN[2:0] | RW 18×4b | 每站点 4bit 编码使能：`1111`=开/`0000`=关，非法码 nibble 拒绝写入；字 [2]=站点 12..17，[1]=6..11，[0]=0..5 |
| 0x0C | CFG_INJ_FORCE | RW [17:0] | 每站点强制报错 |
| 0x10 + 8·s | CFG_INJ_POS[s] | RW 64b | s=0..17，占 2 个 32b 字（0x10..0x9F），mbus 本地写（不占握手） |
| 0xA0 | STA_ERR | RW1C [17:0] | err 轨粘滞（含注错） |
| 0xA4 | STA_FAULT | RW1C [17:0] | fault 轨粘滞（organic） |
| 0xA8 | CFG_IRQEN | RW [17:0] | err 轨中断使能 |
| 0xAC | STA_PAR | RW1C/R | 寄存器奇偶状态（§8.7） |
| 0xB0 | CFG_REGST | W (key=0xA) | 寄存器奇偶自测控制（§8.7），读回 0 |
| 0xB4 | STA_MISC | R/W1C | [0] CFG_BUSY (RO)：握手在途（`req_t != ack_s2`）；[1] WR_DROPPED (W1C)：忙时到达的跨域写被丢（显性化，见 §8.2） |
| 0xFC | ID | RO | `32'hEDC0_1000 \| IDX` |

EN/FORCE/IRQEN 的 mbus 读回 = **mod 域影子的同步镜像**（单一事实源
在 mod 影子）：被丢弃的写哪里都不生效，读回显示旧值（可观察）。

实例号：master 端口 `p` = `p`（0..NM-1），slave 端口 `q` = `NM+q`。
APB 地址 `paddr[15:8]` 选实例，`paddr[7:0]` 选寄存器（18 站点 INJ_POS × 8B
占到 0x9F，状态寄存器 0xA0 起）。

### 8.2 cfg 下发（mbus → mod，ia 式一次一条 toggle 握手）

跨域命令（INJ_EN / INJ_FORCE / IRQEN 写、STA_ERR/STA_FAULT/STA_PAR
的 W1C、CFG_REGST 注错）共用一条握手通道：

```
mbus 域 (24MHz)                         mod_clk 域 (= axi_clk)
------------                         --------------------
跨域写: 锁存 {wsel_q, wdata_q}        sync_2dff 同步 req_t (s1/s2)
        翻转 req_t                    sync_dff 延迟拍 d = s2 打一拍
在途期间锁存值保持稳定                  req_edge = s2 ^ d (边沿检出)
                                      req_edge 拍: 用锁存值译码——
                                        cfg 影子载入 / sticky W1C 掩码
                                        / PERR W1C / REGST 注错
                                      然后翻转 ack_t
sync_2dff 同步 ack_t -> ack_s2
cdc_busy = (req_t != ack_s2)
```

- **多位数据靠稳定传输**：写命令只翻转 `req_t` 一个 bit，负载是 mbus
  侧锁存值（在途期间保持稳定），mod 域在 `req_edge` 拍采样锁存值译码
  ——不需要与负载同深度的并行 2FF 链（改版前 en/force/irqen 负载
  同步 + pos 影子合计 1152b 级同步面积全部撤销）；
- **mbus 叶端零等待不能反压** → `cdc_busy` 期间到达的写被**丢弃**，
  置粘滞 WR_DROPPED（0xB4[1]，W1C）——丢写显性化，不无声吞掉；
  SW 契约：相邻跨域写之间轮询 0xB4[0] CFG_BUSY，或按握手往返
  （约 3 mod + 2 mbus 拍）间隔写；
- **负载是绝对量**（全量配置），一次握手一条命令，按 wsel 完整译码，
  不存在部分更新；
- 在途锁存 `{wsel_q, wdata_q}` 的偶校验在 mbus 域检查（PERR13，
  锁存通道在途损坏检出，见 §8.7）；
- **INJ_POS 不占握手**（准静态直出，设计取舍）：pos 是位置数据，
  软件协议先写 pos 后开 en，en 的握手装载沿即门控沿（开启前 pos 早已
  稳定）；pos 写为 mbus 本地操作（不会忙丢），省掉 mod 域影子，
  存储本身仍有 mbus 域 reg_wrap 保护（PERR3）。

### 8.3 RW1C 清除（mbus → mod）

- W1C（STA_ERR / STA_FAULT / mod 域 PERR 组）与 cfg 写走**同一条
  握手**：写数据锁存进 `wdata_q`，`req_edge` 拍执行
  `sticky <= (sticky & ~wdata_q) | site_err`——**一次性掩码**，
  **置位优先**（同一拍又来新错不会丢）；
- 改版前 `clr_mask` 累加 + ack 窗口合并机制已撤销（PERR4 组随之
  退役）：ack 未追平时的新 W1C 会被忙丢并置 WR_DROPPED，由 SW
  契约（轮询 CFG_BUSY）保证不发生。

### 8.4 sta 回读（mod → mbus）

- `err_st` / `fault_st` / `irq` 为 mod 域电平，mbus 域 2FF 同步
  （sticky 位逐位独立）后直接参与读 mux；
- RW1C 经握手执行（req_edge 拍清除 + ack 回转），写后约
  3 mod + 2 mbus 拍内读回值才反映清除（SW 契约同 §8.2：写 W1C
  前轮询 CFG_BUSY）。

### 8.5 复位语义（FuSa 关键）

- **mbus 域**寄存器复位于 `mbus_rstn`；
- **mod 域**寄存器（同步链/影子/sticky）一律复位于
  `rst_sync(mbus_rstn → mod_clk)`（异步断言/同步释放），**不接
  axi_rstn**；mbus_rstn 复位时 req_t/ack_t 同归零，握手天然对齐；
- 因此 **AXI（被监视域）单独复位时**：站点引擎随 `axi_rstn` 复位
  （监视器重新对齐），但 err/fault sticky 与 cfg 影子**全部保留**——
  故障已记录不能丢，CPU 读回照旧，W1C 后才干净；
- **mbus_rstn 复位**时 regfile 两域全清（mod 域经同步复位，无亚稳
  窗口）。用例：tb_edc_side S12。

### 8.6 双轨语义

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

### 8.7 寄存器奇偶保护（FuSa）

参照 hang_prot 的 reg_wrap 设计：**每个数据寄存器是存储 + 偶校验 +
自测注错 + 自愈粘滞的保护单元，检查与被保护的存储同域**。

```
reg_wrap (每寄存器, mbus 域或 AXI 域):
   data_q / par_q 同沿载入  -> 任一单 bit 翻转 => (^data_q != par_q)
   flt_q / flt_q_n 反相副本  -> SEU 清除自愈回 SET (永不无声丢失)
   selftest_key 脉冲         -> 只翻校验位, data_q 永不污染 (自测注错)
```

保护对象与 PERR 编号（STA_PAR bit = 2 + 组号，共 15 组，PERR14
即 bit16）：

| PERR | 对象（域） | 说明 |
| --- | --- | --- |
| 0 | CFG_INJ_EN 图像（mbus，18×4b） | 编码使能；单一事实源在 mod 影子，mbus 侧为同步镜像 |
| 1/2 | CFG_INJ_FORCE / CFG_IRQEN 图像（mbus） | 同上（mod 影子镜像） |
| 3 | CFG_INJ_POS（mbus，18×64b 整组） | mbus 本体（准静态，不跨域握手） |
| 4 | （退役）原 CLR_MASK | W1C 改锁存 + req_edge 一次性掩码后无 mbus 域累加寄存器；组号保留不重排（bit6 恒 0，REGSEL=4 无注错目标） |
| 5/6 | STA_ERR / STA_FAULT 读回镜像（mbus，2FF 的 s2 级） | |
| 7/8/9 | inj_en_q / inj_force_q / irqen_q 影子（mod） | |
| 10 | （退役）原 inj_pos_q 影子 | pos 改准静态直出后无 mod 域影子；组号保留不重排，STA_PAR bit12 恒 0，REGSEL=10 无注错目标 |
| 11/12 | err_st / fault_st 粘滞（mod） | |
| 13 | 在途写锁存奇偶（mbus 域锁存通道，mbus 侧检查） | `{wsel_q, wdata_q}` 整体偶校验——稳定传输期间锁存值损坏检出 |
| 14 | 命令在途奇偶（mbus 域，ce 拍检查；STA_PAR **bit16**） | APB→mbus 命令链在途损坏 |

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
    与 `req_t` 翻转/锁存装载统一被 `par_ok` 门控，坏命令不落任何
    寄存器；读时 `rdata` 驱 0，不交付错地址的数据；

- **在途写锁存奇偶（PERR13）**：`par_pay` = 在途锁存
  `{wsel_q, wdata_q}` 的整体异或，随锁存同拍更新、mbus 域本地比对
  ——稳定传输协议依赖「在途期间锁存值不变」，该窗口内的寄存器位
  翻转（SEU/译码毛刺锁进错误值）被 1bit 偶校验检出，mod 域拿到的
  一定是通过校验的那一代数据（准静态假设之外的一层防线）；
- PERR14 为 mbus 本域粘滞（自愈双副本，同 PAR_FAULT 锁存风格），
  STA_PAR bit16 W1C 当拍清（不经 AXI 命令通道）；REGST 无法注入
  PERR14（源端无注入点），tb 用 force 翻转 apb2mbus 地址同步链 1 bit
  验证（用例 T13）；
- **双轨 ESM**：`esm_err/_n`、`esm_fault/_n`、`reg_par_fault/_n` 三对双轨
  输出（mbus 域）；顶层真轨 OR / 反轨 AND 汇聚，ESM 侧校验互补性，
  输出/汇聚通路自身 stuck-at 可检出。`irq` 为冗余通知级，保持单轨；
- **逐源清除**：STA_PAR (0xAC) W1C，mbus 域组（0..6/13/14）当拍清 +
  mod 域组（7/8/9/11/12）经握手 req_edge 译码清（一个 SW 写，两域
  同步清除，不脱同步）；bit0 只清自测锁存；
- **自测**：CFG_REGST (0xB0) 带 key（[3:0]=0xA，防误触发），REG_SELFTEST
  按 REGSEL 注入指定组的校验错（0..3/5/6 本域，7..9/11/12 经握手在
  mod 域注入，4/10 退役无目标/13 无注入点）；
  PAR_SELFTEST 只置锁存，形成"有 fault 无源"的 ESM 服务签名；
- **未保护项（取舍）**：2FF 首级（1 拍瞬态窗口）、irq 镜像（冗余级）、
  req_t/ack_t 等控制位（toggle 协议受 ack 追平约束，忙丢经
  WR_DROPPED 显性化兜底）、**INJ_POS 跨域通路**（准静态 + 软件先
  pos 后 en 协议 + en 装载沿门控，存储侧有 PERR3 保护）。APB 地址/命令链
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

### 9.1 两级拓扑与 fault 聚合器 edc_top（当前集成形态）

`edc_top` 现为**独立 mbus 叶端 IP**（fault 聚合器），与各 `edc_core`
叶端并列挂在 mbus 星型上；每条 NIC AXI 端口对应一个 `edc_core`（IDX
= 实例号），聚合器参数 `NUM_CORE` = core 数量（1..32）。各 core 的
`esm_err / esm_fault / reg_par_fault` **双轨**接到聚合器
`core_err_i/_n / core_fault_i/_n / core_par_i/_n`，聚合器提供：

- **per-core sticky**：STA_ERR / STA_FAULT（站点级故障，置位优先于
  W1C，源在线清不掉，撤源后可清）；
- **per-core 寄存器奇偶 sticky**：STA_PARCORE 独立通道，不与站点
  故障混排（不同失效模式分开查询），并折入聚合 `reg_par_fault` ——
  聚合器是完整汇总点，ESM 可只接聚合器；core 侧明细（PERR0..14
  逐源归组）仍进各 core 寄存器面查询；
- **输入轨互补校验**：每 core 三对轨逐拍查真/反轨同值违例（真轨须
  恒等于 ~反轨），STA_RAIL per-core 粘滞 + STA_RAWRAIL 实时电平 +
  `rail_fault/_n` 双轨上报；真值捕获仍用真轨，违例只上报不改写
  （同 ESM 接收侧行为）。

| 偏移 | 寄存器 | 属性 | 说明 |
| --- | --- | --- | --- |
| 0x00 | STA_ERR | RW1C | [N-1:0] 各 core sticky err（含注错归因） |
| 0x04 | STA_FAULT | RW1C | [N-1:0] 各 core sticky fault（organic） |
| 0x08 | STA_RAWERR | RO | [N-1:0] 各 core err 实时电平 |
| 0x0C | STA_RAWFLT | RO | [N-1:0] 各 core fault 实时电平 |
| 0x10 | STA_PARCORE | RW1C | [N-1:0] 各 core reg_par_fault sticky（置位优先，先撤 core 源再清） |
| 0x14 | STA_RAWPAR | RO | [N-1:0] 各 core reg_par_fault 实时电平 |
| 0x18 | STA_PAR | RW1C/R | 家族标准布局：[0] PAR_FAULT（= PERR0..4 源或 + 自测锁存 + 各 core 奇偶 sticky 或）；[1] PAR_FAULT_N 反轨；[6:2] PERR0..PERR4 W1C（0=STA_ERR 1=STA_FAULT 2=命令在途 3=STA_PARCORE 4=STA_RAIL） |
| 0x1C | CFG_REGST | W(key) | key=4'b1010；[4] REG_SELFTEST 对 [11:8] REGSEL（0..4，>4 忽略）注错；[5] PAR_SELFTEST |
| 0x20 | STA_RAIL | RW1C | [N-1:0] 输入轨互补违例 sticky（置位优先） |
| 0x24 | STA_RAWRAIL | RO | [N-1:0] 违例实时电平 |
| 0xFC | ID | RO | 32'hEDC0_2000 \| IDX |

ESM 输出四对双轨：`esm_err / esm_fault / reg_par_fault / rail_fault`
（各带反轨，聚合 sticky；ESM 侧校验互补性，失配 = 报告通路自身
故障）。各 core 自带 ESM 双轨仍可直出（集成可选，独立冗余通道）。
时钟域：单 mbus 域 —— core 双轨是各 core regfile（mbus_clk 域）的
寄存器输出，mbus 树同源同时钟，同域直采粘滞，无需同步器。

## 10. 验证

### 10.1 观测模式（tb_edc_top）

`sim/tb_edc_top.v`：apb2mbus 桥 + 双 edc_core（均 `SIDE=2` 观测）+
edc_top 聚合器，四个异步时钟：APB 20ns、mbus 42ns（≈24MHz）、
master AXI 13ns、slave AXI 17ns。

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
| T11 | 寄存器奇偶自测：mbus 域 PERR0 注错（双轨 ESM 置位 + 恢复 + W1C）、mod 域 PERR7 注错（REGST 经握手在 mod 域注入 + W1C 经握手跨域清）、PAR_SELFTEST 锁存、错误 key 拒绝 |
| T12 | 在途写锁存奇偶：force 破坏在途锁存通道奇偶 → PERR13 置位 + 恢复 + W1C |
| T13 | 命令在途奇偶：force 翻转 apb2mbus 地址同步链（写偏移位 → 错址、读实例位 → 错实例）→ PERR14 + 双轨 ESM 置位、坏写被门控（IRQEN/INJ_POS 完好）、坏读回 0、W1C 恢复 |
| T14..T25 | 多 beat 突发/回压/全站注错/真实连线损坏/自检扫描 regsel/双轨副本注错扫描/hang 看门狗/h_dup/rpar 回程（见 `sim/tb_edc_top.v` 头部用例索引） |
| T26 | 聚合器 per-core 寄存器奇偶：core 自测 → STA_PARCORE 粘滞/RAWPAR/折入 PAR_FAULT、置位优先 W1C 阻塞、撤源可清、PERR3/PERR4 组自测 + 双轨副本注错；输入轨互补违例：三对轨各注错（TB 轨监视器窗口旁路）→ STA_RAIL/RAWRAIL/rail_fault、在线阻塞/修复可清 |

tb 在 `mm_*`（mport m 侧）与 `ss_*`（sport s 侧）之间例化 `tb_relay_cdc`
（toggle 握手 + 稳定负载）模拟 NIC 内部 fabric，user 位全程随事务搬运，
与真实 NIC 跨时钟 CDC 语义一致。

结果：**全部检查 PASS**（含 T9 的 64×5 条端到端字段比对、T11/T12 的
寄存器奇偶 / 在途奇偶用例、T13 的命令在途奇偶用例）。

### 10.2 部署角色（tb_edc_side）

`sim/tb_edc_side.v`：单 AXI 总线最小系统，master 模型驱 req payload、
slave 模型驱 rsp payload 与 req ready；`u_ms`（`SIDE=0`，NIC 入口）
tap 总线并把 GEN 出的 req user（`awuser_o/wuser_o/aruser_o`）驱动上
总线，`u_sl`（`SIDE=1`，NIC 出口）tap 同一总线做 req CHK 并把 GEN 出
的 rsp user（`buser_o/ruser_o`）驱动回总线；`u_agg` 聚合两核。
时钟：mbus 42ns（≈24MHz）+ AXI 8ns 异源。

| 用例 | 内容 |
| --- | --- |
| S1 | 静息：三 ID / 双核 STA_PAR=0x2 / agg 全 0 / 双轨互补 / user_o 方向性（非生成方向恒 0） |
| S2 | E2E 干净业务（写/读 + 属性变体）：双核 STA 恒 0、出口采样 payload+EDC 非 0 |
| S3 | GEN 组合零延迟：握手前 user 已随 payload 生成、随 payload 变化（不插拍） |
| S4 | req GEN 注错 pos（u_ms 站点1）→ u_sl 报 err+fault（organic），u_ms 本地干净 |
| S5 | req GEN 注错 force（u_ms 站点5）→ u_sl 报 |
| S6 | rsp GEN 注错 pos（u_sl 站点17）→ u_ms 报，agg 归 core0 |
| S7 | 链路真实损坏：force 总线 awuser 一拍 → u_sl 报 organic |
| S8 | CHK 侧注错掩蔽（u_sl 站点2）：只 err 无 fault |
| S9 | 寄存器奇偶自测双核（PERR0 自愈 / PERR7 跨域 / PAR_SELFTEST 锁存 / 错 key）+ agg STA_PARCORE 联动 |
| S10 | agg 联动：源在线 W1C 清不掉，撤源 → core W1C → agg W1C → 0 |
| S11 | 40 混合事务随机压力（随机回压发生器 + 随机间隔），全程干净 |
| S12 | 复位语义：AXI 域单独复位 sticky/影子保留（W1C 才干净、影子存续注错再触发）；mbus 复位经 rst_sync 两域全清 |
| S13 | 结论：OR 网未选中驱 0、双轨互补、`TB PASS` |

### 10.3 波形与运行（VM VCS）

`sim/run_vcs.sh`（VM `~/work/parity/sim` 内）：默认双 TB 全跑
（`top` + `side`），各自编译到 `obj_vcs` / `obj_vcs_side` 并自检日志
（`TB PASS` 且无 `ERR:`），随后 urg 合并双 vdb 出覆盖率；
`run_vcs.sh verdi [top|side]` 打开对应 fsdb（struct 需 `+all`，
脚本已带），`run_vcs.sh cov [top|side]` 打开单 TB 覆盖率 GUI。

### 10.4 覆盖率（VCS/urg）

`-cm line+fsm+tgl+branch`（不收 cond：parity XOR 树条件向量爆量被
VCS 截断，分数无意义）。`run_vcs.sh` 默认把两个 TB 的 vdb 合并出
报告（双顶层名合并需 `-lca -flex_merge code_union`，且该模式下不能用
`-excl_strict`，脚本已按 vdb 数自适应）；toggle 的结构常量排除走
`tgl_struct_excl.el`。
注意 SIDE 装配 + regfile 双域化后实例路径两次变动（chk 引擎进
generate 域 `g_req_chk`/`g_rsp_chk`；影子/sticky 自 edc_core 移入
`u_edc_regfile`，PERR10 组退役），**排除表需按脚本头注释重建**。
当前基线数字见 VM `obj_vcs/urg_report_excl/`。

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

- **多 bit CDC 为准静态**：en/force/irqen 负载通过 2FF 跨域，依赖“改
  配置时 mod 侧无并发更新”的前提；若需完全动态，可改为每站点独立
  握手。
- **INJ_POS 跨域无同步/无在途保护**：准静态直出（软件先写 pos 后开
  en，en 同步链即门控沿）；违反该软件顺序时存在采到撕裂值的理论
  窗口（最坏注错位置错一拍，不破坏检测功能）。存储侧仍有 PERR3。
- **RW1C 窗口**：写清与 mod 域实际清除之间有数个周期，期间读回仍可能
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
   使能后不生效、ERR_STAT 不置位。（req_edge 改版后并行负载链整体
   撤销——负载稳定传输，此坑类别不复存在。）
3. **chk 的 INJ_POS 切片少了 128 bit**（当时为 128b/站点布局）：
   `inj_pos_q[8*128-1:6*128]` 应为 `[9*128-1:6*128]`（3 个站点）。
   现象：站点 8 的注错位错位。本版改为 64b/站点后切片按
   `inj_pos_q[18*64-1:13*64]` 显式对齐。
4. **照搬 sysm_msync 的 ce 电平会双写 regfile**（本轮重写 apb2mbus 时
   分析避免，未实际触发）：参考的 `memo_ce` 保持到下游 rdy 握手、
   rdy 自环下约 2 拍，`edc_regfile` 会对同一地址写两次、`req_t` 双翻转；
   mod 时钟慢于 mbus 时两个边沿在 2FF+边沿检测下可能合并成一个
   `req_edge`，ack 少翻一次，`ack_s2 == req_t` 永不相等 → `cdc_busy`
   卡死、之后每条跨域命令都被忙丢（WR_DROPPED 持续置位）。对策：
   ce 做成单拍（零等待当拍自完成），见 §7.2。

5. **SI/MI 拆分 + user 位传输**（本轮）：`edc_chguard` 改为双模 `edc_site`
   （`MODE` 0=GEN/1=CHK），`edc_gen/edc_chk` 各带 `MODE`，`edc_core`
   增加 `SIDE`，顶层按端口类型绑定 `SIDE=0/1`；EDC 向量从/到 AXI user 位
   切片，tb 新增 `tb_relay_cdc` 模拟 NIC fabric 跨时钟搬运。原先 tb 直接
   驱动 `mm_*`/`ss_*` 的方式改为外部只驱动 `sm_*`/`ms_*`，中间由 fabric
   串起，从而验证“SI gen → MI chk、MI gen → SI chk”的完整闭环。

6. **寄存器奇偶保护 + 双轨 ESM + 编码使能**（本轮，参照 hang_prot
   reg_wrap）：cfg/sta 镜像与 AXI 影子/sticky 全部换成 reg_wrap
   （存储+偶校验+自愈粘滞+自测注错）；新增 STA_PAR (0xAC) / CFG_REGST
   (0xB0，key=0xA)、在途负载奇偶 PERR13；esm_err/esm_fault/
   reg_par_fault 改双轨输出（顶层真轨 OR / 反轨 AND）；注错使能改
   每站点 4bit 编码（1111/0000，非法码 fail-safe 关），INJ_EN 扩为
   0x00/0x04/0x08 三个字，后续寄存器整体 +8 平移。本轮调试中踩的坑：
   ① STA_PAR 读回拼接顺序（旧布局 4+组号时期的保留位问题; 2026-11-06 统一为 2+组号后已无保留位）；
   ② tb 自测写值忘编 key（0xA）；③ 期望值没扣除反轨 bit1 的常 1。
   均已修复，T11/T12 全 PASS。

7. **命令在途奇偶 PERR14**（本轮，闭环 SIL3 差距残余 #6 的 APB 地址
   通路）：apb2mbus 增加与 payload 3FF 同深度的 `par` 链（源端组合
   生成 `^{paddr, pwrite, pwdata}`）；每个 edc_regfile ce 拍重组比对，
   失配 → 全部写使能与 req_t 翻转/锁存装载被 `par_ok` 门控（fail-safe
   拒写）、rdata 驱 0、置 PERR14（mbus 本域自愈双副本粘滞，STA_PAR bit16
   W1C 当拍清）。要点：PERR 位号公式 2+n 对 n=14 自然落在 bit16，
   既有 PERR0..13 位位置不变，软件兼容；检查不 gate sel（公共通路
   损坏全实例置位、局部损坏单实例置位，置位模式即诊断信息）。
   tb 新增 T13（force apb2mbus 地址同步链 1 bit：写偏移位验证门控、
   读实例位验证错实例读回 0），全 PASS；本轮覆盖率 line 96.7→97.1%。

8. **edc_regfile CDC 改版为 ia 式锁存 + req_edge 握手**（2026-11-08
   二次钦定，结构对齐 ia_bus_timeo_regfile）：改版前 en/force/irqen
   负载并行 2FF + cmd_t/clr_mask 累加 + ack 窗口合并；改版后 mbus 侧
   锁存 `{wsel_q, wdata_q}` + `req_t` 翻转，mod 侧 sync_2dff + 延迟拍
   检出 `req_edge` 用锁存值译码（影子载入/W1C 一次性掩码/REGST 注错），
   `ack_t` 回转，忙时写丢弃并显性化 WR_DROPPED。要点：
   - 新增 **0xB4 STA_MISC**（[0] CFG_BUSY / [1] WR_DROPPED），SW
     契约相邻跨域写之间轮询 CFG_BUSY；
   - **PERR4 退役**（clr_mask 累加器撤销）、**PERR13 重定义**为在途
     写锁存奇偶（mbus 域锁存通道，检查移回 mbus 侧）；组号保留不重排；
   - EN/FORCE/IRQEN 的 mbus 图像改为 **mod 影子的同步镜像**（单一
     事实源在 mod 影子），INJ_POS 保持 mbus 本地准静态直出；
   - mod 域组 PERR 的 W1C/REGST 注错经同一握手跨域（一个 SW 写，
     两域同步生效）；
   - 双 TB（tb_edc_side / tb_edc_top）回归全绿；TOGGLE 覆盖率
     两设计 **100.00 双域**（module-definition 与 instance 视图，
     结构常量排除 tgl_struct_excl.el + S14k/S14l/T29i 注错扫描）。
