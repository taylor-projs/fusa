# ia_timeo_gen_regfile 寄存器说明

**模块**：`ia_bus_timeo_regfile`（[ia_bus_timeo_regfile.sv](../rtl/ia_bus_timeo_regfile.sv)）+ 每寄存器 `reg_wrap` 实例（[reg_wrap.sv](../../common_modules/reg_wrap.sv)）**参考**：TI Hercules RM57Lx TRM SPNU562A ch.3 SCM 寄存器模型
**文档版本**：v1.3（2026-11-08）——**单端口独立 IP 化**：删除 `NUM_M` 多主控聚合（观测口 12 tap 全部标量化，内部流固定 `NUM_IA=2`：RD=bit0 / WR=bit1）；FUSRC 固定 7 位；监控核更名 `ia_bus_timeo_core.sv`→`ia_bus_timeo_mon.sv` 并与 regfile 打包成**单口 mbus leaf IP `ia_bus_timeo_core`**；新增两级聚合器 `ia_bus_timeo_top`（§9）；mbus 读回程补 `rpar = ^rdata`；ESM 双轨改为 rail 寄存器面镜像（复位即空闲互补 `1010`）；ID 升版 `0x4941_0002`
**前版**：v1.2（2026-11-06）——寄存器地图统一到 house standard：SCMREGPARSTAT 更名 STA_PAR（字段重排 bit = 2+组号）、自检键从 SCMCNTRL 拆出独立 CFG_REGST 0x28（house key 1010）、新增 ID 0xFC 殿后
**更早**：v1.1（2026-10-29）——配置接口由 APB3 更换为 mbus leaf（单拍 `ce`、零等待、命令奇偶 `par`、无 wait/error 通道）

---

## 1. 概述

`ia_bus_timeo_regfile` 是总线超时监控器 `ia_bus_timeo_core` 的 mbus leaf 寄存器接口模块，负责：

1. 提供 TI SCM 风格的寄存器模型（状态 / 控制 / 阈值 / 故障源）
2. 完成 `mbus_clk`（mbus 域）与 `aclk`（监控域 = 顶层 `ia_bus_aclk`）之间的时钟域 crossing
3. 产生监控核所需的单拍脉冲（`to_clear` / `selftest_key` / `fu_selftest`）与 W1C 清零向量
4. 将监控核的状态、深度、阈值回读、双轨事件同步回 mbus 域供软件读取
5. 对每个 SW 可见寄存器（mbus 镜像 + aclk 影子 + CMD wrap）做逐寄存器偶校验（parity），独立双轨事件 `reg_par_fault`/`reg_par_fault_n` 上报 ESM（见 §5）
6. 对每条 mbus 命令做在途奇偶检查（`par`），坏奇偶写被阻断、读门控为 0，并锁存 `PERR_CMD`（见 §3.4）

`mbus_clk` 与 `aclk` **无相位/频率关系约束**（可异步、可同频异相）。

mbus leaf 协议要点（与 apb2mbus 桥一致）：`ce` 单拍选通；`addr[15:8]` = 实例号（须等于参数 `IDX`）、`addr[7:0]` = 字节偏移；`par = ^{addr, wr, wdata}` 为命令在途奇偶；读数据组合返回、零等待；**没有 wait / error 通道**——无效访问静默忽略，CDC 忙时的写被丢弃并记录（§3.2）。

---

## 2. 接口

### 2.1 mbus 侧（mbus_clk 域）

| 端口 | 方向 | 宽度 | 说明 |
|---|---|---|---|
| `mbus_clk` | in | 1 | mbus 时钟 |
| `mbus_rstn` | in | 1 | mbus 域复位，异步断言、低有效 |
| `ce` | in | 1 | 单拍选通（chip enable 脉冲） |
| `wr` | in | 1 | 1=写 / 0=读 |
| `addr` | in | 16 | `[15:8]` 实例号（== `IDX`），`[7:0]` 字节偏移，字对齐访问 |
| `wdata` | in | 32 | 写数据 |
| `par` | in | 1 | 命令在途奇偶 `^{addr, wr, wdata}`，每次 `ce` 都检查 |
| `rdata` | out | 32 | 读数据，组合返回、零等待（`ce` 当拍有效） |
| `rpar` | out | 1 | 读回程偶校验 `^rdata`，**无条件组合驱动**（mbus leaf 契约）：未选中/坏命令时 rdata=0 → rpar=0，集成侧 OR 网合并且桥侧检出后 pslverr（与 rdata 同为组合直采类，SDC datapath_only 集合同类 +1 bit） |

无 `pready`/`pslverr`：读零等待；写 fire-and-forget，跨域靠 toggle 握手（§4.1），忙时的写被丢弃并置 `WR_DROPPED`；非对齐/越界/写只读访问静默忽略。

### 2.2 监控域（aclk 域）

| 端口组 | 方向 | 关键信号 | 说明 |
|---|---|---|---|
| 配置 | out | `cfg_wr`、`cfg_key`、`cfg_ena`、`cfg_req2accept_max`、`cfg_req2resp_max` | 单拍写脉冲 + 影子值；`cfg_key` 恒为 `4'b1010` |
| 动作 | out | `to_clear`、`selftest_key`、`fu_selftest` | 单拍脉冲，源自 keyed SCMCNTRL 位 |
| 清零 | out | `r2a_w1c`、`r2r_w1c`、`fu_w1c` | W1C 向量（CPU 清除优先级最高） |
| 状态 | in | `r2a/r2r_err_status`、`ia_active`、`otd` | 监控状态 |
| 回读 | in | `thr_rd_r2a/r2r`、`ena_rd` | 阈值/使能有效值回读 |
| 事件 | in | `err_event(_n)`、`fu_fault(_n)` | 双轨 ESM 事件 |
| 奇偶故障 | out | `reg_par_fault`、`reg_par_fault_n` | mbus_clk 域 ESM 双轨事件（见 §5） |
| 故障源 | in | `fu_src` | 固定 7 位完整性故障源 `{OTDSAT[6], STAT[5], CMP[4], CNT[3], THRR[2], THRA[1], ENA[0]}`（v1.3 单口 m=0） |

复位 `rstn`：异步断言、低有效（与监控核 `rstn` 同源）。

---

## 3. 寄存器映射

实例号由 SoC 集成决定（`addr[15:8]` 须等于参数 `IDX`）；偏移单位为字节（`addr[7:0]`），11 个 32 位寄存器（0x00–0x28）+ ID 殿后 0xFC。
所有访问必须字对齐；非对齐/越界/写只读访问被**静默忽略**（mbus 无错误通道），坏奇偶访问被阻断并锁存 `PERR_CMD`（§3.4）。

寄存器地图位置（house standard，与 fusa 全家族一致）：**STA_PAR 倒数第 3（0x24）、CFG_REGST 倒数第 2（0x28）、ID 殿后 0xFC**。CFG_REGST 用 house key `wdata[3:0]=4'b1010`（独立于 SCMCNTRL [7:4] 的本地 key 空间），错 key 写被静默丢弃（本设计无 REG_PROT 锁存类，与其它 keyed 违例同样处理）。

| 偏移 | 名称 | 访问 | 复位值 | 字段说明 |
|---|---|---|---|---|
| 0x00 | `SCMIAERR0STAT` | **W1C/R** | 0x00000000 | `[1:0]` req2accept 超时状态（sticky）。**bit0=RD 流、bit1=WR 流**（v1.3 单口固定，RD/WR 双流） |
| 0x04 | `SCMIAERR1STAT` | **W1C/R** | 0x00000000 | `[1:0]` req2resp 超时状态（sticky）。bit0=RD、bit1=WR |
| 0x08 | `SCMIASTAT` | R | — | `[1:0]` IA 活动（pending 事务），动态值。bit0=RD、bit1=WR |
| 0x0C | `SCMOTD` | R | — | `[2*OTD_W-1:0]` 每流 outstanding 深度（[OTD_W-1:0]=RD、[2*OTD_W-1:OTD_W]=WR），动态值 |
| 0x10 | `SCMCNTRL` | W/R | 0x0000000F | 见下表 |
| 0x14 | `SCMTHRESH0` | W/R | 0x0000000F | `[15:0]` REQ2ACCEPT_MAX（req2accept 阈值） |
| 0x18 | `SCMTHRESH1` | W/R | 0x00000000FF | `[15:0]` REQ2RESP_MAX（req2resp 阈值） |
| 0x1C | `SCMIAFUSTAT` | **W1C/R** | 0x0000000A | `[0]` FU_FAULT（W1C）；`[1]` FU_FAULT_N、`[2]` ERR_EVENT、`[3]` ERR_EVENT_N（只读双轨，复位即空闲互补 `1010`：真轨 0 / 反轨 1）；`[4]` CFG_BUSY（RO，CDC 写在途）；`[5]` WR_DROPPED（W1C，见 §3.2） |
| 0x20 | `SCMIAFUSRC` | **W1C/R** | 0x00000000 | `[6:0]` 完整性故障源（v1.3 固定 7 位），见 §3.3 |
| 0x24 | `STA_PAR` | **W1C/R** | 0x00000002 | 寄存器奇偶状态（house standard 字段布局）：`[0]` PAR_FAULT / `[1]` PAR_FAULT_N / `[12:2]` PERR（bit = 2+组号），见 §3.4。静息读 0x2 |
| 0x28 | `CFG_REGST` | **WO** | — | 寄存器奇偶自检控制（house standard）：key[3:0]=1010 + `[4]` REG_SELFTEST + REGSEL[11:8] + `[5]` PAR_SELFTEST，见 §3.5。读恒 0；错 key 写静默丢弃 |
| 0xFC | `ID` | R | 0x4941_0002 | `"IA"` v1.3（house standard 殿后；单口化 SW 可见地图变更 → 版本号升位）。仅 `addr[7:0]==8'hFC` 精确译码（0x3C/0x7C/0xBC 落在 wsel 15 越界读 0） |

### 3.1 SCMCNTRL 字段（0x10）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [7:4] | KEY | W | 必须为 `4'b1010`（0xA），否则整个写操作被忽略 |
| [3:0] | ENA | W/R | 使能码字：`0xF` 开 / `0x0` 关。非法码字被拒绝，回读显示未变的码字 |
| [8] | TO_CLR | W（脉冲） | 1-aclk-拍脉冲，重启实时计数器。**动作写必须保 ENA=0xF**（见 §5.2） |
| [9] | SELFTEST | W（脉冲） | 强制比较器触发，证明 err_event 上报链路（含双轨） |
| [10] | FU_SELFTEST | W（脉冲） | 强制 fu_fault 但不锁存 fu_src，证明监控故障上报链路 |

（v1.2 起 PAR_SELFTEST/REG_SELFTEST/REGSEL 从 SCMCNTRL 移除，由 CFG_REGST 0x28 承担，见 §3.5。）

脉冲位只在写当拍起作用，读回恒 0；ENA 回读显示监控侧 `ena_rd` 有效码字。
KEY 只写不读（读 0）。

### 3.2 SCMIAFUSTAT 字段（0x1C）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [0] | FU_FAULT | W1C/R | 监控完整性故障（sticky）。写 1 清除 |
| [1] | FU_FAULT_N | R | FU_FAULT 双轨补码，恒等 `~[0]` |
| [2] | ERR_EVENT | R | 真实总线超时事件电平 |
| [3] | ERR_EVENT_N | R | ERR_EVENT 双轨补码，恒等 `~[2]` |
| [4] | CFG_BUSY | R | 配置写 CDC 在途（req_t != ack_t_s2）。依赖前一次写的后续写必须先轮询此位为 0 |
| [5] | WR_DROPPED | W1C/R | CDC 忙时的写被丢弃（sticky，fail-visible）。写 bit5=1 清除；与置位互斥（置位优先） |

软件可在同一寄存器里看到双轨互补对 `[1]≠[0]` 或 `[3]≠[2]` 即传输故障。
mbus 零等待语义下写不再阻塞总线：CFG_BUSY=1 期间到达的有效写**不会执行**（丢弃而非等待），软件流程为"写 → 轮询 CFG_BUSY=0 → 下一笔依赖写"；任何丢弃都有 WR_DROPPED 记录，不会静默丢失。

### 3.3 SCMIAFUSRC 字段（0x20）

| 位 | 名称 | 说明 |
|---|---|---|
| [0] | ENA | 使能码字完整性故障 |
| [1] | THRA | req2accept 阈值副本失配 |
| [2] | THRR | req2resp 阈值副本失配 |
| [3] | CNT | 计数器/深度副本失配（Q/Q_n 自检） |
| [4] | CMP | 双比较器分歧 |
| [5] | STAT | 状态副本失配 |
| [6] | OTDSAT | outstanding 账本饱和丢递增：账本已在 OTD_MAX 时同拍又来 AR/AW/WLAST 握手，深度计数不可信（可能掩盖真挂死）。置位同时拉 FU_FAULT；SW 应 quiesce 流量 + TO_CLR 重启账本。饱和流靠 SCMOTD（=OTD_MAX 的流）定位 |

（v1.3：单口 m=0，原 per-master 展开 `[3+3m+*]` 折叠为固定位 [3]/[4]/[5]，OTDSAT 落 bit6。）

写入非零值同时清除 FU_FAULT 与全部故障源位；仍然存活的故障源下一拍重新置位。

### 3.4 STA_PAR 字段（0x24，house standard 布局）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [0] | PAR_FAULT | R（电平） | 寄存器奇偶故障 = 全部 PERR 位与自检锁存的 OR；直连 ESM 双轨 `reg_par_fault`/`reg_par_fault_n`。写 [0] 仅清除自检锁存，各 PERR 位在其 own bit 清除 |
| [1] | PAR_FAULT_N | R | PAR_FAULT 双轨补码 |
| [12:2] | PERR10..PERR0 | W1C/R | 每组奇偶错误，**bit = 2+组号**（house standard）。组 k = 偏移 0x4*k 的寄存器（4..6 = mbus 镜像 + aclk 影子两处 sticky 汇总）；组 9 = 在途写锁存奇偶（latch lane，任意寄存器，无注错目标）；组 10 = PERR_CMD mbus 命令奇偶（W=1 wrap：sticky 体即 wrap 存储，写 bit[12] 是一次重写、重算奇偶）。组 10 详解：`ce` 当拍 `par != ^{addr, wr, wdata}`（**每次 ce 都检查，与实例号译码无关**——错误实例号+坏奇偶同样锁存，因为实例号本身可能已被翻转）。坏奇偶写被阻断（不执行任何副作用），坏奇偶读门控为 0 |

每个 PERR 位清除对应组在**两个域**的 sticky（mbus 镜像同拍、aclk 影子经握手 req_edge 拍）；故障仍存活时重新置位（T6 语义）。各 sticky 内部带反相副本（失配自愈为置位，见 §5.2）。

### 3.5 CFG_REGST 字段（0x28，house standard）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [3:0] | KEY | W | 必须为 `4'b1010`（house key），否则整个写被静默丢弃（无副作用、无锁存；本设计无 REG_PROT 类） |
| [4] | REG_SELFTEST | W（脉冲） | 逐组奇偶注入：翻转所选组的奇偶位（数据不动），经存储+比较器+sticky+ESM 完整链路上报 |
| [5] | PAR_SELFTEST | W（脉冲） | 强制 PAR_FAULT 但不置任何 PERR 位（无源注错），证明奇偶→ESM 上报链路（写 0x2A） |
| [11:8] | REGSEL | W | REG_SELFTEST 的目标组号（0–10 = 偏移 0x4*k 的寄存器，10 = CMD wrap；9 = 在途锁存 lane、无注错目标、忽略），>10 时注入被忽略 |

读恒 0（WO）；典型写值：组 k 注入 `0x1A \| (k << 8)`、PAR_SELFTEST `0x2A`。

---

## 4. 时钟域与 CDC 设计

```
mbus_clk 域                         aclk 域（ia_bus_aclk）
─────────────                       ─────────────────────
mbus leaf 从机                      监控核 ia_bus_timeo_core
  │ 写锁存 wsel_q/wdata_q              ▲
  ▼                                   │
req_t ──toggle──► 2FF同步+边沿检测 ──► req_edge 译码
                   (aclk 侧执行)
ack_t ◄──toggle── 回 ack              │
  ▲                                   │
  2FF同步回 mbus_clk                   状态/深度/事件 2FF同步 ──► rdata
  └─ CFG_BUSY = !busy (SCMIAFUSTAT[4], 忙时写丢弃 + WR_DROPPED)
```

### 4.1 写方向（mbus → aclk）：单飞 toggle 握手

- mbus 写当拍（`wr_fire`）锁存 `{wsel, wdata}` 并翻转 `req_t`；数据**保持稳定**直到 ack 返回
- aclk 侧经 2FF 同步 + 寄存一拍做边沿检测（对同步器输出上的亚稳态毛刺免疫）
- aclk 侧译码执行后翻转 `ack_t`；`ack_t` 2FF 同步回 mbus_clk，`req_t != ack_t_s2` 期间 `CFG_BUSY`=1
- **多比特数据（地址+数据）靠稳定性跨域，无需 Gray 码**
- 同一时刻最多一个写在途（one at a time）：mbus 零等待、写不阻塞——CFG_BUSY=1 期间到达的有效写被**丢弃**（不执行），并置 sticky `WR_DROPPED`（fail-visible）。软件必须按 §3.2 的流程轮询 CFG_BUSY
- 任何译码（含无效 key 的忽略型写）都会被 ack——握手不会悬挂

### 4.2 读方向（aclk → mbus）：2FF 同步

- sticky 状态位（IAERR0/1、FUSTAT、FUSRC）逐位独立 → **任何采样点都相干**
- 动态多比特值（SCMIASTAT / SCMOTD / 阈值回读 / ENA 回读）：一次读取与监控侧变化存在竞态，可能采到过渡值。**仅影响观测，不影响安全功能**；重新读即可解决。TI 周期性回读的用法（SPNU575）不是单发判定，因此安全
- 双轨事件（FUSTAT[3:0]）是 **rail 寄存器面镜像**（v1.3）：`u_rail_sync`（sync_dff，s1 亚稳吸收）→ `u_r_fustat`（reg_wrap，s2 存储 + 偶校验），esm 双轨输出取自 rail_s2 同一寄存器面，不再另起同步链。**复位值即空闲互补 `4'b1010`**（`{EV_n=1, EV=0, FU_n=1, FU=0}`）——复位窗口内双轨即满足互补契约，下游聚合器/ESM 的逐拍互补校验不会误报；rail 寄存器面自身的 SEU 翻转单 bit 会破坏互补 → 聚合器 rail 校验捕获（比"本地取反"更强的覆盖）。采样窗口内两侧可能同时翻转，软件判定用连续两次一致采样
- 读为组合返回、零等待；坏奇偶读（`par` 不匹配）门控为 0 且不产生任何副作用

### 4.3 复位

- `mbus_rstn`（mbus_clk）与 `rstn`（aclk）**必须系统级同时断言**（同源、同步释放），否则握手 toggle 状态失配，第一次写可能丢失
- 这是系统集成约束，文档级约定（TI 安全外设整块复位的做法）；模块内部不做复位 bridging
- 监控核内部再对 `rstn` 做异步断言 / 3 级同步释放（见 `ia_bus_timeo_core.sv`）

---

## 5. 寄存器奇偶功能安全监测（FuSa）

每个寄存器在自己所在的时钟域里是一个独立的 `reg_wrap` 实例（[reg_wrap.sv](../../common_modules/reg_wrap.sv)）：存储 + 偶校验 + `selftest_key` 奇偶注入 + 自身故障 sticky（`flt` / `flt_w1c`）。独立双轨事件上报 ESM（`reg_par_fault` / `reg_par_fault_n`，mbus_clk 域电平），与总线超时（err_event）和监控核完整性（fu_fault）分开——寄存器损坏是独立的失效模式。

`reg_wrap` 端口结构：`wdata`/`wr`/`rdata`（纯 RW 存储，W1C/set 语义由父级编码在 wdata 上）、`selftest_key`（本域内注入）、`flt`（sticky 电平输出 → 聚合/ESM）、`flt_w1c`（W1C 清除，CPU 优先）。**检查与存储同域同体**——不再有外部故障源端口，跨域只同步 `flt` 结果。

### 5.1 实例分布（每个寄存器在自己被使用的域里）

| 实例 | 域 | 覆盖对象 | 说明 |
|---|---|---|---|
| u_r_iaerr0..u_r_otd, u_r_fustat, u_r_fusrc | mbus_clk | 0x00/0x04/0x08/0x0C/0x1C/0x20 的 s2 镜像（SW 实际读到的值） | wr=1 跟随 s1，flt 同域直接用 |
| u_c_ena/u_c_thresh0/u_c_thresh1 | **aclk** | SCMCNTRL.ENA / SCMTHRESH0 / SCMTHRESH1 配置影子 | 经 CDC 握手写入（req_edge 译码、数据稳定跨域）；cfg_ena/cfg_req2accept_max/cfg_req2resp_max 即其 rdata；**flt 2FF 同步回 mbus 域**聚合 |
| u_w_cmd | mbus_clk | 命令奇偶 sticky 体（组 10，W=1 wrap） | wdata=`par_bad`、wr=`par_bad \|\| W1C bit[12]`：坏命令奇偶写 1 进 wrap（即 PERR_CMD 置位），其 W1C 位本身是一次 wrap 重写 |
| （latch） | mbus_clk | 在途写锁存 {wsel, wdata} 奇偶 | 瞬态窗口，锁存为组 9（STA_PAR bit 11） |

0x10/0x14/0x18 的读回显示（监控有效值回读）仍是 mbus 侧镜像 u_r_cntrl/u_r_thresh0/u_r_thresh1——组 4/5/6 的 PERR 位 = 镜像 flt + 同步后的影子 flt（同一寄存器在两个域的存储各自检查，一个 PERR 位汇总）。

### 5.2 注错、清除与上报

- **注错（selftest_key）在本域译码**：mbus 镜像在 wr_fire 拍、aclk 影子在 req_edge 拍，各自由 CFG_REGST REG_SELFTEST/REGSEL（house key 1010）选择目标。regsel 4..6 时镜像与影子**同时注入**：镜像侧 wr=1 下一拍自动恢复（par_err 恰 1 拍）；影子侧保持到该寄存器被重写（测试序列的恢复步骤）；regsel 10 注入 u_w_cmd（wr 非恒 1，保持到 W1C 重写）
- **W1C 一次写、两域同清**：写 0x24 时 mbus 侧同拍清镜像 sticky，同一写经 CDC 后 aclk 侧 req_edge 清影子 sticky——任何清除/注入都源自同一次 SW 写，两域不会失同步
- **PAR_FAULT = 所有 sticky + 锁存的 OR**（电平）：任一源未清除则事件保持，单一事实来源
- 各 sticky 与 2 位锁存内部带反相副本：失配自愈为置位——被 SEU 清掉的故障会重新上报
- `PAR_SELFTEST`（CFG_REGST[5]，house key，写 0x2A）只置锁存、不置任何 PERR——ESM 服务程序以"fault 无 source"识别自检模式
- `REG_SELFTEST`（CFG_REGST[4] + [11:8] REGSEL，house key，写 `0x1A \| (k << 8)`，k=0..10）：逐组奇偶注入，SW 序列：注入 → 读 PERR 位（bit 2+k）验证 → 重写该寄存器（影子侧恢复）→ W1C → 确认 fault 保持清除，端到端证明该寄存器全链

### 5.3 已知行为与残余风险

- 动态镜像寄存器（SCMIASTAT / SCMOTD / 阈值回读）的 2FF 同步亚稳态可能偶发假 PERR（安全方向，W1C 清除即可）
- 在途写奇偶错误统一锁存为 PERR9（不按地址归属，故障仍会上报，fail-visible）
- 只读寄存器（0x08 / 0x0C）无写路径，仅镜像奇偶覆盖
- 共模（数据+奇偶同时翻转）不由本层覆盖：周期 PAR_SELFTEST + SW 回读兜底

## 6. 软件使用指南

### 6.0 mbus 写排序规则（相对 APB 版的行为变化）

mbus 写是 fire-and-forget（零等待）：regfile 收写后经 toggle 握手跨到 aclk。两笔**有依赖**的写（或写后读回同一寄存器）之间必须确认前一笔已跨域：

```
write <reg> = <val>
do { read SCMIAFUSTAT } while (bit[4] CFG_BUSY == 1);   // 等待跨域完成
if (read SCMIAFUSTAT bit[5] WR_DROPPED) -> 错误处理      // 不应发生; 发生了说明没等忙
```

无依赖的写（不同寄存器、且后者不依赖前者生效）可以背靠背发出，但忙时到达的写会被丢弃（WR_DROPPED 置位），因此驱动程序统一用"写+轮询 CFG_BUSY"最稳妥。读零等待，随时可发。

### 6.1 典型序列

```
1. 配置阈值 (每笔写后轮询 CFG_BUSY, 下同):
   write SCMTHRESH0 = 0x0000000F   // req2accept = 15 周期
   write SCMTHRESH1 = 0x000000FF   // req2resp   = 255 周期

2. (可选) 关闭监控:
   write SCMCNTRL = 0x000000A0     // KEY=0xA, ENA=0x0 (关)
   // 注意: ENA=0xF 是唯一合法"开"码字

3. 开启/保持监控 + 重启计数器:
   write SCMCNTRL = 0x000001A0     // KEY=0xA, ENA=0xF, TO_CLR=1

4. 读状态 (轮询或 ESM 中断后):
   read SCMIAERR0STAT              // req2accept 超时源
   read SCMIAERR1STAT              // req2resp 超时源
   read SCMIAFUSTAT                // 监控自身完整性
   read SCMIAFUSRC                 // (若 FUSTAT 报故障) 定位源

5. 服务后清状态:
   write SCMIAERR0STAT = <bits>    // W1C
   write SCMIAERR1STAT = <bits>    // W1C
   write SCMIAFUSTAT   = 0x1       // 清 FU_FAULT
   //   或
   write SCMIAFUSRC    = 0x7F      // 非零写同时清 FU_FAULT+FUSRC (7 位)

6. 奇偶自检 (周期性, 证明 reg_par_fault -> ESM 链路):
   write CFG_REGST = 0x2A          // house key 1010 + PAR_SELFTEST
   // ESM 应收到 reg_par_fault; 读回 STA_PAR = 0x1 (仅 bit0)
   write STA_PAR   = 0x1           // 清除 (读回 0x2 静息)
```

### 6.2 动作写必须带 ENA=0xF

SCMCNTRL 的 ENA 字段在**每一次**带 key 的写中都会被监控采样。若软件为了清计数器写 `0x100`（ENA=0x0），监控会真的关闭（0x0 是合法“关”码字）。
**约定：所有 SCMCNTRL 动作写一律使用 0x1A0（TO_CLR）/ 0x2A0（SELFTEST）/ 0x4A0（FU_SELFTEST）**——高位 key + ENA=0xF。

### 6.3 双轨校验（软件侧）

- 正常：`SCMIAFUSTAT[1] == ~[0]` 且 `SCMIAFUSTAT[3] == ~[2]`
- 违反 → regfile→mbus 读路径或 ESM 接线传输故障，按 FUSA 流程处理
- SELFTEST / FU_SELFTEST 是链路证明：若写后对应事件不置位 → 上报链路断，FuSa latent fault

### 6.4 W1C 优先级

监控核内部 W1C 优先于同时刻的错误置位（TI TRM 3.2.2 CPU 清除优先）。若清除瞬间故障仍存在，状态位下一拍重新置位——软件不应把“清不掉”当作异常，而应视为故障持续。

---

## 7. 安全属性小结

| 机制 | 实现位置 | 作用 |
|---|---|---|
| Key 保护 | SCMCNTRL[7:4]=0xA，regfile + 监控双重检查 | 随机写不能破坏配置 |
| ENA 码字 | 仅 0xF/0x0 被接受，非法码字拒绝且可回读验证 | 使能位 SEU 防护 |
| 阈值写即全量重发 | 任意阈值写重发完整 {ena, thr_a, thr_r} 三元组 | 监控键控端口永远看到相干配置 |
| 单飞 toggle 握手 | mbus 写路径 | 多比特数据稳定跨域，无亚稳态采样 |
| 忙时写丢弃 + WR_DROPPED | mbus 写路径 | 零等待总线上的写冲突 fail-visible，绝不静默丢失 |
| mbus 命令奇偶 par | 每次 ce 检查 | 命令/地址/数据在途翻转 → PERR_CMD + 写阻断/读门控 |
| sticky 位逐位同步 | 读路径 | 状态回读任何时刻相干 |
| 脉冲位自动回零 | TO_CLR/SELFTEST/FU_SELFTEST | 电平位冻结监控的 latent fault 防护 |
| 双轨 ESM | err_event(_n)、fu_fault(_n) | 传输故障检测 |
| 周期回读 | 阈值/使能回读寄存器 | SPNU575 配置周期性校验 |
| 寄存器奇偶 | s2 镜像 + aclk 影子 + CMD wrap + 在途写锁存，逐周期检查 | SW 可见寄存器存储损坏 → 独立 ESM 事件 |
| 奇偶状态反相副本 | STA_PAR 锁存 lane 自身 | SEU 清除的奇偶故障自愈为置位，重新上报 |
| PAR_SELFTEST | CFG_REGST[5]，house key 脉冲 | 证明奇偶→ESM 链路（含双轨） |
| REG_SELFTEST | CFG_REGST[4] + REGSEL[11:8]，house key | 逐组注入，端到端证明每组全链 |

**已知限制（文档化的残余风险）**：

1. 动态多比特读（SCMIASTAT/SCMOTD）存在单次采样不一致窗口——观测用，重读解决
2. 阈值寄存器对 SW 是普通 RW（key 由 regfile 构造性提供）；配置空间权限由 SoC MPU/总线层隔离
3. mbus_clk 与 aclk 复位必须同源同释——系统集成约束
4. 共模故障（同一数据的两份副本同时同值翻转）不由本层覆盖，由周期 SELFTEST + 启动端到端事务测试兜底

---

## 8. 参数

| 参数 | 默认 | 约束 | 说明 |
|---|---|---|---|
| `OTD_MAX` | 8 | ≥1 | outstanding 饱和深度 |
| `OTD_W` | `$clog2(OTD_MAX+1)` | — | 深度位宽 |
| `REQ2ACCEPT_RST` | 16'h000F | 非零 | req2accept 阈值复位值 |
| `REQ2RESP_RST` | 16'h00FF | 非零 | req2resp 阈值复位值 |
| `IDX` | 0 | 0–255 | mbus 实例号（`addr[15:8]` 须等于 IDX 才译码本实例） |

（v1.3：`NUM_M` 删除——监控核单口化后流数固定 `NUM_IA=2`（RD=bit0 / WR=bit1），不再参数化。）

Elaboration 检查（编译期 `$error`）：`IDX > 255`、`OTD_W*2 > 32`、`FU_SRC_W > 32` 均报错终止。

---

## 9. 两级集成架构与聚合器（v1.3）

### 9.1 打包与拓扑

`ia_bus_timeo_core`（[ia_bus_timeo_core.sv](../rtl/ia_bus_timeo_core.sv)）= `ia_bus_timeo_mon`（监控核，原 `timeo_core.sv`/`ia_bus_timeo_core.sv` 更名）+ 本文所述 regfile 打包成的**单口 mbus leaf IP**：一个被监视 AXI4 接口配一个实例（12 个观测 tap 全部标量输入），寄存器面即 §3 地图，自带 fault sticky + ESM 双轨直出（可选独立冗余通道）。

```
AXI4 tap ──► ia_bus_timeo_core<0..N-1> ──esm_err/_n, esm_fault/_n,──► ia_bus_timeo_top ──esm_* 4 对双轨──► ESM
 (每口一实例)   (mon + regfile 打包)      reg_par_fault/_n (双轨)       (mbus 聚合器)     (含 rail_fault)
```

`ia_bus_timeo_top`（[ia_bus_timeo_top.sv](../rtl/ia_bus_timeo_top.sv)，参数 `NUM_CORE`=1..32）是镜像 2.parity `edc_top` 的 fault 聚合器，**不接任何 AXI 信号**，只收各 core 的三对双轨（err / fault / reg_par），做四件事：per-core sticky 状态、per-core 寄存器奇偶 sticky（独立通道 STA_PARCORE，不与超时 fault 混排）、**输入轨互补校验**（真轨须恒等于 ~反轨，违例按 core 粘滞 STA_RAIL + rail_fault 双轨上报——真值捕获仍用真轨，违例只上报不改写）、聚合 fault 四对双轨送 ESM。单 mbus 域：core 输出是 regfile mbus 域寄存器输出（rail_s2），同域直采粘滞无 CDC；异构时钟的 core 须在源侧同步后再接入。

### 9.2 聚合器寄存器映射（`addr[15:8]`=IDX_agg，`addr[7:0]`=偏移）

| 偏移 | 名称 | 访问 | 复位值 | 字段说明 |
|---|---|---|---|---|
| 0x00 | `STA_ERR` | **RW1C** | 0x0 | `[NUM_CORE-1:0]` 各 core err sticky（真实总线超时，含 selftest 归因）。置位优先于 W1C（源在线清不掉，撤源后可清） |
| 0x04 | `STA_FAULT` | **RW1C** | 0x0 | `[NUM_CORE-1:0]` 各 core fault sticky（监视器/寄存器面完整性，organic） |
| 0x08 | `RAWERR` | R | — | 各 core err 当前电平（区分"正在报"与"报过已被粘滞"） |
| 0x0C | `RAWFLT` | R | — | 各 core fault 当前电平 |
| 0x10 | `STA_PARCORE` | **RW1C** | 0x0 | 各 core 寄存器奇偶 sticky（源=core reg_par_fault 电平；先在 core 侧 W1C 撤源，此处才可清） |
| 0x14 | `RAWPAR` | R | — | 各 core reg_par_fault 当前电平 |
| 0x18 | `STA_PAR` | **W1C/R** | 0x00000002 | house standard：`[0]` PAR_FAULT（电平=全部 PERR 源或 + 自测锁存 + 各 core 寄存器奇偶 sticky 或）/ `[1]` PAR_FAULT_N / `[6:2]` PERR0..PERR4（bit=2+组号）。**每笔 PERR W1C 同时重写本组 wrap**（复原注错翻转的存储奇偶），单笔完成清除 |
| 0x1C | `CFG_REGST` | **WO** | — | house key `wdata[3:0]=4'b1010`；`[4]` REG_SELFTEST 对 `[11:8]` REGSEL 组（0..4，>4 忽略）注错；`[5]` PAR_SELFTEST 只置自测锁存。读恒 0 |
| 0x20 | `STA_RAIL` | **RW1C** | 0x0 | 各 core 输入轨互补违例 sticky（err/fault/par 任一对真/反轨同值；置位优先） |
| 0x24 | `RAWRAIL` | R | — | 输入轨互补违例当前电平 |
| 0xFC | `ID` | R | 0x4941_2000\|IDX | `"IA"` 聚合器版 |

聚合器 PERR 组号：**0=STA_ERR、1=STA_FAULT、2=命令在途（PERR_CMD，W=1 wrap，W1C 即重写）、3=STA_PARCORE、4=STA_RAIL**；5 个 reg_wrap 与叶端同构（存储 + 偶校验 + 注错 + sticky 双副本自愈）。

**PERR W1C 重写语义**（v1.3 设计要点）：reg_wrap 的无写注错把存储奇偶位翻转后，只有 wrap 重写才能复原——单独 `flt_w1c` 清了 flt，残余 par_err 下一拍又置回。因此四个事件写入型 sticky wrap（组 0/1/3/4）的 `wr` 条件并入了本组 PERR W1C（0x18 对应 bit），与组 2 "W1C 位即重写" 统一成同一 SW 契约：**写 0x18 的 PERRk 位一笔完成 flt 清除 + 奇偶复原**。

### 9.3 输入轨契约

- 各 core 的三对双轨在**复位期间就必须互补**：core 侧 rail 镜像复位值 `4'b1010`（空闲互补，见 §4.2），`reg_par_fault_n = ~reg_par_fault` 组合直出——聚合器逐拍 `~(真轨^反轨)` 校验从复位第一拍起合法
- 违例 = 传输/轨寄存器单 bit 翻转（任一轨上翻转都破坏互补）：粘滞到对应 core 的 STA_RAIL 位 + `rail_fault`/`rail_fault_n` 双轨 ESM；真值捕获继续用真轨（同 ESM 接收侧行为，违例只上报不改写）
- 聚合器自身 ESM 输出四对双轨：`esm_err/esm_err_n`、`esm_fault/esm_fault_n`、`reg_par_fault/reg_par_fault_n`（已折入 per-core 寄存器奇偶 sticky——本模块是完整汇总点，集成可只接本模块）、`rail_fault/rail_fault_n`

### 9.4 集成注意事项

- 各 core 自带的 ESM 双轨输出仍直出可用（独立冗余通道，集成可选）
- core 的 `reg_par_fault` 不并入 STA_ERR/STA_FAULT（与超时 fault 不同失效模式，独立查询通道），只走 STA_PARCORE 聚合
- 聚合器 sticky 无功能使能门控（观测恒使能，fail-visible）；sticky 位在 reg_wrap 内已双副本自愈，无内部计数器，不需 Q/Q_n 副本（同 10.dup_ctrl 论证）
- 复位：core 与聚合器同为异步低有效 `rstn`，mbus 域同源同释（§4.3 约束对聚合器同样适用）
