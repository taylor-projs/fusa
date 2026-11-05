# int_prot — SPI 中断信号对一致性监视 IP 设计规格

> 来源：Horizon 参考设计 `int_prot.v`（`int_prot_fixed_hier`，原件留档于
> `doc/int_prot_orig.v`）。本项目完成三件事：
> 1. **风格转换**：Verilog → SystemVerilog，GRLIB two-process（r/rin），
>    去库单元依赖（cell_inv → 常量掩码取反；cbb_cdc_sync_stage →
>    `sync_2dff` 标准单元例化，2/3 级可选 + 复位电平参数）；
> 2. **mbus 配置接口**：`int_prot_regfile.sv`，输入 enable（4bit 编码 SEC）
>    + spi_err 粘滞 + ESM 双轨上报；
> 3. **FuSa 加固**：计数器 Q/Q_n 互补自检 / 注错自检（key 门控 + 4bit
>    注错使能）/ 寄存器奇偶保护 / 命令在途奇偶（§5–§7）。
>
> 检测协议与原设计**逐 bit 一致**（阈值 3'h3/3'h5、超时公式、复位空闲电平），
> 加固只做"加法"，不改动检测语义。

---

## 1. 功能概述

监视 NUM_INT 对互补信号（`spi[i]` / `spi_chk[i]`）。协议约定空闲电平
spi=0 / spi_chk=1；一次**事件** = spi 上升沿（POSEDGE 模式），必须由
spi_chk 下降沿**配对**。逐通道独立检测两类失配：

| 错误类型 | 机制 | 阈值 | 语义 |
| --- | --- | --- | --- |
| change_cnt_error | 3bit 加减计数：spi 事件 +1 / chk 事件 −1，同拍配对保持 | 计到 3'h3（0-1-2-3）或绕回 3'h5（0-7-6-5） | **数量失配**：连续 3 个未配对事件 |
| diff_cnt_error | 失配存在期间（\|change_cnt\|≠0）逐拍计时，配对/空闲清 0 | FUSA_STA_INT_TIMEOUT−1（默认 15） | **时间失配**：失配超 TIMEOUT 拍未配对 |

`spi_err[j]` 为 1 拍脉冲（错误拍计数器清 0，原设计语义），粘滞与上报
由 regfile 完成。失效模式视角：spi 断裂/stuck → 数量失配或超时；
chk 断裂（单侧事件同理反向）；两根同时断裂但"看起来配对"→ 由上游
互补编码保证（见 §9 残余）。

## 2. 架构

```
     mbus (24MHz, ce/wr/addr/wdata/par, 单拍, 组合 rdata)
        │
        ▼
  int_prot_regfile ──en(4bit SEC解码)──┐  inj_spi/inj_chk (写拍1拍虚拟事件,
   CFG_EN/INJ_EN/INJ/                  │  受 INJ_EN(key+4bit码) 双门控)
   STA_ERR/STA_PAR/                    ▼
   REGST/ID                    int_prot (同步链 + 边沿检测 + 双计数器)
        │                            ▲            │
        │                            │ spi/spi_chk (异步输入)
        │                            └── spi_sync (同步后 spi 转出)
        ├── esm_err / esm_err_n          (监视错误, 电平双轨, 不可屏蔽)
        └── reg_par_fault / _n           (寄存器/通路奇偶错误, 双轨)
```

单时钟域：监视器与寄存器文件共 clk/rstn（mbus 域），spi_err 脉冲直接
粘滞，无跨域。spi/spi_chk 为异步输入，由 int_prot 内部按 SYNC_MODE
逐通道同步（`sync_2dff` 单元例化，2/3 级链；或单级寄存，复位值保持
互补空闲电平 0/1）。

## 3. 文件与模块

| 文件 | 模块 | 说明 |
| --- | --- | --- |
| rtl/int_prot.sv | int_prot | 监视器本体（原设计转换，协议不变；计数器 Q/Q_n 自检） |
| common_modules/sync_2dff.sv | sync_2dff | 2/3 级同步器标准单元（RST_VAL/STAGES 参数；fusa 单一源 common_modules/，同步一律例化此单元） |
| rtl/int_prot_regfile.sv | int_prot_regfile | mbus 寄存器文件 + 4bit SEC + 奇偶保护 + 注错 |
| $ROOT/../common_modules/reg_wrap.sv | reg_wrap | 单寄存器奇偶保护单元（同 2.parity） |
| rtl/int_prot_top.sv | int_prot_top | 集成顶层 |
| sim/tb_int_prot.sv | tb_int_prot | T1–T16 自检测试台 |
| doc/int_prot_orig.v | int_prot_fixed_hier | Horizon 原件留档（不编译） |

参数（int_prot，与原设计同名同义）：`NUM_INT=20`、`INT_INV/INT_CHK_INV`
（逐通道输入取反掩码）、`SYNC_MODE`（逐通道 1=同步链/0=单级）、
`SYNC_STAGE=3`（2 或 3）、`FUSA_STA_INT_TIMEOUT=16`（**必须 2 的幂**）、
`POSEDGE_DETECT_ONLY=1`。

## 4. 寄存器地图（mbus，addr[15:8]=IDX，[7:0]=偏移）

| 偏移 | 名称 | 访问 | 复位 | 说明 |
| --- | --- | --- | --- | --- |
| 0x00 | CFG_EN | RW | 0xF | [3:0] 监测使能 4bit 编码（§4.1；**非法不可纠时默认开**）；[31:4] 保留 |
| 0x04 | CFG_INJ_EN | RW | 0x0 | [3:0] 注错使能 4bit 编码（**非法不可纠时默认关**）；写需 key：[7:4] 必须为 4'b1010，否则整写忽略 |
| 0x08 | CFG_INJ_SPI | RW | 0x0 | [NUM_INT-1:0] 虚拟 spi 事件图样：**写拍产生 1 拍虚拟事件**（每写一次=每选中通道 1 个事件），受 INJ_EN 解码门控；读回最近图样 |
| 0x0C | CFG_INJ_CHK | RW | 0x0 | 同上，虚拟 chk 事件 |
| 0x10 | STA_ERR | RW1C | 0x0 | [NUM_INT-1:0] spi_err 粘滞；**置位优先于 W1C**（脉冲源不重置，见 §6.3） |
| 0x14 | STA_PAR | RW1C/R | 0x2 | [0] PAR_FAULT 电平（W1C 只清自测锁存）/[1] PAR_FAULT_N 反轨 RO/[7:2] PERR5..PERR0 W1C |
| 0x18 | CFG_REGST | W | — | [3:0] key=1010 否则整写忽略；[4] REG_SELFTEST（[11:8] REGSEL 选组 0..5）；[5] PAR_SELFTEST；读回 0 |
| 0xFC | ID | RO | — | 32'h5AFE_1000 \| IDX |

PERR 组：0=CFG_EN，1=CFG_INJ_EN，2=CFG_INJ_SPI，3=CFG_INJ_CHK，
4=STA_ERR，5=命令在途奇偶（PERR5 = 该组 wrap 的 flt 或粘滞）。

### 4.1 4bit 编码使能（标准做法：d=4 最近邻纠错 + 写回）

4bit 码 1111/0000，码距 d=4（**纠 1bit / 检 2bit**），解码规则
（`dec4()`）：

| 读出码 | 判定 | 动作 |
| --- | --- | --- |
| 1111 / 0000 | 合法 | 正常解码 |
| popcount=3（如 1110） | 1111 的 1bit 错 | **最近邻纠正为开 + 纠正值写回存储** |
| popcount=1（如 0001） | 0000 的 1bit 错 | **最近邻纠正为关 + 纠正值写回存储** |
| popcount=2（如 1100） | 距两码字等距，不可纠 | 按 fail-safe 默认方向解码，不写回 |

- **默认方向按功能属性区分**：监测功能使能（CFG_EN）默认**开**——
  监控关闭会掩盖故障，宁可误报不可漏报（fail-visible）；注错使能
  （CFG_INJ_EN）默认**关**——不可纠时绝不注入（fail-safe）。复位值
  跟随：CFG_EN 复位 1111（上电即监控，同步链复位空闲电平不会产生
  伪事件），INJ_EN 复位 0000；
- **纠正写回 = 功能自愈**：即使 wrap 偶校验通路失效，编码自身也能
  恢复正确值；与 wrap 互补——wrap 检出报 PERR（诊断粘滞，W1C 清），
  编码纠正保证功能值正确（写回重载后偶校验恢复一致）；
- 写侧不变：仅接受 1111/0000，其余 12 种非法码整写拒绝（保持旧值）；
- SW 合法写优先于纠正写回（同拍并发时 SW 值生效）。

## 5. 奇偶保护（与 2.parity 同构）

- 每个数据寄存器 = `reg_wrap`：存储+偶校验同沿载入、
  自测注错只污染校验位（数据永不污染）、粘滞 flt 带反相副本
  （SEU 清正本 → dup 失配 → 自愈回 SET）；
- PAR_SELFTEST 自测锁存同样双副本自愈；
- PAR_FAULT = 全部 flt 之源或 + PERR5 粘滞 + 自测锁存，双轨输出
  `reg_par_fault/_n` → ESM；
- 命令在途奇偶（PERR14 同款）：apb2mbus 源端对 {paddr,pwrite,pwdata}
  算偶校验 par 同深度同步广播，本模块 ce 拍重组比对；失配 **fail-safe**：
  拒写（wr_ok 门控）+ 读驱 0 + PERR5 粘滞。全实例检查不 gate sel，
  置位模式本身即诊断信息（全报=公共通路，单报=fanout 后局部）。

## 6. 注错设计（FI）——两个层级 + 三道门

**结论：错误注入不是（只是）对 spi_err OR / spi_err_n AND 输出轨做
force。那只覆盖聚合与驱动，检测逻辑本身（边沿检测、双计数器、比较器）
完全没被锻炼。本设计用两层：**

### 6.1 层 1：事件级深注错（CFG_INJ_SPI / CFG_INJ_CHK）

在 int_prot 内把虚拟事件**与真实事件同级并入** `spi_changed/chk_changed`
（同受 enable 门控，走同一条计数器/比较器/错误生成路径）：

- `INJ_SPI=1`（单次写）→ 1 个未配对 spi 事件 → 走 **diff_cnt 超时路径**
  （约 16 拍后报错）；
- `INJ_SPI` 连写 3 次 → change_cnt 0-1-2-3 → **上溢路径**；
- `INJ_CHK` 连写 3 次 → 0-7-6-5 → **下溢（绕回）路径**；
- 全链覆盖：事件合并 → 计数器 → 阈值比较 → spi_err 脉冲 → regfile
  粘滞 → esm_err/_n 双轨 → ESM。

写拍脉冲语义（每写一次一个事件，无持续电平）避免"忘记关注入"的
持续报错问题。

### 6.2 层 2：输出/汇聚签名（PAR_SELFTEST）

CFG_REGST key+bit5 只置 PAR_FAULT 自测锁存——"**有 fault 无源**"，
验证 PAR_FAULT 聚合、双轨驱动与 ESM 服务程序通路，不经过监视器
（这两层互不遮蔽：层 1 检测逻辑坏了层 2 仍能过，反之亦然）。

### 6.3 STA_ERR 粘滞的优先级（有意偏离惯例）

惯例（edc_regfile）是 W1C（CPU）优先于置位——对**电平**源无损
（源仍在则下一拍重新置位）。本设计源是 **1 拍脉冲**，若 W1C 优先，
清除拍与错误拍同拍巧合时会**吞掉脉冲且永不重置**。故 STA_ERR 采用
**置位优先**：`(r & ~w1c) | spi_err`——并发拍 W1C 不清该位，软件
最多多写一次，脉冲永不丢（fail-visible 方向）。

### 6.4 注错的三道门（防误注入）

1. **keyword**：CFG_INJ_EN 写必须带 [7:4]=4'b1010 key，否则整写忽略；
2. **4bit 编码注错使能**：INJ_EN=1111 才放行注错动作（非法码拒写；
   存储侧 SEU 不可纠时默认关，见 §4.1）；
3. **监测使能**：虚拟事件与真实事件同级受 CFG_EN 门控——测的就是
   工作状态下的监视器。

注入寄存器本身受 wrap 奇偶保护，写入受命令在途奇偶保护。

## 7. 加固分析（原设计弱点 → 对策）

| # | 原设计弱点 | 风险 | 对策（本设计） |
| --- | --- | --- | --- |
| 1 | spi_err 仅 1 拍脉冲，无粘滞、无聚合、无 ESM 通路 | 下游漏采即**静默丢失**（λ_DU） | regfile 粘滞 STA_ERR + `esm_err/_n` 电平双轨（不可屏蔽） |
| 2 | 裸 1bit enable，静默失效方向（stuck-0=关且无告警） | 监视器被无意/翻转关闭 | 4bit 编码使能 + **SEC 纠正写回**（§4.1）：1bit 翻转自动纠回原值并写回（功能不中断）；2bit 平局默认开（监测）——fail-visible |
| 3 | 无任何自检手段（监视器自身 stuck → 永不报错，latent） | λ_DU 大头 | §6 两层注错：事件级（锻炼检测逻辑全链）+ 签名级（锻炼聚合/ESM），周期执行（T_diag 约束见 §9） |
| 4 | 配置无保护（若外部加配置寄存器，SEU 静默） | λ_DU | 全寄存器 wrap 奇偶（自愈粘滞+W1C）+ 4bit SEC + 命令在途奇偶拒写 |
| 5 | 依赖库单元 cell_inv/cbb_cdc_sync_stage（源码缺位、不可移植） | 验证盲区 | 常量掩码取反 + `sync_2dff` 标准单元例化（复位值/深度语义不变，全项目统一的同步单元例化方法） |
| 6 | diff_cnt 比较点 `TIMEOUT[CW-1:0]-1`：TIMEOUT 非 2 幂时截断歧义 | 参数误用 | 参数约束"必须 2 的幂"写入文件头 + 文档 |
| 7 | 计数器（change_cnt/diff_cnt）本体无任何检测：SEU 翻正本到 0 → diff_cnt 条件同步失效，**丢事件无声**；翻副本/误加 → 假超时难溯源 | λ_DU（监视状态被扰动不可见） | **Q/Q_n 互补自检**：每计数器一份反相副本，逐拍比较 `正本 != ~副本`（任一副本单 bit 扰动下一拍即失配）→ 该通道报 1 拍 spi_err（同通道 STA_ERR 粘滞，故障可见）+ 计数器清 0 自愈，副本每拍从次态重算自动回贴。边沿检测前拍寄存（spi_q1/chk_q1）不加副本：其扰动要么空闲自愈无害，要么幻化为假事件由计数器协议有界检出，无静默路径 |
| 8 | 同步链/边沿检测前端无在线检测（无流量时不报） | 固有残余 | 前端靠注错覆盖其后端、靠业务流量覆盖前端；SIL3 差距项（§10） |

**检测逻辑的比较器/边沿检测不加双份冗余**：这是"检测通知型"机制，
比较器双份属 SIL3 路线（HFT=1）；计数器状态本体已按上表 #7 加
Q/Q_n 互补自检（用户评审要求），SIL2 下比较器以周期注错覆盖——
与 2.parity sil_analysis 的路线结论一致。

## 8. 验证状态

VM VCS（V-2023.12-SP2）+ 覆盖率，`sim/run_vcs.sh`，**T1–T16 全绿**
（100 个检查点 + 全程 ESM 双轨互补性在线监视）：

| 测试 | 覆盖 |
| --- | --- |
| T1 | 复位默认值（CFG_EN=1111 默认开 / INJ_EN=0000 默认关）/ ID / 双轨空闲电平 |
| T2 | 4bit 编码：非法码拒写（5、3）、1111/0000 切换 |
| T3 | 配对流量无误报（单级+同步链通道）、窗口内补配对、spi_sync 转出延迟（3 拍/1 拍） |
| T4/T5/T6 | 上溢 0-1-2-3 / 超时（diff_cnt）/ 下溢 0-7-6-5 → STA_ERR → W1C |
| T7 | 使能关：事件不检测 |
| T8 | INJ_EN 三道门：关时注错无效 / 无 key 拒写 / 非法 nibble 拒写；开后 FI：超时+上溢 |
| T9 | FI chk 侧下溢、INJ 读回 |
| T10 | 全沿模式（POSEDGE_DETECT_ONLY=0 对照实例）：配对无误报+未配对报错 |
| T11 | REGST 逐组（0..5）校验位注错 → PERR/PAR_FAULT/双轨 → 治愈写+W1C；REGSEL>5 忽略 |
| T12 | PAR_SELFTEST 有 fault 无源签名 → W1C bit0 清锁存 |
| T13 | mbus 命令在途奇偶：坏 par 拒写+读回 0+PERR5+W1C、好写恢复 |
| T14 | 非法 REGST key / 未映射读写 / 错实例访问 静默 |
| T15 | 4bit SEC：1bit 错纠正写回（CFG_EN 1111→1110→1111 功能保持开 / INJ_EN 0000→0001→0000 保持关）+ 2bit 平局默认方向（CFG_EN 1100→开不写回 / INJ_EN 0011→关且注错不生效）；force 注入带 firing-proof 读回 |
| T16 | 计数器 Q/Q_n 自检：change_cnt 正本 bit 翻转（001→000）→ 失配报 1 拍 → STA_ERR[0] 粘滞 + esm_err 可见 → release 后通道计数器清 0 自愈 + 副本回贴 111 → W1C → 自愈后配对流量无误报 |

原始覆盖率（未做结构常量排除）：line ~92 / branch ~88 / toggle ~39
——toggle 低位主要来自结构常量（未实例化通道位、常量掩码路径、
保留位），后续按 urg 排除流程出 `tgl_struct_excl.el`（同五设计
toggle 战役模式）。

## 9. 集成约束与残余风险

1. **单域假设**：int_prot 与 regfile 必须共 clk。若监视器需跑在
   spi 源域，spi_err 过域前先电平化（sticky 前置）+ 2FF；
2. **准静态 cfg**：业务流量期间不写 CFG_EN / INJ 类寄存器（mbus
   单拍写不会撕裂，但使能切换应在无失配 pending 时进行——enable
   关闭会冻结计数器，重开时旧失配仍按新窗口计时）；
3. **T_diag 约束**：层 1/层 2 注错周期 ≤ PFDavg 分配置的间隔——
   检测逻辑静默失效只在诊断时刻暴露；REGST 周期自检约束寄存器
   2bit MBU 共模暴露窗口；
4. **TIMEOUT=2 的幂**、**NUM_INT≤32**（INJ/STA 位图一个字内）；
5. **ESM 在线**：双轨互补校验由 ESM 侧负责（本 IP 输出互补轨，
   不自带校验）；
6. 残余（SIL3 差距，同 2.parity 清单）：前端同步链/边沿检测的
   在线并发检测缺失（无流量即无覆盖；计数器本体已由 Q/Q_n 自检
   覆盖，见 §7 #7）；检查分支双份比较器；
   寄存器 2bit 共模（周期 REGST 兜底 + 4bit SEC 吸收编码使能位的
   1bit 错）；ESM 本身失效（系统级）。

## 10. SIL 视角小结

Type B + HFT=0：检测通路（计数器/比较器/粘滞/上报）以周期注错
诊断覆盖（DC≈90%，依赖 T_diag），寄存器/通路奇偶 ~90%，编码使能
SEC+默认方向 ~100%（1bit 自纠、2bit 有向 fail-safe），双轨输出 ~99%。
与 2.parity 同构的论证路线，加权 SFF 估计 91–95% → **SIL2 可达
（有条件）**，条件同 2.parity sil_analysis §3（ESM 在线、T_diag
定量化、FIT 代入 FMEDA）。SIL3 走路 A（双份检查器 HFT=1）。
