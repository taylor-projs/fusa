# apb2mbus — APB3 slave → mbus master 桥设计说明

X7A MCU System / TR4 / MCUSys / FuSa。APB3 从端 (apb_clk) 到 mbus 主端
(mbus_clk = 24 MHz) 的 CDC 桥, 面向 FuSa: 命令在途奇偶 + APB 域 hang
看门狗 + 双轨事件输出。CDC 采用 **MCP 直采结构** (静态数据直采 + 单 bit
toggle 同步, 同步一律例化标准 sync 单元)。

## 1. 接口

| 组 | 信号 | 说明 |
|----|------|------|
| APB3 (apb_clk) | paddr[15:0] / psel / penable / pwrite / pwdata → prdata / pready / pslverr | 标准 APB3 从端 |
| mbus (mbus_clk) | ce / wr / addr[15:0] / wdata[31:0] / par → rdata[31:0] | 主端, 叶端零等待 (组合读/单拍写) |
| 事件 (apb_clk) | hang_evt / hang_evt_n | hang 超时单拍脉冲, 双轨反相送 ESM |

越界实例: `paddr[15:8] ≥ NP` 时不发起 mbus 传输, 立即 pready + pslverr。

## 2. CDC 结构 (MCP: 静态数据直采 + toggle 同步)

数据通路一律直采"静止的电平", 不加同步 FF; 同步 FF 只用于两个单 bit
控制 toggle, 例化标准 sync 单元 (`rtl/sync_2dff.sv` / `rtl/sync_dff.sv`,
FPGA / ASIC 仿真 / ASIC 后端工艺 cell 三分支):

```
APB 域                                mbus 域 24MHz
-------------------------             ------------------------------
acc    = psel & penable               req_flag → sync_2dff → flag_s2
ce_reg : acc 打拍, rdy 当拍清 0                    → sync_dff → flag_s3
req_flag: acc 上升沿翻转 (toggle)     ce_flag: s2!=s3 下一拍置 1, 单拍
保持寄存器: req_fire 当拍锁存             (零等待自完成)
  paddr_q/pwdata_q/pwrite_q/par_q     ce 当拍: 采样 rdata → rdat_cap,
addr/wdata/wr/par 直采保持寄存器 ────────►  翻转 ack_flag
ack_flag → sync_2dff → ack_s2            叶端 ce 拍捕获
         → sync_dff  → ack_s3
rdy = s2^s3 → pready
prdata 直采 rdat_cap ◄────────────────
```

### 2.1 直采安全论证 (MCP 三不变量)

多比特跨域只有"被时钟链逐级采样"才有代际错位; 直采静态电平时, 亚稳态
由**时间**排除 (信号在被采样的时刻前后都不动), 不由 FF 级数排除:

1. **最多一笔在途** (ce_reg 边沿检测 + drain 屏蔽) → 保持寄存器从
   req_fire 到下一笔 req_fire 全程静止;
2. **ce 距 req_flag 翻转 ≥ 3 个 mbus 拍** (flag 同步链传播) → 叶端 ce 拍
   捕获时 payload/par 已静止 ≥ 3 拍; 下一笔 req_fire 必在 rdy (即 ce)
   之后 → ce 拍后也不动。捕获沿前后 ±3 拍无跳变;
3. **rdat_cap 自 ce 拍静止**; rdy (ack 同步链) 距 ce ≥ 2 个 apb 拍 →
   主设备采 prdata 时 rdat_cap 早已静止 (超时/越界/drain 路径输出 0)。

### 2.2 与早期链式版的关系 (演进说明)

早期为与 sysm_msync 同构的链式版 (payload/par 3FF 与 flag 同深度,
rdat 2FF, ack 4FF —— 4FF 是为给 2FF rdat 链让出 1 稳定拍: 两链
aperture 相互独立, ack 早捕 1 拍 + rdat 晚捕 1 拍时 3FF 会让主设备采到
旧 rdat_s2)。引入请求保持寄存器后 payload 与 flag 同沿翻转, 链间存在
**跨代混采的理论窗口** (mbus 采样沿落入两者 clk2q 偏斜窗时, flag 链领先
payload 链一代 → ce 携带旧负载; 且 par 与 payload 同源同深度, 一致落后
时奇偶兜不住)。MCP 直采从结构上消除该窗口 (无链可落后), 并省
~215 FF (payload 3FF + par 3FF + rdat 2FF + ack 1FF)。代价是直采跨域
路径需 SDC 约束 + CDC 工具声明 (§3.5), 窗口极宽, 时序无压力。

ack 回程级数下限说明: rdy 扇出到 pready/ce_reg/wait_ack/drain 四个
消费者, 未解析的 s1 若参与组合 XOR, 同拍采样可能分歧 → 边沿检测必须
"s1 吸收 + s2 解析 + s3 延迟" 三级 (sync_2dff + sync_dff), 不可再少。

## 3. FuSa 机制

### 3.1 命令在途奇偶 (par)

`par_q = ^{paddr, pwrite, pwdata}` 在 req_fire 当拍与 payload **同一沿**
锁存 (APB 域), 与 payload 同为静态直采 → 叶端 ce 拍比对时**必为同一代**
(同一个锁存事件的产物, 无链可落后)。叶端 (edc_regfile / cmm_regfile)
在 ce 拍用收到的负载重组比对, 失配 = 在途 1bit 损坏 → 门掉写 + PERR
(错位写/错实例读来源)。

注意: **par 与 payload 必须同代直达** — 要么都走链要么都直采; 混搭
(一个留链一个直采) 会产生跨代错位 (旧 par 配新 payload), 反而引入
误报/漏报。

保护边界 = req_fire 锁存点之后 (保持寄存器 + 跨域路径 + 广播通路 +
叶端捕获): 保持寄存器在途 SEU = payload 坏 / par_q 好 → 失配检出。
(早期"par 由 paddr_q 在 mbus 采样沿组合生成"的方案对保持寄存器 SEU
漏检 — 同源一致损坏; 已随 par_q 锁存修正。)

### 3.2 APB 域 hang 看门狗 (bus-level hang protection)

mbus 叶端全部零等待, mbus 传输本身永不 hang; 唯一 hang 源是 CDC 链路:
mbus_clk 死/停顿、mbus 域复位卡死、广播通路断 → ack toggle 永不返回 →
pready 永久拉低, CPU 总线挂死。该故障只能在 apb_clk 域检测 (看门狗
计数必须依赖一个对端死掉时仍然存活的时钟), 故做在本桥内而不是各叶端:

- **timeout 强制完成**: req 发出后 ack 未在 HANG_TO 个 apb_clk 内返回
  → 当拍完成该笔 APB (pready=1, pslverr=1), CPU 收 bus error 而不是
  挂死; hang_evt 单拍脉冲 (双轨) 送 ESM。
- **DRAIN 重对齐**: timeout 后被延误的 ack 可能迟到 (如 mbus_clk 抖
  动); 迟到 toggle 若被误认为下一笔的 ack 会造成 rdata 错位 → 进入
  drain: 屏蔽新 req 发起, 新访问立即 pready+pslverr 快速失败, 直到
  迟到 ack 到达被消化, 链路自动恢复正常 (toggle 重新对齐)。mbus 侧
  永久死亡时 drain 保持, 后续访问全部快速 SLVERR, 不 hang。
- **计数器双轨 + 双比较 OR 触发** (同 ia_bus_timeo_core / cmm_regfile
  的看门狗惯例): 任一单点翻转立即强发事件 (fail-visible, 永不漏报)。
- **边界拍保护**: rdy 同拍优先, ack 恰在 timeout 拍返回时按正常完成,
  不误报。

timeout 后该笔访问实际可能已在 mbus 侧生效 (迟到完成) — SW 恢复流程:
收 SLVERR/hang_evt 后对目标寄存器重新读写确认 (与 PCIe completion
timeout 语义一致: 超时 = 完成状态未知)。

### 3.3 超时笔的执行语义与请求保持寄存器

在途的 req toggle **无法撤回** (cancel 信号自己也过不了死掉的时钟域;
等它能过去时请求可能早已被采样) — 超时后 mbus 恢复, 被延误的请求
**一定会迟到完成**, 这与 PCIe completion timeout 语义一致: 超时 =
完成状态未知。设计能做的保证是"迟到完成时动作正确":

- **请求保持寄存器**: req_fire 当拍把 addr/wdata/wr/par 锁存进 APB 域
  保持寄存器, mbus 侧直采保持值而不是活的 APB 引脚 → 迟到 ce 携带
  **原请求负载** (恰好一次, 地址数据正确), 与当时引脚值无关。消除了
  "迟到写携带当前引脚值误写他址"的窗口 (TB T5: T4 之后引脚是别的
  地址/读, 迟到的写仍以原负载落地)。
- **顺序**: drain 保证迟到笔消化完之前没有新请求上路, 不会乱序。
- **SW 约束**: 超时 = 完成状态未知。对幂等目标 (普通寄存器) 重试即
  可; 对非幂等目标 (FIFO push、W1C、清中断类) 重试前必须先读回确认
  原写是否已生效, 防止双写。

### 3.4 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| NP | 2 | mbus 实例数 (地址译码越界判断) |
| AW | 16 | mbus 地址位宽 |
| DW | 32 | 数据位宽 |
| HANG_TO | 64 | hang 看门狗阈值 [apb_clk 拍]。正常往返 ≈ 3 拍 mbus (req 同步链) + 1 拍 ce + 3 拍 apb (ack 同步链); 按最慢 mbus / 最快 apb 折算后留 ≥4× 裕量。默认 64 拍 (mbus 24 MHz / apb_clk ≥ 50 MHz 时约 5×) |

### 3.5 后端 signoff 要求 (MCP 直采的配套)

直采跨域路径必须加 datapath max_delay 约束 (否则后端不检查这些路径;
窗口给得很宽, 时序无压力):

```sdc
# 请求方向: 保持寄存器 -> mbus 域叶端捕获 FF (~2.5 个 mbus 拍)
set_max_delay -datapath_only \
  -from [get_cells {paddr_q* pwdata_q* pwrite_q* par_q*}] \
  -to   [mbus 域叶端捕获 FF]  100
# 返回方向: rdat_cap -> apb 域 prdata 消费 FF
set_max_delay -datapath_only \
  -from [get_cells {rdat_cap*}] -to [apb 域 prdata 消费 FF]  15
```

CDC 工具 (SpyGlass 等): 上述数据声明为 **MCP / quasi-static data**,
enable = 同步后的 ce / rdy; 否则会报"未同步多比特跨域"。

sync 单元分支选择 (rtl/sync_2dff.sv / rtl/sync_dff.sv):

| define | 分支 | 说明 |
|--------|------|------|
| `FPGA` | FPGA | 行为 RTL + ASYNC_REG 属性, Vivado/Quartus 识别为同步器链 |
| `ASIC_SYNCELL` | ASIC 后端 | 例化工艺库 hardened cell; 须同时 `SYNC_2DFF_TECH_CELL=<cell名>` / `SYNC_DFF_TECH_CELL=<cell名>` 注入单元名, 端口映射按工艺库手册调整 |
| (都不定义) | ASIC 仿真 (默认) | 行为模型; GLS 时由网表替代 |

## 4. 验证

`sim/tb_apb2mbus.sv` (VCS 与 iverilog 双过), hang 看门狗专项 +
常时检查, 28 checks 全过 (TB 对 CDC 实现透明, MCP 直采化后原样全过):

| 组 | 内容 |
|----|------|
| T1 | 正常写/读往返 (inst0/inst1), 无误响应, 无 hang 事件 |
| T2 | 越界实例: 立即 pready+pslverr, 不发起 mbus 传输 |
| T3 | mbus_clk 停 (时钟死亡): 当笔 ~HANG_TO 拍后 SLVERR 完成 + hang_evt 单拍脉冲, mbus 侧无 ce |
| T4 | drain 期新访问: 1 拍快速 SLVERR, 不发起 mbus 传输, 无二次事件 |
| T5 | mbus_clk 恢复: 迟到 ack 消化 (drain 自清), 被延误的写迟到生效, 链路恢复正常写读 |
| T6 | hang_evt/hang_evt_n 双轨互补常时检查 |
| T7 | ce 拍命令奇偶 par == ^{addr,wr,wdata} 常时检查 |
| T8 | slave 恢复瞬间立即访问: drain 未释放窗内立即 SLVERR (不挂死); 迟到 ack 消化 (drain 自清) 后访问恢复正常 |

**drain 释放时序** (T8 的重点): mbus_clk 恢复后, 被延误的请求要先走
同步链→ce→ack (~5 个 mbus 拍), ack 再经同步链回 apb 域产生 rdy 脉冲才
清 drain — 即恢复后约 ~25 个 apb 拍 (24MHz mbus / 100MHz apb) 内 drain
仍为 1。**此窗口内的 APB 访问立即 SLVERR (快速失败, 不挂死), 这是设
计语义而不是故障**; drain 自清后的第一笔访问即正常。SW 恢复流程:
收到 SLVERR 后重试即可, 无需额外操作。

本仓相对 `2.parity` 原件的差异:

RTL:
1. **请求保持寄存器** (§3.3): req_fire 当拍锁存 payload, mbus 侧采保
   持值 — 修复"迟到写携带当前引脚值误写他址"的窗口。原件仍是活引脚
   采样。
2. **MCP 直采化** (2026-10-29): payload/par/rdat 去除同步链直采静态
   电平 (三不变量见 §2.1); par 改为 req_fire 同沿锁存 par_q (覆盖保持
   寄存器在途 SEU); ack 4FF → sync_2dff+sync_dff; 同步链一律例化
   sync_2dff/sync_dff 标准单元 (FPGA/ASIC 仿真/ASIC 工艺 cell 三分支)。
   省 ~215 FF; 同时消除"保持寄存器与 flag 同沿翻转导致的链间跨代混采"
   理论窗口 (§2.2)。

TB:
1. **双仿真器兼容**: task 内 `return` → done-flag 退出 (iverilog 不支
   持 task return; VCS 下 `disable task` 不回拷 output 参数)。
2. **HANG_TO 16 → 64**: 16 拍与正常往返 (~17 apb 拍 @ apb 100MHz /
   mbus 24MHz) 零裕量, rdy/timeout 每拍竞争, 各笔随机超时 (T1b/T1c
   即因此失败); 64 = RTL 默认值及 §3.4 的 ≥4× 裕量规则。
3. **T3c 时序对齐**: to_fire 后等 4 拍再查 hang_evt_seen (事件寄存
   1 拍 + seen 锁存 1 拍)。
4. **新增 T8**: drain 释放窗内访问快速失败 + 自清后恢复正常。
