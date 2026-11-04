# TI RM5x ESM (Error Signaling Module) — RTL 重设计规格书

> 依据: RM57Lx TRM SPNU562A CH16 (p549-573)、RM57L843 datasheet SPNS215C §6.19-6.20
> (p127-133)、RM57 Safety Manual DF-21-1604-02 §4.4/§5.6、既有分析
> esm-self-safety-and-external-monitoring.md。目标是可直接指导 RTL 重做。
> 证据页码全部标注; 推断处显式标记【推断】。

## 1. 功能定位

ESM 是全芯片错误聚合中枢: 收集 ~160 个硬件诊断通道的错误事件, 按严重度分组,
产生三类响应: 低优先级中断、高优先级中断(NMI)、nERROR 引脚拉低(给外部监控器
如 TPS65381)。它只聚合不判决——分类在集成时固定(通道→组映射硬连线), 响应
策略软件可配(G1)或固定(G2/G3)。

**核心数字** (TRM 16.1.1):
- 160 通道 = G1×96 + G2×32 + G3×32
- G1: 低严重度, 可配中断 + 可配 nERROR 影响
- G2: 高严重度, 固定高优先级中断 + 固定 nERROR 拉低
- G3: 最高严重度, **无中断**(保留给 CPU 自身诊断, 直接 abort 到 CPU), 固定
  nERROR 拉低
- ESMSR1(G1 状态)无论中断使能与否都会置位(诊断可见性优先)

## 2. 顶层接口定义 (RTL port list)

```verilog
module esm #(parameter N_G1 = 96, N_G2 = 32, N_G3 = 32) (
    // ---- 时钟/复位 ----
    input  wire vclk,            // 外设时钟: 寄存器接口 + LTC 计数 (TRM Fig16-3)
    input  wire gclk,            // CPU 时钟: CPU 域错误输入采样 (Fig16-3 双时钟)
    input  wire nPORRST,         // 冷复位: 清所有寄存器 + nERROR 高阻
    input  wire nRST,            // 暖复位: 不清 SR1/4/7、SSR2、SR3、EPSR (TRM 16.2.1)

    // ---- 错误输入 (通道级, 来自各 IP 诊断) ----
    input  wire [N_G1-1:0] err_g1,   // error_group1[95:0]  (脉冲或电平→内部锁存)
    input  wire [N_G2-1:0] err_g2,   // error_group2[31:0]
    input  wire [N_G3-1:0] err_g3,   // error_group3[31:0] (CPU abort 类, gclk 域)

    // ---- 寄存器总线 (TI 用 CPU 私有外设总线, 重做可用 APB/LB) ----
    //   特权写: 所有写寄存器仅特权模式生效 (R/WP)
    input  wire        reg_wr, reg_rd,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output wire [31:0] reg_rdata,

    // ---- 中断输出 → VIM ----
    output wire esm_lo_irq,      // 低优先级中断线 (G1 映射到低电平线的通道)
    output wire esm_hi_irq,      // 高优先级中断线 (G2 固定 + G1 配成高的通道)

    // ---- nERROR 引脚 ----
    output wire nerror_out,      // 至 pad: 0=active(故障)
    output wire nerror_oe,       // pad 输出使能: nPORRST 期间=0(高阻) (TRM 16.2.1)
    input  wire nerror_in        // pad 回读 → ESMEPSR (TRM 16.4.10, 图上经
                                 //   PINMMR174[16] 选 nERROR/nERROR1, TRM p315)
);
```

【推断标注】TRM 未给端口级 RTL; gclk/vclk 划分来自 Fig16-3 时钟标注(寄存器
接口+VCLK、CPU clock GCLK 同时出现), err_g3 来自 CPU 域需 CDC 是合理推断;
输入脉冲/电平语义 TRM 未明说, 从"error flag 锁存+W1C 清除"模型推输入为事件
脉冲(内部锁存为电平), CCM-R5F 章的"ERROR pulse to ESM"用词佐证。

## 3. 通道→组映射 (集成契约, RM57L843 实例)

完整表在 datasheet Table 6-45 (已抽取到 /tmp/rm57/esm_channels.txt)。
关键条目(重设计时替换成自己 SoC 的诊断清单):

| 组 | 代表通道 | 语义 |
| --- | --- | --- |
| G1 | 1.26 CPU cache 可纠错, 1.72-75 DCAN1-4 SEC, 1.76-80 MibSPI1-5 SEC, 1.30/31 DCC1/2 错误, 1.31/91 CCM 自检/工作状态, 1.69 DMA 总线奇偶, 1.90 SCM 超时 | 可恢复/需统计, 中断处理 |
| G2 | 2.1 CCM CPU 比较错误(lockstep mismatch), 2.6 L2RAMW type B 不可纠错, 2.19 L2FMC OTP 读双比特, 2.20 EPC 不可纠错, 2.23 RTI_WWD_NMI, 2.24 CCM VIM 比较, 2.25 CPU1 AXIM 总线监视器, 2.27 CCM 电源域监视 | 严重, NMI + nERROR |
| G3 | 3.0 eFuse autoload 错, 3.2 L2RAMW 双比特 ECC, 3.11 互连诊断错误, 3.12 L2FMC 地址奇偶/超时, 3.13 L2RAMW type A, 3.14 L2RAMW 地址/控制奇偶, 3.16 L2FMC 空闲命令奇偶, 3.17 CPU 全部 fatal 事件(EVNTBUS 0x60/0x61/0x71...) | CPU 已 abort, 只需 nERROR 通知外部 |

Datasheet §6.20 Table 6-46 同时定义了"错误源→响应→ESM 通道"三联映射
(如 MPU violation→Abort→N/A 不过 ESM; ECC DED→Bus Error+ESM 3.3;
G2 类→ESM=>NMI), 这张表就是集成时的 golden 合同。

## 4. 寄存器映射 (基址 0xFFFF_F500, TRM Table 16-2)

| 偏移 | 名 | 全称 | 访问 | 复位值 | 作用域 |
| --- | --- | --- | --- | --- | --- |
| 00h | ESMEEPAPR1 | Enable ERROR Pin Action 1 | R/WP | 0 | G1 ch0-31 |
| 04h | ESMDEPAPR1 | Disable ERROR Pin Action 1 | R/WP | 0 | G1 ch0-31 |
| 08h | ESMIESR1 | Interrupt Enable Set 1 | R/WP | 0 | G1 ch0-31 |
| 0Ch | ESMIECR1 | Interrupt Enable Clear 1 | R/WP | 0 | G1 ch0-31 |
| 10h | ESMILSR1 | Interrupt Level Set 1 | R/WP | 0 | G1 ch0-31 |
| 14h | ESMILCR1 | Interrupt Level Clear 1 | R/WP | 0 | G1 ch0-31 |
| 18h | ESMSR1 | Status 1 | R/W1CP, X/0 | 0 | G1 ch0-31 |
| 1Ch | ESMSR2 | Status 2 | R/W1CP-0 | 0 | G2 ch0-31 |
| 20h | ESMSR3 | Status 3 | R/W1CP, X/0 | 0 | G3 ch0-31 |
| 24h | ESMEPSR | ERROR Pin Status | R-X/1 | 1(bit0) | nERROR 回读 |
| 28h | ESMIOFFHR | Interrupt Offset High | R-0 | 0 | 向量编码见 §6 |
| 2Ch | ESMIOFFLR | Interrupt Offset Low | R-0 | 0 | 同上 |
| 30h | ESMLTCR | Low-Time Counter | R-3FFF | 0x3FFF | LTC 当前值 |
| 34h | ESMLTCPR | LTC Preload | R/WP(仅[15:14]可写!), R-[13:0]=3FFF | — | 低电平时间 |
| 38h | ESMEKR | Error Key | R/WP | 0 | 0/5/A 语义 §7 |
| 3Ch | ESMSSR2 | Status Shadow 2 | R/W1CP, X/0 | 0 | G2, 仅 POR 清 |
| 40h | ESMIEPSR4 | Influence ERROR Pin Set 4 | R/WP | 0 | G1 ch32-63 |
| 44h | ESMIEPCR4 | (Clear) 4 | R/WP | 0 | G1 ch32-63 |
| 48h/4Ch | ESMIESR4/IECR4 | Int Enable Set/Clear 4 | R/WP | 0 | G1 ch32-63 |
| 50h/54h | ESMILSR4/ILCR4 | Int Level Set/Clear 4 | R/WP | 0 | G1 ch32-63 |
| 58h | ESMSR4 | Status 4 | R/W1CP, X/0 | 0 | G1 ch32-63 |
| 80h-98h | *7 系列 | 同 4 系列 | 同 | 同 | G1 ch64-95 |
| (0x5C-0x7F) | 无 | 未定义窗口 | — | — | — |

要点:
- **Set/Clear 镜像对**: ESMIESRn 与 ESMIECRn 是同一组触发器的两个写窗口
  (写 SET.x=1 置位并自动把 CLR 镜像置 1; 写 CLR.x=1 清零; 写 0 无动作;
  两寄存器读回同值)。同一机制用于 ERROR-pin-influence 对(EEPAPR/DEPAPR,
  IEPSR4/IEPCR4, IEPSR7/IEPCR7)与 int-level 对(ILSR/ILCR)。RTL 实现见 §8。
- W1CP = write-1-to-clear in Privileged; X = 暖复位保持, 0 = POR 复位值。
- **LTCPR 只有 [15:14] 可写**(TRM 16.4.14 Note), 低 14 位固定 3FFF——即
  低电平时间可配档位极少, 防软件误配超短时间; 重做时可改为 key 保护。
- ESMSR2(1Ch) 与 ESMSSR2(3Ch) 是 G2 的双份: SR2 会被暖复位和 IOFFHR 读
  清除, SSR2 只被 POR 清(SM §5.6.3 shadow 机制)。

## 5. 功能行为规格

### 5.1 通道处理 (每通道)
```
err_x[i] 脉冲 → sr_x[i] <= 1 (锁存, 置位优先于任何清除)
G1: 中断使能(IESR) × 通道置位 → 参与对应 level(ILSR) 的 irq 线 OR
    ERROR 影响(IEPSR) × 通道置位 → 参与拉低 nERROR
G2: 置位 → hi_irq 固定 OR 进; nERROR 固定拉低; SSR2 同步置位
G3: 置位 → 仅 nERROR 固定拉低 (无中断)
清除: W1C(特权) 或 (仅 SR2) 读 IOFFHR 命中该通道
```

### 5.2 中断向量 (IOFFHR/IOFFLR, TRM 16.4.11/12)
- 返回当前该电平线上**最高优先级 pending** 的通道号, 读有副作用:
  - 读 IOFFHR 命中 G2 通道 → 清该 ESMSR2 位(SSR2 不清), 向量寄存器更新
    为下一个 pending;
  - 读 IOFFHR/LR 均不清 ESMSR1/4/7/SSR2。
- 编码(高线): 0=无; 01-20h=G1 ch0-31; 21-40h=**G2 ch0-31**; 41-60h=G1
  ch32-63; 81-A0h=G1 ch64-95; 其余保留。低线: 只有 G1 编码段(G2 固定高线)。
- 优先级: **G2 > G1(跨组); 组内 ch0 最高 ch31 最低**。RTL: 固定优先级
  链编码器, G2 段拼接在 G1 bank1 之前。

### 5.3 nERROR 引脚状态机 + LTC (TRM 16.2.2)
```
条件拉低: (G1 置位 & IEPSR) | G2 置位 | G3 置位 | ESMEKR==0xA(forcing)
任一"新失败事件"→ LTC 重装 LTCP 并重新计数 (Example 4: 低电平期间的
  再次失败重启计时窗)
t_ERROR_low = T_vclk × (LTCP + 1)   // LTC 16-bit 预装倒计数, VCLK 触发
LTC 计满且 release 已请求(ESMEKR 写过 5) → nERROR 释放回高, EKEY 自回 0
POR: 引脚高阻(oe=0); 暖复位: 引脚保持当前态不变(pull-down disabled)
EPSR=pin 回读(nerror_in), POR 后=1, 暖复位不变
```
6 个时序例子(TRM Fig16-4..9)归纳: 无 release 则低到 POR; release 早于
t_low 到期→到期即释放; release 晚于到期→立即释放; 预写 release 再失败
(例5, 不推荐)→到期即释放; force 模式下失败仍锁存+LTC 复位停止, 退出
force 后若 pending 则 LTC 重新激活拉满窗(例6)。

### 5.4 ESMEKR 键语义 (TRM 16.4.15)
| 写值 | 行为 |
| --- | --- |
| 0h | 正常模式(默认) |
| 5h | 请求 release: LTC 计满后 nERROR 回高, EKEY 自动回 0 |
| Ah | 进 error-forcing: nERROR 立即拉低(不受 LTC), 用于测外部链路 |
| 其他 | 按正常模式处理 |
前置条件: 进 forcing 要求 ESMEPSR==1(功能态无失败), 否则命令被忽略——
防止用 force 掩盖真实错误。force 期间真实失败仍锁存(LTC 复位停计),
退出后完整补一个 t_low 窗。

### 5.5 复位行为矩阵 (TRM 16.2.1)
| 资源 | PORRST | 暖 RST |
| --- | --- | --- |
| 全部配置寄存器 | 默认值 | 保持 |
| ESMSR1/4/7 | 0 | **保持**(且若中断使能, 复位释放即触发 ISR) |
| ESMSR2 | 0 | **清除** |
| ESMSSR2 | 0 | 保持 |
| ESMSR3 | 0 | 保持 |
| ESMEPSR | 1 | 保持 |
| nERROR 引脚 | 高阻 | 保持电平 |

### 5.6 双 ESM 实例 + 引脚复用 (TRM p315, RM57 双核)
- 芯片有 ESM1/ESM2 两个实例; lockstep 模式仅 ESM1 活跃。
- ESM1 的 EPSR 采样源由 PINMMR174[16] 选: 1=nERROR pad 回读(默认),
  0=nERROR1 pad。
- 双实例 nERROR 组合: ESM1 nERROR_OUT 与 ESM2 nERROR2 经 AND 后出 pad
  (图 6-8)。
【重设计裁剪】单核安全岛可砍成单实例; 若保留双实例, AND 组合语义保留。

## 6. RTL 架构草案

```
                 +--------------------------------------------------+
 err_g1[95:0] -->| edge/latch per ch   sr1/sr4/sr7 (W1CP, warm-kept)|
 err_g2[31:0] -->| sr2 (auto-clr by vec rd) + ssr2 (POR-only)       |
 err_g3[31:0] -->| sr3 (warm-kept)          [gclk→vclk 2FF+握手]    |
                 +------------------+-------------------------------+
                                    |
   +---------+  set/clear 镜像对     v
   | regfile |<-> iep/ies/ilc 触发器组 (G1 三 bank ×3 对)
   +---------+        |
        |             v
        |      +---------------+     +----------------+
        +----->| 向量编码器      |---->| hi/lo irq 线    |→ VIM
        |      | G2>G1, ch0>p31 |     +----------------+
        |      +---------------+
        v
   +-----------+   LTCP   +---------------------------+
   | ESMEKR FSM |-------->| LTC 16b 倒计数 (VCLK)       |---+
   | 0/5/A      |         | 事件→重装; 计满&rel→释放    |   v
   +-----------+         +---------------------------+  nERROR_out/oe
                                                   nerror_in → EPSR
```

关键 always 块(伪代码):

```verilog
// 1) 通道锁存 (置位优先; G1 bank1 为例, X=暖复位保持)
always @(posedge vclk or negedge nPORRST)
  if (!nPORRST)                     sr1 <= 32'b0;
  else if (!nRST)                   sr1 <= sr1;          // 暖复位保持
  else if (err_g1_b1 & ~w1c_hit_b1) sr1 <= sr1 | err_g1_b1; // 置位优先
  else if (w1c_hit_b1)              sr1 <= sr1 & ~w1c_b1;

// 2) Set/Clear 镜像对 (以 int enable 为例)
//    iesr 读回 = 触发器值; 写 iesr=1 置位; 写 iecr=1 清零; 写 0 无操作
wire we_set = reg_wr && addr==IESR && priv;
wire we_clr = reg_wr && addr==IECR && priv;
always @(posedge vclk ...) int_en <= we_clr ? (int_en & ~wdata)
                              : we_set ? (int_en | wdata) : int_en;
assign iesr_rdata = int_en;  assign iecr_rdata = int_en;  // 镜像读

// 3) LTC (失败事件重触发)
wire err_event = |((sr1_new_hit & iep1) | sr2_new_hit | sr3_new_hit);
always @(posedge vclk ...)
  if (err_event || force_enter) ltc <= ltcp_q;   // 重装
  else if (ltc != 0 && nerror_active) ltc <= ltc - 1;

// 4) nERROR 释放条件: ltc==0 && release_req && !any_pin_active_err
assign nerror_out = ~(pin_cond | ekey_force);
// 5) 向量编码器: {G2[31:0], G1b1[31:0]} 优先于 G1b4/b7, 组内低位优先
// 6) 读 IOFFHR 副作用: if (vec_sel==G2) sr2[vec_ch] <= 0;  // SSR2 不动
```

CDC: err_g3(CPU/gclk 域)→vclk: 脉冲展宽+2FF+ack 握手(或异步锁存+同步读);
寄存器接口与 VIM 中断在 vclk; nERROR 输出建议寄存一拍防毛刺。

## 7. 设计陷阱清单 (从 TRM 行为反推, 重做必查)

1. **置位优先于 W1C 同拍冲突** (err 与 w1c 同拍 → 保持置位, 丢 W1C);
2. SR2 的**读清除副作用**: 读 IOFFHR 清 SR2 但不清 SSR2/SR1——向量读取
   路径要做成"服务完一个再给下一个"的自动推进;
3. LTC **重触发**(例4): 低电平期间新失败要重装计数器, 不是忽略;
4. force 模式**前置检查** EPSR==1; force 期间失败仍锁存, 退出补窗(例6);
5. EKEY=5 后**自动回 0**(释放是一次性请求, 不是状态);
6. 暖复位**选择性保持**矩阵(§5.5)——RTL 复位树要分 POR 链/暖复位链两组;
7. 向量优先级是**跨组固定** (G2>G1) + **组内 ch 号序**, 与软件配置无关;
8. LTCPR 仅[15:14]可写(防超短配置); 全 0 非法(CYCLES 类比)需 lint 拦;
9. EPSR 读的是**pad 回读**而非内部 nerror_out——pad 级故障(粘连/短路)
   也能被软件发现; 双实例时还有 PINMMR 选择;
10. 寄存器**特权写门控**(WP)对所有配置寄存器统一, 用户态只读。

## 8. 自身安全(谁监视监视器)与验证义务

TI 的答案(esm-self-safety-and-external-monitoring.md 已沉淀):
- ESM 自身不做 lockstep(160 输入复制+自指悖论, 已论证不划算);
- 四层: SSR2(POR-only shadow)/error forcing(boot)/软件注入测试(boot+周期)
  /外部 TPS65381 监视 nERROR+独立 WDG(最终兜底);
- SM §5.6.4: 配置写后读回校验, 且 ESM 地址空间须 MPU 配成
  strongly-ordered non-bufferable(保证写完成再读)。

重做时的验证清单: 6 个 nERROR 时序例子逐一波形对拍、set/clear 镜像读一致
性、向量优先级全序、暖复位保持矩阵、force 前置条件、LTC 重触发、
SR2/SSR2 清除路径分离、双实例 AND 组合。覆盖率目标: 状态机 one-hot、
160 通道至少逐 bank 置位/清除、时序例 1-6 全覆盖。

## 9. 与本仓库既有设计的映射

- edc_top 的 esm_err/fault 双轨 OR/AND 汇聚 = 本文 ESM 的雏形; 差距:
  无分组严重度、无向量编码器、无 LTC 低电平定时、无 key 语义。可按本
  规格升级: err→G1(可配)、fault→G2(NMI+pin)、新增 G3 留给 CPU abort 类。
- ESMEKR 0/5/A 三键 与 1.parity 的 4-bit 码字(1100/0011)思路同源但 TI
  用单 4-bit 值比较, 无码距保护——重做建议换 4-bit 高完整性码字(d=4),
  非法码按正常模式处理(fail-safe), 正好复用 CMM EN codeword 的论证。

## 10. 证据速查

- TRM SPNU562A CH16: 特性 p550, 框图/行为表 p550-551, 复位行为 p552,
  LTC 时序+6 例 p553-554, error forcing p554-555, 初始化流程图 p555,
  寄存器表 p556, 全寄存器 p557-573, ESM1/2+nERROR mux p315
- DS SPNS215C: ESM 概述+通道表 p127-131, 错误源→响应→通道映射 p132-133
- SM DF-21-1604-02: 错误管理架构 p17-18, ESM 安全机制+使用假设 §5.6 p25
- 本仓库: esm-self-safety-and-external-monitoring.md(四层监控+lockstep
  不适用论证), rm57l843-soc-safety-architecture-design.md(系统级)
