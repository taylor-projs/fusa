# 8.reset_checker — POR 复位双轨检查器 (rst_monitor)

输入同向复制的复位双轨 `reset_p/reset_m`（低有效，正常恒相等），检查分
歧（`p != m`，单轨断/短/卡死 → 非对称部分复位）：rst_sync 复位同步器
（异步断言/2FF 同步释放）同步两轨后异或，XOR=1 经 2FF 释放 `CNT[4:0]`
自由计数，计到全 1（32 采样拍）饱和并产生 `rst_por_n_err`（+反相轨，送
ESM）。复位域（规格）：轨同步器复位 = 轨自身（mbus 复位期间监控器存
活）；counter 与 counter-expire 后的 err 寄存器复位 = 两轨异或再经
rst_sync 的 `rstn_pair_s`（一致异步即时清零、分歧 2FF 释放、恢复一致自
动清除，引脚为活式；SW 粘滞记录在 EV）。配置/状态走 mbus 叶子
（apb2mbus 协议，键控写 + W1C + 寄存器奇偶 + 命令奇偶 + FI 自检）。

设计细节见 [doc/design.md](doc/design.md)（含业内对照：NXP MPC57xx 差
分复位分发、TI nRST 毛刺监视、AURIX SCU）。

结构（与 cmm/hang_prot 同款 LEON two-process + reg_wrap 一件套）：

```
rtl/
  reset_checker_core.sv     check 核心：rst_sync/XOR/饱和计数/err+自愈/事件粘滞
  reset_checker_top.sv      顶层：core 例化 + regfile 实例 + mbus/输出端口
  reset_checker_regfile.sv  mbus 叶子：CTRL/STAT/EV/REGPAR/REGST + 写保护 + 奇偶组
  (rst_sync.sv / sync_2dff.sv / reg_wrap.sv 移至 fusa 根 common_modules/,
   经 filelist 引用; regfile 仍例化 reg_wrap/rst_sync)

doc/
  design.md                 设计说明（功能/业内对照/结构/寄存器/验证矩阵/集成约束）
sim/
  tb_reset_checker.sv       自检 TB（109 checks）
  run_vcs.sh                VCS 编译+仿真（clean|cov），FSDB 含 "+all"
  run_verdi.sh              Verdi 看波形（-dbdir simv.daidir -ssf *.fsdb）
```

仿真（VM，VCS/Verdi）：

```bash
cd ~/work/rst_checker/sim
./run_vcs.sh            # ALL 95 CHECKS PASSED
./run_vcs.sh cov        # 覆盖率 → urg_report/dashboard.txt
./run_verdi.sh          # Verdi（struct 成员已入波形，fsdb 用 "+all"）
```

覆盖率（`cov` + `tgl_struct_excl.el` 结构排除后，2026-11-04 VM 实测）：
SCORE 96.12 / LINE 95.28 / COND 99.21 / **TOGGLE 100.00**（模块定义域同
100.00）/ BRANCH 90.00。排除项全为结构常量：addr[1:0] 字对齐、addr[7:5]
映射孔洞、rdata 保留 0 位、镜像 wrap `wr`≡1；BRANCH/COND 残缺同为结构
死支（镜像 wrap 无 wr=0 路径、单总线 selftest×write 互斥、双轨 OR 单热
死臂）。激励含 P15/P17 全部冗余 force（cnt/err/EV/lst/wrap 反相轨
heal-to-SET）。复跑排除：

```bash
urg -dir simv.vdb -elfile tgl_struct_excl.el -excl_strict -report urg_report_excl
```
