# ESM 设计说明 (esm_core.v)

> 规格: 见同目录 esm-rtl-design-spec.md (RM57 TRM SPNU562A CH16 全提取)。
> 本文只讲"这版 RTL 怎么做的"与"怎么验"。

## 1. 模块参数与接口

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| N_G1/N_G2/N_G3 | 96/32/32 | 三组通道数(TI 布局) |
| LTC_FIXED_L14 | 14'h3FFF | LTCPR 低 14 位硬线值 |

端口(详见 rtl/esm_core.v 头注释):
- vclk/gclk 双时钟; nPORRST(冷)/nRST(暖) 双复位
- err_g1[95:0] / err_g2[31:0] (vclk 域事件脉冲) + err_g3[31:0] (gclk 域, 内部 toggle CDC)
- reg_wr/reg_rd/reg_addr[7:0]/reg_wdata/reg_rdata — 简单同步总线(特权保护在外层)
- esm_lo_irq / esm_hi_irq → VIM; nerror_out/nerror_oe/nerror_in → pad

## 2. 微架构(与规格书 §6 对应)

```
err_g3 (gclk) ─toggle─> 2FF+edge ─> err_g3_sync (vclk 单拍)
err_g1/err_g2 ─────────────────────┐
                                   v
   sr1/sr4/sr7 (G1, 暖保持)   sr2 (暖清+vec自清) + ssr2 (POR-only)   sr3 (暖保持)
        │                          │                                     │
   &ies_b1/4/7 ─┬─ lo_irq(~ilv)    ├──────────── hi_irq(固定) ─────────┤
                └─ hi_irq(ilv)     │                                     │
   &iep_b1/4/7 ───────────────────┴──────────── pin_cond ──────────────┘
                                   │
   向量编码器: G2>G1b1>G1b4>G1b7, 组内 prio_enc(ch0 最高)
     读 IOFFHR → 组合返回当前最高 + vec_rd_pulse 清 sr2 命中位
   LTC: 事件重装 ltcp_val; {ltcp_r[15:14],3FFF} 档位
   nERROR FSM: pin_cond|force 拉低; rel_req&&ltc==0 释放; 计满前不释放(例2)
   EKR: 0 正常 / 5 一次性释放请求 / A force(前置 nerror_in==1)
```

关键实现决定(逐条对应规格 §7 陷阱):
1. **置位优先**: `if (|err) sr <= (sr & ~w1c_mask) | err; else if (w1c) ...`
   —— 同拍冲突时错误不丢、W1C 落空, 下一拍状态位仍在;
2. **SR2 双清除源**(暖复位 / IOFFHR 读 / W1C)在同一 always 内优先级:
   暖复位 > 置位 > vec 清 > W1C;
3. **LTC 重触发**: err_event(本拍新置位, 用 `& ~sr` 边沿检测)重装;
4. **force 前置**: `if (nerror_in) force_mode<=1` —— EPSR=0(有错)时写 A 无效;
5. **EKEY 自动回 0**: rel_req && ltc==0 && !pin_cond 时 ekey<=0;
6. **暖复位选择性保持**: 仅 SR2 有 `if (!nRST) sr2<=0`, 其余寄存器复位链只挂
   nPORRST;
7. **向量读副作用**: ioffh_comb 组合输出, vec_rd_pulse 清 SR2;
   ioffh_r/offl_r 寄存器版本保留(供波形观测"上一读值");
8. **镜像对**: mirror_pair() 函数统一实现 set/clear 窗口语义, 读回同一触发器。

## 3. 波形看点(调试指南)

- `sr*_new` / `err_event`: 一拍脉冲, LTC 重装对齐
- `nr_q`: nERROR 状态机寄存器(拉低/保持/释放三态)
- `ioffh_comb`: 向量编码器实时输出(读时被采样)
- `vec_clr_g2/vec_clr_ch`: SR2 自动清除命中
- `force_mode/rel_req/ekey`: EKR FSM 三状态

## 4. 仿真回归

- `sim/tb_esm_core.v`: T1-T8(见 README 覆盖矩阵), 自检 pass/fail 计数,
  ALL PASS 判定
- WSL: `bash sim/run_iv.sh`(iverilog -g2005)
- VCS: `bash sim/run_vcs.sh`(需 VM ssh; VM_DIR=~/esm)
- 波形: iverilog 版加 `-DUMP_VCD` 未接(如需在 tb 里加 $dumpfile 条件编译)

## 5. 后续迭代(按 spec §9 与 README TODO)

1. LTCP 参数化(timescale 缩比)跑完整时序例 1/2/3 全窗;
2. G3 背靠背事件协议(gclk 锁存+同步);
3. EKR 换 4-bit 码字(d=4, 复用 CMM EN codeword 论证);
4. 覆盖率: VCS -cm line+cond+fsm, 补 bins;
5. 双实例 + nERROR AND pad(TI p315 拓扑)按需加 esm_dual_top.v。
