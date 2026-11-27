# hang_prot 出向 / 入向 Test Plan（功能协议覆盖 + 性能分析）

> 适用 RTL：`hang_prot_mcu2main_top`（出向，下称 **DUT-A**）、`hang_prot_main2mcu_top`（入向，下称 **DUT-B**）
> 重点：① 正常业务下 AXI 读写访问，AXI 协议要素全覆盖；② 加入本 IP 后的性能影响量化
> 文档状态：计划稿 v0.1。凡标「待实测」的数值均为分析预期，首轮仿真后回填，**不是实测结论**。

---

## 1. 被测对象与关注点

| 项 | DUT-A 出向（island→main） | DUT-B 入向（main→island） |
|---|---|---|
| 读通路 AR/R | 组合直通 + per-class ID FIFO 记账；AR 受 `rd_otd < OTD_MAX` 门控 | 同左（`bdry_in`） |
| 写通路 AW/W/B | 双/多槽 **store-and-forward skid**：AW 等齐整笔 W 才与 W 一起下发 | 同左（共享 `hang_prot_wskid`） |
| ID 处理 | 读：mcore 字段匹配→统一转发 ID；写：`AW_ID_REMAP` 恒值；响应还原原 ID | 同左（v3.9 起同一套 `N_CLS/CLS_LSB/CLS_W` 参数） |
| 正常态对业务的影响来源 | ① `OTD_MAX` 限制 outstanding ② 写 store-and-forward 延迟 ③ 读类折叠后类内保序 | 同左 |
| 故障态 | recover（dummy 回 SLVERR，自动退出） | block/隔离 + 软件 `QSR_REL` |

本计划**只覆盖正常业务**；故障/恢复/FI 已由现有三 TB 覆盖（§2），不在此重复。

对性能影响的三个根源（均已核对 RTL）：

1. **读**：`s_arvalid = !mode && m_arvalid && ar_room`、`m_rvalid = s_rvalid && ar_occ[cls]!=0`、`m_bvalid = s_bvalid && wr_otd!=0` —— AR/R/B 均为组合直通，**无附加拍延迟**；唯一代价是 `ar_room`（`rd_otd<OTD_MAX`）反压。
2. **写**：`m_awready/m_wready` 由 skid 槽状态决定；AW 在整笔 W 收齐后才下发 → **写首拍延迟 ≈ 突发拍数**；吞吐依赖槽数 `NSLOT`。
3. **ID 折叠**：同类读共用一个转发 ID → 下游按同 ID 保序返回 → 类内可能被慢请求 HOL 阻塞。

---

## 2. 现有验证盘点与缺口

现有 TB：`tb_hang_prot_a_wrap`（P1~P32）、`tb_hang_prot_b_wrap`（P1~P30）、`tb_hang_prot_gen_wrap`（P1~P30），三者 VM 回归全 PASS。

已覆盖（故障/恢复/完整性为主）：reset/mbus 配置、死机恢复各相位、skid 弧与 FI、FIFO/计数器/寄存器完整性、OTD 饱和、DECERR、payload 变化（P26 类）、mcore 类路由（A-P12）、W 先于 AW（A-P4）、背靠背写（A-P3）。

**对本次目标的缺口**（本计划要补的）：

| 编号 | 缺口 |
|---|---|
| G1 | 正常流量缺**系统化 AXI 协议覆盖矩阵**（burst 类型 × len × size × strb × prot × ID × 响应码），现有 payload 用例是点状 |
| G2 | 缺**协议断言**（valid 保持、valid 不依赖 ready、payload 稳定、WLAST/B 次序、ID/保序）全程在线检查 |
| G3 | 缺**反压随机化**（五通道 ready 的占空比/pattern 扫描）与**长时随机流量零误报** |
| G4 | 缺**独立参考模型 + scoreboard**（端到端数据/ID/响应一致性，而非仅看波形计数） |
| G5 | 缺**阈值边界**用例（合法最大等待 vs `REQ2ACCEPT/REQ2RESP`，防正常业务误触发恢复） |
| G6 | 完全没有**性能测试**（延迟/吞吐/outstanding 利用率/阻塞归因） |
| G7 | 缺**配置矩阵**回归（`OTD_MAX`、`NSLOT`、`WSKID_BEATS`、`AXI_DATA_W`） |
| G8 | ~~接口缺口~~ **已补（v3.10/v3.11）**：AR/AW 增 `AxLOCK/AxCACHE/AxQOS/AxREGION`，五通道增参数化 `AxUSER/WUSER/RUSER/BUSER`（§7 项 1） |

---

## 3. 验证方法学

### 3.1 新增环境（复用现有 BFM 风格，不改 RTL）

```
sim/
├── tb_hang_prot_fn.sv     功能/协议 TB（参数 DUT_SEL=A|B）
├── tb_hang_prot_perf.sv   性能 TB（同一流量并行跑 baseline 与 IP）
├── axi_master_bfm.sv      可配置 master：ID 集合/len/size/burst/outstanding/AW-ahead/W 相位/随机 seed
├── axi_leaf_model.sv      可配置 leaf：延迟分布、按地址通道延迟、乱序/保序、ready 占空比、outstanding 容量、数据缓冲深度
├── axi_proto_chk.sv       SVA 协议检查器（bind 到 m/s 两侧）
└── run_fn.sh / run_perf.sh  自检 + 覆盖率 + CSV 报告（沿用 run_vcs.sh 的"退出码不可信、必须查日志"约定）
```

### 3.2 参考与判据

- **Golden 参考**：同一流量同时灌入 ① 透明直连（baseline，m 直连 leaf）② 经 DUT。功能判据 = 两者**逐事务**的数据、响应码、（还原后的）ID 一致；性能判据 = 两者指标之差。
- **Scoreboard**：master 侧记录请求（addr/len/size/burst/id/strb/data），leaf 内置存储模型，读回数据与写入模型比对；响应 ID 必须还原为原始 ID。
- **SVA**（`axi_proto_chk`，m/s 两侧各一份）：valid 保持、payload 稳定、`valid` 不组合依赖对应 `ready`、`WLAST` 位置、`B` 不早于 `WLAST`、同 ID 保序、读数据不跨突发交织、`rid/bid` 合法。**任何断言失败 = 用例失败**。
- **功能覆盖率**（covergroup，见 §4.2 矩阵）：目标 100% bins，未命中需标注排除理由。
- **随机**：受约束随机 + 每配置 ≥20 seeds；seed 写入日志可复现。

---

## 4. Part 1：正常使用 AXI 读写访问 Test Plan

### 4.1 AXI 协议覆盖矩阵（要素 × 用例）

| AXI 要素 | 取值/场景 | 用例 |
|---|---|---|
| burst 类型 | FIXED / INCR / WRAP(len 1,3,7,15)，读写 | FN-03 |
| len | 0,1,3,7,15,16,31,63,127,255（读）；0 ~ `WSKID_BEATS-1`（写，受 skid 容量限制，见 FN-40） | FN-02 FN-40 FN-41 |
| size / 窄传输 | size 0..log2(DATA_W/8)；窄传输 strb 随 size 与地址低位移位 | FN-04 |
| WSTRB | 全 1、全 0、稀疏、walking-1、与 size 对应的窄通道 | FN-04 |
| prot | 8 个取值全覆盖，透传 | FN-05 |
| 地址 | walking-1 全位、4KB 边界内外（不测协议禁止的跨 4KB） | FN-06 |
| ID | 全 ID 空间（`2^AXI_ID_W`）、同 ID 多笔、多 ID 并发；响应还原 | FN-07 FN-12 FN-13 |
| 响应码 | OKAY / EXOKAY / SLVERR / DECERR，逐拍不同的 RRESP | FN-30 FN-31 |
| 握手 | valid 先于/晚于 ready、背靠背、随机反压、五通道独立 | FN-20~FN-26 |
| AW/W 相位 | W 先于 AW、AW 先于 W、同拍、AW 风暴（AW 先行 > NSLOT 笔） | FN-24 |
| outstanding | 1…`OTD_MAX`，读/写独立，满时反压不丢不重 | FN-10 FN-11 |
| 读写并发 | 两方向同时满负载、互不阻塞 | FN-14 |
| 保序/交织 | 同 ID 保序；m 侧读突发不交织；B 不早于 WLAST | FN-13 FN-15 FN-16 |
| **AxLOCK/CACHE/QOS/REGION/USER** | 随机取值透传；AW/W 经 skid 存取并入奇偶；R/B user 回传逐笔核对（`tb_hang_prot_fn`，USER 位宽 3/5/7/2/4）；dummy 拍 R/B user=0 未单独用例 | FN-03~FN-07 随机字段阶段 |

### 4.2 Case List

优先级：P0=必做首轮；P1=第二轮；P2=按资源。适用：A/B/AB。

| ID | 用例名 | 适用 | 优先级 |
|---|---|---|---|
| FN-01 | 单拍读/写基本通路（len0，OKAY） | AB | P0 |
| FN-02 | 读/写 len 扫描 | AB | P0 |
| FN-03 | burst 类型 FIXED/INCR/WRAP | AB | P0 |
| FN-04 | size 与 WSTRB 模式扫描（含窄传输） | AB | P0 |
| FN-05 | prot 全取值透传 | AB | P1 |
| FN-06 | 地址位扫描与 4KB 边界 | AB | P1 |
| FN-07 | ID 透明（全 ID 空间还原） | AB | P0 |
| FN-10 | 读 outstanding 爬坡至 `OTD_MAX` | AB | P0 |
| FN-11 | 写 outstanding 爬坡至 `OTD_MAX` | AB | P0 |
| FN-12 | 多 ID 并发、leaf 乱序返回 | AB | P0 |
| FN-13 | 同 ID 保序 | AB | P0 |
| FN-14 | 读写同时满负载 | AB | P0 |
| FN-15 | 读突发不交织（m 侧） | AB | P1 |
| FN-16 | B 与 WLAST 次序 | AB | P0 |
| FN-20 | valid 保持 + payload 稳定（全程 SVA） | AB | P0 |
| FN-21 | valid 不依赖 ready | AB | P0 |
| FN-22 | 随机反压扫描（五通道 ready 占空比/pattern） | AB | P0 |
| FN-23 | 背靠背满速 | AB | P0 |
| FN-24 | AW/W 相位组合（含 AW 风暴） | AB | P0 |
| FN-25 | W 内部气泡 / WLAST 前停顿 | AB | P1 |
| FN-26 | R/B 延迟抖动 | AB | P1 |
| FN-30 | 四种响应码透传、逐拍不同 RRESP | AB | P0 |
| FN-31 | 业务 SLVERR/DECERR 不触发 hang 检测 | AB | P0 |
| FN-40 | 写突发容量边界（`len+1` = cap-1 / cap / cap+1） | AB | P0 |
| FN-41 | 读最大突发 256 拍 | AB | P1 |
| FN-42 | 混合 len + 满 outstanding | AB | P1 |
| FN-50 | 阈值边界（thr-1 不报 / thr 报） | AB | P0 |
| FN-51 | 最大合法等待不误报（满 FIFO 排空、慢 leaf） | AB | P0 |
| FN-52 | 长时随机流量零误报（≥1e6 拍） | AB | P0 |
| FN-60 | 复位后首笔 / 空闲后首笔 / 复位期间 ready=0 | AB | P1 |
| FN-62 | 业务流量与 mbus 配置读写并发 | AB | P1 |
| FN-A1 | 出向：mcore 字段命中/others、多 arid 折叠保序 | A | P0 |
| FN-A2 | 出向：`s_in_rst=0` 时对正常流量无影响 | A | P1 |
| FN-B1 | 入向：类字段匹配（命中/未命中/表外）、转发 ID 低位=类号、还原原 ID | B | P0 |
| FN-B2 | 入向：`AW_ID_REMAP` 恒值，`m_bid` 还原 | B | P0 |
| FN-90 | 受约束随机总回归（scoreboard+SVA+覆盖闭合） | AB | P0 |

### 4.3 Case 说明

**FN-01 单拍读/写基本通路** — 激励：len=0、size=满宽、单 ID，读写各 100 笔，leaf 返回 OKAY。检查：m→s 方向 addr/len/size/burst/prot/data/strb 逐位透传（ID 除外，见 FN-07）；响应与数据回到 m 侧一致。通过：scoreboard 0 差异，SVA 0 失败，`esm_*` 全 0。

**FN-02 len 扫描** — 读 len∈{0,1,3,7,15,16,31,63,127,255}，写 len∈{0..cap-1}，各 50 笔。检查：数据/拍数/`RLAST`/`WLAST` 位置正确，写 `WLAST` 之后才出 B。注意：写 len 上限受 `WSKID_BEATS` 约束（FN-40 单独验证边界）。

**FN-03 burst 类型** — FIXED / INCR / WRAP（len 1,3,7,15），读写各覆盖。IP 不解析 burst，要求 `arburst/awburst` 透传、数据拍序不变。通过：与 baseline 逐事务一致。

**FN-04 size 与 WSTRB** — size 0..max，每个 size 配地址低位偏移 walking；WSTRB：全 1、全 0、单字节 walking、稀疏随机、与 size 对应的窄通道。检查：strb 与 data 一起经 skid 存取后位级一致（skid 的 per-beat 奇偶不得误报）。

**FN-05 prot 透传** — `arprot/awprot` 000~111 全取值，读写。检查 m→s 透传且与 payload 同拍对齐。

**FN-06 地址位扫描** — 地址 walking-1（全宽）、walking-0、4KB 边界前后各一笔（不跨 4KB）。检查透传，无位串扰。

**FN-07 ID 透明** — 遍历全部 `2^AXI_ID_W` 个 ID 发读写。检查：s 侧 ID 为重映射值（按配置），m 侧 `rid/bid` 严格还原为原请求 ID；同时发多 ID 时互不错配。

**FN-10/FN-11 outstanding 爬坡** — leaf 延迟拉长，master 连续发读（写）至 1,2,…,`OTD_MAX`,`OTD_MAX+1`。检查：第 `OTD_MAX+1` 笔被 `arready/awready` 反压（不丢账、不重复）；`SCMOTD` 读数与实际一致；leaf 开始响应后可恢复满速。写侧额外检查 `wr_otd` 与 skid 槽占用关系。

**FN-12 多 ID 乱序** — leaf 对不同 ID 乱序返回（出向仅类间可乱序；入向同理）。检查：m 侧每笔响应携带原 ID、数据与请求匹配；同类内不乱序。

**FN-13 同 ID 保序** — 同 ID 连发 `OTD_MAX` 笔，不同 len，leaf 保序返回。检查：响应顺序=请求顺序，len/RLAST 逐笔对齐。

**FN-14 读写并发** — 读写同时满负载 ≥10k 笔。检查：两方向吞吐均不为零，任一方向反压不阻塞另一方向（读写独立）。

**FN-15 读不交织** — leaf 故意在不同 ID 间交织 beat（若 leaf 支持）。检查：m 侧同一时刻只交付一个突发的 beat（与 v3.7 "拍间可停、不得插他事务"一致）。

**FN-16 B/WLAST 次序** — 写突发，leaf 立即回 B。检查：`m_bvalid` 不早于该笔 `WLAST` 在 m 侧完成；B ID 正确。

**FN-20/21 握手 SVA** — 全程在线：任一通道 `valid` 拉起且未握手前不得撤、payload 不变；`s_arvalid/s_awvalid/s_wvalid/m_rvalid/m_bvalid` 不得组合依赖本通道 `ready`（用 ready 随机翻转 + SVA 验证）。

**FN-22 随机反压** — 五通道 ready 各自占空比 {0%(短时),10%,50%,90%,100%} × pattern {周期、突发、随机}，笛卡尔积抽样 ≥200 组。通过：功能一致、无死锁、SVA 0 失败。

**FN-23 背靠背** — `valid` 连续无空拍的 AR/AW/W，leaf 满速 ready、满速 R。检查：m 侧不额外引入空拍（记录气泡数，给 §5 提供输入）。

**FN-24 AW/W 相位** — ① W 先于 AW n 拍（n=1..8） ② AW 先于 W n 拍 ③ 同拍 ④ AW 风暴：AW 先行 `NSLOT+1` 笔再给 W。检查：W 先行时 `m_wready` 受控停等但**不死锁**（已有 A-P4 为点状覆盖）；AW 风暴时第 `NSLOT+1` 笔 AW 被反压直到槽释放；数据不丢不乱。

**FN-25/26 内部气泡** — W 突发中插入 1~16 拍 valid 间隔；R 数据拍间随机延迟。检查：功能正确，且合法气泡长度（小于阈值）不触发监控。

**FN-30 响应码透传** — leaf 返回 OKAY/EXOKAY/SLVERR/DECERR，且同一读突发内逐拍不同 RRESP。检查：m 侧逐拍一致。

**FN-31 业务错误不误报** — leaf 正常返回 SLVERR/DECERR（有响应，非挂死）。检查：不置 `esm_err`、不进 recover，后续事务继续正常。（区分"错误响应"与"无响应"，是正常使用的关键边界。）

**FN-40 写突发容量边界** — 写 `len+1` = cap-1、cap、cap+1（cap=`WSKID_BEATS`）。检查：≤cap 正常；>cap 属违例，**记录实际行为**（`m_wready` 饱和停等、是否触发监控）并写入集成约束（§7 项 2）。这是影响 NIC 集成的硬约束。

**FN-41 读最大突发** — 读 len=255（256 拍）连续发。读无 skid 容量限制，检查 `RLAST` 与账本正确。

**FN-42 混合满载** — 随机 len 混合、outstanding 持续在 `OTD_MAX` 附近，检查无丢账（`rd_otd`/`wr_otd` 回落到 0）。

**FN-50 阈值边界** — 设 `REQ2ACCEPT=T1`、`REQ2RESP=T2`：leaf 延迟（地址相/数据相）=T-1 不报错；=T 报错并恢复。读写各一。目的：验证阈值语义精确，而非只做功能。

**FN-51 最大合法等待** — 构造最坏合法场景：leaf 满 FIFO 排空、慢 leaf、`rd_otd` 满导致 AR 等待、skid 攒齐+补发期间 AW 等待。检查：在 §7 项 5 的阈值公式下不误报；并**据此给出推荐阈值下限**。

**FN-52 长时零误报** — 随机流量 ≥1e6 拍，覆盖 FN-22 的各种反压。通过：`esm_err/esm_fault/skid_fault/reg_par_fault` 与 STA 寄存器全程为 0。

**FN-60 复位/空闲** — 复位释放后首笔、空闲 N 拍后首笔、复位期间 `ready=0` 且不接收事务。

**FN-62 并发配置** — 业务流量进行中读写 mbus 配置/状态寄存器。检查：数据通路不受影响；状态读不破坏账本。

**FN-A1（出向）** — 多个 mcore 的 `nic0_master_num` 命中/未命中（others）；每 mcore 发多个 arid。检查：同一 mcore 的多 arid 折叠为统一转发 ID、响应顺序=请求顺序、还原各自原 arid；不同 mcore 之间互不阻塞（构造慢 mcore 与快 mcore）。

**FN-A2（出向）** — `s_in_rst=0` 且互补轨一致时，正常流量零影响。

**FN-B1（入向）** — 类字段值命中各类/表外（进 others）、转发 ID 低 `CLSW` 位=类号、`s_rid` 低位选对 FIFO、`m_rid` 还原。

**FN-B2（入向）** — 写 `s_awid` 恒为 `AW_ID_REMAP`，`m_bid` 还原为各自原 ID。

**FN-90 随机总回归** — 受约束随机覆盖 §4.1 全矩阵；配置矩阵：`OTD_MAX∈{8,16}`、`NSLOT∈{2,4}`、`WSKID_BEATS∈{8,16}`、`AXI_DATA_W∈{32,64,…}`（按集成）；每配置 ≥20 seeds。通过：scoreboard 0 差异、SVA 0 失败、功能覆盖 100%（或带理由的排除项）。

---

## 5. Part 2：性能分析

### 5.1 指标定义（均与 baseline 对比）

| 指标 | 定义 |
|---|---|
| 读附加延迟 | 同一事务：IP 的 `m_arvalid&&m_arready → 首个 m_rvalid` 与 baseline 之差（周期） |
| 写附加延迟 | `m_awvalid 首次 → m_bvalid` 与 baseline 之差；另记 `首个 m_wvalid → 首个 s_wvalid` |
| 吞吐 | 稳态窗口内 m 侧 R/W 通道 beats/cycle；**效率 = IP/baseline** |
| outstanding 利用率 | `rd_otd/wr_otd` 平均/峰值/处于 `OTD_MAX` 的时间占比 |
| 阻塞归因 | 每周期对 `m_ready=0` 归因：`ar_room 满` / `skid 无空槽` / `下游 ready 低` / `等 W 攒齐` |
| 延迟分布 | 平均、p50、p99、max |

### 5.2 分析模型（预期，待实测校准）

- **读通路**：附加延迟 = 0 拍（组合直通）。带宽 `BW = min(1, N_out × L / RTT)`（Little 定律，`L`=每笔拍数，`RTT`=leaf 往返）。IP 仅当 `OTD_MAX < N_leaf` 时成为瓶颈。
  - 例（假设 RTT=60 拍、leaf 容量 ≥16）：`len=3`（4 拍）：OTD_MAX=8 → 8×4/60≈**53%**；OTD_MAX=16 → 16×4/60≈107%→**100%**。`len=0`（1 拍）：OTD_MAX=16 → **≈27%**（baseline 同样受 leaf 限制，则 IP 中性）。
  - **中性条件**：`OTD_MAX ≥ NIC/leaf 实际可用 outstanding（本场景 16）`。**默认 `OTD_MAX=8` 不满足**（§7 项 1）。
- **读类折叠代价**：同类读共用一个转发 ID，类内按请求序返回；下游若是多通道交织 DDR（通道延迟不同），慢请求会 HOL 阻塞类内后续请求。损失随"通道延迟方差 × outstanding"增大 → 由 PERF-R3 量化。
- **写通路**：首拍延迟 ≈ `len+1`（等整笔 W 收齐）+ 常数 `c`（待标定）。稳态带宽 `≈ min(1, NSLOT × (len+1)/T_slot)`，`T_slot`=槽从分配到释放的周期；长突发应接近 100%，短突发（len=0）受 `T_slot` 开销支配 → 由 PERF-W4 标定 `c`。AW 先行深度上限 = `NSLOT`。
- **写 outstanding**：同样受 `wr_otd < OTD_MAX` 与 B 往返限制。

### 5.3 对比配置

| 配置 | 说明 |
|---|---|
| BASE | 无 IP，m 直连 leaf |
| IP-DEF | 默认参数：`OTD_MAX=8`、`NSLOT=2`、`WSKID_BEATS=16` |
| IP-TUNED | `OTD_MAX=16`、`NSLOT∈{2,4}`、`WSKID_BEATS` ≥ NIC 最大写突发（8 或 16） |

### 5.4 自定义场景 Case List（先做）

| ID | 场景 | 扫描变量 | 目的 |
|---|---|---|---|
| PERF-R1 | 单流读，满速 | len{0,1,3,7,15,31}×leaf RTT{10,30,60,120}×`OTD_MAX{4,8,16,32}` | 画 BW-outstanding 曲线，验证拐点符合 Little；确认附加延迟=0 |
| PERF-R2 | 读被 `OTD_MAX` 限制 | RTT=60，len=0，OTD 扫描 | 量化 `OTD_MAX` 作为瓶颈的区间 |
| PERF-R3 | 多通道交织 DDR 模型（4 通道，延迟 40/60/80/100+bank 冲突抖动），baseline 多 ID 乱序 vs IP 类折叠 | 类数 1..4、ID 数、抖动幅度 | **量化 ID 折叠 HOL 损失** |
| PERF-R4 | 4 mcore + 1 DMA 混合（各 mcore 3~8 outstanding，多 arid） | mcore 数、各核 len | 跨核是否互不阻塞，核内串行代价 |
| PERF-W1 | 单流写，满速 W | len{0,1,3,7}（≤cap）× `NSLOT{2,4}` | 写首拍附加延迟 + 稳态 BW vs baseline |
| PERF-W2 | 慢 master（W 每 N 拍 1 beat） | N{1,2,4,8} | store-and-forward 延迟与吞吐解耦确认 |
| PERF-W3 | AW 风暴（AW 先行 K 笔） | K{1,2,4,8}×`NSLOT` | 验证 AW 先行深度 = NSLOT 及其吞吐影响 |
| PERF-W4 | 小包洪泛 len=0 | `NSLOT`、leaf ready 占空 | **标定槽周期开销 `c`/`T_slot`**，支撑 §5.2 模型 |
| PERF-W5 | 大 B 延迟（B RTT=80）满 outstanding | `OTD_MAX` | 写 `wr_otd` 受限区间 |
| PERF-W6 | 下游 `s_wready` 占空 50% | `NSLOT` | 多槽对下游反压的掩盖效果 |
| PERF-M1 | 读写混合 R:W∈{9:1,7:3,5:5} | 比例 | 读写独立性，互不拖累 |
| PERF-I1~I3 | 入向同 R1/W1/M1 场景 + `N_CLS` 扫描 | `N_CLS` | 入向与出向对照；类数对读吞吐影响 |

每场景输出 CSV（指标 §5.1），并自动生成 BASE / IP-DEF / IP-TUNED 三列对比。

### 5.5 NIC 配置场景（自定义不足时/最终签核）

假设下游/上游 NIC：**AR、AW outstanding = 16；R、W 数据缓冲 = 8 拍**（"W 和 R 可能不是 16，比如 8"，按此理解；若 NIC 实际口径不同，只需改 leaf 参数）。leaf 模型：可接受 16 笔未完 AR/AW，R 数据路径 8 拍缓冲、W 数据路径 8 拍缓冲。

| ID | 场景 | 说明 |
|---|---|---|
| PERF-N1 | 全负载读 | len=7（8 拍，恰等于缓冲）与 len=3、len=0 三档；多 ID |
| PERF-N2 | 全负载写 | len=7（8 拍）；验证 `WSKID_BEATS` 与 NIC W 缓冲 8 的匹配 |
| PERF-N3 | 读写混合 | 7:3、5:5，两方向同时满载 |
| PERF-N4 | 小包 | len=0 读写洪泛，暴露 `OTD_MAX`/`T_slot` 瓶颈 |
| PERF-N5 | 4 mcore（出向）/ 多 master（入向）真实地址流 | 通道交织 DDR 延迟模型，对应 PERF-R3/R4 |
| PERF-N6 | 超缓冲突发 | 写 len=15（16 拍）> NIC W 缓冲 8：确认 NIC 是否拆分，以及 `WSKID_BEATS` 取 8 还是 16 |

对比三配置（BASE / IP-DEF / IP-TUNED）。

### 5.6 判据（建议目标，首轮实测后固化）

| 项 | 目标 |
|---|---|
| 读附加延迟 | **0 拍**（组合直通） |
| 读 BW 效率（IP-TUNED，`OTD_MAX≥16`） | ≥ 98% baseline（类折叠场景 PERF-R3 单列报告损失，不设硬门限） |
| 写首拍附加延迟 | ≈ `len+1+c`，`c` 由 PERF-W4 标定 |
| 写 BW 效率（len≥3，`NSLOT≥2`） | ≥ 95% baseline |
| 读写混合 | 任一方向相对其单独运行的退化 ≤ 2% |
| IP-DEF 对比 | **必须如实报告**默认参数相对 BASE 的退化，作为"必须调参"的证据 |

### 5.7 报告格式

`doc/hang_prot_perf_report.md`：每场景一张表（BASE / IP-DEF / IP-TUNED × 指标）+ 曲线（BW-outstanding、延迟 CDF）+ 阻塞归因饼图 + 结论与参数建议。曲线按 SVG 规范绘制。

---

## 6. 覆盖率与退出准则

| 项 | 准则 |
|---|---|
| 功能覆盖（§4.1 矩阵） | 100% bins，排除项逐条理由 |
| 断言 | 全部用例 0 失败 |
| 随机回归 | 每配置 ≥20 seeds 全 PASS；长时零误报 ≥1e6 拍 |
| 代码覆盖 | 沿用现有 TOGGLE/FSM 口径，新增用例不得降低 |
| 性能 | §5.4/§5.5 全部场景出数；IP-TUNED 达 §5.6；缺口与调参建议入报告 |

里程碑：M1 环境 + SVA + FN-P0（基础/握手/响应）→ M2 FN-90 随机回归 + 阈值边界 → M3 PERF-R/W 自定义场景 + 模型标定 → M4 PERF-N NIC 场景 + 参数建议 → M5 报告与回归固化。

---

## 7. 集成约束与待确认项（本计划已发现）

1. **接口（v3.10/v3.11 已补）**：`hang_prot_*_top` 的 m/s 口新增 `AxLOCK[0] / AxCACHE[3:0] / AxQOS[3:0] / AxREGION[3:0]`，并增参数化 `AxUSER/WUSER/RUSER/BUSER`（`ARUSER_W/AWUSER_W/WUSER_W/RUSER_W/BUSER_W`，默认 1，最小 1；不用则输入接 0、输出悬空）。AR、R、B 组合直通，AW/W 存入 skid（AW 并入 `apar`，W 并入每拍 `wpar`）。独占访问（LOCK）与 QoS 现可穿过本 IP。待补：恢复/隔离期 dummy R/B 拍 user=0 的专项检查。
2. **`WSKID_BEATS` 约束**：写突发拍数 > `WSKID_BEATS`（默认 16）属违例，normal 态 `m_wready` 饱和停等。需保证 `WSKID_BEATS ≥ NIC 最大写突发拍数`；若 NIC W 缓冲为 8 而突发可达 16，需确认拆分策略（PERF-N6、FN-40）。
3. **`OTD_MAX` 取值**：默认 8 < NIC 16。须配 `OTD_MAX=16`（`OTD_W` 自动 5，ID FIFO 面积随之增加）才能保持 outstanding 中性。
4. **下游同 ID 保序与 per-ID outstanding ≥ `OTD_MAX`**：IP 对 leaf 的前提（设计 §3/§10），需 NIC/互连确认。
5. **阈值公式**：`REQ2ACCEPT` 必须覆盖"满 FIFO 排空 + 仲裁延迟 + skid 攒齐/补发"；`REQ2RESP` 必须覆盖 leaf 最坏合法响应（含 256 拍突发）。FN-51 负责给出可验证的推荐下限。
6. **读类折叠的性能代价**：mcore 内多 arid 折叠为单 ID 会在多通道交织下游产生类内 HOL；PERF-R3/N5 量化后再决定是否接受或放宽类划分。
7. **写吞吐上限**：由 `NSLOT` 与 `T_slot` 决定，PERF-W4 标定后可据此选 `NSLOT`（面积=每槽 `WSKID_BEATS×(data+strb)`+FuSa 副本）。
