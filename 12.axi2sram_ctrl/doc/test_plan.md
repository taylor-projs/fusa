# 12.axi2sram_ctrl — AXI 协议完备性验证计划 (test_plan)

> 版本: 2026-11-26 · 范围: AXI4 从口常规功能 (协议 / 次序 / 边界 / 并发 / 复位) 的完备性验证。
> FuSa 机制 (ECC / 注错 / 寄存器加固 / 数据面防护) 的用例见 `design_spec.md` §10 与
> `sim/tb_axi2sram_ctrl.sv` (T0..T25), 本文只引用不重复。
>
> **结论先行**: 新增独立 TB `sim/tb_axi2sram_proto.sv` (15 组用例 P1..P15 + 常开协议监视器 +
> 独立 AXI 规范参考模型), 首跑即抓到 **1 个真实 RTL 缺陷** (非对齐起始 INCR 读丢低位 lane,
> 同时 FIXED 被当 INCR), 已修复; 另按 NIC 前接场景加固 **WRAP 非对齐起始容错** (P15, 变异检查
> 证明用例有效); 修复后 5 个参数配置全绿, 原 TB 4037 项回归全绿, 排除后 TOGGLE/FSM 保持 100。
> 性能 (延迟 / 吞吐 / 利用率 / 背压 / 系统混合) 由 `sim/tb_axi2sram_perf.sv` 周期精确测量并设基线守卫,
> 见 [perf_report.md](perf_report.md)。

## 1. 为什么需要这份计划 (原验证的结构性缺口)

| # | 缺口 | 后果 |
| --- | --- | --- |
| G1 | **参考模型与 DUT 同源**: 原 TB 的 `tbeat_addr/tlane_mask` 是 DUT `beat_addr/lane_mask_l` 的逐字副本 | 共模偏差不可见 —— 非对齐窄传输 / 非对齐整行 INCR 的错误 **永远测不出** |
| G2 | 无常开协议检查 (valid 保持 / 负载稳定 / X / rlast / 次序 / 幽灵响应) | 协议违例只能靠用例里零星断言发现 |
| G3 | 无随机并发压力: 全是手写定向序列, 读写通道各自只有 1~2 笔在途交织 | 通道仲裁 / 背压组合 / 队列满边界的交叉场景覆盖有限 |
| G4 | 仅 DEPTH=256 (LAW=8) 一种配置 | 真实配置 DEPTH=32768 (LAW=15, PAW=20) 的地址位宽 / 截断 / 高位别名从未跑过 |
| G5 | 仅一个时钟比 (axi 38MHz : mbus 24MHz) | 寄存器 CDC 在 axi≫mbus / axi≪mbus 时的行为未验 |
| G6 | 读写冒险 (RAW/WAR/WAW) 仅在不同地址上测 | 同行在途冒险的次序语义未验 |
| G7 | 复位只测"静息复位 + force 后复位" | 流量中途复位 (含 axi 域单独复位) 无用例 |
| G8 | strobe 只测字节/半字/字/空拍 | 稀疏 / 交替 / 逐 lane / 突发内逐拍变化未验 |
| G9 | BYPASS 模式只有 T16 一个小序列 | 双模式 (FuSa / BYPASS) 的协议矩阵不等价覆盖 |

## 2. 用例表 (tb_axi2sram_proto)

参考模型 (独立于 DUT, 严格按 AXI4 A3.4.1): INCR 非首拍地址 = `align(起始, 2^size) + b·2^size`;
WRAP 容器 `(len+1)·2^size`; FIXED 每拍同址; 有效 lane = `[addr%32, align(addr,n)%32 + n)`。
读比对只看有效 lane, 写 strobe 只开有效 lane (其余 lane 数据随机, 抓 DUT 误用未选通 lane)。

| ID | 场景 | 激励要点 | 检查 |
| --- | --- | --- | --- |
| **P1** | 窄传输对齐矩阵 | size 0..5 × len 0..3 × 多起点, 写后读 + 窗口读回 | 规范模型逐拍数据 / last / id / user |
| **P2** | **非对齐起始 INCR** | size 1..5, 起始偏移 1..n−1 (含首拍 lane 子集), 读写各一轮 | 非首拍地址对齐到 size, lane 全有效 (缺陷 BUG-1 由此抓到) |
| **P3** | WRAP 矩阵 | len 1/3/7/15 × size 0..5 × 容器内多个起点 (含跨行容器) | 回卷次序 + 容器外不被碰 |
| **P4** | WSTRB 扫面 | 32 个单 lane / 8 种稀疏图样 (0x55.. 0xAA.. 半字 跨字) / 全零拍 / 突发内逐拍变 strobe | 字节粒度合并 (RMW) 正确, 零 strobe 不改存储 |
| **P5** | W 通道时序 | 突发中途插 gap / W 先于 AW 12 拍 (超 wskip 深度 4) / W 晚 20 拍 / 6 笔 AW 超前 (在途帽 5) W 晚 25 拍 / 无气泡 len=0 连发 8 笔 | 无死锁, 数据完整, B 次序 |
| **P6** | 读写冒险 | RAW (AW+W 发完再发同行 AR, B 压住) / WAR (AR 先发 R 压住, 再同行写; 读必须旧值, 快照比对) / WAW 部分写重叠 lane 后者胜 / 字节-半字-字-稀疏 RMW 背靠背后读 | 发射序 = 执行序, 同行数据按序可见 |
| **P7** | 独占变体 | size 0..5 各一对 / 多拍独占 (len=3) / 异 id 写失败不写 / 他 id 写同行清监视器 / 本 id 写同行清 / 他 id 读不清 / 失败写不改监视器 | EXOKAY / OKAY 语义 + 数据是否落存储 |
| **P8** | id / user 全值与保序 | id 0..15 × user 0..15 回传 / 5 笔读在途 (rready 压住) / 5 笔写在途 (bready 压住) | rid/ruser/bid/buser 回传 + 响应保序 |
| **P9** | 地址别名与边界 | DEPTH=256 全 256 行唯一标签写后全读; DEPTH=32768: walking-1 / walking-0 行号 + 首末行 + 200 随机行; 末行 INCR / 顶端 WRAP / 末行末字 / 首行首字节 | 无别名, 无截断, 高位地址线全部有效 |
| **P10** | FIXED 突发 | 整行 / 字 / 半字 FIXED 写读 | 每拍同址, 末拍胜出, 邻行不被碰 |
| **P11** | 复位中途 | axi 域单独复位 (AW/W 半途 + 读在途) / 全局复位 (W 半途) / 复位后无幽灵 R/B / 初始化引擎重扫 / mbus 侧配置保留 | awready/arready 复位后低 (初始化期) / 内容清零 / CFG_EN 保留 |
| **P12** | 随机并发压力 (FuSa) | 读写分区 (写窗口 vs 读窗口) 并发; 7 个相位: 最大速率 / 轻背压 / 重背压 (rready/bready 25%) / B 反压 / R 反压 / 只写 / 只读; 另加高地址窗口 (DEPTH>256); INCR+WRAP+FIXED 随机, 非对齐起始, 任意 strobe, 随机 id/user, 随机 AW/W/AR 间隔; 期间 mbus 轮询 ID / STA_PAR | 读: 规范模型逐拍; 写: 窗口读回对 refmem; 监视器全程零违例 |
| **P13** | BYPASS 模式协议回归 | 切 bypass (重扫) → 随机压力 + 窄传输矩阵 → 切回 FuSa | 同 P12 / P1 |
| **P15** | **非对齐 WRAP 起始 (容错)** | 64B 容器 (len=1 size=5) 起始偏移 1/8/15/22/29 (NIC upsizer 保持 master 原地址的形态) + 全 len(1/3/7/15) x size(1..5) 的非对齐起点, 读写各一轮 | 起始按 size 下对齐, 首拍取整块不丢 lane; 容错机制的变异检查: 去掉容错 P15 报 313 错, 加上 0 错 |
| **P14** | 注错下的并发压力 | 单比特注入 (pos 12) 开启时跑纯写压力 → 关注入 → 全窗口读回 | 数据全部被纠正; STA_ERR == CERR 唯一; STA_FAULT 干净; CNT_CERR 计数; STA_PAR 静息 |
| **M0** | 常开协议监视器 (axi_mon) | 全程挂 DUT 口 | R/B valid 保持 + 负载稳定 / ready-valid-负载无 X / R: id·user·rlast 位置·rresp (独占=EXOKAY) / B: id·user·bresp (EXOKAY 仅限独占) / B 不早于对应 WLAST / 无幽灵 R/B; 并统计 R 握手 / 反压拍数以证明背压真实施加 |

全程另有: rpar 契约 + ESM 三对双轨互补性在线监视 (沿用原 TB 做法)。

## 3. 配置矩阵 (run_proto_regress.sh)

| 配置 | 参数 | 目的 |
| --- | --- | --- |
| base | DEPTH=256, axi 38MHz / mbus 24MHz, NTX=300 | 与原 TB 同口径基线 |
| d32k | DEPTH=32768 (LAW=15, PAW=20), NTX=200 | **真实配置**: 地址位宽 / 高位别名 / 高地址窗口 |
| fast | AXI_HP=2 (axi≫mbus), NTX=200 | 寄存器 CDC 在 axi 极快时 |
| slow | AXI_HP=60 (axi<mbus), NTX=200 | 寄存器 CDC 在 axi 慢于 mbus 时 |
| seed7 | SEED=7, NTX=600 | 换随机序列 + 加大事务量 |

`bash run_vcs.sh proto` 跑单个配置 (`PROTO_TAG` / `PROTO_PV="DEPTH=32768 NTX=200"` / `WAVES=1` 带 fsdb);
`bash run_vcs.sh perf` 跑性能 TB; `bash run_proto_regress.sh` 并行跑上表全部 + perf 基线并汇总, 任一失败返回非 0。

## 4. 发现的问题

### BUG-1 (已修): 非对齐起始 INCR 读, 第 2 拍起低位 lane 丢失; FIXED 被当 INCR

- **现象**: 读 `a=0x528 size=5 len=3` (起始偏移 8, 非对齐): beat1..3 的低 8 字节读回 0,
  规范要求这些 beat 是对齐整行、32 lane 全有效。窄传输 (size 1..4) 同理 lane 错位。
  首跑 2278 项失败, 全部同一根因。
- **根因**: `axi2sram_ctrl_core.sv` 的 `beat_addr` 对 INCR 用 `a0 + b·n`, 非首拍未对齐到 size;
  读 lane 掩码 `lane_mask_l(op_size, op_off)` 按这个错位偏移生成 → 掩掉 `[0, off)`。
  FIXED (burst=00) 落入同一 else 分支, 被当 INCR (每拍地址递增)。
- **影响面**: 仅读 (写 lane 由主设备 wstrb 决定, 行号不受影响)。GMAC / USB2 DMA 缓冲区起始地址
  任意字节对齐, 非对齐起始的整行宽 INCR 读是**常规流量**, 会静默丢数据 (RRESP 仍 OKAY, 无任何告警)。
- **为什么原验证测不出**: 见 G1 —— TB 参考模型是 DUT 公式的副本。
- **修复**: `beat_addr` 改为 FIXED=同址 / INCR 首拍=a0、非首拍=`align(a0,n)+b·n` / WRAP 起始按 size
  下对齐 (容错, 见 P15) (2026-11-26)。原 TB 4037 项回归全绿, 排除后 TOGGLE 100.00 / FSM 100.00 保持, proto 5 配置全绿。

### 已知约束 / 未定义行为 (文档化, 不判错)

| 项 | 现状 | 备注 |
| --- | --- | --- |
| AWCACHE/PROT/QOS/REGION 等端口 | 无 | NIC 侧译码, 本 IP 不消费 |
| AR/AW 同拍竞争 | **严格轮询 RR** (v4.2, 原读优先会在读流持续时饿死写) | 公平性由 perf TB PF11 守卫 (变异检查已验证) |
| burst=11 (保留) / size>5 (超总线宽) | 按 INCR / 位宽截断处理, 无 SLVERR | v3.6 退役防御译码 (用户决策); 由 NIC / 主设备保证不发 |
| WRAP 起始非对齐 | AXI 未定义; **本 IP 容错**: 起始按 size 下对齐后计算 (2026-11-26 加固) | P15 覆盖; 防前级 NIC upsizer 输出非对齐 WRAP 起始 (如 0x528 size=5) 时静默丢低位 lane |
| INCR 跨 4KB | 本 IP 不依赖 4KB 边界, 功能正确 | AXI 禁止, 主设备保证; 原 TB T17e 的 INCR256 有意越过 |
| 地址越出 DEPTH×32B | PAW 高位被截断别名到区内 | NIC 译码保证不发; P9 只测边界内 |
| 独占监视器粒度 | {id, 首拍所在 32B 行}, 单项 | 同行别名竞争表现为额外 STREX 失败重试 (设计 §5) |
| 并行 AR/AW 同拍的执行次序 | 由 rac 仲裁决定, 主设备不可依赖 | 冒险用例用"先发完 A 再发 B"保证次序 |

## 5. 覆盖率

| 口径 | LINE | COND | TOGGLE | FSM | BRANCH |
| --- | --- | --- | --- | --- | --- |
| 原 TB (4037 项), 排除后, 2026-11-26 修复后复测 | 96.81 | 94.25 | 100.00 | 100.00 | 92.13 |
| 原 TB 模块定义域 (排除后) | 97.53 | 93.30 | 100.00 | 100.00 | 94.94 |
| proto TB 单独 (模块定义域, 未排除) | 81.13 | 57.28 | 85.57 | 43.33* | 75.32 |
| 原 TB + proto 合并 (模块定义域, 未排除) | 97.53 | 93.30 | 94.85 | 43.33* | 94.94 |

\* FSM 未挂 `fsm_struct_excl.el` 的 raw 值 (见 `design_spec.md` §10 覆盖率注记), 排除后 100。

**读法**: proto TB 的价值不在补代码覆盖 —— 合并后 LINE/COND/BRANCH 与原 TB 持平 (协议路径早被原 TB
走到); 它补的是**功能覆盖**: 同一段代码在"非对齐 / FIXED / 稀疏 strobe / 并发 / 背压 / 高地址"这些
数据条件下的**正确性** (BUG-1 恰是代码覆盖 100% 也测不出的那一类 —— 行被执行了, 结果错了)。
剩余代码覆盖洞集中在 FuSa 故障路径 (毒化完成 / 数据面防护冻结等, 靠 force 注错, 见 T23/T25) 与
参数防御分支, 非协议功能。

## 6. 仍可继续的方向 (backlog)

1. **回归常态化**: `run_proto_regress.sh` 纳入每次 RTL 改动的必跑集 (5 配置并行约数分钟), 并按提交轮换 SEED。
2. **随机 + ECC 全位置**: 现有 T7/T24c 只铺开部分注错位置; 可加 266 个汉明位置逐位单错 + 随机双错的
   "读得对 / 报得对" 扫描, 与随机流量并发。
3. **协议 VIP 对拍**: 若有 Synopsys/Cadence AXI4 VIP 授权, 用其 checker 对拍本 TB 的 M0 监视器。
4. **形式验证**: `beat_addr` / `lane_mask_l` 与 AXI 规范公式的等价性 (组合小函数, 适合 SEC/属性证明),
   可把 BUG-1 这类缺陷从"测"升级到"证"。
5. **FuSa 面与协议面交叉**: 注错 + 非对齐 / WRAP / 独占同时发生 (现 P14 为纯单比特 + 随机写)。
6. **长时 soak**: 夜间 N 万笔随机 (多 SEED), 观察监视器与 refmem 零差异。
