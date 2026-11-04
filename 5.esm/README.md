# ESM (Error Signaling Module) 重设计 — rtl/doc/sim

> 依据 RM57 ESM 规格书(esm-rtl-design-spec.md)实现的参考 RTL。
> 目标结构 1:1 对齐 TI TRM SPNU562A CH16 行为。

## 目录

```
esm/
├── rtl/
│   └── esm_core.v        # 核心模块 (160ch: G1x96 + G2x32 + G3x32)
├── doc/
│   ├── design.md         # 本设计说明(接口/架构/与TRM差异)
│   └── esm-rtl-design-spec.md  # 上游规格书副本
└── sim/
    ├── tb_esm_core.v     # 自检 testbench (T1-T8)
    ├── run_iv.sh         # WSL iverilog 快速回归
    └── run_vcs.sh        # Rocky VM VCS 回归 (ssh 到 VM 执行)
```

## 快速开始

WSL 本地(iverilog, 秒级):
```
bash sim/run_iv.sh
```

Rocky VM(VCS, 需 VM ssh 可达):
```
bash sim/run_vcs.sh          # 默认同步 ~/esm 到 VM 并跑 vcs
USER=xxx HOST=1.2.3.4 bash sim/run_vcs.sh
```

## 设计覆盖矩阵 (tb → TRM 行为)

| TB | TRM 依据 | 验证点 |
| --- | --- | --- |
| T1 | 16.4.7/11 | 置位/G2>G1 向量优先级/组内 ch0 高/中断线 |
| T2 | 16.4.3-4 | Set/Clear 镜像对读写一致性 |
| T3 | 16.2.2 例1/2 | 无 release 持续低; 请求后未到期保持低 |
| T4 | 16.2.2 例4 | 新失败 LTC 重装 |
| T5 | 16.2.3 例6 | force 前置 EPSR=1; 退出补窗; EKEY 自动回 0; 有错时 force 被拒 |
| T6 | 16.2.1 | 暖复位矩阵: SR1/SSR2/SR3/EPSR 保持, SR2 清, nERROR 电平保持 |
| T7 | 16.4.11 Note | IOFFHR 读清 SR2, 不清 SSR2/SR1; 低线向量 |
| T8 | 16.4.14 | LTCPR 仅 [15:14] 可写, 低 14 位固定 3FFF |

## 与 TI 原版差异(裁剪说明)

1. 寄存器接口用简单 wr/rd 总线(TI 是 CPU 私有外设总线), 特权保护由总线侧做;
2. nERROR1/ESM2 双实例未实现(单实例); 需要时复制例化+AND pad 逻辑(TRM p315);
3. LTC 计满时间 = LTCP × T_vclk, 档位 {00,01,10,11}×3FFF 补码——与 TI 一致;
   仿真里 3FFF@10ns≈328us, 时序例 1-3 的完整窗口在 tb 中用截面验证;
4. EKR 键无码距保护(与 TI 一致); 生产建议换 4-bit 码字 d=4(见 spec §9)。

## 已知限制 / TODO

- [ ] ltc 计满释放的完整时序例(例2/3 全窗)需 timescale 加速版 tb(参数化 LTCP)
- [ ] G3 CDC 用 toggle 握手, 未覆盖背靠背 gclk 事件(< 2 vclk 间隔会丢)——
      TRM 未定义, 自研需补充协议(建议: gclk 域先锁存再同步置位)
- [ ] 代码覆盖率(bins)待 VCS 跑出后补
