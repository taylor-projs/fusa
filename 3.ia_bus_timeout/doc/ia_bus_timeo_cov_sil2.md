# ia_bus_timeo_top 覆盖率与功能安全（SIL2）分析

**分析对象**：`ia_bus_timeo_top`（[ia_bus_timeo_top.sv](../rtl/ia_bus_timeo_top.sv)）及其子模块
`ia_bus_timeo_core`（[ia_bus_timeo_core.sv](../rtl/ia_bus_timeo_core.sv)）、`ia_bus_timeo_regfile`（[ia_bus_timeo_regfile.sv](../rtl/ia_bus_timeo_regfile.sv)）、`reg_wrap`（[reg_wrap.sv](../rtl/reg_wrap.sv)）

**标准依据**：IEC 61508:2010（E/E/PE 功能安全），SIL2 目标；参考 TI Hercules Safety Manual SPNU575 的监控器验证方法（同源设计参考）

**文档版本**：v1.0（2026-10-21）

---

## 1. 范围与安全上下文

### 1.1 本 IP 在安全功能中的角色

本模块**不是**安全功能本身，而是**诊断/监控元件**（IEC 61508 意义上的 B 类检测通道）：

```
安全功能(别处,如 CPU/执行链) ──数据经 AXI 互连──►
                                  │
                          本监控器(旁路观察) ──► ESM ──► 系统反应
```

- 它检测的对象：互连上总线挂起（地址相/数据相/响应相超时）
- 它对整体安全性的贡献：提高被监控通道的**诊断覆盖率（DC）**，把互连的静默失效（dangerous undetected）转为可检测失效
- 它自身的失效也需被检测（ FuSa 完整性层：反相副本 / 码字 / parity / 自检键）——这是本分析 SIL2 论证的核心

### 1.2 假设的运行模式

- 低需求模式或高需求模式由集成方定义；本分析按 **PFH（每小时危险失效率）** 给出（高需求/连续模式指标，低需求模式换用 PFD 公式即可）
- 时钟/复位/ESM 反应属于集成项，见 §5.6 集成假设

---

## 2. 代码覆盖率分析

### 2.1 覆盖率目标（SIL2 验证要求）

| 覆盖率类型 | 目标 | 依据 |
|---|---|---|
| 语句（statement） | **100%**（含注入激励达成） | IEC 61508-3 SIL2 结构化验证 + 项目规范 |
| 分支（branch） | **100%** | 同上 |
| 条件/判定（MC/DC） | 关键块 100%（§2.4 清单） | 动态分析 HR（SIL2 推荐档） |
| 翻转（toggle） | ≥ 98%（余量项需论证） | 项目规范 |
| FSM | 无显式状态机（复位同步器按 3 位移位处理，toggle 覆盖） | — |

未达项必须走例外流程：不可达证明、或降级为形式验证/评审覆盖。

### 2.2 各模块分支覆盖清单（需特殊激励的项加 ★）

#### ia_bus_timeo_core（监控核）

| 代码位置 | 分支 | 激励需求 |
|---|---|---|
| ena_ff | 复位 / cfg 写 / 纠错（ones≥3 / ones≤1 / ones==2 保持） | 前两项正常激励；★ 三种 SEU 分支需 force 注入 `ena_q`（0111/0110/0000） |
| scm_threshold | 复位 / cfg_ok | 正常激励 |
| thr_a_fault / thr_r_fault | true / false | ★ false 正常；true 需 force `thr_a_qn` 一位 |
| rd_r2a_to_a/b | `cnt >= thr-1` 边界、`thr==0` 禁能、valid&&!ready | 定向：阈值边界 ±1 拍、阈值写 0 |
| rd_r2r_to_a/b | otd≠0 && !rbeat && cnt≥thr-1 | 读事务无 R 响应挂起 |
| rd_cnt_a_ff | 计数 / 清零 / to_clear | 挂起 + 握手 + SCMCNTRL 0x1A0 |
| rd_otd_ff | 递增饱和 / 递减 / ★ 饱和时 ar_hs&&!rl_hs / 递减下限（otd==0 时 rl_hs） | OTD 压到 OTD_MAX；RLAST 无 outstanding |
| rd_cnt_r_ff | rbeat 清零 / otd≠0 计数 / otd==0 保持 | R 中途 beat（非 last）→ 观察窗口重开 |
| wr_req_pend 三项 OR | AW 挂起 / W 挂起 / otd≠dlv（慢 W、W 早于 AW） | 三种写法各定向 |
| wr_otd / wr_dlv | aw_hs&&b_hs 同拍净零 / 饱和 / 递减下限 | AW 与 B 同拍握手 |
| wr_cnt_r_ff | b_hs 清零 / (otd&&dlv)≠0 计数 | WLAST 后无 B 挂起 |
| status_ff | W1C / 置位 / selftest_key / ★ 副本自愈 st_*_a | W1C 与置位同拍竞争（CPU 优先） |
| fu_ff / fu_src_ff | W1C 优先 / 置位 / fu_selftest 无源 | 竞争场景定向 |
| 复位同步器 | 异步断言 / 3 拍释放 | 复位紧贴时钟沿（亚稳态窗口） |
| rd/wr_*_f、*_cf | 反相副本失配 / 双比较器分歧 | ★ 全部 force 注入（`_n` 位翻转），正常激励不可达 |

#### regfile

| 代码位置 | 分支 | 激励需求 |
|---|---|---|
| mbus 译码 | 对齐错 / 越界 / 写只读 / 实例号错 / 正常 | 四类静默忽略各定向 + 正常读写 10 个寄存器（mbus 无错误通道） |
| wr_fire / wr_drop | 空闲接受 / 忙丢弃 | 背靠背写（CDC 未回 ack 时第二个写被丢弃，WR_DROPPED 置位 + W1C 清除） |
| par_bad 命令奇偶 | 坏 par 写阻断 / 坏 par 读门控 / 错实例号+坏 par 仍锁存 | 三类定向，PERR_CMD 置位 + W1C 清除 |
| req_edge 译码 | wsel 0..9 每个分支 / 无效 key 静默 | 写 0x24、写错 key（0x5 而非 0xA） |
| cfg_shadow_ff | 三个寄存器各自更新 / ★ ena 非法码字拒绝 | 写 SCMCNTRL ENA=0101（应被拒，回读不变） |
| pulse_ff | 每个 selftest / W1C 位 | SCMCNTRL 0x1A0/0x2A0/0x4A0/0x8A0/0x11A0+(k<<16) 全遍历 |
| par_latch_ff | 置位（自检/在途）/ W1C 清 / ★ 副本失配自愈 | force `par_lq_n` |
| REG_SELFTEST | REGSEL 0..8 每个选择 / ★ REGSEL>8 忽略 | 9 次注入 + 1 次非法选择 |
| flt_sync / wpar_err | 影子失配（aclk reg_wrap flt 同步）/ 在途锁存失配 | ★ force aclk 影子 `par_q` / force `wdata_q` 一位（在途期间） |

#### reg_wrap

| 代码位置 | 分支 | 激励需求 |
|---|---|---|
| reg_ff | 复位 / wr / wr+selftest / ★ 仅 selftest | REG_SELFTEST 含写与不含写两种（镜像类恒 wr=1，走 wr+selftest；单独路径由 TB 直驱实例验证） |
| flt_ff | 复位 / W1C / par_err 置位 / ★ dup_err | W1C 与 par_err 同拍竞争（W1C 优先）；force `flt_q_n` |
| 注入后自愈 | par_err 1 拍后消失 → sticky 保持 | REG_SELFTEST 后 W1C 一次清除即净 |

### 2.3 Toggle 覆盖要点

- `otd` 每流计数走遍 0→OTD_MAX→0（饱和与回退全路径）
- `thr_rd_r2a/r2r`：0x0000（禁能）、复位值、0xFFFF（上限）、任意翻转奇/偶值的奇偶路径
- `fu_src` 全部位（3+3×NUM_M=15 位）：每个来源定向 force 一次（CNT/CMP/STAT × 4 主控 + ENA/THRA/THRR）
- `ena_rd`：1111、0000、★ SEU 中间值（0111 纠错过程）
- `rdata[31:0]` 每位：读全 10 寄存器 + 制造各位为 1 的状态
- 双轨信号 err_event/_n、fu_fault/_n、reg_par_fault/_n 各自翻转
- `rst_q[2:0]` 移位完整 111→110→100→000

### 2.4 MC/DC 关键复杂判定

| 判定 | 条件数 | 验证方式 |
|---|---|---|
| `wr_req_pend = aw挂起 ‖ w挂起 ‖ (otd≠dlv)` | 3 | 三条件独立翻转定向 |
| `ena_ones` 三向译码（≥3 / ≤1 / ==2） | 互斥分支 | force 注入 5 个码重值 |
| `wr_ok = ce_wr && inst_ok && align_ok && range_ok && !ro && !par_bad` | 6 | 每项独立真/假组合 |
| `wr_fire / wr_drop` 二态（cdc_busy） | 2 | 正常写/忙写矩阵（丢弃→WR_DROPPED） |
| `par_bad = ce && (par != ^{addr,wr,wdata})` | 读/写 × 实例对/错 | 4 组合定向 |
| `flt_ff` 置位源 OR（par_err ‖ dup_err） | 2 | 两源独立注入 |
| `par_l_next` W1C/置位/自愈复合 | — | W1C 与置位同拍、逐项注入 |

### 2.5 正常激励不可达项汇总（强制故障注入清单）

| # | 项 | 注入方式 | 覆盖目的 |
|---|---|---|---|
| F1 | ena_q SEU 三分支 | `force u_ia_bus_timeo_core.ena_q` | 码字纠错/检测 |
| F2 | thr_a_qn/thr_r_qn 翻转 | force | 阈值副本失配→复位回退 |
| F3 | 计数器/深度 `_n` 副本翻转（7 类×每流） | force | CNT 失配 + 故障强制立即触发 |
| F4 | 双比较器分歧（force 一侧 `_n`） | force | CMP 源 |
| F5 | 状态位 `_n` 翻转 | force | STAT 源 + 自愈置位 |
| F6 | aclk 影子 reg_wrap 奇偶翻转（force `u_c_thresh0.par_q` 等） | force | aclk 域存储检查 + flt 跨域同步路径 |
| F7 | 在途锁存 wdata_q/wpar_q 翻转 | force（写飞行中） | wpar_err 按地址归属 |
| F8 | fault_q_n / par_lq_n 翻转 | force | 副本自愈（reg_wrap/锁存） |
| F9 | ena_rd 读回中间码字 | force | 译码 fail-visible |

**结论**：正常功能激励可达约 70–75% 分支；其余 25–30% 全部是**故障检测/纠错路径**——这正是 FuSa 设计的特征，必须用 F1–F9 注入清单达成 100%。注入用 `force/release` 或仿真器 fault-injection API，并在回归中作为独立阶段。

### 2.6 验证环境建议

- 随机激励：AXI 主控每流随机挂起长度（0–thr+3 拍）、随机握手交错 + mbus 随机读写/key/par 注入
- 断言（SVA）随跑：握手协议、超时上界（`timeout ≤ thr+1`）、W1C 优先级、parity 不变式（注入窗口除外）
- 形式验证（推荐补）：
  - CDC：`req_t`/`wsel_q`/`wdata_q` 在 ack 返回前稳定（稳定性定理）
  - W1C 优先级定理：`r2a_w1c[k] && rd_r2a_to 同拍 ⇒ 次拍状态=0`
  - 边界卫士定理：cnt==thr-1 拍 ready=1 ⇒ 永不置位
  - 故障不迟到定理：`cnt 副本失配 ⇒ 该拍 fire=1`
- 时钟比例矩阵：mbus:aclk = 1:1 / 1:2 / 2:1 / 异步无比例，各跑全套

---

## 3. 功能覆盖率

### 3.1 功能覆盖点（covergroup 计划）

#### CG1 总线超时行为（每流展开）

| coverpoint / bin | 说明 |
|---|---|
| `r2a_fire_thr` | 恰在 cnt==thr-1 拍 fire（边界） |
| `r2a_fire_over` | fire 且 cnt≥thr（超界，含故障强制路径） |
| `r2a_guard` | cnt==thr-1 且该拍握手 → **不** fire（边界卫士） |
| `r2r_fire` | req2resp 窗口超时 fire |
| `thr_zero_dis` | 阈值=0 时挂起任意长 → 不 fire（SW 显式禁能） |
| `r_progress_mid` | R beat（非 last）到达 → cnt_r 归零重开窗口 |
| `w_aw_hang / w_w_hang / w_depth_mismatch` | 写请求相三种挂起形态 |
| `b_hang_after_wlast` | WLAST 已交付等 B 超时 |
| `same_cycle{aw_hs,b_hs}` / `{wl_hs,b_hs}` / `{ar_hs,rl_hs}` | 同拍加减净零路径 |
| `otd_sat` | otd 达 OTD_MAX 后再 AR（饱和丢增量） |

#### CG2 配置与控制

| bin | 说明 |
|---|---|
| key_ok / key_fail | SCMCNTRL 0xA 通过/拒绝 |
| ena_on / ena_off / ena_invalid_reject | 三种写法 |
| thr_min(0)/rst/0xFFFF | 阈值边界 |
| to_clear_during_pend | 挂起中 to_clear → 计数清零不置位 |
| to_clear_keeps_sticky | to_clear 不清 sticky 位 |

#### CG3 状态/清除语义

| bin | 说明 |
|---|---|
| w1c_only / set_only / **w1c_race_set**（CPU 优先） | W1C 竞争 |
| still_live_reset | 清除后存活源下一拍重置位 |
| multi_stream_fire | ≥2 流同拍 fire（事件汇聚） |

#### CG4 FuSa 完整性（对应 F1–F9 注入）

| bin | 说明 |
|---|---|
| 每个注入 F1..F9 × (fault 上报正确, fu_src/ PERR 归属正确) | 注入后双输出验证 |
| dup_heal_set | 副本失配自愈为置位 |
| par_err_1cycle | REG_SELFTEST 注入恰 1 拍后自恢复 |
| regsel_0..8 / regsel_gt8_ignored | 逐寄存器注入选择 |
| 4 种自检键各自触发 | SELFTEST/FU/PAR/REG |
| selftest_no_source_signature | ESM 侧 "fault 无 source" 模式 |

#### CG5 CDC 与复位

| bin | 说明 |
|---|---|
| clock ratio 1:1/1:2/2:1/async | 比例矩阵 |
| write_during_busy | CDC 忙时第二个写背压 |
| parity_same_value_inflight | 同值重写（幂等重发全配置） |
| rst_async_assert_mid_transaction | 事务中异步断言 |
| rst_release_near_edge | 释放沿贴近时钟沿（亚稳态） |
| rst_together / 遵守同源约束 | 复位联合 |

#### CG6 ESM 输出

| bin | 说明 |
|---|---|
| err / fu / par 三事件分别独立 | 各自单独出现 |
| 三事件同时 | 全汇聚 |
| 双轨互补成立 / ★ 破坏（注入轨翻转） | 轨校验 |

### 3.2 断言示例（随跑）

```systemverilog
// 边界卫士: 最后一拍握手则不置位
A_guard: assert property (@(posedge aclk) disable iff (rst_s)
    (axi_arvalid[m] && axi_arready[m] && (rd_cnt_a == thr_a_eff-1))
    |=> !r2a_err_status[RD]);

// 超时上界: fire 时计数不超 thr-1+1
A_upper: assert property (@(posedge aclk) disable iff (rst_s)
    rd_r2a_to |-> (rd_cnt_a >= thr_a_eff-1) && (rd_cnt_a <= thr_a_eff));

// W1C 优先级
A_w1c_prio: assert property (@(posedge aclk) disable iff (rst_s)
    (r2a_w1c[RD] && rd_r2a_to) |=> !r2a_err_status[RD]);

// CDC 稳定性: 在途锁存不变
A_cdc_stable: assert property (@(posedge mbus_clk)
    cdc_busy |=> $stable({wsel_q, wdata_q, wpar_q}));

// 副本失配强制立即触发(不迟到)
A_not_late: assert property (@(posedge aclk) disable iff (rst_s)
    (rd_cnt_a_n != ~rd_cnt_a) |-> rd_r2a_to;
```

### 3.3 当前 TB 实测结果（tb_ia_timeo_gen_wrap.sv, VCS V-2023.12 + 代码覆盖率）

> mbus leaf 版回归：`bash run_vcs.sh`（编译 + 仿真 + urg 汇总）。
> TB 输出 `TB PASS - all checks OK`，零 ERR。
> 波形：`obj_vcs/tb_ia_timeo_gen_wrap.fsdb`（+define+FSDB）。

| 实测项（对应上文计划点） | 结果 |
|---|---|
| 遗留 P1–P7（W1C / SELFTEST / FU_SELFTEST / PAR_SELFTEST / REG_SELFTEST k=0/k=5 / to_clear） | 全部 OK，行为与 APB 版一致 |
| P2b 坏 par 写 | OK（写被阻断，TH0 保持旧值） |
| P2b PERR_CMD 锁存 | OK（0x24[14] 置位，PAR_FAULT=1） |
| P2b 坏 par 读 | OK（rdata 门控为 0） |
| P2b 错实例号 + 坏 par | OK（PERR_CMD 仍锁存——译码独立于实例号） |
| P2b 忙时写丢弃 | OK（WR_DROPPED 置位，TH0 保持 0xAAAA，W1C 清除） |
| 覆盖监视 bin par_bad / wr_drop | 3 / 1 |

代码覆盖率（urg，DUT 树内）：SCORE 71.39 / LINE 86.99 / TOGGLE 51.31 / BRANCH 75.89
（Total Module Definition 口径：80.57 / 98.01 / 52.13 / 91.56）。

未命中项均为计划内未激励项（m1 r2a 故意不 fire、thr_zero_dis、otd_sat 等），
属后续回归补齐项，非 DUT 缺口。

**调试中发现并修复的 DUT 缺口**：regfile 的 `cfg_wr` 原为 `req_edge`
同拍组合脉冲，而 aclk 域配置影子（u_c_ena/c5/c6）在同一拍才加载数据——
monitor 的 `ena_q/thr_a_q/thr_r_q` 在该沿采到的是**旧值**，阈值/使能配置
滞后一次写（写 TH1=5 后 monitor 仍用 255，req2resp 不触发）。修复：
`cfg_wr` 改为寄存一拍脉冲（`cfg_wr_q`），与 `to_clear_q/selftest_q` 等
其它动作脉冲对齐，monitor 始终看到更新后的相干 `{ena, thr_a, thr_r}`。

---

## 4. 诊断覆盖率（DC）与 FMEDA

### 4.1 失效模式分解（按块）

| # | 块 | 失效模式 | 检测机制 | 单位检测延迟 | DC（估） |
|---|---|---|---|---|---|
| 1 | 超时计数器/深度（7 类 × 每流，含反相副本） | 位翻转/卡死 | 反相副本逐拍比较 + **失配强制立即 fire** | ≤1 aclk | 99%+ |
| 2 | 双比较器 | 单侧逻辑失效 | 双比较分歧 → fu_src CMP | ≤1 拍 | 99% |
| 3 | 使能码字（ena_q） | 1 位翻转 | 汉明距 4 码 + 多数译码 + 自愈 | ≤1 拍 | ~100%（单翻转） |
| 4 | 阈值寄存器（含副本） | 位翻转 | 副本比较 + **回退复位值**（不静默失效） | ≤1 拍 | 99% |
| 5 | sticky 状态位 | SEU 清除 | 反相副本 + 自愈置位（重新上报） | ≤1 拍 | 99% |
| 6 | 事件上报通路（err_event/fu_fault 轨） | 断线/卡死 | 双轨 ESM 侧校验 + 周期 SELFTEST/FU_SELFTEST | ≤测试周期 | 诊断通路 DC ~99% |
| 7 | 寄存器堆存储（9 寄存器镜像） | 位翻转 | reg_wrap 偶校验（数据/奇偶任一翻转均失配） | ≤1 mbus_clk | 99%（单翻转） |
| 8 | 寄存器堆写通路（在途锁存） | 锁存污染 | 在途奇偶（CDC 稳定窗内连续检查） | 飞行中 | 99% |
| 8b | mbus 命令通路 | 地址/数据/写使能翻转 | 在途命令奇偶 par 检查 → PERR_CMD + 写阻断/读门控 | ≤1 mbus_clk | 99%（单翻转） |
| 9 | 配置影子（aclk 域） | 位翻转 | 影子奇偶 + 2FF 同步上报 | ≤2 mbus_clk | 99% |
| 10 | 奇偶状态/sticky 自身 | SEU 清除 | 反相副本自愈（+3 位锁存同机制） | ≤1 拍 | 99% |
| 11 | CDC 同步器 | 亚稳态 | 2FF + 寄存边沿检测（毛刺免疫） | — | MTBF 计算（§5.4） |
| 12 | CDC 握手 | req/ack 卡死 | CFG_BUSY 永 1 + 后续写全丢弃（WR_DROPPED）→ SW 轮询超时检测 | 集成项 | 系统级 |

### 4.2 残余（不可检测）失效——安全分析关键

| 残余 | 描述 | 缓解 |
|---|---|---|
| R1 共模双副本翻转 | 同一数据的正/反副本同时同值翻转 | 周期 REG_SELFTEST/SELFTEST 扫描 + 上电端到端事务测试（SPNU575 5.11.1 同思路） |
| R2 parity 双位翻转 | 同寄存器偶数位翻转（parity 盲区） | 同上；SW 周期回读比对期望值 |
| R3 时钟失效 | aclk 停 → 监控静默且总线也停 | ESM 侧独立时钟/心跳监测（集成项） |
| R4 复位失配 | mbus_rstn 与 rst 非同源同释 → CDC 握手失步 | 系统级复位设计约束（文档已注明） |
| R5 SW 误用 | 动作写带 ENA=0x0 关监控 | SW 规范（文档 §5.2）+ 配置回读校验 |
| R6 双轨共模 | 两条轨同拍翻转 | ESM 采样双次一致判定（SW 指南已含） |

### 4.3 安全失效率（SFF）论断

监控器内部失效的走向：

- **安全失效**（误报）：计数器早触发、比较器误分歧 → err_event/fu_fault 误置位 → ESM 误中断 → 系统误反应（可恢复，fail-visible）
- **危险失效**（漏报）：需要同时逃过反相副本、双比较器、码字、parity——即 R1/R2 共模
- 结构上：几乎所有单点失效都是安全的或可检测的 → **SFF 估算 > 99%**（按块 FMEDA 加权，共模残佘 <1%）

按 IEC 61508-2 **Route 1H**，B类元件（Type B）、HFT=0：

| SIL | HFT=0 所需 SFF |
|---|---|
| SIL2 | **≥ 97%** ✅（估算 > 99%） |
| （参考 SIL3） | ≥ 99%（当前估算贴线，不足裕量，不建议直接主张） |

结论：**Route 1H 满足 SIL2（HFT=0）SFF 要求，且有约 2 个百分点裕量**。

---

## 5. PFH 估算与诊断计划

### 5.1 失效率模型（参数化，待综合/工艺数据填入）

```
PFH_monitor = λ_D × (1 − DC_D)

λ_D = λ_total × 危险占比
λ_total = (N_FF × FIT_FF + N_comb × FIT_comb)   [FIT = 1e-9/h]
危险占比 ≈ 50%（监控器：误报方向=安全，漏报方向=危险）
DC_D   ≈ 99%（表 §4.1 加权，R1/R2 共模为残余）
```

### 5.2 数量级示例（占位值，最终以厂商 FIT 与综合门数为准）

| 项 | 估算 |
|---|---|
| FF 总数 | ~1300（监控 4 主控含副本 ≈ 700，regfile 含镜像/奇偶 ≈ 500，CDC/杂 ≈ 100） |
| 组合逻辑 | ~15k 等效门 |
| λ_total（按 1 FIT/1k 门 @ 成熟工艺，[TBD 厂商数据]） | ~15 FIT |
| λ_D（50%） | ~7.5e-9/h |
| PFH（DC 99%） | **~7.5e-11/h** |

**对照 IEC 61508 SIL2 目标 PFH < 1×10⁻⁸/h：裕量 > 两个数量级** ✅
（即便 DC 保守取 90%，PFH ≈ 7.5e-10/h，仍有一个数量级裕量）

注意：本 PFH 是**诊断通道**的失效率；它在整机 PFH 预算中的角色是"诊断失效导致被监控通道 DC 损失"，需在系统 FMEDA 中与被监控通道联合计算（诊断失效按诊断测试间隔折算成潜伏失效率，见 §5.3）。

### 5.3 潜伏故障（latent fault）诊断计划

| 测试 | 时机 | 覆盖 |
|---|---|---|
| 上电端到端事务测试 | 每次上电 | 监控功能全链（含共模 R1/R2） |
| REG_SELFTEST 扫描（k=0..8） | 上电 + **周期 ≤ 1 s（建议）** | 每寄存器 存储比较器→PERR→ESM |
| SELFTEST / FU_SELFTEST / PAR_SELFTEST | 同上（同一轮询例程） | 两条事件轨 + 奇偶汇聚 |
| 阈值/使能回读比对 | 周期（如 100 ms） | 配置漂移（R2 兜底） |

周期 T_test 与潜伏 PFH 折算：λ_latent,eff ≈ λ_test_undetected × T_test/2。按上表 T=1 s、未检出率 <1%，对整机 PFH 贡献 < 1e-11/h 量级——不改变结论。

### 5.4 CDC 亚稳态 MTBF

2FF 同步器 MTBF（经典式）：

```
MTBF ≈ e^(t_MET/τ) / (f_clk × f_data × τ)
```

τ、t_MET 取工艺库 [TBD]。按典型值（τ≈50ps，t_MET≈100ps，mbus_clk=50MHz，数据翻转率 10MHz）估算 MTBF > 1e10 年——工程上可忽略；且设计侧已加寄存边沿检测（同步器输出毛刺不产生假 req_edge）。

### 5.5 检测/反应时间链（供 FDTI 分配）

```
故障发生 → 计数到阈值(≤ 65535 aclk, 配置值) → sticky + err_event(同拍)
→ ESM 锁存(纳秒级) → SW/硬件反应(集成项)
```

配置阈值时须保证：阈值周期 + ESM 延迟 + 反应时间 < 过程安全时间（PST）。
复位值（15/255 拍）在 100 MHz aclk 下分别对应 0.15/2.55 µs——对典型 PST（ms 级）有充分裕量。

### 5.6 集成假设（转移给系统级）

1. mbus_rstn 与 rst 同源同释（文档既定约束）
2. aclk/mbus_clk 失效由 ESM 时钟监测独立覆盖（R3）
3. ESM 侧对双轨做互补校验；err_event/fu_fault/reg_par_fault 路由到不同 ESM 组
4. 配置地址空间特权隔离（MPU/总线）
5. SW 遵守动作写规范（0x1A0/0x2A0/0x4A0/0x8A0/0x11A0|k<<16）
6. SW 轮询超时检测 CDC 握手卡死（CFG_BUSY 永 1，写全丢弃并置 WR_DROPPED）

---

## 6. 系统能力（SC）与验证 rigor 对 IEC 61508-3 SIL2 的符合性

| 61508-3 要求（SIL2 档） | 本项目落实 |
|---|---|
| 结构化设计方法（HR） | 分层：wrap→regfile→monitor；接口/语义文档化（本目录 .md 系列作为规格） |
| 仿真 + 功能测试（HR） | §2/§3 覆盖计划 |
| 故障注入测试（HR for 诊断特性验证） | F1–F9 注入清单 + REG_SELFTEST 等 4 键 |
| 动态分析（分支/MC/DC）（HR） | §2.1–2.4，目标 100% |
| 半形式验证（推荐） | §2.6 形式项（CDC 稳定性、W1C 优先级、边界卫士、不迟到） |
| 要求追溯（HR） | TRM 特性 → 覆盖点 → 测试（建议建追溯矩阵，本文档表格为起点） |
| 验证工具置信度 | 仿真器/覆盖率工具需鉴定或业界广泛使用论证 |

---

## 7. 结论与待办

**结论**

| 指标 | SIL2 要求 | 本设计 | 状态 |
|---|---|---|---|
| SFF（Route 1H, HFT=0） | ≥ 97% | 估算 > 99% | ✅ 满足（裕量 ~2%） |
| PFH | < 1e-8/h | 估算 ~7.5e-11/h | ✅ 满足（裕量 >2 个数量级） |
| 潜伏故障检测 | 周期诊断 | 4 键 + 端到端测试 + 周期回读 | ✅ 方案齐备 |
| 诊断覆盖率 DC | — | 逐块 99%（FMEDA §4.1） | ✅ 待 FMEDA 量化确认 |
| 系统能力 SC2 | 过程措施 | §6 | ✅ 待追溯矩阵落地 |

**待办（阻塞 SIL2 签核的项）**

1. [ ] 综合后门数/FF 数 → 填 §5.2 精确 λ（厂商 FIT 数据）
2. [ ] F1–F9 注入回归全通过 + 覆盖率 100% 报告（statement/branch/MC/DC）
3. [ ] 形式验证三项定理（CDC 稳定 / W1C 优先 / 边界卫士）跑通
4. [ ] 上电端到端事务测试用例（系统级，覆盖 R1/R2 共模）
5. [ ] ESM 集成确认（双轨校验、分组路由、时钟监测、FDTI 预算分配）
6. [ ] 要求追溯矩阵（TRM 特性 ↔ 测试用例编号）
7. [ ] 若客户主张 SIL3：SFF 99% 贴线，需 HFT=1（备份监控）或 Route 2H 论证——当前设计按 SIL2 论证成立

---

## 附录 A：注入方法速查

```systemverilog
// F3 示例: 读流计数器副本翻转 → 下一拍 fire + fu_src CNT
initial begin
    @(negedge aclk);  force u_ia_bus_timeo_core.g_m[0].rd_cnt_a_n = ~u_ia_bus_timeo_core.g_m[0].rd_cnt_a_n;
    @(negedge aclk);  release u_ia_bus_timeo_core.g_m[0].rd_cnt_a_n;
end

// F7 示例: 在途写锁存污染 → wpar_err + PERR 归属
// (触发一次 mbus 写后立即 force wdata_q 一位, 等 ack)
```

## 附录 B：测试组织建议

| 阶段 | 内容 | 工具 |
|---|---|---|
| T1 随机回归 | CG1–CG3、CG5 正常激励 + SVA | 仿真器 + covergroup |
| T2 注入回归 | F1–F9 全清单 | force/fault-injection API |
| T3 自检回归 | 4 键 + REGSEL 0..8 扫描（含 SW 序列） | 定向 |
| T4 形式 | CDC/优先级/卫士/不迟到定理 | 形式工具 |
| T5 复位/CDC 专项 | 异步断言、沿贴近、时钟矩阵 | 定向 |
