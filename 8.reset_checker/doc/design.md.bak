# reset_checker 设计说明 (rst_monitor)

POR 复位双轨检查器：输入同向复制的 `reset_p/reset_m`，内部检查电路产生
`rst_por_n_err`。规格框图来源：rst_monitor 结构图（MKCV 4bit 模式比较 FSM +
fault_inject 门控 + OR + `CNT[4:0]` 滤波计数器 `filt(&cnt)` + DFF 锁存）。

## 1. 功能定义

- 复位经差分对分发到接收端，接收端从两根线各自恢复出**同极性（同向）的
  两个逻辑副本** `reset_p` / `reset_m`（均为低有效：双低 = 复位有效，
  双高 = 释放，正常时二者恒相等，复位到来时同向一起拉低）。
- 检查器监视两副本**一致性**：`p != m` 即分歧（单根线断/短路/卡死/翻转，
  部分电路看到的复位与其它部分不同 → 非对称部分复位，危险）。
- 分歧持续超过滤波窗口 → 置位粘滞 `rst_por_n_err`（送 ESM/FUSA_ERR）。

### 滤波计数器（规格语义）

两轨各自经 **rst_sync wrapper**（复位同步器：**异步断言 / 2FF 释放**——
轨即复位，复位入口语义）后做**异或**：XOR=1 再经第二级 rst_sync
（u_rst_pair）释放计数器自由递增，计到**全 1**（`5'h1F`）后停止计数；
计数器全 1 即产生 `rst_por_n_err`。即分歧需连续 **32 个采样拍**（+pair
2FF 释放；若分歧由对侧轨上升建立，再加该轨 2FF）才告警；短于窗口的
毛刺（轨间偏斜、亚稳态窗口、单拍毛刺）被静默滤除——亚周期分歧根本
不会让 pair 同步器释放。两轨恢复一致时计数器清零（去抖：多次分开的
短毛刺不累积）。

**复位域（规格）**：
- 两轨同步器采用 **rst_sync wrapper**（复位同步器：异步断言 / 2FF 释放，
  标准例化单元，ASIC/FPGA 分支与 sync_2dff 同款）。轨即复位：轨下落 →
  p_s/m_s 立即断言（零延迟），轨上升 → 2FF 对齐释放。同步 FF 的复位取
  **轨自身**而非 `mbus_rstn`——mbus 复位期间监控器仍在岗（fail-visible）；
- **counter 以及 counter-expire 之后的 err 寄存器不用 mbus_rstn**：其异步
  复位 = 原始异或 `rstn_pair = p_s ^ m_s` 再经一级 rst_sync（u_rst_pair）
  得到的 `rstn_pair_s`——两轨一致（XOR=0）时 pair 同步器输出**异步断言**，
  即时清零 counter 和 err（零延迟去抖）；分歧（XOR=1）时经 **2FF 释放**
  计数，计数域复位释放永远时钟对齐（p_s/m_s 断言是异步的，正是这一级
  保证释放沿 recovery/removal 干净）。因此 `rst_por_n_err` 是**活式**输出
  （分歧消失即回 0），SW 侧的粘滞记录由 mbus 域的 EV 事件承担（W1C）。

**边界语义**（自释放态轨下落建立分歧、持续 N 个时钟周期）：≤32 拍静默
滤除；恰 33 拍——计数器在第 33 拍计满，但恢复一致的异步清除先于判定沿
到达，计数与判定一起被淹没（引脚/EV 均无变化）；恰 34 拍——判定沿已
过，EV 锁存取证，但 err 引脚只出现亚周期窄尖（恢复即异步清），引脚不可
见；**≥35 拍**才在引脚上可见（最小可见触发）。

| 状态 (p,m 同步后) | 含义 | 检查结果 |
|---|---|---|
| 0,0 | 复位有效（正常） | 合法 |
| 1,1 | 复位释放（正常） | 合法 |
| 0,1 | 仅 p 轨拉低 → DIV_A | 分歧，计数 |
| 1,0 | 仅 m 轨拉低 → DIV_B | 分歧，计数 |

DIV_A / DIV_B 分别粘滞记录在 EV 寄存器（诊断哪根轨），聚合出唯一的
`rst_por_n_err`。

## 2. 业内做法对照

| 厂商/器件 | 复位监督做法 | 与本设计的关系 |
|---|---|---|
| NXP MPC5744P (BOLERO) | RGSU 复位生成/监督单元，复位以冗余/差分形式分发，接收侧不一致 → FCCu 告警 | **同构**：双轨分发 + 接收侧一致性检查 |
| TI TMS570/RM57 | nRST 引脚毛刺监视（采样滤波窗口，窄于阈值的复位脉冲按毛刺报 ESM 错）；复位源锁存 | 滤波思想相同：持续窗口计数；`rst_por_n_err` 可直接接 ESM 通道（本仓 5.esm） |
| Infineon AURIX TC3xx | SCU 复位请求监督 + 复位配置奇偶保护，异常经 SMU 告警；ESR 引脚支持差分 | 分歧告警走错误信号通道的模式相同 |
| ARM 参考流程 | 复位入口单元（2FF 同步器）+ 独立常开时钟做监督 | 本设计 rst_sync 输出即 p 轨复位同步器（异步断言/2FF 释放），就是复位入口单元语义 |

ISO 26262 角度：
- **故障探测（FHTI/FDTI）**：分歧 → err 延迟 = pair 2FF 释放 + 32 采样拍
  + 1 拍置位 ≈ 34–35 个 mbus_clk（轨下落建立分歧；对侧轨上升建立 +2）。
- **潜伏故障（LFM）**：CTRL.FI 把 m 轨副本异或翻转（任意电平下都能制造
  分歧），开机自检时在复位保持窗口脉冲一次即可证明检查链路（探测+报告）
  完好，系统零代价。
- **寄存器完整性**：所有 SW 可见寄存器带奇偶 + 自检注入 + sticky flt
  反相冗余（heal-to-SET），reg_wrap 一件套（cmm/hang_prot 同款）。

## 3. 结构

```
reset_p -------------> rst_sync --> p_s --+   rstn_pair (raw XOR)
                                          XOR|--------> rst_sync --------> rstn_pair_s
reset_m --[XOR FI]----> rst_sync --> m_s --+  (异步断言,      (分歧=2FF释放,        |
                                              释放=2FF)        一致=异步清零)        |
                                                             CNT[4:0] / err <--------+---> rst_por_n_err (+_n)
                                            div_a/div_b -----------------------> EV.DA/EV.DB/EV.ERR (mbus 域粘滞)
```

- 复位域：轨同步 FF 复位 = **轨自身**（监控器不随 mbus_rstn 静默）；counter
  与 counter-expire 后的 err 寄存器复位 = `rstn_pair_s`（原始异或再经
  rst_sync：一致即时异步清零，分歧 2FF 释放，见第 1 节）。
- 双轨计数器（`cnt` + 反相副本 `cnt_n`，fire = a|b|dup，永不迟到 —— cmm
  看门狗同款）；err / EV sticky 均带反相冗余（SEU 清零自愈回置位）。
- `rst_sync` 输出 = p 轨 rst_sync wrapper 的输出 p_s（异步断言 / 2FF 释放）
  ——本身就是标准复位入口单元，释放沿 recovery-clean，下游直接使用；
  监控滤波不在该路径上（滤波只作用于告警判定）。

### 单时钟域决策（分层说明）

监控引擎与 regfile **同跑在 mbus_clk**（安全岛常开总线时钟），无 CDC 握
手。理由：本模块职责是**复位轨对**的完整性；mbus_clk 自身的活性由 CMM
层（时钟监视器）负责，正如 cmm_regfile 的 mbus 侧大脑活性论证。若集成
时采样时钟必须独立于 mbus_clk，再加一级 cmm 式 toggle 握手（预留扩展，
见第 8 节）。

## 4. 接口

| 端口 | 方向 | 说明 |
|---|---|---|
| mbus_clk / mbus_rstn | in | 常开采样时钟 / 监控器自身复位（**不得取自被监控轨的下游**） |
| ce, wr, addr[15:0], wdata[31:0], par | in | mbus 叶子（apb2mbus 协议；addr[15:8]=IDX 实例号；par=^{addr,wr,wdata} 命令在途奇偶） |
| rdata[31:0] | out | 组合读，未选中/坏奇偶时为 0 |
| reset_p, reset_m | in | 被监控的同向复制复位轨（异步，低有效） |
| rst_por_n_err / _n | out | 分歧告警（高有效，活式：恢复一致自动清 0）+ 反相轨 |
| rchk_par_fault / _n | out | 寄存器奇偶/命令奇偶完整性事件 |
| rst_sync | out | p 轨经 rst_sync（复位同步器：异步断言/2FF 释放）后的输出，下游复位入口直接使用；同步 FF 复位 = 轨自身 |
| scan_mode | in | DFT：1 = 监控器收拢到单一控制点 reset_p——rst_sync 单元输出 mux 选原始轨、m_g 强制随 p（分歧恒 0，输出静默）、pair XOR 重定义为 reset_p（viol 域复位经主输入直接可控、不经 2FF）；同步 FF 照常挂链，监控功能在 scan 下无定义 |

## 5. 寄存器详细说明

### 5.1 访问通用规则

- **寻址**：addr[15:8] = IDX 实例号（不匹配 → 整体不选中，读写忽略，
  不误报 REG_PROT）；addr[7:0] = 字节偏移；addr[1:0] 由上游 apb2mbus
  桥保证 00（word 对齐）。
- **命令在途奇偶**：par = ^{addr, wr, wdata}，ce 拍检查，读/写命令一律
  校验。坏命令 → 写阻塞、读回 0、PERR_CMD 锁存（在 keyed 检查之前拦
  截，不会连带 REG_PROT）。
- **读**：组合逻辑当拍返回；未选中或坏奇偶 → 0；未知偏移读 → 0（读
  不触发写保护）。
- **写**：wr_ok = 选中 && wr && 奇偶好，单拍有效。
- **keyed**：CTRL / REGST 需 wdata[31:28] = WKEY（4'h5），无键写整体
  拒绝并锁 REG_PROT。
- **写保护**（锁 REG_PROT，写整体拒绝）：写 RO（ID/STAT）、写未知偏
  移、keyed 寄存器无键写、CTRL 非法 MODE 值。
- **W1C 通用语义**：清除当拍 CPU 优先；**活源仍在则下一拍重置**——
  W1C 永远无法掩蔽物理上仍存在的故障源（EV.ERR 的活源 = 分歧仍在且
  计满；REGPAR wrap 位的活源 = 存储 parity 仍坏）。

### 5.2 寄存器一览

| 偏移 | 寄存器 | 属性 | 复位值 |
|---|---|---|---|
| 0x00 | ID | RO | 0x5243_0001 |
| 0x04 | CTRL | keyed RW | 0x1（MODE=NORMAL one-hot，fail-safe 在岗） |
| 0x08 | STAT | RO（实时镜像） | 跟随实时态，空闲 0x200 |
| 0x0C | EV | W1C | 0x0 |
| 0x10 | REGPAR | RO/W1C | 0x2（bit1 fault_n=1） |
| 0x14 | REGST | keyed WO（读恒 0） | — |

### 5.3 ID（0x00，RO）

只读标识 "RC" v1 = 0x5243_0001；任何写 → REG_PROT。

### 5.4 CTRL（0x04，keyed RW）

EN/FI 配置为 **4bit one-hot MODE 字段**（非两个独立 bit）：独立 bit 下
`(EN=0, FI=1)`（注错进行、告警被掩 = 静默破坏）是合法态——one-hot 编码
从结构上让它**不可表达**；且单 bit 翻转必落非法码（译码级防错，与
reg_wrap 的存储级 parity 互补）。

| MODE[3:0] | 译码 | 说明 |
|---|---|---|
| 4'b0001 NORMAL | EN=1 FI=0 | 监视在岗（**复位值**，fail-safe） |
| 4'b0010 INJECT | EN=1 FI=1 | m 轨副本异或翻转（m_g = reset_m ^ FI），任意轨电平下制造分歧——检查链路潜伏故障自检；应在复位保持窗（轨双低）脉冲，系统零代价 |
| 4'b0100 OFF | EN=0 FI=0 | 掩判定与 DA/DB 事件（计数器仍由轨 XOR 释放/清零，滤波器不关） |
| 其它（非法） | — | **写整体拒绝 + 锁 REG_PROT**（与写保护同类，SW 造成的编码字段违规）；存储不可达，译码后备 = fail-safe NORMAL（EN=1 FI=0，绝不注错） |

存储为**配置保持型** reg_wrap（u_ctrl，wr 仅来自带键且合法 MODE 的 CTRL
写）：parity 错只坏检查位、data 永不坏；注入后恢复 = 带键重写 NORMAL
（流程与顺序约束见 5.9）。上电 NORMAL：fail-safe，监视默认在岗。

### 5.5 STAT（0x08，RO 实时镜像）

| 位 | 字段 | 说明 |
|---|---|---|
| 0 | viol | 实时分歧 p_s ^ m_s（2FF 同步后视图） |
| 1 | div_a | 仅 p 轨拉低（m 副本漏复位） |
| 2 | div_b | 仅 m 轨拉低（非对称部分复位） |
| 3 | cnt_full | 滤波计数饱和（cnt == 5'h1F，裸指示，不受 EN 门控） |
| 8:4 | cnt | 分歧持续计数；两轨恢复一致即经 rstn_pair_s 异步清零（短毛刺不累积） |
| 9 | EN | MODE 译码镜像（NORMAL/INJECT=1，OFF=0） |
| 10 | FI | MODE 译码镜像（仅 INJECT=1） |

读出为 u_statimg 镜像 wrap（wr≡1 每拍跟随，滞后一拍视图），带奇偶保
护；写 → REG_PROT。

### 5.6 EV（0x0C，W1C）

| 位 | 字段 | 性质 | 说明 |
|---|---|---|---|
| 0 | DIV_A | 粘滞 | div_a 类分歧事件（诊断：哪根轨） |
| 1 | DIV_B | 粘滞 | div_b 类分歧事件 |
| 2 | ERR | 判定粘滞 | 滤波触发（filt_fire）即锁存——err 引脚是活式的（恢复一致自动清），本位是 SW 侧的取证记录；W1C 清，分歧仍在（计满）则下一拍重置 |

三位粘滞都在 mbus 域（复位 = mbus_rstn）：轨恢复一致后仍保留供 SW 取
证，仅 W1C 清（ERR 与 DA/DB 同拍由各自 W1C 位清除）。读出为 u_evimg
镜像（每拍跟随 {ev_err, ev_db, ev_da}）；W1C 写生成单拍清除脉冲作用
于引擎 sticky，镜像下一拍跟随。

### 5.7 REGPAR（0x10，RO + W1C）

| 位 | 字段 | 源 | W1C | 说明 |
|---|---|---|---|---|
| 1:0 | {fault_n, fault} | rchk_par_fault 双轨回读 | — | 干净时 = 2'b10；ESM 完整性事件 = wrap flt、PERR_CMD、PAR_SELFTEST 任一（REG_PROT 不上轨：保护违规≠完整性故障） |
| 4 | CTRL wrap | u_ctrl.flt | ✓ | 配置保持型：注入后 parity 保持坏，恢复 = 重写 CTRL（顺序见 5.9） |
| 5 | EV image | u_evimg.flt | ✓ | 跟随型：注入下拍自愈，W1C 即净 |
| 6 | STAT image | u_statimg.flt | ✓ | 同上 |
| 16 | PERR_CMD | 命令奇偶锁存 | ✓ | 任何命令在途奇偶错（写阻塞 + 读 0） |
| 17 | PAR_SELFTEST | 自检锁存 | ✓ | REGST[9] 无源注入锁存 |
| 18 | REG_PROT | 写保护锁存 | ✓ | 写 RO / 未知偏移 / 无键 keyed 写 / 非法 MODE 值 |

wrap flt（[6:4]）与本地 sticky（[18:16]）均带反相冗余：SEU 清零自愈
回置位（heal-to-SET）。其余位保留，读 0。

### 5.8 REGST（0x14，keyed WO，读恒 0）

| 位 | 字段 | 说明 |
|---|---|---|
| 4:0 | TGT | 注入目标 wrap：0=CTRL（配置保持型）1=EV image 2=STAT image；>2 静默忽略（不算保护违规） |
| 8 | INJ | 1 = 对 TGT wrap 发单拍奇偶注入（翻转 par_q；data 永不损坏） |
| 9 | PASS | 1 = 无源注入：仅锁 PAR_SELFTEST 并上 fault 轨，不真坏任何 parity（证明锁存+上报链路） |

INJ 与 PASS 可同拍复合。

### 5.9 奇偶自检流程（**顺序硬性：先修复、后 W1C**）

1. `REGST = KEY|0x100`（CTRL 注入）→ REGPAR[4]=1，fault 轨起；
2. `CTRL = KEY|01` **先重写**恢复 parity（flt 粘滞仍为 1）；
3. `REGPAR = 0x10` **后 W1C** → [4]=0，轨落，干净；
4. `REGST = KEY|0x101` / `KEY|0x102`（镜像注入）→ 下拍自愈 →
   `REGPAR = 0x20` / `0x40` W1C；
5. `REGST = KEY|0x200`（无源）→ REGPAR[17]=1 → `REGPAR = 0x2_0000` 清。

顺序为什么硬性（W1C 先于重写 = 无效修复，正是"活源重置"语义的体现）：
- W1C 后不重写：flt 下一拍重置并保持（parity 仍坏 = 活源在）；
- W1C 后紧跟重写也不行：重写拍 par_err 仍按旧存储态计算 → flt 重置 →
  parity 已好但 sticky 卡 1，须再补一次 W1C。
镜像 wrap（步 4）无此约束：wr≡1 下拍自愈。

## 6. 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| WKEY | 4'h5 | keyed 寄存器键值 |
| IDX | 0 | mbus 实例号（addr[15:8]） |
| SAT_VAL（内部常量） | 5'h1F | 计数全 1 饱和值（滤波窗口 = 32 采样拍，规格固定，不可配） |
| rst_sync.SYNC_LVL_NUM（例化单元） | 2 | 复位同步器级数（≥2：一级亚稳吸收 + 一级解析），本设计三处例化均为 2 |
| rst_sync.DEF_VAL（例化单元） | 1'b0 | 断言期间输出值（低有效复位；释放值 = ~DEF_VAL） |

## 7. 验证（tb_reset_checker，109 checks）

| 相位 | 覆盖 |
|---|---|
| P1 启动 | ID/STAT/CTRL/EV/REGPAR 复位值；err 双轨空闲；rst_sync 跟随 |
| P2 写保护 | 无键/RO/未知偏移 → REG_PROT；W1C |
| P3 EN 门控 | EN=0 掩掉判定与事件（计数器仍由轨 XOR 释放）|
| P4 偏斜吸收 | 双向 7ns 轨间偏斜（释放→DIV_B 瞬态、有效→DIV_A 瞬态）不误报 |
| P5 DIV_A | 持续分歧告警；延迟 = pair 2FF+32+1 ≈ 34–35 拍；活源 W1C 重置；EV=101 |
| P6 DIV_B | 对称轨故障；EV=110 |
| P7 滤波边界 | 2/3 拍毛刺滤除；33 拍计满但被恢复异步清淹没（引脚/EV 皆无）；34 拍 EV-only（判定锁存、引脚仅亚周期尖）；35 拍最小可见触发 |
| P8 FI 自检 | 复位窗口内 FI 翻转 m 轨 → 告警（潜伏故障证明） |
| P9 寄存器奇偶 | CTRL 配置型注入→重写恢复；EV/STAT 镜像自恢复；无源锁存 |
| P10 命令奇偶 | 坏奇偶写阻塞 / 读 0 / PERR_CMD |
| P11 实例译码 | addr[15:8]≠IDX 读写忽略、不误报 REG_PROT |
| P12 自愈+自动清 | EN=0 掩源下 force SEU 清 err → 反相冗余 heal-to-SET 重报；恢复一致 → XOR 复位自动清 0 |
| P13 随机流量 | 100 轮随机电平+随机偏斜（0–30ns）无误报 |
| P14 译码/保护边界 | EV 部分位 W1C（只清 DA 留 ERR）；无键 REGST → REG_PROT；TGT>2 注入静默忽略；高实例号译码读 0 |
| P15 冗余 force | cnt_n/cnt 单轨污染即触发；sat_a/sat_b 单独饱和臂触发；ev_da/ev_db/ev_err/lst 反相冗余 SEU 清零自愈回置位 |
| P16 复位重断言 | FI 于释放轨（m_g=1^1 组合）；mbus_rstn 重断言 → CTRL fail-safe 重载、EV/REGPAR 清、ID 可读 |
| P17 冗余自愈扩展 | 早期 cnt dup（未饱和先触发）；u_ctrl/u_evimg/u_statimg wrap 反相轨 force → dup_err 自愈置位 REGPAR[4]/[5]/[6] → W1C 清（parity 未坏，无需重写） |
| P18 DFT scan | scan_mode：同步器 Q 输出 mux（0=2FF q，1=原始 rstn）；m 强制随 p（reset_m 无视、分歧恒 0）；viol 域复位 = 原始 reset_p（计数器即刻可控）；退出 scan 后 2FF 语义完整恢复 |
| P19 MODE 编码 | 非法 MODE（0x3/0xF）写拒绝 + REG_PROT + 存储不变；OFF/NORMAL 译码与 STAT 镜像 |

运行（VM）：`cd ~/work/rst_checker/sim && ./run_vcs.sh`（`cov` 模式出覆
盖率；Verdi 用 `./run_verdi.sh`）。覆盖率（`tgl_struct_excl.el` 结构排
除后）：SCORE 96.12 / LINE 95.28 / COND 99.21 / **TOGGLE 100.00**（双
域）/ BRANCH 90.00；BRANCH/COND 残缺均为结构死支（镜像 wrap wr≡1、单
总线 selftest×write 互斥、`filt_fire` 双轨 OR 单热死臂——cnt_dup=0 时
sat_a≡sat_b）。

## 8. 集成注意事项

1. **监控器自身复位**（mbus_rstn）必须来自被监控轨上游的常开 POR，绝不
   可从 reset_p/reset_m 的下游分接 —— 否则轨卡死时检查器一起被复位，无
   法报告。
2. FI 自检应在复位保持窗口（轨双低）脉冲；此时注入对系统零代价。
3. `rst_por_n_err` 接 ESM（5.esm）的一个通道；`rchk_par_fault` 接独立
   的完整性通道（勿与功能告警合并）。
4. `rst_sync` = p 轨复位同步器输出（异步断言/2FF 释放，FF 复位取轨自身），
   即标准复位入口单元：释放沿时钟对齐（recovery-clean），下游直接作复位
   入口使用；监控滤波只作用于告警判定，不在该路径上。
5. 若集成需要采样时钟独立于 mbus_clk：在 cfg（CTRL）路径上加 cmm 式
   one-at-a-time toggle 握手 + 在途载荷奇偶（PERR11 同款），引擎部分不
   变。
