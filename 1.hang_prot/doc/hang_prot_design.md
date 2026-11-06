# hang_prot 总线挂起监控与域边界隔离 —— 统一设计文档（v2）

**模块族**：`hang_prot_core`（监控核）/ `hang_prot_recover`（出向恢复桥）/ `hang_prot_bdry_in`（入向边界单元）/ `hang_prot_wskid`（双 slot W skid，两单元共享）/ `hang_prot_top`（单主控顶层）/ `hang_prot_regfile` + `reg_wrap`（mbus leaf 寄存器）
**参考**：TI Hercules RM57Lx TRM SPNU562A ch.3 SCM / 4.3.5；Safety Manual SPNU575；ARM AXI4（AMBA 4）；IEC 61508:2010 SIL2
**文档版本**：v3.3（v3.2：mcore 感知读类重映射；v3.3：寄存器地图统一 house standard——SCMREGPARSTAT 更名 STA_PAR、自检键拆出 CFG_REGST 0x28、ID 殿后 0xFC，见 §7.1；v3.1：SIL2 FuSa 全机制注入验证）
**写法说明**：本文面向学习与交付——每个设计决策给出"备选方案 → 拒绝理由"，关键流程给出逐周期时序推演。

> **v2 相对 v1 的核心变化**
> 1. **ID 重映射**：所有 AR 转发为固定 `AR_ID_REMAP`、AW 转发为固定 `AW_ID_REMAP`；leaf 端对同 id 必须保序（AXI 强制规则）→ 响应序 = 请求序 = FIFO 序。
> 2. **ID FIFO**：内部存每笔在途事务的 `{原始id, len}`；`m_rid/m_bid` 在**任何模式**都从 FIFO 头还原——dummy 响应自然带**正确的原始 id**（v1 用 1 深 id skid 近似，是文档化残留）。
> 3. **LEN 精确 dummy R**：按 arlen+1 拍补齐（含恢复前已交付的拍数），不再是"单拍 RLAST 提前截断"。
> 4. **dummy W 补齐**：AW 已被下游接受但 W 突发不完整（aw ost > 已发 w 拍）时，单元自己补发剩余拍（wdata=0/wstrb=0/wlast 按 len）——**下游写通道真正归零，不依赖域复位清残留**。
> 5. **幽灵响应结构性吸收**：otd==0 时任何 s 侧 R/B 一律吸收丢弃——v1 的"响应窃取"残留消除。
> 6. 修复 v1 一个实际 bug：恢复单元的 m 侧 B 通道（bvalid/bresp/bready）从未在端口表声明、wrapper 也未连接——B 通路此前根本不通。

> **v2.1 变更（AW/W 匹配后一起下发）**
> 出向恢复桥也改为 **store-and-forward**：AW 被扣住，直到对应的 W burst **全部收齐**才与 W **一起**下发到下一级——半截 W 从物理上不可能跨出边界：
> 1. **dummy W 引擎删除**：恢复时 skid 要么**丢弃**从未过界的 burst，要么用**真数据**把已缓存的 burst **补发到底**——不再需要假数据补拍（v2 第 4 条被本方案取代）。
> 2. **"丢弃"的精确语义**：丢的只是 skid 里的**数据**（从未过界，下游无责任）；**账本条目不能丢**——AW 在 m 侧已握手，wr_otd 和 master 都记着，必须走 sink-W → dummy B 正规退休，否则 otd 与 FIFO 永久失配。
> 3. **wopen ≤ 1**（= wr_otd − wr_dlv）：单 slot 下 AW(k+1) 必须等 W(k) 攒齐才能握手。这个不等是过渡态、语义正确（写请求进行中）、自愈、不下溢——**不用管**（§5.7 全情形遍历）。
> 4. 代价：边界写吞吐一次一笔 burst；req2accept 阈值须覆盖攒齐+补发时间（§10.2）。

> **v2.3 变更（性能修复：双 slot skid + 读多类重映射 id）**
> 性能分析（M85+DMA → 4 通道交织 DDR）发现 v2.1 的两个吞吐瓶颈：
> 1. **写 ~50% 占空**：单 slot skid 把"攒齐 slot k"和"补发 slot k"**串行**——攒齐期间 s 侧 W 通道空闲，补发期间 m 侧 W 通道空闲。**双 slot**（`hang_prot_wskid`，两单元共享）：slot k 在 REPLAY 时 slot k+1 可同时 FILL → 写占空 ~100%。wopen ≤ 1 变为 **wopen ≤ 2**（NSLOT），§5.7 的四条论据逐条携带（"1"→"2"）。skid 从两单元**各自内嵌**重构为**共享子模块**（v2.1 后两份代码已完全同构）。
> 2. **读跨 master HOL**：v2 的单 `AR_ID_REMAP` 把所有 master 的读**串行**在同一 leaf id 上——同 id 必须保序，慢 master 的读（如 M85）堵住快 master 的读（如 DMA），即使两者在 DDR 是相互独立的访问。**多类重映射**：按 `m_arid[AR_CLS_LSB +: CLSW]` 分 N_AR_CLASS 类（集成时 NIC 把源 master 编进这几位 id），每类自己的 remap id + 自己的 ar FIFO。**每类内部的保序论证不变**（leaf 对同类 id 按请求序返回），FIFO 记分板论证不变；跨类响应可以乱序完成，互不堵塞。`N_AR_CLASS=1`（默认）退化为 v2 单 id 行为。写保持单类 `AW_ID_REMAP`——写被 2-slot skid 串行化，第二类 id 无收益。
>
> **v2.3 修复（复查发现，随双槽语义审查）**：
> 3. **WLAST 拍不入 wbuf（严重，重构引入）**：buffer 写保护误写为 `!m_wlast`，但 `beats=fill_cnt+1` 计入尾拍、replay 要读 `wbuf[beats-1]` → **每笔 burst 最后一拍重放陈旧数据**。修复：写保护只看溢出门，WLAST 拍照常入 buffer。
> 4. **恢复期孤儿 W 拍被无账消费（v2.1 遗留缺口）**：`mode ? 1'b1` 的无条件 sink 把"AW 从未握手"的 W 拍也吞掉（master 合法地 pipeline W 先于 AW 被接收）→ 退出后该 AW 握手开 FILL → 等一个已消费的 WLAST → wopen 卡 1 循环 r2a → 永卡。修复：`m_wready = has_fill && (mode || 溢出门)`——FILL 槽的拍照吞（坑 1 对象，覆盖不变），无槽拍 **stall**（与 normal 态满槽背压同形，退出后 AW 握手开的 FILL 接住）。坑 1 论证更新见 §5.5。
> 5. **对端复位重启的通道清洁（新 §8.5）**：main 复位重启后其端口 5 通道必须 idle。1b 挂住的 dummy 由 QSR_REL 退出拍撤回（原有机制，时序契约写死）；**2b 卡死的 REPLAY 原无出口**——ESM 复位 main 后重放拍会灌进已忘记 AW 的 main（非预期 wdata）。修复：Unit A 新增 `s_in_rst`（ESM 电平，"main 在复位保持"）：强制进入恢复 + `s_force=s_in_rst∧mode∧wr_otd==0` 受控清槽 + 退出推迟到 `!s_in_rst`。ESM 序列见 §8.5。

> **v3.1/v3.2 变更（SIL2 FuSa + mcore 感知读类）**
> 1. **v3.1 FuSa（§9.2c）**：regfile 奇偶之外，recover/wskid/bdry_in/gen_wrap
>    全部加上反转副本（双轨寄存器）、FIFO 条目奇偶、one-hot/计数器副本
>    检查——1 拍显式检出 → 失配即隔离（fail toward containment）→ 粘滞
>    双轨故障上报。TB-A P11 / TB-B P9 注错注入验证。
> 2. **v3.2 mcore 感知读类重映射（§3.6）**：v2.3 的
>    `m_arid[AR_CLS_LSB+:CLSW]` 位域选类改为**全 id 匹配**——
>    `MCORE_MASTER_IDS[k]` 命中的 mcore 各占一类（自己的
>    MCORE_REMAP_IDS[k]），其余 master 共享类 0（AR_ID_REMAP）。
>    N_MCORE 参数化（2/3/…，无需 2 的幂），N_CLS = N_MCORE+1。
>    TB-A P12 验证（正常路由 + 按类 dummy 排空）。
> 3. **v3.2 `s_in_rst` 双轨（§8.5）**：ESM 复位保持电平改为互补轨对
>    `{s_in_rst, s_in_rst_n}`——单轨 stuck-0 会静默丢掉复活 main 的通道
>    清洁保护（危险失效），stuck-1 无限锁死通路。失配 → 强制进入 +
>    退出阻塞 + 粘滞上报（与内部完整性故障同语义）。TB-A P13 注入
>    验证。

---

## 目录

- §1 设计目标与场景
- §2 三个基础设计问题的推导
- §3 v2 总体架构：自然保序 + ID 重映射
- §4 监控核（hang_prot_core）设计
- §5 出向恢复桥（hang_prot_recover）逐通道详设
- §6 逐周期时序推演：normal → 恢复 → normal
- §7 寄存器模型（hang_prot_regfile）与软件配置序列
- §8 Safety Island ↔ Main 域边界隔离设计（hang_prot_bdry_in + ADB400）
- §9 FuSa / SIL2 分析
- §10 验证设计与集成约束
- §11 残余风险与设计决策总表

---

## 1. 设计目标与场景

### 1.1 单主控场景（hang_prot_top 的本命场景）

| # | 目标 | 判据 |
|---|---|---|
| G1 | 检测地址相挂起（AR/AW 发出后长期不被接收） | req2accept 计数 ≥ 阈值 |
| G2 | 检测数据相挂起（读无 R、写无 B、写数据停滞） | req2resp 计数 ≥ 阈值 |
| G3 | 超时后**清空 master→总线→slave 通路上的所有在途请求** | 恢复结束时四本账全部 = 0（§5.2） |
| G4 | 释放 master（不让它永远挂死） | 每笔在途事务得到一个**带正确 id、精确 len** 的 SLVERR dummy |
| G5 | 恢复过程 fail-visible（不假装成功） | dummy 用 SLVERR，不用 OKAY |
| G6 | 恢复后回到正常状态，无需整体复位 | 自动退出 + 监控状态自清零 |
| G7 | 监控器自身失效可检测 | 反相副本/码字/双比较器 + 独立 ESM 事件 |

### 1.2 Safety Island 域边界场景（hang_prot_bdry_in 的本命场景）

| # | 场景 | 死方 | 要保护的 | 危害 |
|---|---|---|---|---|
| S1 | island master → NIC → main：main 不收 req / 不回 rsp | main（响应方） | island | NIC 在途 req 无法回收 → o.t 槽位占死 → master 发不出新 req |
| S2 | main → island NIC → SRAM：SRAM 回了数据，main 不收（rready/bready=0） | main（请求方） | island | SRAM 的 o.t 无法回收 → 其他 island 主机访问 SRAM 永久 hang |

```
  ┌──────────── safety island ────────────┐      ┌──────── main domain ────────┐
  │                                        │      │                             │
  │  masters ──▶ NIC ──▶ AXI(出向) ───────────────▶ main 域 IC ──▶ main slaves │
  │                      ▲                │ ADB400│        ▲                    │
  │                      │ Unit A         │      │        │ Unit B             │
  │  island slaves ◀── SI ◀─ AXI(入向) ◀─────────────── (main 发起的访问)      │
  │  (SRAM 等)      ◀── NIC ◀─────────────┘      └─────────────────────────────┘
  └────────────────────────────────────────┘
```

**隔离的本质**：边界单元把每笔跨域在途事务的**两端都了结**——请求端给合成终结响应（SLVERR dummy，带正确 id），响应端吸收并丢弃已发出的响应；写通道两端都补齐/吞干净。S1 用 dummy 引擎，S2 用吸收引擎，两套缺一不可。

**铁律（决定一切放置）**：隔离单元必须活在**被保护域**（island）——岛时钟、岛复位、岛电源。放在被隔离域（main）里，main 一死隔离器陪葬。

---

## 2. 三个基础设计问题的推导

### 2.1 超时判定：ARVALID=1 且 ARREADY=0，怎么算谁的错？

**结论：不需要判定，也不应该判定。**

AXI 的 ready/valid 握手只描述"事实"，不携带"原因"。ARREADY=0 的可能原因：

| 原因 | 性质 | 持续时间 |
|---|---|---|
| 下级 outstanding 满，正常背压 | 正常 | **有界** |
| 下级仲裁暂时偏向别的 master | 正常 | 有界 |
| 下级死锁/挂死 | 故障 | **无界** |

从 master 端口看，前两种和第三种**现象完全相同**，只有"持续多久"能区分。所以监控语义只能是时间上界：

> **req2accept = 请求从发出到被接收的时间上限。** 超过即为超时事件。

这正是 TI SCM 的定义。它监控的是**通路的服务能力**，不是责任归属——责任判定是 ESM 服务程序的事。

**推论（初学者最易走偏处）**：不要试图在监控器里解析下级 outstanding 状态来"区分正常背压和故障"。那要求监控器理解下级协议细节，与层级解耦原则冲突。时间上界 + 可配阈值是唯一与协议细节无关的判据。

v2 新增注意：ID FIFO 满造成的 `m_arready=0` 与 slave 慢造成的 `arready=0` 同属合法背压（见 §5.1）——阈值必须覆盖满 FIFO 排空时间（§10 集成约束）。

### 2.2 "Σ(所有 master 的 o.t) = 下级总线 outstanding 容量"是不是就没问题了？

若满足集成约束：

> **Σ(挂在同一 Slave 上的所有 master 的 outstanding 上限之和) ≤ 该通路的 outstanding 容量**

那么正常背压一定**有界** → ARREADY=0 超过阈值 ⟹ 一定是故障 → **不会误报**。但必须文档化两件事：

- **这是集成约束，监控器不检查它。** 误报是安全方向（fail-visible），但污染诊断。缓解：阈值可配（keyed SCMTHRESH）、监控可关（ENA 码字）。
- 本设计单 master 时约束简化为：**本 master 的 OTD_MAX ≤ 下级通路 outstanding 容量**；v2 还要求**同 id 多笔 outstanding ≥ OTD_MAX**（IC 必须支持，主流都支持——见 §3）。

### 2.3 超时后对下级和 master 各怎么处理，怎么恢复正常？

恢复的本质是**把四本账各自归零**（v1 是三本，v2 增加了下游 W 完成度这本）：

| 在途内容 | 位置 | 恢复手段 |
|---|---|---|
| ① master 已发出、未被接收的请求（地址相） | m 侧 | 压住 m 侧 ready → master 停发新请求 |
| ② 已被接收、在互连/Slave 处理中的事务（outstanding） | 互连/Slave | 回不了真响应 → 给 master 回 SLVERR dummy（**带正确 id、精确 len**），让它退休事务 |
| ③ master 正在发的 W burst（数据相，m 侧视角） | m→单元 | 在 m 侧就地吸收（m_wready=1，丢弃）——绝不能留半开 || ④ **已转发到下游的半截 W burst（s 侧视角）** | 单元→互连 | **不存在了（v2.1）**：AW 等齐 W 才一起下发，半截 W 从不过界；恢复时已缓存的 burst 用真数据补发到底，从未过界的直接丢弃 |

"怎么算恢复正常、谁来放行"：

- **退出条件用硬件可证的客观条件**（§5.2 四本账全零），不用软件放行；
- **软件只做三件事**：W1C 清 sticky 状态、（可选）TO_CLR 重启计数器、按 ESM 诊断决定挂死 slave 复位还是隔离；
- **顺序很重要**：先修根因，再 W1C（顺序反了会立刻再触发一轮恢复——故意的 fail-visible 语义，见 §6.3）。

---

## 3. v2 总体架构：自然保序 + ID 重映射

### 3.1 核心思想

```
      master 侧 id 空间                    下游（leaf）侧 id 空间
   ┌────────────────────┐              ┌──────────────────────────┐
   │ AR: id3, id1, id7 …│   重映射      │ AR: = AR_ID_REMAP|cls    │
   │ AW: id2, id5 …     │ ──────────▶  │     (v2.3: 每类一个 id)  │
   └────────────────────┘              │ AW: 全部 = AW_ID_REMAP   │
          ▲                             └──────────────────────────┘
          │  m_rid/m_bid = FIFO 头部还原     │  leaf 对同 id 按请求序
          │  (AR: 按返回响应的类选 FIFO)     │  返回响应（AXI 强制规则）
          └──── ID FIFO {id,len} ◀──────────┘
               (AR: 每类一条 FIFO)
```

1. **重映射**：每个转发的 AR 变成 `AR_ID_REMAP | cls`（cls = `m_arid` 的类域，§3.6），AW 变成 `AW_ID_REMAP` 常量。AXI 规定 slave 对**同 id** 必须按请求顺序返回响应 → 每类内部响应顺序 = 请求顺序 = 该类 FIFO 顺序。于是**每类一条 FIFO 就是完整的 id 记分板**——不需要任何 id 匹配/比较硬件。
2. **ID FIFO**（每类深度 = OTD_MAX，与监视器 otd 上限一致；**全局**监视器计数 = 各类 FIFO 水位之和，两者由**同一组握手事件**驱动，不可能漂移；全局背压 `rd_otd < OTD_MAX` 保证任何一类不可能超深）：
   - `ar_fifo[cls]`：push `{m_arid, m_arlen}` 于 m 侧 AR 握手（按请求类），pop 于 m 侧 RLAST 握手（按返回类）；`rbeat_cnt[cls]` 记该类头部条目已交付拍数。
   - `aw_fifo`：push `{m_awid}` 于 m 侧 AW 握手，pop 于 m 侧 B 握手；另有 `wm/wp` 两个进度指针（§5.3）。
3. **id 还原在任何模式都生效**：下游回来的 rid/bid 永远是重映射 id，master 必须看到自己的原始 id → 正常模式 `m_rid` 按 **s_rid 的类域**选对应类 FIFO 头；恢复模式 dummy 引擎自选类（当前最低未清类）→ 同一套 FIFO。正常/恢复走**同一逻辑**——dummy 响应自然带正确的原始 id。
4. **精确 len**：dummy R 按剩余拍数补齐到 len+1（按所选类的头部条目）。

### 3.2 ID 重映射为什么让设计"自然"

| v1（深度计数） | v2（ID FIFO） |
|---|---|
| dummy 响应无 id（1 深 skid 近似，worst case master 报协议错） | dummy 带精确的原始 id |
| 晚到真实响应无法对账 → "响应窃取"残留 | otd==0 时结构性吸收幽灵响应 |
| 写 o.t 靠 B 归零，半截 W 留给域复位清 | dummy W 把下游写通道补齐归零 |
| dummy 读单拍 RLAST（严格 master 可能拒收） | LEN 精确补拍 |

**代价**：
- 请求转发多了 FIFO 满背压（otd==OTD_MAX 时 arready/awready=0）——与 slave 慢背压同类，合法；
- master 原来用不同 id 做的响应并行度被**类内**串行化（同 id 必须保序）——v2.3 多类重映射已把**跨 master** 的串行化拆开（§3.6），类内串行化对单 master 无损（边界单口、保序交付）；
- 需要寄存器/参数配置重映射 id 值，且 id 宽度内不得与真实路由需求冲突（重映射 id 对 leaf 只是一个普通 id）；多类时 `AR_ID_REMAP` 低 CLSW 位必须为 0（类域叠加位，综合期检查）。

### 3.3 拓扑（hang_prot_top）

```
                 mbus_clk 域                   ia_bus_aclk 域
              ┌──────────────┐   CDC(在regfile内)  ┌─────────────────────────────┐
   mbus ─────►│  hang_prot   │◄──────────────────►│                             │
              │  _regfile     │  写:toggle握手      │  ┌─────────┐   ┌─────────┐  │
              │  (SCM寄存器 + │  读:2FF同步         │  │ monitor │◄──│ recover │  │
              │   逐寄存器    │                    │  │ (观测)  │otd│  bridge │  │
              │   parity)     │                    │  └────┬────┘   └────┬────┘  │
              └──────────────┘                    │       │err_event    │       │
                          ▼                       │       ▼(边沿脉冲)   │       │
                   reg_par_fault                  │  recover_req ──────►│       │
                                                  └───────┼─────────────┼───────┘
                                                          ▼             ▼
        master ──────── m_axi_* ────────► [bridge m 侧]  [bridge s 侧] ── s_axi_* ─► interconnect/slave
                                    （监控观察点在这里！）
```

### 3.4 关键架构决策：观察点放在 bridge 的 m 侧

| 观察点 | 后果 |
|---|---|
| **s 侧** | monitor 的 otd 计"已进互连"的事务。dummy 发生在 m 侧，**monitor 看不到 dummy 握手** → otd 永不清零 → 恢复永不结束 ✗ |
| **m 侧**（采用） | dummy R/B 握手与真响应握手在 monitor 眼里**完全同形** → otd 自然递减 → 恢复结束条件 = monitor 自己说"没有在途了" → **恢复后监控状态自清零** ✓ |

一般原则：**监控计数器的语义必须定义在"恢复动作的作用面上"**。v2 补充第二条：**FIFO 指针也必须与计数器同源**——push/pop 用与 monitor 加减完全相同的握手事件，账本之间才不会漂移。

### 3.5 控制流（一次完整恢复）

```
monitor: 计数 ≥ 阈值 → sticky 置位 → err_event (电平,sticky)
wrapper: err_event 上升沿检测（一拍寄存）→ recover_req（单拍脉冲）
bridge:  recover_req → mode_r 自保持 → 恢复动作（§5）
monitor: （同时）看到 dummy 握手 → otd 递减 → 0
bridge:  四本账全零（§5.2）→ mode_r 清零 → 退回直通（含 id 重映射/还原）
SW:      ESM 中断 → 修 slave → W1C 状态位 → (可选)TO_CLR → 恢复正常
```

### 3.6 读多类重映射（v3.2：mcore 感知分类，跨 master HOL 消除）

**问题**（v2/v2.1 的隐性吞吐税）：NIC 汇聚 island 多个 master（M85、DMA）到
一条 AXI 出边界。单 `AR_ID_REMAP` 把**所有**读映射到同一个 leaf id → leaf
对同 id 保序 → **不同 master 的读在 leaf 处串行完成**。M85 的长延迟读堵住
DMA 的短读——即使 DDR 4 通道交织下两者是完全独立的访问。这叫跨 master
HOL（head-of-line blocking）。

**方案（v3.2，mcore 感知）**：mcore 类 master **按完整 m_arid 全匹配识别**
（参数化列表 `MCORE_MASTER_IDS`，条数 `N_MCORE` 可为 2/3/…，集成而定），
每个 mcore 独占一个 leaf id；**其余所有 master 共享** `AR_ID_REMAP` 一个 id：

```
   m_arid ──全匹配 MCORE_MASTER_IDS[k]？
        │是                        │否（所有非 mcore master）
        ▼                          ▼
   ┌──────────── AR 转发 ────────────┐
   │ mcore k → MCORE_REMAP_IDS[k]    │  leaf 视角：mcore 各自独立 id，
   │           （类 k+1）            │  其余 master 共享 id；
   │ 其他     → AR_ID_REMAP（类 0）  │  mcore 间可乱序完成、互不堵塞
   └──────────────────────────────────┘
   ar_fifo[0](共享)  ar_fifo[k+1](每 mcore)     ← 每类一条记分板
```

- **线上类编码不变**：转发 id 低 CLSW 位 = 类号（CLSW = clog2(N_MCORE+1)；
  类 0 = 共享类，类 k+1 = mcore k）。约束（综合期参数检查）：
  `AR_ID_REMAP` 低 CLSW 位为 0；`MCORE_REMAP_IDS[k]` 低 CLSW 位 = k+1
  （保证各 mcore 转发 id 互异且路由域成立）；`MCORE_MASTER_IDS` 表项唯一。
  v3.2 之前用 `m_arid[AR_CLS_LSB +: CLSW]` 位域切片选类（要求 NIC 把源
  master 编进 id 位域）——全匹配识别对 NIC 零编码要求，且 mcore 数量
  无需 2 的幂。
- **保序论证不变，只是范围缩小到类内**：leaf 对**同类 id** 按请求序返回 →
  每类 FIFO 头 = 该类下一笔应还的事务。跨类完成顺序任意合法。共享类内
  多个 master 的事务按请求序在该类内完成——与 v2 单 id 行为一致。
- **返回路由**：正常模式由 `s_rid` 低 CLSW 位指出当前 R beat 属于哪类（leaf
  回的就是我们发出的 remap id）；恢复模式 dummy 引擎自选当前最低未清类
  （`dum_cls`），各类 dummy 可交错——跨类本来无序，不存在交错违例。
- **每类占用计数器 `ar_occ[c]`**（不能用指针相等判空：单类可占满全局
  OTD_MAX 预算 → 满环 wr==rp 误读为空）：与指针/监视器 rd_otd 同一组
  握手事件驱动，账本不漂移；Σar_occ = rd_otd。用途：dummy 引擎选类、
  **幽灵 R 门控细化为"返回类占用==0 时吸收"**（坑 3，v2.3）——仅共享类
  有流量时精确退化为 v2 的总 otd 门控。
- **背压保持全局**（`rd_otd < OTD_MAX`，不是每类配额）：单类吃满 OTD_MAX
  顶多堵住该类新 AR——而 leaf 允许的 per-id outstanding 上限（集成约束）
  本来就是这个量级；全局预算让 FIFO 深度每类都是 OTD_MAX 而无需再加宽。
- **写不分类**：写被 2-slot skid 串行化（§5.9），第二类 id 买不到任何并行度。
- **入向单元（bdry_in）不受影响**：其 m 侧是单 main master 流，仍用
  v2.3 的位域类方案（参数独立）；mcore 识别仅用于出向（island NIC 侧）。

**集成约束（更新，§10.2 汇总）**：集成方给出 `N_MCORE` +
`MCORE_MASTER_IDS`（各 mcore 在 m_arid 上呈现的 id）+ `MCORE_REMAP_IDS`
（各 mcore 的转发 id，低 CLSW 位 = k+1）；leaf 对**每个**类 id 都须满足
"同 id 保序 + ≥ OTD_MAX outstanding"。

**验证**：TB-A P12——(a) 正常模式 4 笔读（两个非 mcore id 共享类 0、两个
mcore id 各自类）：响应方回显转发 id，逐 burst 校验还原 rid 与次序
（5/2、3/1、1/3、0/1 拍）；(b) 三类同时在途时 main 死于响应中途：dummy
引擎按类排空，每类还原**该笔事务自己的** rid，真实+dummy 拍数精确 = len+1
（0/2、1/3、3/1），与死亡时刻无关。

---

## 4. 监控核（hang_prot_core）设计

### 4.1 双流模型（TI 原样映射到 AXI）

每个 master 端口 = 两条独立监控流（IA bit）：

| 流 | req2accept 窗口 | req2resp 窗口 |
|---|---|---|
| 读 (IA 2m) | ARVALID&&!ARREADY 起计，AR 握手清零 | AR 握手起计，任一 R beat 清零，RLAST 时 otd 减 |
| 写 (IA 2m+1) | "写请求完整"= AW 握手 + W 全发完（WLAST 过）；AW 挂/W 挂/深度不配平都算"请求 pending" | WLAST 交付起计，B 握手清零 |

**为什么写的 req2accept 不是"AW 握手"**：TI 的总线写请求带数据，一笔"请求"天然含数据。AXI 把 AW 和 W 拆开，所以"写请求被完整接收"要到 WLAST 才成立。

### 4.2 otd（outstanding depth）——监控侧的"账本"

```
读 : rd_otd = (AR 握手数) - (RLAST 握手数)      饱和于 OTD_MAX
写 : wr_otd = (AW 握手数) - (B  握手数)          饱和于 OTD_MAX
     wr_dlv = (WLAST 握手数) - (B 握手数)        饱和于 OTD_MAX
```

**饱和即故障**：账本已在 OTD_MAX 而同一拍又来递增请求（AR/AW/WLAST 握手）时，
该笔递增被丢弃、账本就不可信了——这可能是真正的 outstanding 溢出，监控会看不见
挂死。此时置 `fu_src` 顶位 **OTDSAT** 并拉 `fu_fault`（完整性事件，不走 err_event），
T6 sticky；SW 需 quiesce 主控 + TO_CLR 重启账本。wrapper 集成中 room 门控
（`rd_otd < OTD_MAX` 才放行）使饱和带握手只可能出现在裸监控核直连场景。

监控核**本身仍然是无 ID、无顺序的深度计数**（TI 原话"no need to save outstanding transactions"）——v2 的变化是**恢复单元**持有 ID FIFO：监控核管"有没有进展"，恢复桥管"每笔事务的身份"。两者账本同源（同一握手事件），各司其职。

**wr_dlv 与 dummy B 的时序约束（v2 新增决策 D-B序；v3.4 改为计数器实现）**：dummy B 对某笔写只在该笔的 WLAST 已过 m 侧后发出。v2~v3.3 用第三枚指针 `aw_bp != aw_wm` 门控，但 mod-OTD_MAX 指针在**满环**时无法区分"0 笔 WLAST 完成"与"OTD_MAX 笔 WLAST 完成"（两态指针相等）——TB_A P22b（OTD_MAX=4 笔写全部 WLAST 完成、B 停在 m 侧、main 挂死超时进恢复）触发该歧义：进入 mode 的瞬间被屏蔽的 real B 掉电（违 AXI hold），且 dummy B 永远不发，`wr_otd` 卡 4 无法退出恢复 = **真 hang**。v3.4 起改为精确的上下计数账本 `bdum_owed`（m WLAST +1 / m B −1，0..OTD_MAX 无歧义，双轨+dup 检查），两个模块（recover / bdry_in）同步修复。若 B 先于 WLAST 出现，`wr_dlv = WLAST − B` 会出现"先减后加"的负漂移窗口，期间 `wr_otd != wr_dlv` 使写流被判"请求 pending"，r2a 计数上涨——恢复期间制造虚假 r2a 上报。门控后每笔写保持 AW → WLAST → B 的规范顺序，账目全程干净。

### 4.3 err_event 与恢复触发的关系

err_event = 所有 r2a/r2r sticky 位的 OR，**W1C 之前保持为高**。触发必须用**上升沿脉冲**：

> 电平触发 + 自动退出 = **2 周期振荡**。退出后电平还高（sticky 没清）→ 立即再进恢复 → otd 已是 0 立即退出 → 再进……

上升沿脉冲语义 = "**一次超时事件触发一次恢复**"。若恢复后 master 重试、slave 仍坏 → 新超时 → 新上升沿 → 新一次恢复。**每阈值周期一次恢复、ESM 持续可见**——fail-visible。

### 4.4 FuSa 完整性层（监控器自身失效检测）

| 机制 | 实现 | 作用 |
|---|---|---|
| 码字使能 | 4'b1111 开 / 4'b0000 关，汉明距 4，多数判决 | 使能位 SEU 防护，1 位翻转自愈 |
| keyed 配置 | cfg_wr 需要 cfg_key==4'b1010 | 随机写不能破坏阈值/使能 |
| 阈值副本 | thr + 反相副本，逐周期比较；失配 → fu_fault 且回落复位值 | 阈值损坏不能静默关检查 |
| 计数器副本 | 每个计数器带反相副本；失配**强制立即触发** err_event | 损坏的计数器不会让报告迟到 |
| 双比较器 | fire 条件算两遍，OR 进 fire，分歧 = fu_fault | 比较器单点翻转可见 |
| 状态副本 | sticky 位带反相副本；失配自愈为**置位** | 被 SEU 清掉的错误重新上报 |
| 双轨输出 | err_event/err_event_n、fu_fault/fu_fault_n 对 | 传输故障在 ESM 侧可检 |
| fu_src | 故障源 sticky 状态（ENA/THRA/THRR + 每 master CNT/CMP/STAT + 顶位 OTDSAT） | SW 定位哪路完整性检查坏了；OTDSAT 靠 SCMOTD 逐流定位 |
| 残余 | 共模 → 周期 selftest + 启动端到端事务测试兜底 | 文档化的残余风险 |

**err_event 与 fu_fault 刻意分开**：坏掉的监控器不能和真总线超时不可区分——各走各的 ESM 组。

---

## 5. 出向恢复桥（hang_prot_recover）逐通道详设

### 5.1 详细框图（m/s 两侧 5 通道的 vld/rdy 全展开）

```
        island NIC (master)                     main 域 IC (slave)
═══════════════════════════╦══════════════════════════╦═══════════════════════════
                           ║   hang_prot_recover      ║
                           ║                          ║
 AR  m_arvalid ───────────▶║ req门(otd<MAX)──────────▶║ s_arvalid ──────────────▶
     m_arready ◀───────────║ ◀────────────────────────║ s_arready ◀──────────────
                           ║   push{arid,arlen}       ║  s_arid = AR_ID_REMAP|cls
                           ║  ┌──────────────────┐    ║  (v3.2: cls=全id匹配mcore,
     m_rid ◀═══════════════║══│ AR FIFO(OTD_MAX) │    ║   MCORE_REMAP_IDS[k] /
     (按s_rid类域选头)      ║  │ ×N_CLS条          ║   AR_ID_REMAP)
 R   m_rvalid ◀──mux───────║  │ ar_wr/ar_rp[cls] │    ║  s_rvalid ──────────────▶
     m_rready ────────────▶║  │ rbeat_cnt[cls]   │    ║ ◀ s_rready ◀──absorb─────
     m_rresp ◀─────────────║  └──────────────────┘    ║   (mode∨otd==0 → 1,
     m_rlast ◀─────────────║  正常: s_rvalid∧otd≠0    ║    否则透传 m_rready)
     (m_rdata=0,wrapper)   ║  恢复: dummy(自选类,    ║  (s_rid类域→返回路由)
                           ║   SLVERR,len精确)       ║
 AW  m_awvalid ───────────▶║ ┌────────────────┐      ║ s_awvalid ◀─READY槽─────
     m_awready ◀───────────║ │ W SKID (2 slot) │─────▶║   (仅normal; 恢复时丢弃)
                           ║ │ FREE→FILL→     │      ║ s_awid = AW_ID_REMAP
     m_bid ◀═══════════════║═│ READY→REPLAY   │      ║ s_awaddr/len/size/burst
 W   m_wvalid ────────────▶║ │ 每slot:AW负载+  │      ║   = issue槽锁存值
     m_wready ◀────────────║ │ W beats缓存     │─────▶║ s_wvalid ◀──REPLAY──────
     m_wlast/wdata/wstrb ▶║ │ 环形3指针:      │      ║ ◀ s_wready ◀─────────────
      (正常=填最老FILL槽,  ║ │ alloc/fill/issue│      ║  s_wdata/s_wstrb=缓存值
       溢出保护; 恢复=1)   ║ │ k补发时k+1可攒  │      ║  s_wlast=(ridx=beats-1)
                           ║ └────────────────┘      ║  (REPLAY两模式都跑完)
                           ║  push{awid}(AW握手)     ║
                           ║  ┌──────────────────┐   ║
                           ║  │ AW FIFO(OTD_MAX) │   ║
                           ║  │ wr push / wm WLAST│  ║
                           ║  │ bp B进度(m_bid头) │  ║
                           ║  └──────────────────┘   ║
 B   m_bvalid ◀──mux───────║  正常: s_bvalid∧otd≠0    ║  s_bvalid ──────────────▶
     m_bready ────────────▶║  恢复: B dummy(SLVERR)   ▶║ ◀ s_bready ◀──absorb─────
     m_bresp ◀─────────────║   门控 bp≠wm             ║   (mode∨otd==0 → 1,
     m_bid  ◀─────────────║   (该笔m侧WLAST已过)      ║    否则透传 m_bready)
                           ║                          ║
   ═════ m 侧（监视器观测点）═════║═════ s 侧 ════════════║
                           ║        ▲ rd_otd / wr_otd  ║
                           ║        │ recover_req(脉冲) ║
                           ║   [hang_prot_core 监视器]  ║
                           ╚══════════════════════════╝
```

**正常模式不再是"纯透传"**（v1 是）——几处永久逻辑：
1. `s_arid = AR_ID_REMAP|cls`、`s_awid` 恒为重映射常量；`m_rid` 按返回类选该类 FIFO 头还原、`m_bid` 恒为 aw FIFO 头还原；
2. AR 转发门控 `otd < OTD_MAX`（FIFO 满背压，全局预算）；R/B 转发门控 `otd ≠ 0`——幽灵响应就地吸收；
3. **AW/W 走双 slot store-and-forward skid（v2.1 引入，v2.3 加深到 2 slot，§5.9）**：AW 等齐完整 W burst 才一起下发；m/s 两侧 AW 握手**解耦**（m 侧握手即入账，s 侧等攒齐才发）；slot k 补发的同时 slot k+1 可在攒齐。
除上述（+ ready 多一级 MUX）外 AR payload 仍在 wrapper 层直通；AW/W 数据通路在 skid 内（有寄存）。

### 5.2 四本账（恢复 = 四本账全部归零）

| 账本 | 定义 | 归零手段 | 监视器/本地 |
|---|---|---|---|
| rd_otd | m AR − m RLAST | dummy R 引擎按 len 补拍（自选类），pop 于 m 侧 RLAST | 监视器（= 各类 ar_fifo 水位之和） |
| wr_otd | m AW − m B | dummy B（SLVERR，bid=FIFO 头），pop 于 m 侧 B 握手 | 监视器（= wr−bp） |
| wopen | m AW − m WLAST（**≤2**） | master 活着 + m_wready=1 → 必然排空 | 本地（= FILL 槽数，恰等价） |
| s 侧 W | 下游写完成度 | **skid replay 补发到底（真数据）**；从未过界的直接丢弃 | 本地（= 两 slot 全 FREE） |

**退出条件 = `rd_otd==0 ∧ wr_otd==0 ∧ skid.all_free ∧ !s_in_rst`**（all_free 同时覆盖 wopen=0 与无 replay；`!s_in_rst` 见 §8.5——main 域复位保持期间不退出，复活时 5 通道 idle）。

### 5.3 AW FIFO 的三个指针 + skid 状态

```
  条目:      [已回B] [B待回] [W未完(FILL)] [W未完(FILL)] [新push?]  (环形,深度OTD_MAX)
  指针:      bp ────▶ wm ────▶ ……(最多2笔)……      wr           bp ≤ wm ≤ wr
             B进度   m侧W完    (skid 2 slot占用)    push点
```

- `bp`：m 侧 B 握手推进（真实 B 或 dummy B 各 pop 一条）。
- `wm`：m 侧 WLAST 推进——master 的 W 交齐。**dummy B 门控 `bp ≠ wm`**：
  一笔写的 B 只在该笔 WLAST 已过 m 侧后才能回（理由见 §4.2 wr_dlv 账目）。
  推论：master 若扣着 W 不发（master 侧故障），dummy B 卡在那笔上、
  wr_otd 永不归零、恢复态保持——fail-visible，等 ESM/复位。
- `wr`：m 侧 AW 握手时 push（与 s 侧下发**解耦**——s 侧要等 skid 攒齐）。
- **wopen（wr−wm）≤ 2**（v2.3）：skid 双 slot 占用 ⟺ 最多两笔 W 未完
  （v2.1 单 slot 时 ≤1；四条论据见 §5.7）。
- **s 侧 W 完成度不再用指针跟踪**：skid 环形指针体系本身就是这本账
  （两 slot 全 FREE = 无 replay 在途；v2 的 wp/wbeat_cnt 随 dummy W 引擎一并删除）。

### 5.4 恢复模式逐通道驱动表

| 通道 | m 侧 | s 侧 | 说明 |
|---|---|---|---|
| AR | `arready = 0` | `arvalid = 0` | stall master；撤回未接受 VALID 是文档化残留 R1 |
| R | `rvalid = dummy引擎`（otd≠0，自选最低未清类）；`rid = 类FIFO头`；`rlast = (rbeat_cnt[cls] ≥ len)`；`rresp = SLVERR`；rdata=0 | `rready = 1`（吸收迟到真 R） | LEN 精确补拍；`rbeat_cnt ≥ len` 含"slave 超发拍"强制截断路径；类间 dummy 可交错（跨类无序） |
| AW | `awready = 0` | `awvalid = 0` | 同 AR；READY 槽中未过界的 burst 直接丢弃 |
| W | `wready = has_fill`（FILL 槽的拍全吞，违例尾拍也吞） | FILL→WLAST 丢弃；REPLAY→**真数据补发到底** | 半截 W 从不过界；replay 两模式都跑完；**无 FILL 槽的孤儿拍 stall 不吞**——其 AW 从未握手，吞=丢数据且无账可还，退出后永卡；stall 留给退出后 AW 握手开的 FILL 接收（v2.3 修复） |
| B | `bvalid = (otd≠0 ∧ bp≠wm)`；`bid = FIFO头`；`bresp = SLVERR` | `bready = 1`（吸收迟到真 B） | 每笔欠账一个 SLVERR，序守 FIFO |

### 5.5 深坑与决策（v2 逐条）

**坑 1：恢复期已握手写的尾拍必须吸收（m_wready 覆盖 FILL 槽），不能堵。**
超时时 master 可能 W 发到一半；堵住 → master 按规范必须永远保持 WVALID →
协议引擎卡在"发 W"态 → 无法处理 B dummy → master 永久锁死。吸收则
master 发完 WLAST 后认为"事务已完整发出，等 B" → B dummy 到达正常退休。
v2.3 精化：坑的适用对象是 **AW 已握手**的写（FILL 槽必在），`m_wready =
has_fill` 恰好覆盖；对 AW 未握手的孤儿拍则 stall（不吞，见 §5.9 恢复
模式语义第 1 条）——
那笔写没有 B 在等，master 卡在发 W 与面对普通背压（慢 slave）同形，且
退出后 awready 一开即解。两行为不冲突。

**坑 2：丢迟到响应不能用 ready=0，必须吸收。**
AXI 要求 RVALID 声明后保持到握手。压 s_rready=0，修好的 slave 吐出那笔 R
没人收，**永远保持 RVALID**，恢复退出后直通给 master → 幽灵响应。
吸收让**双方账都平**，堵住只让自己账平。

**坑 3（v2 新增，v2.3 细化到类）：幽灵响应的转发门控。**
返回类占用为 0 时（其事务早已被 dummy 归零）任何 s 侧 R 都是幽灵。v1 会把它
转发给 master（"响应窃取"）。v2 结构性消除：`m_rvalid = s_rvalid ∧ occ≠0`，
同时 `s_rready = 1` 吸收。安全性论证：监视器在 m 侧、R 通道由本单元交付，
**occ==0 ⇒ 该类没有任何一笔在等响应** ⇒ 此刻的 s_rvalid 不可能属于该类
合法在途事务。（R 突发中途该类 occ 必 ≥1——pop 只发生在 RLAST。）
**v2.3 细化**：门控从总 otd 改为**返回类占用**（`ar_occ[s_rcls]`，占用
计数器而非指针相等——满环时 wr==rp 会被误读为空）。单类时占用 ≡ 总 otd，
精确退化为 v2 行为。B 通道保持总账门控（写单类）。

**坑 4（v2 新增）：dummy B 的顺序约束。**
见 §4.2 / §5.3 的 `bp≠wm` 门控。备选方案"立即回 B 加快排空"被拒：
wr_dlv 账目负漂移 + 恢复期虚假 r2a。

**坑 5（v2.1 重写）：超时时 W 未收完——"丢弃"的精确语义。**
半截 W burst 的去向分两种：
- **从未过界**（还在 skid FILL/FULL 中）：数据**直接丢弃**——下游从未见过
  这笔写，无下游责任；
- **已在 REPLAY 中**：用**真数据**（缓存里的）补发到底——它是完整合法
  burst，中途撤 VALID 反而是协议违例。
关键是：**aw FIFO 里的账本条目不能丢**——AW 在 m 侧已握手，wr_otd 和
master 都记着这笔，必须等 master 把剩余 W 拍发完（sink 吸收）→ WLAST 过
m 侧 → dummy B 退休。若直接删账不发 dummy B，otd 与 FIFO 永久失配、恢复
永不退出。数据丢、账不丢。

**坑 6：入口快照竞态。** 不用快照，全部活账本——入口当拍完成的握手也覆盖。

**坑 7：退出条件不看请求 VALID。** 地址相挂死时 master 合法地永远挂
ARVALID；退出只看"账平没平"（客观可证），不看"请求在不在"（master 的
合法权利）。

### 5.6 状态机

```
        recover_req(脉冲)          四本账全零
 NORMAL ────────────────────► RECOVER ─────────────► NORMAL
（直通+重映射）               (mode_r=1,自保持)      （直通+重映射）
```

若 slave 修好了：退出后 master 挂着的/重试的请求被正常接收。
若 slave 还死着：新请求再超时 → 新上升沿 → 再进恢复（每阈值周期一轮，ESM 持续告警）。
若 master 死了（扣 W 不发）：wopen/wm 不动 → 恢复态保持 → ESM。

### 5.7 AW/W 全情形遍历与 wr_otd/wr_dlv 账目分析（v2.1）

**账本恒等式**（监视器 m 侧视角）：
`wr_otd − wr_dlv = wopen` = AW 已握手但 WLAST 未到的写笔数 ≤ 2（双 slot，v2.3；v2.1 单 slot 时 ≤1）。
监视器把 `wopen≠0` 计入 r2a 窗口——**语义正确**：TI 定义下写请求到 WLAST
才算发完，"不等"本身就是"请求进行中"的指示，不是异常。

| # | 边界处 AW/W 状态 | 触发超时 | 恢复动作 | wr_otd−wr_dlv |
|---|---|---|---|---|
| 1 | W 先于 AW（AXI 合法） | r2a（WVALID∧¬WREADY） | 正常态：AW 握手开 FILL 后 W 自然流入；恢复态：无 FILL 槽的 W 拍 **stall**（不吞——吞=丢数据无账，退出后新开的 FILL 等不到 WLAST 永卡），退出后 AW 握手 → FILL → 存着的拍交付 | 0 |
| 2 | AW+W 已攒齐下发，等 B | r2r | dummy B | 0 |
| 3 | AW 已收，W 半截，master 停 | r2a（wopen≠0 计 pending） | 丢弃 skid 数据（从未过界）→ sink 尾拍 → WLAST 过 m → dummy B | ≤2→0 过渡自愈 |
| 4 | W 攒齐（READY），AW 未下发 | r2r | 丢弃（从未过界）→ dummy B | 0 |
| 5 | REPLAY 中，slave 活 | r2r | replay 真数据跑完 → dummy B | 0 |
| 6 | REPLAY 中，slave 死 | r2r | replay 保持 offer，不能强推（弃半截 burst=违例）→ 退出阻塞 → fail-visible，ESM | 0 |
| 7 | r2r 期间另有新写在 FILL（1~2 个槽） | r2r | 老条目按序 dummy B；轮到 FILL 条目时 bp==wm 卡住等 master 补 W → 顺序无死锁 | ≤2 |
| 8 | burst > WSKID_BEATS（违例） | r2a（fill 饱和停收） | 恢复期 m_wready 不设溢出门（FILL 槽的违例尾拍继续吞）→ sink 完 → 丢弃 → dummy B（可恢复） | ≤2 |
| 9 | slot k 在 REPLAY、slot k+1 在 FILL | r2r | k 真数据跑完；k+1 若超时期间攒齐→未过界丢弃，未攒齐→sink 完丢弃；各自 dummy B | ≤2 |

**wr_otd ≠ wr_dlv 为什么不用管（四条论据）**：
1. **语义正确**：不等 ⟺ 有写的 W 未发完 ⟺ "写请求 pending"——r2a 本来就该计；
2. **有界**：2 slot skid ⇒ AW(k+2) 必须等某 slot 释放才能握手 ⇒ wopen ≤ 2
   （v2.1 是 ≤1；加深换吞吐，性质不变——若改 OTD_MAX 深多 slot，可到
   OTD_MAX，同样安全，但失去小常数性质且费面积）；
3. **自愈**：恢复期 m_wready=1 sink，master 发完 WLAST → 归零；唯一不自愈是
   master 死（fail-visible，本来就不该自愈）；
4. **不下溢**：dummy B 被 bp≠wm 门控，任何 B（真/dummy）必晚于该笔 m 侧
   WLAST ⇒ wr_dlv 永不出现"B 先于 WLAST"的负向窗口。

### 5.8 "W 未到 WLAST 就超时 + AW 在 FIFO 里"的精确处理（v2.1 决策记录）

**架构事实**：store-and-forward 下，"AW 已发到下游、W 未发完"这个状态
**不存在**——AW 只在 WLAST 已入缓存（slot 进入 READY，v2.1 称 SK_FULL）
时才下发。超时瞬间的物理状态是：m 侧账已入（wr_otd/aw_fifo/wopen）、
skid 某槽里有 AW 负载 + k 拍真数据（FILL）、**s 侧什么都没有**。下游
从未见过这笔 AW，不欠任何 W 拍。

处理链：sink master 尾拍 → WLAST 过 m 侧（wopen→0）→ FILL 直接
丢弃（数据从未过界，下游零责任）→ dummy B 退休账本 → 退出。

**两条候选策略的对比（为什么选"丢弃"）**：

| | A 丢弃（采用） | B AW+真实拍+dummy 补发 |
|---|---|---|
| 下游内存 | 写要么完整、要么不发生 | 落下 k 拍真 + 尾部假数据的**残影** |
| master 语义 | SLVERR，重试即可（一致） | SLVERR 但内存有半个写（不一致） |
| 死 slave | 无依赖 | dummy 拍照样挂（wready=0）——**同样救不了** |
| 硬件 | 无 dummy W 引擎 | 需补拍引擎 + 数据 mux |

**若选 B 的硬规则（防止后来人走捷径）**：补发必须**补满 AWLEN+1 拍**，
严禁只发一个带 wlast 的单拍——W 通道没有 R 通道那种 early-termination
宽容，AXI 要求 W 拍数与 AWLEN+1 严格相等、WLAST 恰在末拍；只发 wlast
会让下游 burst 计数器失配。v2 的 dummy W 引擎正是按 len+1 补满实现的
（后被 v2.1 的 skid 方案整体取代）。唯一"W 部分过界"的情形是 mid-REPLAY
slave 死：此时用**缓存真数据**继续补发到底（拍数=锁存 beats，天然满足
AWLEN+1），绝不伪造、绝不截断。

### 5.9 双 slot W skid（v2.3 性能修复：写占空 ~100%）

**问题**：v2.1 单 slot 状态串行 `EMPTY→FILL→FULL→REPLAY→EMPTY`——
**攒齐期间 s 侧 W 通道空闲、补发期间 m 侧 W 通道空闲**。满速写流下
占空 ~50%（DDR 4 通道交织把写带宽顶满时，这直接砍半边界吞吐）。

**结构**（`hang_prot_wskid.sv`，recover/bdry_in 共享实例化）：2 个 slot
各持 {AW 负载锁存, wbuf[WSKID_BEATS], sbuf, fill_cnt, beats, ridx}，
环形三指针：

```
   alloc_p : 下一个要分配的 FREE slot（驱动 m_awready）
   fill_p  : 最老的 FILL slot（m 侧 W 拍永远属于最老未攒齐 burst——
             AXI W 无交错；master 在 WLAST(k) 前发 AW(k+1) 就是同时填两槽）
   issue_p : 最老的 READY/REPLAY slot（s 侧 AW/W 来源）
   ── 三指针按同一环序互相追逐：W 完成序 == 分配序（W 无交错）──
```

**slot 生命周期（每槽独立 one-hot 状态）**：

```
  FREE ──m AW握手(alloc_p槽)──▶ FILL ──WLAST──┬─normal─▶ READY
        ◀──────────────────────┘             └─mode───▶ FREE(丢弃)
  READY ──s AW握手(issue_p槽,仅normal)──▶ REPLAY     (mode直接FREE,丢弃)
  REPLAY ──W拍从缓存补发,两模式都跑完──▶ FREE (末拍: ridx==beats-1)
```

**流水重叠（为什么 ~100%）**：

```
 拍:      1    2 …  B    B+1  B+2 … 2B   2B+1 2B+2 …
 m侧W:   |──填slot0(B拍)──|  |──填slot1(B拍)──| |填slot2…   ← m侧不断流
 s侧W:            (静默等AW攒齐)  |──放slot0(B拍)──| |放slot1… ← s侧不断流
 slot0:  FREE→FILL───────→READY→REPLAY──────→FREE
 slot1:       FREE→FILL────────────→READY→REPLAY…
```
slot 0 在 REPLAY 时 slot 1 已在 FILL——**两条 W 通道各跑各的，占空由
下游 wready 决定，不再由 skid 结构决定**。代价：存储 ×2、wopen ≤2、
skid 故障面 ×2（每 slot 独立 one-hot 检测，FuSa 论证不变，§9.2b）。

**写冲突无关性**（同一拍内四条规则不同状态各碰各的槽）：分配目标必为
FREE、填充目标必为 FILL、下发目标必为 READY/REPLAY——状态互斥 ⇒ 目标
槽互斥 ⇒ 每槽每拍至多一条规则写入。

**恢复模式语义**（逐条对应单 slot 版）：
- `m_awready=0`（不再分配——**分配⟸AW握手⟸awready⟸!mode** 三环相扣，
  恢复期槽集合只减不增，all_free 不会被 master 重新填槽饿死；master 挂着
  awvalid 是合法背压，退出后下一拍立即握手）；`m_wready=has_fill`（FILL 槽
  的拍全吞、缓冲至 WLAST 丢弃，违例尾拍不设溢出门也吞；**无 FILL 槽的
  孤儿拍 stall 不吞**——那是 AW 未握手写的数据，吞掉=消费无账数据，退出
  后该 AW 握手开的 FILL 将等不到已消费的 WLAST → 永卡；stall 把它们留给
  退出后交付，坑 7 保证退出只看账不看 VALID，死 master 的 VALID 由
  ADB400 撤走（Unit B）或退出后自行流入（Unit A）——v2.3 修复，v2.1 是
  无条件 sink）；
- READY 槽未过界 → 丢弃；REPLAY 槽用真数据跑完（死 slave 卡 replay →
  all_free 永不成立 → 退出阻塞 → fail-visible；**出口**：对端在复位保持
  时 force_clear 丢弃（§8.5，2b））；
- **恢复静止点**：全部 slot FREE 且处于 mode 时三指针强制归 0——恢复
  结束后的环从一致起点重启（否则指针残留在不同相位，重启后 fill 路由
  可能错槽）；
- `force_clear`（bdry_in 的 QSR_REL；recover 的 `s_in_rst ∧ mode ∧
  wr_otd==0`，即 2b 卡死 REPLAY 的受控出口）：同步清槽+指针，但**不清
  故障锁存**——事件必须报告到复位。

**为什么不做成参数化的更深 skid**：2 slot 已达 ~100% 占空（再深无吞吐
收益），wopen 保持小常数（§5.7 论据 2），面积/复杂度封顶；需要
OTD_MAX 级深度时另按论据评估，当前场景无需求。

---

## 6. 逐周期时序推演：normal → 恢复 → normal

### 6.1 读数据相挂起（len=3 的 4 拍读，slave 死在第 2 拍后）

设：TH1=20，master 发 1 笔 ARLEN=3 读；slave 回了 2 拍后死；m_rready=1。

```
── normal ──────────────────────────────────────────────────────────────
 T0  : AR 握手(m,s 同拍)。rd_otd 0→1；ar_fifo push{id0,3}；rbeat_cnt=0。
 T1-T2: R beat1/2 交付(m/s 同拍)。rbeat_cnt→2。
 T3..: slave 死，无 R beat。rd_cnt_r 每周期 +1。
 T21 : cnt_r ≥ thr-1 → r2r sticky 置位 → err_event 上升沿。
 T22 : recover_req 脉冲（wrapper 边沿检测）。
── 恢复 ────────────────────────────────────────────────────────────────
 T23 : mode_r=1 生效：m_arready=0；s_rready=1（吸收）；s_arvalid=0；
       dummy R 引擎：otd=1≠0 → m_rvalid=1。
       rbeat_cnt=2, len=3 → 本拍是第 3 拍，rlast=0。
 T24 : R beat3 握手（SLVERR,rid=id0）。rbeat_cnt→3。
       rl 条件 rbeat_cnt(3) ≥ len(3) → 下一拍是末拍。
 T25 : R beat4 握手，m_rlast=1。
       monitor: rl 握手 → rd_otd 1→0；ar_fifo pop；rbeat_cnt→0。
 T26 : 账本检查：rd_otd=0, wr_otd=0, skid 双槽全 FREE → recover_exit
       → mode_r ← 0。
── normal（回到常态）───────────────────────────────────────────────────
 T27 : 纯直通（含 id 重映射/还原）。master 已拿到完整的 4 拍 SLVERR 读
       （rid 与它发的 AR id 完全一致，len 精确）。
 剩余：r2r sticky 仍置位、err_event 仍高（等 SW W1C）。
 SW  : 修 slave → W1C 0x04 → err_event 落 → 交通恢复。
```

闭环要点：**dummy 的每拍握手都发生在 m 侧 = monitor 观察点** → otd 按
真实语义递减 → 恢复退出条件由 monitor 亲自证明，无旁路"完成"信号。

### 6.2 写半截 W 挂起（aw ost > 已发 W 拍，skid 上场）

设：master 发 AW（len=3, id2），W 发了 2 拍后 master 侧 W 源停住。

```
 T0  : AW 在 m 侧握手（skid 某槽 FREE→FILL，AW 负载锁存——注意此时
       s 侧还没有任何信号！）。wr_otd 0→1；aw_fifo push{id2}；wopen 0→1。
 T1-T2: W beat1/2 入缓存（fill_cnt→2）。s 侧仍静默（等攒齐）。
 T3..: master W 停（wvalid=0）。wopen=1 → wr_req_pend → r2a 计数。
 ...  : 超时 → err_event 上升 → recover_req → mode_r=1。
 Tn  : 恢复动作：m_wready=1（master 再发的拍全吞）；skid 某槽处于 FILL，
       半截数据在缓存里但**从未过界**——WLAST 到达时直接丢弃（FILL→FREE）。
 同期: master 把剩余 W 拍发给 m 侧（被 sink）；WLAST 过 m 侧 →
       wopen→0（wr_dlv+1，与 wr_otd 差归零），wm 推进 →
       dummy B 门控(bp≠wm)打开。
 Tn+1: m_bvalid=1, bresp=SLVERR, bid=id2 → B 握手 → wr_otd 0，
       aw_fifo pop(bp)；skid 双槽已全 FREE。
 Tn+2: rd_otd=0 ∧ wr_otd=0 ∧ skid 双槽全 FREE → mode_r←0 → 回 normal。
       （master 收到 SLVERR：写从未到过 slave，不得提交数据。）
```

对比另一支——**slave 死在 replay 中途**（W 已攒齐、AW+W 已开始下发）：
恢复时 replay 继续（缓存真数据），slave 活则跑完 → dummy B；slave 死
（wready=0）则 s_wvalid 保持 offer、退出阻塞——fail-visible，等 ESM。

两条链路依然独立：**replay 走 s 侧**（了结下游，真数据），**dummy B 走
m 侧**（了结 master）——互不阻塞、可并行收敛；唯一顺序约束是 B 等 m 侧
WLAST（`bp≠wm`），因为那是 master 侧"事务完整发出"的标志。

### 6.3 地址相挂起

```
 T0  : master ARVALID=1，slave ARREADY 永远 0。rd_cnt_a 每周期 +1。
 ...  : r2a sticky → err_event 上升 → recover_req → mode_r=1。
 Tn+1: otd 本来就是 0，wopen=0，wp==wr → recover_exit 立即成立
       → mode_r←0 → 直通。master 的 ARVALID 还挂着（合法）。
   a : slave 已修 → AR 立刻握手 → 正常完成（fifo push → 正常 R 还原 id）。
   b : slave 未修 → cnt_a 继续涨；SW W1C 后立即再触发 → 新一轮恢复
       （fail-visible 的"每 W1C 一轮"循环）。
```

### 6.4 W1C 与再触发语义（服务规程）

fire 条件是**电平比较**（cnt ≥ thr-1），不是事件。计数器在故障存续期持续
> 阈值：**W1C 清 sticky 后，若挂起条件仍在，下一周期立即再置位**。这不是
bug，是 TI 的 T6 语义（"清不掉 = 故障持续"）。软件规程：

1. **先修根因（slave 复位/隔离），再 W1C**；
2. 想临时静默用 ENA=0x0 关监控（keyed），比反复 W1C 干净；
3. W1C + TO_CLR 一起写重启计数器，把再触发等待窗拉长到整个阈值周期。

### 6.5 入向：main 发 AW 后 W 发一半死亡（WLAST 永远等不到）

Unit B（main→island）的典型死法——master 本身死亡。四阶段：

**① 出事（normal）**：AW 在 m 侧握手（skid 某槽 FREE→FILL，AW 负载锁存、
aw_fifo push、监视器 wr_otd+1）；k 拍 W 入 wbuf；main 死。
**下游（岛内）从头到尾没见过这笔 AW**——s_awvalid 只在某槽 READY 呈现。

**② 检测（必然报警，无需 valid 挂着）**：写流 pending 条件的第三项
`wr_otd(1) != wr_dlv(0)` 恒成立——"写请求发了一半"本身就是 pending，
且再无进展事件 → r2a 计数无界上涨 → sticky → err_event 上升沿 →
blk_r=1（隔离态）。

**③ 隔离态（硬件到此为止，是设计意图）**：
- 岛侧零影响：AW 从未过界，NIC/SRAM 无此账，其他岛主机照常（S2 目标达成）；
- skid 某槽卡死在 FILL（等一个永远不会来的 WLAST）；dummy B 被
  `bdum_owed==0` 门控**正确地不发**（master 写未完整发出，过早回 B 违背
  master 侧语义；v3.4 前门控写作 `aw_bp≠aw_wm`，语义相同）；
- **硬件自动退出不可能**：欠的 WLAST 只有 main 能还，main 死了账就
  永远挂着——block_active/sticky/ESM 持续保持 = fail-visible。

**④ 软件服务（QSR_REL 三步曲，唯一出路）**：

```
 1. ESM: 读 SCMIAERR0STAT(写流 r2a 位) + SCMOTD(wr_otd=1, 预期挂账)
 2. 系统级: ADB400 隔离 + main 复位保持        ← 硬性前提(见下)
 3. 写 SCMCNTRL=0x10AF (QSR_REL) → 安全周期 → 退出动作:
      blk_r←0; skid 强清双槽 FREE(卡死的 FILL + AW 负载 + k 拍数据全弃,
      安全: main 已复位且数据从未过界); aw/ar FIFO 指针清零
 4. 写 SCMCNTRL=0x1AF (TO_CLR): 监视器 wr_otd 归零, 与空 FIFO 重新一致
    ("账不丢"规则在 master 确证死亡时的例外: 账由软件清, 不由硬件等)
 5. W1C SCMIAERR0STAT → err_event 落 → ESM 解除
 6. 解除 main 复位/隔离 → main 全新起点发新 AW → skid 空闲正常收 → normal
```

**为什么 QSR_REL 前必须复位 main（硬约束）**：若 main 活着强清——skid 空、
fifo 空，但 main 心里这笔写还欠 W 拍，孤儿 W 拍发来时 `m_wready=0`
（skid 空、无 AW 对应）→ main 按规范必须永远挂 WVALID → 通路楔死。
复位是唯一把 main 的"心理账"也清掉的手段。

**对照（出向 Unit A 同场景）**：master=island NIC 活着，隔离/恢复态
`m_wready=1` sink 其尾拍 → WLAST 必到 → 账自愈 → dummy B → 自动退出。
同一个"半截 W + FIFO 有 AW"状态，**master 死活决定出路**：活→硬件等它
还账；死→软件清账。这正是两单元退出策略分叉的根源。

### 6.6 入向：main 发 AR 后死在半途 R burst（读版 S2）

与 §6.5 写版对称的场景：main 发出 AR，island（SRAM）回 R 到第 k 拍
（未到 RLAST），main 死、`m_rready` 拉不动。此时 **R 通道 valid 是 SRAM
拉的、ready 是 main 拉的**——SRAM 手握 k 拍数据和后续拍等握手，o.t 槽位
被占 → 其他 island master 访问 SRAM 挂起（S2 的危害）。

**检测**：监视器 m 侧 `rd_otd=1`（AR 收了、RLAST 未归）→ r2r 无界计数
→ err_event → blk_r=1（隔离态）。

**隔离态三件事**：

| 动作 | 代码 | 效果 |
|---|---|---|
| **岛侧吸收** | `s_rready = 1`（blk 强制） | SRAM 的 R 拍**逐拍收下并丢弃**，RLAST 被握手 → **SRAM o.t 槽位立即回收** → 其他岛主机恢复访问 ← S2 的核心保护 |
| m 侧 dummy R | LEN 精确补拍引擎（SLVERR, rid=FIFO 头） | main 活着收则退休；死了不收则 dummy 挂着等——无害，强清兜底 |
| 账本 | 读不碰 W skid | rbeat_cnt 接续已交付拍数 |

**出口**：与写版完全相同的软件三步曲（main 复位 → QSR_REL 强清
ar/aw FIFO → TO_CLR 归零 rd_otd → W1C → 解复位）。QSR_REL 的强清
对象覆盖 `rbeat_cnt`/`ar_rp`（FIFO 指针统一清零）。

**读写版 S2 的一个不对称性**：写版卡点在 skid + `bp≠wm` 门控（账的
归还路径整个断掉）；读版**岛侧通道在隔离瞬间就已恢复**（吸收不看
main 死活），卡住的只是"main 心里那笔读"的账——对岛的保护是
即时完成的，QSR_REL 只是收尸。

**出向 Unit A 的同形场景**（island master 发 AR、main IC 回了半途 R 后死，
master 活着拉 m_rready）：dummy R 从 `rbeat_cnt=k` 接着补 SLVERR 到
len+1 拍 → rd_otd 归零 → **自动退出**（与写版出向对称：活 master 必
配合）；迟到真 R 由幽灵吸收规则吞掉（otd==0 后 s_rready 恒 1）。

---

## 7. 寄存器模型（hang_prot_regfile）与软件配置序列

### 7.1 寄存器映射

mbus leaf 从机（单拍 `ce`、零等待、命令奇偶 `par`、无 wait/error 通道；`addr[15:8]`=实例号须等于参数 `IDX`，`addr[7:0]`=字节偏移），11 个 32 位寄存器（0x00–0x28）+ ID 殿后 0xFC，字对齐访问（非对齐/越界/写只读 → 静默忽略；坏 `par` → 写阻断/读门控 + PERR_CMD 锁存）。`mbus_clk` 与 `aclk` 可异步（CDC 在内）。写为 fire-and-forget：CDC 忙时写被丢弃并置 `SCMIAFUSTAT[5]` WR_DROPPED，依赖写前须轮询 `[4]` CFG_BUSY（见 §7.6）。

寄存器地图位置（house standard，与 fusa 全家族一致）：**STA_PAR 倒数第 3（0x24）、CFG_REGST 倒数第 2（0x28）、ID 殿后 0xFC**。CFG_REGST 用 house key `wdata[3:0]=4'b1010`（独立于 SCMCNTRL [7:4] 的本地 key 空间），错 key 写被静默丢弃（无锁存类，与其它 keyed 违例同样处理）。

| 偏移 | 名称 | 访问 | 复位值 | 字段说明 |
|---|---|---|---|---|
| 0x00 | `SCMIAERR0STAT` | **W1C/R** | 0x00000000 | `[NUM_IA-1:0]` req2accept 超时 sticky（读=IA0，写=IA1） |
| 0x04 | `SCMIAERR1STAT` | **W1C/R** | 0x00000000 | `[NUM_IA-1:0]` req2resp 超时 sticky |
| 0x08 | `SCMIASTAT` | R | — | IA 活动（pending），动态值 |
| 0x0C | `SCMOTD` | R | — | 每流 outstanding 深度，动态值 |
| 0x10 | `SCMCNTRL` | W/R | 0x0000000F | 见 7.2 |
| 0x14 | `SCMTHRESH0` | W/R | 0x0000000F | `[15:0]` REQ2ACCEPT_MAX |
| 0x18 | `SCMTHRESH1` | W/R | 0x000000FF | `[15:0]` REQ2RESP_MAX |
| 0x1C | `SCMIAFUSTAT` | **W1C/R** | 0x00000000 | `[0]` FU_FAULT（W1C）；`[1]`/`[2]`/`[3]` FU_FAULT_N / ERR_EVENT / ERR_EVENT_N（RO 双轨）；`[4]` CFG_BUSY（RO，CDC 写在途）；`[5]` WR_DROPPED（W1C，忙时写被丢弃） |
| 0x20 | `SCMIAFUSRC` | **W1C/R** | 0x00000000 | 完整性故障源（ENA/THRA/THRR + 每 master CNT/CMP/STAT + 顶位 OTDSAT） |
| 0x24 | `STA_PAR` | **W1C/R** | 0x00000002 | 寄存器奇偶状态（house standard 布局）：`[0]` PAR_FAULT / `[1]` PAR_FAULT_N / `[12:2]` PERR（**bit = 2+组号**），见 §7.2b。静息读 0x2 |
| 0x28 | `CFG_REGST` | **WO** | — | 寄存器奇偶自检控制（house standard）：key[3:0]=1010 + `[4]` REG_SELFTEST + REGSEL[11:8] + `[5]` PAR_SELFTEST，见 §7.2c。读恒 0；错 key 写静默丢弃 |
| 0xFC | `ID` | R | 0x4841_0001 | `"HA"` v1（house standard 殿后）。仅 `addr[7:0]==8'hFC` 精确译码（0x3C/0x7C/0xBC 落在 wsel 15 越界读 0） |

#### 7.2 SCMCNTRL 字段（0x10）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [7:4] | KEY | W | 必须为 `4'b1010`（0xA），否则整个写被忽略 |
| [3:0] | ENA | W/R | 使能码字：0xF 开 / 0x0 关；非法码字拒绝、回读不变 |
| [8] | TO_CLR | W（脉冲） | 重启实时计数器。动作写必须保 ENA=0xF |
| [9] | SELFTEST | W（脉冲） | 强制比较器触发，证明 err_event 上报链路 |
| [10] | FU_SELFTEST | W（脉冲） | 强制 fu_fault，证明监控故障上报链路 |
| [12] | **QSR_REL** | W（脉冲） | **入向边界单元隔离释放**：main 保持复位时 SW 退出隔离态（§8.4） |

（v3.3 地图起 PAR_SELFTEST/REG_SELFTEST/REGSEL 从 SCMCNTRL 移除，由 CFG_REGST 0x28 承担，见 §7.2c；原 [11]/[20]/[19:16] 写此处为无害忽略位。）

脉冲位只写当拍起效、读回恒 0；KEY 只写不读。

#### 7.2b STA_PAR 字段（0x24，house standard 布局）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [0] | PAR_FAULT | R（电平） | 寄存器奇偶故障 = 全部 PERR 位与自检锁存的 OR；直连 ESM 双轨 `reg_par_fault`/`reg_par_fault_n`。写 [0] 仅清除自检锁存，各 PERR 位在其 own bit 清除 |
| [1] | PAR_FAULT_N | R | PAR_FAULT 双轨补码 |
| [12:2] | PERR10..PERR0 | W1C/R | 每组奇偶错误，**bit = 2+组号**（house standard）。组 k = 偏移 0x4*k 的寄存器（4..6 = mbus 镜像 + aclk 影子两处 sticky 汇总）；组 9 = 在途写锁存奇偶（latch lane，无注错目标、REGSEL=9 为文档化 no-op）；组 10 = PERR_CMD mbus 命令奇偶（W=1 wrap：sticky 体即 wrap 存储，写 bit[12] 是一次重写、重算奇偶）。组 10 详解：`ce` 当拍 `par != ^{addr, wr, wdata}`（**每次 ce 都检查，与实例号译码无关**）。坏奇偶写被阻断（不执行任何副作用），坏奇偶读门控为 0 |

每个 PERR 位清除对应组在**两个域**的 sticky（mbus 镜像同拍、aclk 影子经握手 req_edge 拍）；故障仍存活时重新置位。各 sticky 与 2 位锁存内部带反相副本（失配自愈为置位）。

#### 7.2c CFG_REGST 字段（0x28，house standard）

| 位 | 名称 | 属性 | 说明 |
|---|---|---|---|
| [3:0] | KEY | W | 必须为 `4'b1010`（house key），否则整个写被静默丢弃（无副作用、无锁存） |
| [4] | REG_SELFTEST | W（脉冲） | 逐组奇偶注入：翻转所选组的奇偶位（数据不动），经存储+比较器+sticky+ESM 完整链路上报 |
| [5] | PAR_SELFTEST | W（脉冲） | 强制 PAR_FAULT 但不置任何 PERR 位（无源注错），证明奇偶→ESM 上报链路（写 0x2A） |
| [11:8] | REGSEL | W | REG_SELFTEST 的目标组号（0–10 = 偏移 0x4*k 的寄存器，10 = CMD wrap；9 = 在途锁存 lane、无注错目标、忽略），>10 时注入被忽略 |

读恒 0（WO）；典型写值：组 k 注入 `0x1A \| (k << 8)`、PAR_SELFTEST `0x2A`。

### 7.3 软件配置序列 —— 上电初始化（出向 Unit A 场景）

前置：`mbus_rstn` 与 `rst` 系统级同时断言、同步释放（CDC 握手对齐，§7.5）。

| 步 | 操作 | 寄存器/值 | 功能说明 |
|---|---|---|---|
| 1 | 读 | `SCMCNTRL` | 确认回读 `[3:0]=0xF`（复位默认使能码字）+ `[7:4]` 读回为 0（KEY 只写）——同时验证 mbus 通路与复位值 |
| 2 | 读 | `SCMIAERR0/1STAT`、`SCMIAFUSTAT`、`STA_PAR` | 状态全 0、`STA_PAR` 恰为 0x2（仅 PAR_FAULT_N）= 复位干净；否则复位不完整或已有故障 |
| 3 | 写 | `SCMTHRESH0 = REQ2ACCEPT_MAX` | 配地址相阈值。**必须 > 最坏合法等待**：满 FIFO(OTD_MAX 笔) 排空时间 + 仲裁延迟。写不需要 KEY（阈值寄存器无钥匙；监控核有码字使能与副本校验兜底） |
| 4 | 写 | `SCMTHRESH1 = REQ2RESP_MAX` | 配数据相阈值。必须 > slave 最坏合法响应延迟（含 256 拍突发整流时间） |
| 5 | 写 | `SCMCNTRL = 0x1AF` | KEY=0xA + ENA=0xF + TO_CLR：以 keyed 动作**重启所有实时计数器**，从干净起点开始监控（也验证了 key/动作链路） |
| 6 | （可选，周期性） | `SCMCNTRL = 0x2AF`（SELFTEST） | 强制一次 err_event → ESM 应收到事件 → 证明**事件上报链路**活着（FuSa 周期诊断） |
| 7 | （可选） | `SCMCNTRL = 0x4AF`（FU_SELFTEST）→ W1C `0x1C[0]`/`0x20` | 证明监控器故障上报链路活着 |
| 8 | （可选） | `CFG_REGST = 0x2A`（PAR_SELFTEST）→ W1C `0x24[0]` | 证明寄存器奇偶上报链路活着（v1.2 地图：自检键在 CFG_REGST，house key 1010） |
| 9 | 读 | `SCMOTD`、`SCMIASTAT` | 业务流量起来后确认 otd 在 0..OTD_MAX 内活动（动态值，两读一致才可信） |

### 7.4 软件服务序列 —— S1（出向超时恢复）

硬件已自动完成：恢复 → dummy → 四本账归零 → 回 normal（§6）。
软件在 ESM 中断里做收尾：

| 步 | 操作 | 寄存器/值 | 功能说明 |
|---|---|---|---|
| 1 | 响应 ESM | `err_event` 双轨 | 只读事件，不写任何寄存器——**不要在中断里先 W1C**（根因未除，清了立刻再触发） |
| 2 | 读 | `SCMIAERR0STAT`（0x00） | bit0=读流 r2a、bit1=写流 r2a → **地址相挂死**（req 发不进去） |
| 3 | 读 | `SCMIAERR1STAT`（0x04） | bit0/bit1 → **数据相挂死**（接收了没响应）。两表组合定位故障性质 |
| 4 | 读 | `SCMOTD`（0x0C） | 0 = 硬件恢复已完成（四本账归零）；非 0 = 恢复仍在进行（master 扣 W 或 slave 吞 dummy 握手——等/升级处理） |
| 5 | 修根因 | 系统级 | 复位/隔离挂死的 main 域 slave 或通路（这是唯一真正的"修"） |
| 6 | 写 | `SCMCNTRL = 0x1AF`（TO_CLR） | 计数器重启：把"再触发等待窗"拉回完整阈值周期，便于观察修复效果 |
| 7 | 写 | `SCMIAERR0/1STAT`（W1C，写 1 清对应位） | 清 sticky → err_event 落 → ESM 事件解除。**放在修根因之后**（§6.4） |
| 8 | 观察 | 轮询 `SCMOTD`/状态 | 若再触发（新上升沿、新一轮自动恢复）→ 根因未除，回到第 5 步升级 |

### 7.5 软件服务序列 —— S2（入向隔离释放，QSR_REL）

硬件自动做了：进入隔离（block）→ 吸收 island 侧 R/B →（活着的 main 收
dummy；死掉的 main 不收，账挂着）。退出**必须**软件 keyed 放行：

| 步 | 操作 | 寄存器/值 | 功能说明 |
|---|---|---|---|
| 1 | 响应 ESM，读 `SCMIAERR0/1STAT` 定位 | — | 同 S1 第 1–3 步 |
| 2 | 隔离 main 域 | 系统级：ADB400 iso 使能 + main 复位保持 | 硬件前提：QSR_REL 时 main **必须在复位**（否则单元退出的瞬间会把撤回的 dummy 暴露给活 master） |
| 3 | 确认 island 干净 | （可轮询 `SCMOTD`，但死 main 挂账不归零是**预期**的——见 §8.3"检测 vs 记账"） | otd≠0 不阻塞 QSR_REL；退出条件是**本地**安全条件（s 侧无 pending R/B、无 REPLAY） |
| 4 | 写 | `SCMCNTRL = 0x10AF`（QSR_REL，KEY+ENA+bit12） | keyed 隔离释放脉冲。单元在下一个**安全周期**退出：清 ID FIFO、强清残留 skid（死 main 留下的半截 FILL）、block_active 落 0。main 侧经 ADB400 隔离后无任何在途信号，强清是安全的 |
| 5 | 写 | `SCMCNTRL = 0x1AF`（TO_CLR） | **必须**：把监视器里挂着的陈旧 otd/计数器清零（死 main 永远不会握手 dummy，这些账只能软件清；TO_CLR 后 otd 与已清空的 FIFO 重新一致） |
| 6 | 写 | `SCMIAERR0/1STAT`（W1C） | 清 sticky → err_event 落 → ESM 解除 |
| 7 | 恢复 main | 系统级：解除 main 复位 → ADB400 iso 撤销 | main 从复位起来，通路两侧都是干净状态 |
| 8 | 观察 | 轮询 | main 业务恢复，岛内全程未受影响（这正是 Unit B 的设计目标） |

**顺序为什么是 QSR_REL → TO_CLR → W1C**：先放行（硬件清 FIFO）再清账
（软件清计数器）再清事件——顺序颠倒会在中间态出现"FIFO 空但 otd≠0"的
账本失配，虽无功能危害（otd 只用于 dummy 使能和状态），但诊断时读数混乱。

### 7.6 CDC 与寄存器奇偶（要点）

- **写方向**（mbus→aclk）：单飞 toggle 握手，数据保持稳定跨域（无需 Gray 码）；同一时刻最多一个写在途；任何译码（含无效 key 的忽略型写）都被 ack，握手不会悬挂。mbus 零等待：忙时到达的写被丢弃并置 `WR_DROPPED`（sticky，fail-visible）——软件的依赖写前先轮询 `SCMIAFUSTAT[4]` CFG_BUSY 为 0。
- **读方向**（aclk→mbus）：sticky 位逐位独立同步；读组合返回、零等待；坏 `par` 读门控为 0；动态多比特值（IASTAT/OTD）读取有竞态——仅影响观测，重读解决。
- **命令奇偶**：每次 `ce` 检查 `par == ^{addr, wr, wdata}`（与实例号译码无关）；失配 → 写阻断/读门控 + `PERR_CMD`（`STA_PAR[12]`，bit = 2+组10，W1C 即 wrap 重写）。
- **逐寄存器偶校验**：每个寄存器在自己所在时钟域是独立 `reg_wrap`（存储+偶校验+selftest 注入+自身故障 sticky）；W1C 一次写、两域同清。
- **配置旁路时序（cfg_wr 寄存一拍）**：`cfg_ena/cfg_key/cfg_req2a_max/cfg_req2r_max` 由 shadow 寄存器驱动，写落地的那一拍 `cfg_wr` 必须**晚一个 aclk**（`cfg_wr_q`）再脉冲——否则监控核在 shadow 的 NBA 更新同一拍采样，拿到的是上一次写的旧值（配置总线滞后一笔写：ENA 关→开序列会把监控核永远留在关态）。与 ia regfile 的 `cfg_wr_q` 做法一致。
- **复位**：`mbus_rstn` 与 `rst` 必须系统级同时断言、同源同步释放，否则第一次写可能丢——集成约束。

---

## 8. Safety Island ↔ Main 域边界隔离设计（hang_prot_bdry_in + ADB400）

### 8.1 方向决定一切：Unit A vs Unit B

| 维度 | Unit A（出向，recover） | Unit B（入向，bdry_in） |
|---|---|---|
| master 是谁 | island NIC（**活着**） | main（**可能死**） |
| slave 是谁 | main 域（**死/伤**） | island NIC+SRAM（**要保护**） |
| AW/W 转发 | **store-and-forward（v2.1）**：AW 等齐 W 一起下发，半截 W 从不过界；恢复时未过界的丢弃、REPLAY 用真数据跑完 | 同左（本来就如此设计） |
| dummy 响应给谁 | 活 master → 必被接收 → otd 可归零 | 可能死的 master → 可能永远不收 → otd 可能挂账 |
| 退出方式 | **自动**（otd==0 ∧ skid==EMPTY） | **软件 keyed**（QSR_REL，前提 main 在复位） |
| ID 重映射 | s_arid=AR_ID / s_awid=AW_ID，m_rid/m_bid 从 FIFO 还原 | 同左（镜像方向） |
| dummy R | LEN 精确、带原始 id | 同左 |
| dummy B | 门控 bp≠wm | 同左 |
| dummy W | **无（v2.1 起与 B 相同）**——skid 保证过界的 W 永远完整 | **无**——同理由 |
| 幽灵吸收 | otd==0 时吸收 s 侧 R/B | 同左 |

### 8.2 Unit B 详细框图（5 通道 vld/rdy）

```
        main 域 (经 ADB400, island 时钟)          island NIC SI 口
═════════════════════════╦══════════════════════════╦═══════════════════════════
                          ║  hang_prot_bdry_in       ║
 AR  m_arvalid ──────────▶║ 门(otd<MAX, !blk)───────▶║ s_arvalid ──────────────▶
     m_arready ◀──────────║ ◀────────────────────────║ s_arready ◀──────────────
                          ║ push{arid,arlen}         ║ s_arid = AR_ID_REMAP|cls
     m_rid ◀══════════════║═┌────────────────┐       ║  (v2.3: 类域,同§3.6)
 R   m_rvalid ◀──mux──────║ │ AR FIFO×N类    │       ║ s_rvalid ──────────────▶
     m_rready ───────────▶║ │ rbeat_cnt[cls] │       ║ ◀ s_rready ◀──absorb─────
     m_rresp/rlast ◀──────║ └────────────────┘       ║   (blk∨otd==0 → 1)
     m_rdata=0(wrapper mux)║ blk: LEN精确dummy(自选类)║ (s_rid类域→返回路由)
                          ║                          ║
 AW  m_awvalid ──────────▶║ ┌────────────────┐       ║ s_awvalid ◀─READY槽─────
     m_awready ◀──────────║ │ W skid (2 slot)│──────▶║   (仅 normal；blk 时丢弃)
     m_awid ─────────────▶║ │ FREE→FILL→     │       ║ s_awid = AW_ID_REMAP
                          ║ │ READY→REPLAY   │       ║ s_awaddr/len/size/burst
 W   m_wvalid ───────────▶║ │ 每槽AW负载+W缓存│      ║   = issue槽锁存值
     m_wready ◀──────────▶║ │ 环形3指针       │──────▶║ s_wvalid ◀──REPLAY──────
     m_wlast/wdata/wstrb ▶║ │ k补发时k+1可攒  │       ║ ◀ s_wready ◀─────────────
                          ║ └────────────────┘       ║
                          ║ push{awid}               ║
     m_bid ◀══════════════║═┌────────────────┐       ║
 B   m_bvalid ◀──mux──────║ │ AW FIFO        │       ║ s_bvalid ──────────────▶
     m_bready ───────────▶║ │ bp / wm        │       ║ ◀ s_bready ◀──absorb─────
     m_bresp ◀────────────║ └────────────────┘       ║   (blk∨otd==0 → 1)
                          ║ blk: B dummy 门控 bp≠wm  ║
   ═══ m 侧（监视器观测点）══║═══ s 侧（岛内）═════════║
                          ║   ▲ rd/wr_otd, recover_req, quiesce_rel(SCMCNTRL[12])
                          ║ [hang_prot_core 流1] + [hang_prot_regfile]
                          ╚══════════════════════════╝
```

### 8.3 W skid：双 slot store-and-forward（v2.3，与 Unit A 共享模块）

```
 每slot: FREE --m AW握手(锁存负载)--> FILL --WLAST--> READY --s AW握手--> REPLAY --补发完--> FREE
          |                              |                |                     |
       仅normal开门                  blk: WLAST→丢弃回FREE  blk: 未被接受→丢弃    即使blk也补发完
                                     (m侧剩余拍照收=吞)    (从未过界)           (完整合法burst)
 环形: alloc(分配)/fill(最老FILL)/issue(最老READY|REPLAY) 三指针追逐，k 补发时 k+1 可攒
```

- **为什么入向必须 store-and-forward**：岛是受保护方且**不复位**。半截 W
  突发一旦进了 NIC/SRAM，岛侧要吃协议违例（slave 等 WVALID 永远等不到
  wlast）——污染不可清除。所以 W 必须攒齐 WLAST 才放行。
- **为什么 v2.1 起出向也采用**：入向是"半截写绝不能进不复位的岛"（硬约束）；
  出向采用同一结构后额外收获——dummy W 引擎整个删除（过界的 W 永远完整、
  恢复用真数据 replay），两个单元结构收敛，只差退出策略。
- **v2.3 双 slot（两单元同时升级，共享 `hang_prot_wskid`）**：`m_awready`
  在任一 slot FREE 时给出（+ otd<MAX）——slot k 补发时 slot k+1 可同时
  攒齐，边界写占空 ~100%（v2.1 单 slot ~50%）；wopen ≤2（§5.7 论据携带）。
  详细结构/时序/恢复语义见 **§5.9**（同一模块，此处不重复）。
- **REPLAY 在 blk 期间也跑完**：那是一笔完整合法的突发，让它完成保持
  NIC 写通道一致性；它的 B 按隔离规则吸收/dummy。

### 8.4 隔离进入/退出与 quiesce 序列

```
进入（自动）: recover_req 脉冲 → blk_r=1 自保持
  - m_arready/m_awready = 0        （main 停发；ADB400 岛侧半片看不到新请求）
  - m_wready = has_fill            （FILL 槽的拍全吞——ADB400 W 通路不楔死；
                                     无槽的孤儿拍 stall，死 main 的 VALID 本就
                                     被 iso 撤走，不会积压）
  - s_rready/s_bready = 1          （岛侧还在吐的 R/B 全吸收→NIC/SRAM 回收 o.t
                                     → 其他岛主机照常访问 SRAM ← S2 的解）
  - m 侧 dummy R/B 引擎照 §5 规则  （活着的 main 收到带正确 id 的 SLVERR 退休；
                                     死掉的 main 不收——dummy 挂着，无害）
退出（软件 keyed）: QSR_REL → qrel_pend → 安全周期（!s_rvalid ∧ !s_bvalid ∧
  skid quiesce_ok：每槽解码为合法非 REPLAY 码）→ 退出动作：
    block_active←0；skid force_clear（槽+指针，故障锁存不清）；**清 ID FIFO
  全部指针（含各类 ar FIFO）**
  （安全前提：main 在复位、ADB400 iso 已撤掉 main 侧 VALID——残留的半截
  FILL 是死 main 的遗物，强制丢弃；若 SW 违反前提在 main 活着时放行，
  行为是 fail-visible 的：其 W 拍会被 stall，监视器 r2a 报警）
随后（软件）: TO_CLR 清陈旧 otd → W1C 清状态 → 解除 main 复位/iso → 恢复
```

**检测 vs 记账（入向的本质差异）**：监视器 otd 只经 m 侧 dummy 握手递减；
死 main 永不握手 → otd 全程可能非零——**检测**（sticky/ESM）始终正确，
但**退出不能用 otd**，用本地安全条件（s 侧 pending、skid 状态）。退出后
TO_CLR 把账拉平。

### 8.5 对端复位重启的通道清洁（5 通道 idle 契约，v2.3）

**需求**：main 域复位重启后，main 端口面对的 5 个 AXI 通道必须全部 idle
（本单元驱动的 VALID 全 0；main 自己的 VALID 由其复位保证为 0）——否则
复活即见"非预期响应/非预期 W 数据"（脏状态或永久楔死）。逐通道核查：

| 通道 | 方向 | 本单元驱动的 VALID | 清洁机制 |
|---|---|---|---|
| Unit A W（main 在 s 侧，场景 2） | s | `s_awvalid` / `s_wvalid` | 恢复态前者恒 0；后者（2b 卡死的 REPLAY）由 **`s_in_rst` force_clear** 清 0 |
| Unit A AR（main 在 s 侧） | s | `s_arvalid` | 恢复态恒 0（单拍请求，撤回=R1；读响应**流入**死域外，无存储、无 2b 等价物——见下节） |
| Unit B R/B（main 在 m 侧，场景 1） | m | `m_rvalid` / `m_bvalid` | 挂住的 dummy 在 **QSR_REL 退出拍撤回**（`blk_r` 的组合函数，退出下一拍即 0；FIFO/rbeat_cnt 同拍全清） |

（表首两行原为一行合并，v2.3 拆分以显式覆盖 AR；READY 通道非污染向量：
复位中的对端不采样，复活后 ready=1 只意味着"可以发"。）

**Unit A 新增 `s_in_rst`（ESM 驱动，aclk 域电平，v3.2 起双轨）**："main 域
在复位保持中"。三个作用，缺一不可：

1. **强制进入恢复**：main 每次复位都必须穿过一个"先排空、再清洁"的边界，
   不限于已检出的挂死——NIC 在途事务由 dummy 引擎以 SLVERR 退休（main
   已忘，SLVERR=写"结局未知"，重试覆盖）；不复位直接换 main 会留下孤儿事务。
2. **受控槽清除（2b 出口）**：`s_force = s_in_rst ∧ mode_r ∧ wr_otd==0`
   → wskid force_clear。main 已复位 ⇒ 其 AW 接受记录已抹 ⇒ 丢弃 REPLAY
   剩余真数据拍是**双方一致遗忘**的选择；该条目的账早已由 dummy B 退休。
   `wr_otd==0` 门控保住 FILL 吸收通路（活 NIC 的 W 中途不得强清，坑 1）。
   故障锁存不清——受监督的恢复，事件仍上报。
3. **退出推迟到 `!s_in_rst`**：整个复位窗口内 mode 保持（m 侧停发、s 侧
   静默），没有新请求被 offer 给复位中的 main；ESM 先释放 main 复位、再
   撤 s_in_rst → 下一拍退出 → 通道重开。

**`s_in_rst` 双轨（v3.2 FuSa）**：单轨下 stuck 是危险失效——**stuck-0**
静默丢掉复活 main 的通道清洁保护（2b 的 REPLAY 拍会灌进已忘 AW 的 main，
非预期数据）；**stuck-1** 把边界永远锁死（fail-visible 但无人知道）。
故 ESM 契约改为互补双 `{s_in_rst, s_in_rst_n}`（同源复位保持触发器或
双份序列器输出）：每拍 XOR 检查（`sir_dis`，1 拍检出），失配按内部完整性
故障同一语义处理——**强制进入恢复（fail toward containment：复位状态
不可信时唯一安全方向是通路关闭）、失配存活期间退出阻塞、iflt 粘滞经
sk_fault 双轨上报**。双轨残余（两线同翻转）由周期 SELFTEST + ESM 端到端
监督兜底，与其余双轨同待遇。

**ESM 服务序列（Unit A，2b）**：
```
卡死可见（mode=1 长期不退，recover_done 不来）→ ESM 拉 main rst
  ∧ s_in_rst/_n 轨对 → 排空（dummy 退休 NIC 在途）→ wr_otd=0 → s_force
  清 REPLAY → all_free（退出仍被 !s_in_rst 压住）→ 释放 main rst → 撤
  s_in_rst/_n 轨对 → 退出 → NIC 挂着的 awvalid 下一拍握手，流水续上
```

**SW 服务序列（Unit B，1b 挂住的 dummy）**：QSR_REL 写入时 main 必须在
复位里（§8.4 前提）；退出拍撤回 dummy VALID（无握手撤回，R1 类残留——
对端在复位中，事务已系统级死亡，撤回不可见）→ FIFO 全清 → TO_CLR →
**先**解除 main 复位。复位释放晚于退出至少一个时钟（SW/ESM 节奏天然
满足）。

**读通道为何无 2b 等价物（读/写不对称性）**：W 的 REPLAY 是"**我们持有
数据、要推进死域**"——skid 存着 burst，死 main 永不接，故需 `s_in_rst`
受控清。读的响应数据**流向相反**——从死域流出，边界只是阀门：真拍来了
**吸收不存储**（R 通道组合透传，无 buffer——挂住的绝不该是缓存的数据）；
缺的拍由 m 侧 dummy 凭账本（ar FIFO + rbeat_cnt）现造，接收方是**活着的**
master。s 侧唯一属于我们的读 VALID 是 `s_arvalid`（单拍，mode 内恒 0，
撤回= R1）。逐场景：**1b 读**=挂住的 dummy R 在 QSR_REL 退出拍撤回
（`m_rvalid` 是 blk_r 组合函数），rbeat_cnt 续拍一致性由
`rdum_last = rbeat_cnt ≥ len` 保证（mode 进入瞬间停在边界的恰是尾拍时
两者重合）；**2a 读**=AR 未过界即撤回，dummy 退休，自动退出；**2b 读**=
main 侧挂着的 RVALID 由 mode 内 `s_rready=1` 吸收、退出后由 occ==0
幽灵门控继续吸收。读的退出对 Unit A 永远可达（NIC 活），对 Unit B 由
QSR_REL 兜底——**读不需要 force_clear**。

**残留分类**：对端复位保持期间的 VALID 撤回/丢弃，与 s 侧撤回（R1）同类
——协议约束针对"活着的事务"，复位重启后双方状态同零，无事务可违。SW
违反前提（对端活着时 QSR_REL / 撤 s_in_rst 早于复位释放）行为是 fail-visible
的：脏 W/响应触发 r2a 报警，不会静默损坏。

### 8.6 ADB400 的职责边界

ADB400（或等效 CDC/隔离单元）在 main↔island 边界做：时钟域转换、电压
隔离（iso 撤断）、支持单侧复位。它**不**检测挂死、**不**终结事务——
那是 hang_prot 的事；hang_prot 也不依赖 ADB400 的"复位时 DECERR"能力：
过界的 W 永远完整（skid 攒齐 WLAST 才放行）、半截 W 根本过不了 skid——
**ADB400 内即使有残留，复位它自己两侧即可，无需特殊 drain 语义**。

### 8.7 复位树

```
 island rst ──────────────► Unit A / Unit B / 岛侧监视器/寄存器 aclk 半边
 main rst (受控于 ESM) ────► main 域; ADB400 main 侧半片
 s_in_rst (受控于 ESM) ────► Unit A（main 复位保持窗口的通道清洁，§8.5）
 presetn + rst 同源同步释放 ► regfile CDC 握手对齐（§7.6）
```

岛复位**永不**来自 main 域；QSR_REL 服务序列里 main 复位的拉起/放下都
在隔离态中完成；main 复位的拉起/放下必须伴随 `s_in_rst` 窗口（§8.5）。

---

## 9. FuSa / SIL2 分析（IEC 61508:2010）

### 9.1 设计原则

**fail-visible（每个单点失效收敛到可观测）**：
- dummy 用 SLVERR 不用 OKAY——恢复是"承认失败并了结"，不是"假装成功"；
- 误恢复签名：SLVERR 到达但 sticky 状态全 0 → SW 可识别"恢复单元自身
  毛刺/SEU"类事件（区别于真超时）。

### 9.2 各机制的单点失效覆盖

| 单点 | 后果 | 可观测路径 |
|---|---|---|
| mode_r/blk_r 卡 1 | 通路永久钳断 | 双轨失配 1 拍检出（v3.1）+ 下一请求 r2a 超时 → ESM |
| mode_r 卡 0（该恢复不恢复） | 挂死不隔离 | 原始超时 sticky 一直在 → ESM；轨失配强制进入受控态 |
| err_event 某轨断/搭 | 双轨失配 | ESM 侧双轨比较 |
| 计数器/阈值 SEU | 反相副本失配 | fu_fault + fu_src 定位；失配强制触发（宁可误报不迟报） |
| 比较器翻转 | 双比较器分歧 | fu_fault |
| sticky 被清 | 副本失配自愈置位 | 重新上报 |
| 寄存器位翻转 | 偶校验 | PERR bit → PAR_FAULT 双轨 |
| ID FIFO 条目损坏（v2 面） | **条目奇偶（v3.1 已实现）**：头表项检出 → iflt sticky；坏 id 若仍被用，恰好一笔 dummy 的 id/len 错，master 侧响应校验报错（fail-visible） |
| FIFO 指针/占用/rbeat 翻转 | 反相副本失配 1 拍检出（v3.1）→ 强制进入受控态 + 退出阻塞 + sticky |
| **sk_e 状态位翻转（两单元，v2.2）** | 非独热码被**连续检测** | 见 §9.5：sticky 双轨 sk_fault + 强制进入恢复/隔离 + 退出阻塞 |
| skid FSM 单点（Unit B） | FILL 楔死→写流 r2a；丢 replay→main 侧超时 | 各自的监视器 |
| skid 存储位翻转（v3.1） | W 拍/AW 载荷奇偶在跨 s 边界前检出 | sticky sk_fault + sk_integrity=0（检测并上报；burst 照常完成——中途截断会楔死岛侧 NIC，比单拍坏数据更糟，数据完整性归系统端到端） |
| skid 计数器/指针翻转（v3.1） | 反相副本失配 1 拍检出 | 同上（不再依赖楔死→r2a 的无界延迟路径） |
| err 边沿检测器翻转（v3.1） | 轨失配 → 强制一次 recover_req | 脉冲进受控态 + sticky（并入 skid_fault 组） |

### 9.2b skid 状态机 one-hot 完整性（v2.2，v2.3 扩为每槽独立）

**v2.3 起两个单元的 skid 都是共享的 `hang_prot_wskid`（2 slot）**：每个 slot
的状态 `st[0]/st[1]` 独立采用 **one-hot 编码**（0001/0010/0100/1000，
FREE/FILL/READY/REPLAY），各自带**恰好独热检测器**（非零 且
`st & (st−1) == 0`），两槽检测相与后为 `sk_onehot`。任何非独热码
（SEU/卡死）触发四重响应：

1. **sticky 双轨故障输出** `sk_fault/sk_fault_n`（独立 ESM 组，复位前
   不清——瞬态 SEU 也被记住；**force_clear 也不清**，QSR 后事件仍可见）；
2. **强制进入恢复/隔离**（`recover_enter` 加 `!sk_onehot` 项）：单元向
   受控态失效——出向 master 收到 SLVERR dummy（"SLVERR 无 sticky 状态"
   签名），入向岛侧静默；
3. **全解码比较天然遏制**：`m_wready` 要 FILL、`s_awvalid` 要 READY、
   `s_wvalid` 要 REPLAY、`m_awready` 要 FREE、`all_free` 要双 FREE——
   非法码**全部失配**，不可能半转发，两侧停住 → 监视器 r2a 报警；
4. **退出阻塞**：出向 exit 要 `all_free`（双槽解码 FREE）；入向
   quiesce_exit 要 `quiesce_ok`——**每个槽都显式解码为合法非 REPLAY 码**
   （FREE/FILL/READY 之一）。不能用 `!any_replay`：状态从 REPLAY 腐化成
   非法码时 NIC 可能正在岛侧收半截 burst，它已不再解码 REPLAY，此刻
   强清会把岛内写通道楔死；quiesce_ok 对非法码解码为假 → 隔离保持 →
   ESM。**治愈只靠系统复位**（致命完整性策略：硬件不自愈一个
   它已无法信任的状态）。
   指针（alloc/fill/issue，1 bit 各）单点失效楔死环形指针 → r2a → fail-visible。

仿真期另有 `$error` 立即报错（`SYNTHESIS` 宏保护）。wrapper 的
`skid_fault/skid_fault_n` 输出对不变（从 wskid 实例直连）；Unit B 的
`wskid_st` 观测口扩为 8 位（`{st[1], st[0]}`）。

### 9.2c v3.1 全模块 FuSa 补齐（SIL2 目标）

v3.1 之前 regfile=偶校验、core=反相双份、wskid=one-hot，其余 sv 文件的
安全相关状态只有"楔死→r2a→fail-visible"这条**无界延迟**兜底。v3.1 把
每个单元的安全相关寄存器都纳入显式检测（1 拍检出），失效反应统一为
**失效导向受控态（fail toward containment）+ sticky 上报**：

| 单元 / 文件 | 机制 | 失效反应 |
|---|---|---|
| hang_prot_wskid | 存储载荷奇偶：每 (slot,beat) 一位 `{wdata,wstrb}` 校验 + 每 slot AW 载荷一位；计数器/指针（fill_cnt/beats/ridx/alloc_p/fill_p/issue_p）反相双份 | `sk_integrity=0`（实时聚合）→ 父单元强制进入；sticky sk_fault；burst 照常完成（不中途截断，理由见 §9.2 表） |
| hang_prot_recover | mode_r 双轨；ar/aw FIFO 表项奇偶（push 写、head 查）；指针/占用/rbeat 反相双份；内部 sticky iflt；**v3.2：`s_in_rst` 输入轨对（sir_dis）** | 轨/失配 → 强制进入 + recover_exit 加 `!int_dis`（活失配不退出）；自愈瞬态仍被 sticky 记住；s_in_rst 轨失配同语义（复位状态不可信 → 通路必须关闭） |
| hang_prot_bdry_in | blk_r/qrel_pend 双轨；FIFO 表项奇偶 + 指针/占用/rbeat 反相双份（与 recover 同构） | 失配 → 强制进入 + quiesce_exit 加 `!int_dis`（不确定态永不退出——本单元危险方向是带在途流量退出） |
| hang_prot_top / main2mcu_mon | err_event 边沿检测器双轨（err_event_q_n） | 轨失配 → 强制一次 recover_req（脉冲进受控态）+ sticky edgeflt |
| mon 顶层（两方向） | 状态输出双轨化：recover_active/_n、recover_done/_n、block_active/_n（源寄存器内部双轨，ESM 传输侧可比对） | ESM 侧双轨比较 |

**聚合语义**：`sk_fault/sk_fault_n` 从"wskid 槽状态非独热"升级为**边界
完整性聚合故障**（wskid 内部故障 ∪ recover/bdry_in 的 mode/FIFO 故障 ∪
wrapper 边沿检测器故障），双轨聚合用"真轨 OR / 假轨 AND"——任一贡献者
轨对断掉，聚合对即出现 (1,1)/(0,0) 非法码，ESM 侧可检。进入条件从
`!sk_onehot` 换为 `!sk_integrity`（one-hot ∩ 载荷奇偶 ∩ 计数器双份）。

**注错验证**（iverilog，两 TB 全 PASS）：TB-A P11 / TB-B P9 注入
mode/blk 轨失配与 FIFO 指针副本失配，确认：(1) 强制进入受控态；
(2) 活失配期间退出被阻塞；(3) 指针补码注错必须用**全宽真补码**
`~aw_bp` heal（固定字面量 1'b1 不是 3-bit 补码，曾导致"heal 后仍失配"
的 TB bug——指针空闲值经回绕未必为 0）。
TB-A P13（v3.2）注入 `s_in_rst` 轨对失配（翻转单轨）：强制进入、
失配存活期间退出阻塞（idle 账本也不重开通路）、heal 后自动退出、
skid_fault 保持粘滞。

### 9.3 独立性论证要点

- err_event（真总线超时）与 fu_fault（监控器自身坏）走**不同 ESM 组**：
  坏掉的监控器不能与真超时不可区分；
- reg_par_fault 独立双轨：寄存器坏不影响事件语义；
- 共模残余（同数据两副本同时翻转）由周期 SELFTEST/FU_SELFTEST/
  PAR_SELFTEST + 启动端到端事务测试兜底（启动时发一笔已知事务走完整
  通路，验证含恢复链在内的全链）。

### 9.4 v2 新增的存储面（SEU 预算）

ID FIFO：读侧每类 `OTD_MAX × (ID_W + 8)` 位 + 每类指针/拍计数、写侧
`OTD_MAX × ID_W`（v3.2 默认 N_MCORE=2 → N_CLS=3：≈ 3×8×12 ≈ 300 bit）；
W skid v2.3 双 slot ≈ 2 × 16 × (DATA_W+STRB_W+辅助)
（默认 32+4 位数据面 ≈ 1.2 Kbit）。
相比 v1 新增的 SEU 暴露面，失效模式全部是有界的单笔响应 id/len 错或单槽
数据错（fail-visible，master 可检/slave 侧 ECC 可检），不产生"静默丢检"。
v3.1 起这些面全部带显式检测（条目奇偶/副本/双轨，§9.2c），检测逻辑本身
的残余共模仍由周期 SELFTEST 兜底；若 FMEDA 要求更严，指针三模仍是
明确扩展点。

---

## 10. 验证设计与集成约束

### 10.1 验证（TB-A / TB-B，iverilog 全 PASS：P1..P13 / P1..P9）

P1 复位回读 / P2 配置 / P3 正常流量 / P4 读数据相挂死 / P5 地址相挂死 /
P6 写 B 挂死 / P7 半截 W / P8 迟到 R 吸收 / P9 自检注入。
**v2 需要新增/改造的检查点**（TB 更新在待办清单）：

- id 往返：master 用多组不同 id 发请求，校验每个 R/B 的 rid/bid 与其
  发出的 id **逐笔精确对应**（FIFO 还原，不再只是"最后一个 id"）；
- **mcore 类 remap（v3.2，TB-A P12 已实现）**：非 mcore id 共享转发 id、
  mcore id（全匹配 MCORE_MASTER_IDS）各用 MCORE_REMAP_IDS[k]；正常模式
  逐 burst 校验还原 rid/次序/拍数；三类同时在途恢复时校验 dummy 引擎
  按类排空、每类还原该笔事务自己的 rid、真实+dummy 总拍数 = len+1；
- **s_in_rst 轨对失配（v3.2 FuSa，TB-A P13 已实现）**：翻转单轨 →
  强制进入受控态；失配存活期间退出阻塞（idle 账本也不重开）；heal 后
  自动退出；skid_fault 保持粘滞；
- dummy R 长度：len=0/1/15/255 各档，校验 dummy 精确补到 len+1 拍；
- **双 slot skid（v2.3）**：背靠背两笔写，校验 slot k REPLAY 期间
  slot k+1 可 FILL（吞吐检查：满速下 s_wvalid 无气泡）；恢复期两槽
  分别处于 FILL/READY/REPLAY 组合的枚举场景，校验各自丢弃/补发/dummy B；
- 半截 W 恢复：AW(len=N) 发 k<N 拍后挂，校验退出后 wr_otd/wopen 全零；
- FIFO 满背压：发 OTD_MAX+1 笔，校验第 MAX+1 笔被 stall 而非丢账；
- 幽灵吸收：恢复退出后人为再给一个 s_bvalid，校验被吸收、master 侧
  无 bvalid；
- bp≠wm：构造"B 想发但 master 还欠 WLAST"场景，校验 dummy B 等待；
- Unit B QSR_REL：死 main 挂账 + 强清 skid（含 stale FILL 槽）+ TO_CLR
  拉平的全序列。

### 10.2 集成约束（v2.3 全量）

1. **leaf 端同 id 保序 + 同 id outstanding ≥ OTD_MAX**（IC 能力，主流满足）；
   **多类时对每个类 id 都须满足**（类 id 对 leaf 只是普通 id）；
2. master 单主（NUM_M=1）；多主需 NIC 先聚合为单口再挂本单元；
   **读 mcore 类（v3.2）**：集成方给出 N_MCORE + MCORE_MASTER_IDS（各
   mcore 呈现的 m_arid 值）+ MCORE_REMAP_IDS（转发 id，低 CLSW 位 = k+1，
   综合期参数检查）；其余 master 共享 AR_ID_REMAP（低 CLSW 位 0）；
   mcore 数量任意（2/3/…，无需 2 的幂）；
3. req2accept 阈值 > 最坏合法等待：满额 FIFO 排空 + 仲裁延迟 + **W skid
   攒齐+补发时间（16 拍缓存的接收与重放 + master 的 W 发送节奏；双 slot
   下排空至多两笔攒齐中 burst，预算翻倍）**；
4. req2resp 阈值 > slave 最坏合法响应延迟（含 256 拍突发）；
5. Σ(o.t) ≤ 下游 outstanding 容量（§2.2，误报方向）；
6. `presetn` 与 `rst` 同源同步释放（regfile CDC）；
7. 岛内复位永不来自 main；隔离单元供电/时钟/复位全在岛内；
8. QSR_REL 时 main 必须在复位且 ADB400 iso 已生效；
9. master 需容忍 SLVERR（标准要求）；**不再要求**容忍提前 RLAST
  （v2 dummy 按 len 精确——v1 的该约束作废）；
10. TO_CLR 只允许在业务静默/隔离态使用（会清在途账）；
11. master 不得发超过 WSKID_BEATS 拍的写突发（**两个单元，每 slot**，
    默认 16=ARLEN15；违例会被溢出保护停收 → r2a 报警 → 恢复期可解，
    但属 fail-visible 违例）；
12. 重映射 id（含各类 id）不得与下游对 master 原始 id 有特殊路由/排序
    依赖的配置冲突；
13. **边界写吞吐（v2.3 已解）**：双 slot skid 下写占空 ~100%（slot k 补发
    时 slot k+1 可攒齐）；wopen ≤2 由 §5.7 论据覆盖。单 slot v2.1 的
    "一次一笔 burst"约束作废。
14. **ESM 必须互补驱动 `{s_in_rst, s_in_rst_n}`（v3.2）**：两根出自同一
    复位保持源（或双份序列器输出），任何时刻互为反相；失配会被本单元
    判为完整性故障并关闭通路（fail toward containment）。ESM 序列见
    §8.5。

---

## 11. 残余风险与设计决策总表

### 11.1 残余风险（v2 清点）

| # | 残余 | 等级 | 处置 |
|---|---|---|---|
| R1 | 进入恢复时撤回未被接受的 s 侧 VALID（AXI master 侧违例）；同类：对端复位保持窗口内撤回/丢弃 VALID（Unit B dummy 于 QSR_REL 退出拍、Unit A 卡死 REPLAY 于 s_in_rst 清除，§8.5） | 低 | 互连普遍容忍；复位窗口内对端不采样、事务已系统级死亡；文档化 |
| R2 | master 扣 W 不发 → wopen 不归零 → 恢复态保持 | 设计意图 | fail-visible，ESM/复位路径 |
| R3 | ID FIFO 无条目级奇偶（SEU → 单笔 dummy id/len 错） | 低 | master 可检；扩展点 |
| R4 | 共模（双副本同值同翻） | 极低 | 周期 selftest + 端到端启动测试 |
| R5 | FIFO 满背压若阈值过紧 → r2a 误报（安全方向） | 配置 | 阈值约束 #3 |
| R6 | ~~两单元写吞吐：一次一笔（skid 1 深）~~ | **已消除** | v2.3 双 slot skid：~100% 占空（§5.9） |
| ~~v1-R1~~ | ~~半截 W 留给域复位清~~ | **已消除** | v2.1 skid：半截 W 从不过界 |
| ~~v1-R2~~ | ~~dummy 读单拍 RLAST，严格 master 拒收~~ | **已消除** | v2 LEN 精确 |
| ~~v1-R4~~ | ~~晚到真实响应被窃给新事务~~ | **已消除** | v2 幽灵结构性吸收 |
| ~~v1-bug~~ | ~~B 通道端口未声明/未连接~~ | **已修复** | v2 全端口连接 |

### 11.2 设计决策总表

| # | 决策 | 备选 | 拒绝理由 |
|---|---|---|---|
| D1 | 观察点在 m 侧 | s 侧 | dummy 在 m 侧握手，s 侧看不到 → otd 永不清零 |
| D2 | 恢复触发用 err_event 上升沿脉冲 | 电平 | 电平+自动退出=2 周期振荡 |
| D3 | 恢复期 m_wready=1 吸收 | 0 堵住 | master 协议引擎锁死在发 W 态 |
| D4 | 迟到 R/B 吸收（ready=1） | 丢弃（ready=0） | slave RVALID 永挂 → 通道毒化 |
| D5 | dummy 用 SLVERR | OKAY | fail-visible 原则 |
| D6 | 退出条件=账本客观归零 | 软件放行 / 看 VALID | 软件门可能死在自己要解封的通路上；VALID 是 master 合法权利 |
| D7 | 活 otd 驱动 dummy（非入口快照） | 快照 | 入口拍握手竞态漏账 |
| D8 | ID 重映射到每方向单 id + FIFO | per-outstanding id 比较器 | leaf 保序使 FIFO 即记分板；省掉全部比较硬件 |
| D9 | id 还原在正常模式也生效 | 仅恢复模式 mux | 两模式同一路径，无模式切换毛刺；也修复正常模式响应 id |
| D10 | dummy R 按剩余拍补到 len+1 | 单拍 RLAST | 严格 master 不接受提前截断 |
| D11 | AW/W store-and-forward：AW 等齐 W 一起下发（v2.1，两单元） | 透传+dummy W 补齐（v2 过渡方案） | 半截 W 从源头不过界；恢复用真数据 replay，dummy W 引擎整个删除；代价=写串行化（D15 合并） |
| D12 | dummy B 门控 bp≠wm（B 后于 m 侧 WLAST） | 立即回 B | wr_dlv 账目负漂移 + 恢复期虚假 r2a |
| D13 | otd==0 时吸收 s 侧 R/B（幽灵门控） | 无条件透传 | 响应窃取；FIFO 头读越界 |
| D14 | FIFO 满背压 otd<OTD_MAX | 无背压 | FIFO 溢出丢账；监视器即水位，天然同步 |
| D15 | W store-and-forward（v2.1 起两单元一致） | 透传 | 半截写绝不能过界（Unit B：岛不复位；Unit A：省掉 dummy W 引擎） |
| D16 | Unit B 退出 = keyed QSR_REL + 强清 | 自动退出 / 不清 | master 可能死（otd 永不归零）；不清则 FIFO 与 TO_CLR 后的 otd 永久失配 |
| D17 | 两单元均无 dummy W | v2 的假数据补拍方案 | skid 保证过界的 W 永远完整；超时未过界的丢弃数据、账走 dummy B（数据丢、账不丢） |
| D18 | sk_e one-hot + 恰好独热检测 + sticky 双轨 sk_fault（v2.2） | 二进制编码 / 仅 sim 断言 | 全解码比较天然遏制（非法码全失配、不可能半转发）；故障强制进入恢复/隔离；退出用显式解码防"REPLAY 腐化成非法码后强清楔死 NIC"；硬件不自愈不可信状态 |
| D19 | 双 slot W skid（v2.3，两单元共享 `hang_prot_wskid`） | 保持 1 slot / OTD_MAX 深 | 1 slot 写占空 ~50%（DDR 目标不可接受）；2 slot 已 ~100%，再深无吞吐收益且 wopen 失去小常数；共享模块消除两份同构代码的漂移风险 |
| D20 | 读多类 remap：类域取自 m_arid 位（v2.3） | 保持单 id / 完整透传原始 id | 单 id 跨 master HOL（M85 堵 DMA）；完整透传需要 per-id 记分板（比较硬件，v2 已拒绝）；类域把保序论证无损缩小到类内，FIFO 记分板结构不变。写不分类（被 skid 串行化，无收益） |
| D21 | 对端复位重启走"清洁通道"：Unit A `s_in_rst`（强制入恢复 + 受控清 REPLAY + 退出推迟），Unit B QSR_REL 退出拍撤回 dummy（v2.3，§8.5） | ESM 直接复位 main / 挂住不管 | 复位使对端遗忘接受记录——挂住的 VALID（dummy 或重放 W 拍）复活即成非预期数据；`wr_otd==0` 门控保住活 NIC 的吸收通路；5 通道 idle 是重启的前提 |

### 11.3 学习要点（最浓缩的十条）

1. 恢复 = **把账本清零**，不是"发出一个恢复信号"——每本账都要有明确的归零机制和归零主体。
2. 账本必须定义在**恢复动作的作用面**上（m 侧），且各账本之间**同源**（同一握手事件驱动）。
3. **吸收 vs 堵住**：吸收让双方账都平；堵住只让自己的账平，还毒化通道。
4. ready=0 只能对"活着的、会重试的"对象用；对"死掉的"对象必须吸收。
5. 退出条件只看**客观可证**的状态（账平），不看对方的主观状态（VALID 在不在）。
6. 电平 sticky + 自动退出必须配**边沿触发**，否则振荡。
7. **顺序换正确性**：dummy B 等 WLAST、QSR_REL 等 main 复位——每一步等待都对应一个账目/协议不变量。
8. **重映射把无序问题变有序**：同 id 保序是 AXI 免费提供的全局不变量，FIFO 顺流而下就成了记分板。
9. 方向决定策略：master 活 → 自动退出；master 可能死 → 隔离 + keyed 软件放行。
10. fail-visible 不是"不失败"，而是"每个失败都有唯一签名"——SLVERR、双轨、误恢复签名、账目残留，全是签名。

---

## 附：文件清单

```
design/ hang_prot_core.sv        监控核（v1，未改）
design/ hang_prot_wskid.sv      双 slot W skid（v2.3 新增：两单元共享，环形三指针，每槽 one-hot；v3.1 FuSa 载荷奇偶/计数器副本）
design/ hang_prot_recover.sv    出向恢复桥（v3.2：mcore 感知多类 AR remap + 共享双 slot skid + v3.1 FuSa 双轨/条目奇偶）
design/ hang_prot_bdry_in.sv    入向边界单元（v2.3 位域多类 AR remap——main 单主口无 mcore 语义，见 §3.6；共享双 slot skid + QSR 强清 + v3.1 FuSa）
design/ hang_prot_top.sv   单主控顶层（v3.2：N_MCORE/MCORE_MASTER_IDS/MCORE_REMAP_IDS/AR_ID_REMAP 参数 + s_rid 类域连接 + s_in_rst 透传 + FuSa 边沿双轨）
design/ hang_prot_mcu2main_top.sv Unit A 集成顶层（v3.2 mcore 参数透传）
design/ hang_prot_main2mcu_top.sv Unit B 集成顶层（v2.3 + FuSa）
design/ hang_prot_regfile.sv mbus leaf (reg_wrap 单一源在 fusa 根 common_modules/) 寄存器（奇偶保护，含 QSR_REL）
sim/    tb_hang_prot_a_wrap.sv / tb_hang_prot_b_wrap.sv TB（P1..P12 / P1..P9，iverilog 全 PASS）
sim/    run_iverilog.sh         WSL iverilog 功能仿真脚本（陈旧 .vvp 防护）
doc/    hang_prot_design.md     本文档
```

**待办**：① 覆盖率跑数（Questa/VCS，按 coverage_plan §1 激励映射）；
② 岛边界顶层组装（Unit A/B + NUM_M=2 监视器 + 双 ADB400 + 每流边沿
检测/QSR_REL 布线 + **ESM 复位序列器输出 s_in_rst**，§8.5 契约）；
③ 若 main 侧将来也聚合多 mcore 主，bdry_in 需对称引入 mcore 类（§3.6 末注）。


