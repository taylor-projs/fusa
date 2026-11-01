# apb2mbus 交互时序 与 edc_regfile 寄存器说明

本文是 `doc/design_spec.md` §7（mbus 协议）与 §8（寄存器映射）的展开，
分两部分：

1. **apb2mbus 交互时序**：APB3 访问如何跨域到 mbus(24MHz) 并返回；
2. **edc_regfile 寄存器说明**：每实例 256B cfg/sta 寄存器组的逐条说明。

对应 RTL：`rtl/apb2mbus.sv`、`rtl/edc_regfile.sv`、`rtl/edc_core.sv`。

## 1. 访问路径总览

```
                     APB3 (apb_clk)              mbus (24MHz, 广播)
 APB 主端 ──paddr/pwrite/pwdata──> apb2mbus ──ce/wr/addr/wdata/par──┬──> EDC_REGCHK[0]
                 <──pready/prdata──────── <──rdata(按位OR)──────┼──> EDC_REGCHK[1]
                                                               └──> ...[NP-1]
```

- `apb2mbus` 内部完成 APB 时钟域 ↔ 24MHz 的请求/应答跨域（toggle 握手）；
- mbus 侧 `ce/wr/addr/wdata/par` **广播**到所有实例，每个 `edc_regfile` 用
  `addr[15:8] == IDX` 自行译码（`sel`），未选中实例 `rdata` 驱动 0，
  顶层按位 OR 汇聚成一条回读数据；
- `par` = `^{paddr, pwrite, pwdata}` 的 1bit 偶校验，与 payload 3FF 同
  深度同步——**命令在途奇偶**，各实例 ce 拍比对，失配 = 在途 1bit 损坏
  → 拒写 + 读回 0 + PERR14（§3.8）；
- mbus 从端**零等待**：`ce` 为单拍脉冲，读数据与 `ce` 同拍组合输出，
  写在同一 mbus 上升沿完成。

## 2. apb2mbus 交互时序

### 2.1 握手原理

CDC 结构与 `sysm_msync` 的 memi/memo 两域 toggle 握手一致：

```
APB 域 (apb_clk)                        mbus 域 (24MHz)
--------------------------------        --------------------------------
acc     = psel & penable                req_flag 3FF 同步   (s1/s2/s3)
ce_reg  : acc 打拍, rdy 当拍清 0         payload 3FF         (addr/wdata/wr,
req_flag: acc 上升沿翻转 (toggle)            与 flag 链同深度对齐)
                                         ce_flag : s2!=s3 的下一拍置 1,
                                           单拍脉冲 (零等待自完成)
ack 4FF 同步 (s1..s4)                    ce 当拍: 采样 rdata 进 rdat_cap,
rdy = s3 ^ s4  -> pready                   翻转 ack_flag (toggle)
rdat 2FF (s1/s2) -> prdata
```

要点：

- **去程**：APB access 相首拍检出 `acc` 上升沿（`ce_reg` 从 0 变 1）→
  翻转 `req_flag`（1 bit toggle 跨域安全）；`paddr/pwrite/pwdata` 不在
  APB 侧打拍，直接送 mbus 域 3FF——payload 在整个 access 相内稳定，
  回程 `rdy` 远晚于 3FF 采样完成，因此安全；
- **mbus 侧**：`s2 != s3` 的那一拍（请求边沿窗口）的下一拍 `ce_flag`
  置 1；此时 `flag_s3` 与 `payload_s3`（addr/wr/wdata 输出）刚好同沿
  载入新值，**ce 拍 payload 新鲜**；再下一拍自动回 0，`ce` 恰好一个
  mbus 周期；
- **ce 当拍自完成**（零等待）：读时采样组合 `rdata` 进 `rdat_cap`，
  同时翻转 `ack_flag`；
- **回程**：APB 域对 `ack_flag` 做 4FF，`ack_s3 ^ ack_s4` 得到单拍
  `rdy` → `pready`；`prdata = rdat_s2`（`rdat_cap` 的 2FF），在
  `pready` 拍有效、实际早已稳定；
- `rdy` 当拍把 `ce_reg` 清 0，同一笔访问不会重复触发 `req_flag`，
  因此支持 `pready` 后背靠背发起下一笔。

### 2.2 事务级交互图

```
  APB 主端         apb2mbus                    edc_regfile[选中]   edc_regfile[其他]
  (apb_clk)        APB域   mbus域(24MHz)         (24MHz)             实例
     │               │        │                    │                   │
     │ setup/access  │        │                    │                   │
     │──PSEL/PENABLE─────────>│                    │                   │
     │               │ acc↑: req_flag 翻转        │                   │
     │               │──────3FF 同步──────────────>│ (ce/addr 广播) ──>│
     │               │        │──ce (单拍)────────>│ sel=1             │
     │               │        │<─rdata(组合,读)───│                   │
     │               │        │  [写: 同拍写寄存器 │                   │
     │               │        │   + 翻转 cmd_t]   │                   │
     │               │        │  rdat_cap<=rdata   │                   │
     │               │        │  ack_flag 翻转     │                   │
     │<─ack 4FF, rdy 单拍─────│                    │                   │
     │<─PREADY (+PRDATA)──────│                    │                   │
```

### 2.3 读事务逐拍时序

事件编号（寄存器值为**该拍稳态**，即上升沿之后；①~⑥ 为关键边沿）：

| # | 时刻 | 事件 |
| --- | --- | --- |
| ① | A1 末 | APB：`acc` 上升沿检出（`ce_reg` 0→1），`req_flag` 翻转 0→1 |
| ② | A3 末 (=M1) | mbus：3FF 首拍采样 `req_flag` 与 payload（addr/wdata/wr 进 s1） |
| ③ | A7 末 (=M3) | mbus：`flag_s3` 载入新值；同拍检出 `s2≠s3` → `ce_flag` 置 1 |
| ④ | A9 末 (=M4) | mbus：ce 拍结束——`rdat_cap ← rdata`，`ack_flag` 翻转 0→1，`ce_flag` 回 0 |
| ⑤ | A10 末 | APB：`ack_flag` 进 4FF 首拍（`ack_s1` 载入新值） |
| ⑥ | A13 | APB：`rdy = ack_s3^ack_s4` 单拍 → `pready=1`，`prdata=rdat_s2`，传输结束 |

```
周期          A1   A2   A3   A4   A5   A6   A7   A8   A9   A10  A11  A12  A13
              ①         ②              ③    ce拍 ④    ⑤              ⑥
mbus边沿(末)   -    -   M1    -   M2    -   M3    -   M4    -   M5    -   M6

---------------- APB 域 ----------------
psel           1    1    1    1    1    1    1    1    1    1    1    1    1
penable        1    1    1    1    1    1    1    1    1    1    1    1    1
APB payload    ───────── paddr / pwrite / pwdata：access 相内不变 ─────────
acc            1    1    1    1    1    1    1    1    1    1    1    1    1
ce_reg         0    1    1    1    1    1    1    1    1    1    1    1    1
req_flag       0    1    1    1    1    1    1    1    1    1    1    1    1
ack_flag       0    0    0    0    0    0    0    0    0    1    1    1    1
ack_s1         0    0    0    0    0    0    0    0    0    0    1    1    1
ack_s2         0    0    0    0    0    0    0    0    0    0    0    1    1
ack_s3         0    0    0    0    0    0    0    0    0    0    0    0    1
ack_s4         0    0    0    0    0    0    0    0    0    0    0    0    0
rdy            0    0    0    0    0    0    0    0    0    0    0    0    1
pready         0    0    0    0    0    0    0    0    0    0    0    0    1
prdata         0    0    0    0    0    0    0    0    0    0    0    0    D

---------------- mbus 域 (24MHz) ----------------
flag_s1        0    0    0    1    1    1    1    1    1    1    1    1    1
flag_s2        0    0    0    0    0    1    1    1    1    1    1    1    1
flag_s3        0    0    0    0    0    0    0    1    1    1    1    1    1
payload_s3     o    o    o    o    o    o    o    V    V    V    V    V    V
ce             0    0    0    0    0    0    0    1    1    0    0    0    0
rdata          -    -    -    -    -    -    -    D    D    -    -    -    -
rdat_cap       -    -    -    -    -    -    -    -    -    D    D    D    D
```

图例：`o` = 陈旧值；`V` = 本拍新值（ce 拍使用）；`D` = 读数据有效；
`-` = 无效/不关心。图中假设 1 个 mbus 周期 ≈ 2 个 APB 周期、mbus 上升沿
与 A3/A5/A7/A9/A11/A13 的 APB 上升沿重合——**两域时钟异步，实际相位
任意，图中对齐仅为示意，以事件先后为准**。A0 为 setup 相（psel=1、
penable=0、payload 已稳定），表中省略。

逐拍解读：

1. A1（access 首拍）`acc=1`，A1 末上升沿：`ce_reg←1`、`req_flag` 翻转（①），
   同一笔访问此后不再触发；
2. M1/M2/M3 三个 mbus 周期完成 3FF 同步，payload 链与 flag 链同深度；
3. M3 末检出请求边沿，**M4 即 ce 拍**：`ce=1`、`addr/wr/wdata` 输出 `_s3`
   新值（③），选中的 `edc_regfile` 组合输出 `rdata`（与 ce 同拍）；
4. M4 末：`rdat_cap` 锁存 `rdata`、`ack_flag` 翻转、`ce` 回 0（④）——
   mbus 侧一笔访问恰好 4 个周期；
5. APB 域 4FF 移位 4 拍（⑤），`rdy` 在第 4 拍（A13）出现单脉冲 →
   `pready=1`，APB 主端采样 `prdata`（`rdat_s2`，A12 起已稳定）后结束
   传输（⑥）。

### 2.4 写事务差异

逐拍波形与 §2.3 **完全相同**（握手不区分读写），差异只有：

- `pwrite=1` → 经 3FF 后 `wr=1`；
- ce 拍（M4）选中的 `edc_regfile` 在 M4 末上升沿**写寄存器**（`sel && wr`），
  并翻转 `cmd_t` 下发 cfg/RW1C 命令到 AXI 域（见 §3.5）；
- 组合 `rdata` 在写访问时仍会产生（写地址的回读值），`rdat_cap` 照常
  锁存，但 APB 主端不采样 `prdata`。

### 2.5 越界实例访问

`paddr[15:8] >= NP` 时 `inst_bad=1`，**不发起 mbus 传输**，APB 当拍快速失败：

```
A0: psel=1, penable=0, paddr[15:8] >= NP
A1: acc=1 且 inst_bad=1 -> pready=1 且 pslverr=1 (access 首拍即完成, 2 拍传输)
A2: 总线空闲
```

`req_flag` 不翻转（无 mbus 副作用）；`pready = rdy || (acc && inst_bad)`，
正常访问时 `pslverr` 恒 0。

### 2.6 延迟小结

| 路径段 | 时钟域 | 拍数 |
| --- | --- | --- |
| acc 上升沿 → req_flag 翻转 | APB | 1 |
| req_flag → 3FF 同步完成（payload 新鲜） | mbus | 3 |
| ce 单拍（读采样 / 写寄存器） | mbus | 1 |
| ack_flag → 4FF → rdy 单拍 | APB | 4 |
| **合计（一次 APB 访问）** | — | **≈ 4 mbus + 5 APB**（随两域相位浮动） |

软件无需关心具体数值，只看 `pready`。对 `edc_regfile` 的副作用另加
AXI 域同步延迟（cfg 生效、RW1C 清除，见 §3.5）。

## 3. edc_regfile 寄存器说明

### 3.1 模块功能

`edc_regfile` 是 `EDC_GEN_CHK` 实例内的 24MHz mbus 寄存器文件，**纯
mbus 时钟域**，不含任何 AXI 逻辑：

- cfg 寄存器（INJ_EN / INJ_FORCE / INJ_POS / IRQEN）+ `sel` 实例译码 +
  组合读 mux（与 `ce` 同拍）；
- RW1C 清除：写 1 的位累加进 `clr_mask`，随命令 toggle 下发到 AXI 域；
- sta 回读：AXI 域粘滞电平 `err/fault/irq` 经 2FF 同步后参与读 mux；
- 命令管理：`cmd_t`（每次写翻转）、`cmd_pend`、`ack` 追平后释放；
- ESM 输出（mbus 域，顶层逐实例 OR 汇聚）：`esm_err = |err_s2`、
  `esm_fault = |fault_s2`、`irq = irq_s2`。

### 3.2 地址空间与实例译码

| 项 | 说明 |
| --- | --- |
| 地址构成 | `paddr[15:8]` = 实例号 IDX，`paddr[7:0]` = 寄存器偏移 |
| 实例号分配 | master 端口 p → `p`（0..NM-1）；slave 端口 q → `NM+q`；总数 NP = NM+NS ≤ 256 |
| 每实例空间 | 256B（偏移 0x00..0xFF），32bit 寄存器 |
| 越界（`paddr[15:8] >= NP`） | apb2mbus 直接 `pready + pslverr`，不进 mbus（§2.5） |
| 未选中实例 | `sel = ce && (addr[15:8]==IDX)` 为 0，`rdata` 输出 0，顶层按位 OR |
| 访问对齐 | 32bit 对齐；未定义偏移读 0、写忽略（无副作用） |

### 3.3 寄存器汇总

| 偏移 | 名称 | 访问 | 复位值 | 说明 |
| --- | --- | --- | --- | --- |
| 0x00/0x04/0x08 | CFG_INJ_EN[2:0] | RW | 0x0 | 每站点 4bit 编码使能（1111=开/0000=关），6 站点/字，字[2]=站点 12..17、[1]=6..11、[0]=0..5 |
| 0x0C | CFG_INJ_FORCE | RW | 0x0 | 每站点强制报错 [17:0] |
| 0x10 + 8·s | CFG_INJ_POS[s] | RW | 0x0 | 每站点注错位置，64bit = 2 个 32bit 字（0x10..0x9F） |
| 0xA0 | STA_ERR | RW1C | 0x0 | err 轨粘滞状态（含注错）[17:0] |
| 0xA4 | STA_FAULT | RW1C | 0x0 | fault 轨粘滞状态（organic）[17:0] (inj_en=0时产生的error，由inj_force或真实parity_err产生) |
| 0xA8 | CFG_IRQEN | RW | 0x0 | err 轨中断使能 [17:0] |
| 0xAC | STA_REGPAR | RW1C/R | 0x2 | 寄存器奇偶状态（见 §3.8；bit1 为反轨，复位常读 0x2） |
| 0xB0 | CFG_REGST | W(key) | — | 寄存器奇偶自测控制，[3:0] key=0xA，读回 0 |
| 0xFC | ID | RO | 0xEDC01000\|IDX | 实例标识 |
| 其余 | — | — | — | 保留：读 0，写忽略（不翻转 cmd_t） |

`[17:0]` 寄存器的 bit s 对应全局站点 s（见 §3.6）；[31:18] 保留，读 0、
写忽略。**任何一次对已映射寄存器的写都会翻转一次 `cmd_t`**（ID 与保留
地址除外），把全量 cfg / 累积的清除掩码下发到 AXI 域（§3.5）。

| INJ_EN(解码) | INJ_FORCE | 站点出错时 STA_ERR | STA_FAULT                        |
| ------------ | --------- | ------------------ | -------------------------------- |
| 0            | 0         | 置位（真实失配）   | 置位                             |
| 0            | 1         | 置位（force 强拉） | **置位**（force 不参与归类）     |
| 1            | x         | 置位（注入）       | **不置位**（被 INJ_EN 归类屏蔽） |



### 3.4 寄存器详细说明

#### CFG_INJ_EN[2:0]（0x00/0x04/0x08，RW，复位 0）

每站点 **4bit 编码使能**（与 timeout 设计 SCMCNTRL.ENA 同思路）：

| nibble 值 | 含义 |
| --- | --- |
| `4'b1111` | 站点注错使能（配合 CFG_INJ_POS[s] 在 CHK 侧检查分支输入镜像上按位翻转） |
| `4'b0000` | 关 |
| 其余（非法码） | **拒绝写入**：该 nibble 保持旧值，其余合法 nibble 正常写入 |

- 字与站点的对应：字 0x00 = 站点 0..5（nibble 0..5）、0x04 = 6..11、
  0x08 = 12..17；站点 s 的 nibble 地址 = `0x00 + 4*(s/6)`，
  nibble 位置 = `4*(s%6)`；
- **fail-safe 语义**：任何 1bit 翻转 → 非法码 → 解码为关 → 注错失效
  且 fault 轨解除屏蔽（不会永久屏蔽 organic fault）；翻转同时被影子
  寄存器奇偶（PERR7）捕获；
- 写副作用：翻转 `cmd_t`，**全量**下发所有 cfg 到 AXI 域；
- 注错只影响检查分支的比对镜像，**转发数据不受污染**；
- 编码开的站点 fault 轨被屏蔽（无法区分注入错与真实错，双轨语义见
  design_spec §8.5）；
- GEN 侧站点恒不报错，注错只对本实例的 CHK 侧站点生效（§3.6）。

#### CFG_INJ_FORCE（0x0C，RW，复位 0）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [17:0] | force[s] | 1 = 强制站点 s 报错（不看 CFG_INJ_POS，也不受 CFG_INJ_EN 门控） |
| [31:18] | — | 保留，读 0 写忽略 |

- `force[s]=1` 且 `inj_en[s]=0`：站点同时置位 STA_ERR 与 STA_FAULT
  （ERR+FAULT 双轨，用于验证 ESM fatal 通路）；
- `force[s]=1` 且 `inj_en[s]=1`：只报 ERR；
- 64bit 数据站点（s=5/15）无法经 CFG_INJ_POS 注校验位错，强制报错
  （即“任意错”）只能用本寄存器。

#### CFG_INJ_POS[s]（0x10+8·s 低字 / 0x14+8·s 高字，RW，复位 0，s=0..17）

每站点 64bit 注错位置，仅在 `inj_en[s]=1` 时生效。低字（偏移 +0）=
`cfg_pos[s][31:0]`，高字（偏移 +4）= `cfg_pos[s][63:32]`。

位映射（DW/EDCW 为该站点数据/校验位宽，见 §3.6 表）：

| CFG_INJ_POS[s] 的 bit | 含义 |
| --- | --- |
| `i`（i < DW） | 翻转检查镜像的**数据位 i** |
| `DW+j`（DW+j < 64，j < EDCW） | 翻转检查镜像的**校验位 j** |
| 其余 | 无效 |

- 多个 bit 同时置 1 = 同时翻转多位（可构造 ≥2bit 错误，用于验证检错
  能力；≥3bit 的部分组合可能漏检，属编码特性）；
- 64bit 数据站点（s=5/15）`DW=64`：bit 0..63 全为数据位，校验位不可注
  入（DW+EDCW=71 > 64），任意错用 CFG_INJ_FORCE；
- 写任一字翻转一次 `cmd_t`（全量下发）。

#### STA_ERR（0xA0，RW1C）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [17:0] | err[s] | 读：AXI 域 `err_st` 的 2FF 同步值（含注错错误）。写：写 1 的位并入 `clr_mask`，随下一条命令在 AXI 域清除 |

- 读值是同步后的电平，非瞬时采样——AXI 域 `err_st` 本身为粘滞位，
  置位后保持到被清除；
- RW1C 写后约 2~3 个 mbus 周期（命令下发 + AXI 执行 + 回读同步）内
  读回仍可能为 1（design_spec §12）；
- 若错误源仍在（如注错仍使能且流量持续），清除后会再次置位，属预期；
- 写 0 的位无效；写本身也翻转 `cmd_t`（清除即命令）。

#### STA_FAULT（0xA4，RW1C）

与 STA_ERR 结构相同，对应 fault 轨：

- `fault_st[s]` 置位条件：站点 s 出现 syndrome 错 **且 `inj_en[s]=0`**
  （organic 错误）；
- 注错使能的站点 fault 轨被屏蔽，读回恒 0；
- RW1C 语义、延迟、再置位行为同 STA_ERR。

#### CFG_IRQEN（0xA8，RW，复位 0）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [17:0] | irqen[s] | 1 = 站点 s 的 err 参与实例中断：`irq = |(err_st & irqen)`（AXI 域计算，2FF 回 mbus 域输出） |
| [31:18] | — | 保留，读 0 写忽略 |

- 只影响本实例 `irq` 输出，不影响 `esm_err`/`esm_fault`（二者无条件
  汇聚到 ESM）；
- 写翻转 `cmd_t`（全量下发）。

#### STA_REGPAR（0xAC，RW1C/R，复位 0x2）

寄存器奇偶校验状态（详见 §3.8）：

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [0] | PAR_FAULT | 读：电平 = 所有 PERR 源之或 + 自测锁存。写 1：只清自测锁存（源仍置时读回保持 1） |
| [1] | PAR_FAULT_N | RO 反轨（双轨 ESM 输出 `reg_par_fault_n` 的回读），正常时 = ~bit0 |
| [3:2] | — | 保留，读 0 |
| [17:4] | PERR13..PERR0 | W1C：每位清除对应寄存器的奇偶粘滞。mbus 域（组 0..6）当拍生效；AXI 域（组 7..13）经命令下发清除，两域同步 |
| [18] | PERR14 | 命令在途奇偶（APB→mbus，本域检查）。W1C 当拍清（不经 AXI 命令通道） |
| [31:19] | — | 保留，读 0 |

- 无故障时读回 0x2（反轨 bit1 常为 1）；
- 每个源在**自己的 PERR 位**上清除，"电平保持到无未清源"是单一事实源；
- 写 1 翻转 `cmd_t`（掩码一次性下发，ack 追平后清零）。

#### CFG_REGST（0xB0，W，读回 0）

寄存器奇偶自测控制。**写保护**：`wdata[3:0]` 必须为 4'b1010（key），
否则整写忽略（无 cmd_t 翻转、无副作用）——防软件误触发。

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [3:0] | KEY | 必须为 4'b1010 |
| [4] | REG_SELFTEST | 脉冲：对 REGSEL 选中的组注入校验错（只翻校验位，数据不污染） |
| [12:9] | REGSEL | 目标组号：0..6 本域（mbus）当拍注入；7..12 经命令在 AXI 域注入；>12 忽略（13 无注错） |
| [5] | PAR_SELFTEST | 脉冲：只置自测锁存（"有 fault 无源"= ESM 服务程序的自检签名） |
| 其余 | — | 忽略 |

- mbus 域跟随型寄存器（镜像/sticky）注入后下一拍自恢复（wr=1），
  粘滞已锁存需 W1C；RW 型（cfg）注入保持到该寄存器下次重写；
- 自测序列建议：REG_SELFTEST → 读 STA_REGPAR 验证 PERR/PAR_FAULT
  （及 ESM 双轨）→ 恢复（重写目标寄存器或等跟随自恢复）→ W1C。

#### ID（0xFC，RO）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [31:0] | id | `32'hEDC0_1000 \| IDX`，如 IDX=0 → 0xEDC01000，IDX=1 → 0xEDC01001 |

只读；写忽略（无副作用，不翻转 `cmd_t`）。软件可用低 8bit 反查实例号，
常用于总线连通性自检（tb 用例 T1）。

### 3.5 写副作用与命令下发时序

任何已映射寄存器的写（含 RW1C）→ 翻转 `cmd_t` + 置 `cmd_pend`。AXI 域
收到命令脉冲后一次性应用**全量配置**并应答：

```
mbus 域 (24MHz)                              AXI 域 (axi_clk)
──────────────────────                        ──────────────────────
ce 拍: 寄存器写入
       cmd_t 翻转 ───── 2FF ───────────────▶ cmd_sync (边沿检测)
       cfg/clr 负载 ─── 2FF (与 toggle 同深度) ▶ cmd_*_s1 / cmd_*_s2
                                                cmd_pulse 当拍:
                                                  err_st   <= (err_st & ~clr) | site_err   (置位优先)
                                                  fault_st <= (fault_st & ~clr) | (site_err & ~inj_en)
                                                  inj_en/inj_force/irqen/inj_pos <= 2FF 值 (绝对量)
                                                  ack_t 翻转
                ◀──── 2FF ───────────────── ack_t
ack_sync 追平 cmd_t:
  cmd_pend <= 0, clr_mask <= 0   (清除只生效一次)
```

- **负载是绝对量**（全量配置）：连续多次写产生多个 toggle 边沿，每个
  边沿都触发一次全量载入，后写覆盖前写，中途丢边沿也只落后一拍；
- **RW1C 合并**：ack 到达前的新清除写会 OR 并进 `clr_mask`，不会丢；
  `clr_mask` 在 ack 追平后清 0，保证同一清除只执行一次；
- **置位优先**：`cmd_pulse` 拍若站点同时来新错，置位不被清除吃掉；
- cfg 生效延迟 ≈ 写的 mbus ce 拍 + AXI 侧 2FF + 边沿检测（约 2~3 个
  axi_clk）+ 命令 toggle 的 2FF；多 bit 负载跨域为**准静态**假设——cfg
  应在业务流量空闲时配置（design_spec §11）。

### 3.6 站点索引表

`[17:0]` 寄存器的 bit s ↔ 全局站点 s ↔ AXI 字段（IDW=4 时）。**SI 实例
（SIDE=0，主端口）只有响应站 13..17 能置位/注错；MI 实例（SIDE=1，从
端口）只有请求站 0..12**——对不会报错的站点写 cfg 无效果：

| s | 通道 | 站点内容 | DW | EDCW | INJ_POS 数据位 | INJ_POS 校验位 |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | AW | `awaddr[39:20]` | 20 | 5 | 0..19 | 20..24 |
| 1 | AW | `awaddr[19:0]` | 20 | 5 | 0..19 | 20..24 |
| 2 | AW | `{awlen[7:0], awsize[2:0]}` | 11 | 4 | 0..10 | 11..14 |
| 3 | AW | `{awlock, awcache, awprot, awburst}` | 10 | 4 | 0..9 | 10..13 |
| 4 | AW | `awid` | 4 | 3 | 0..3 | 4..6 |
| 5 | W | `wdata` | 64 | 7 | 0..63 | —（不可注） |
| 6 | W | `wstrb` | 8 | 4 | 0..7 | 8..11 |
| 7 | W | `wlast` | 1 | 1 | 0 | 1 |
| 8 | AR | `araddr[39:20]` | 20 | 5 | 0..19 | 20..24 |
| 9 | AR | `araddr[19:0]` | 20 | 5 | 0..19 | 20..24 |
| 10 | AR | `{arlen[7:0], arsize[2:0]}` | 11 | 4 | 0..10 | 11..14 |
| 11 | AR | `{arlock, arcache, arprot, arburst}` | 10 | 4 | 0..9 | 10..13 |
| 12 | AR | `arid` | 4 | 3 | 0..3 | 4..6 |
| 13 | B | `bresp[1:0]` | 2 | 3 | 0..1 | 2..4 |
| 14 | B | `bid` | 4 | 3 | 0..3 | 4..6 |
| 15 | R | `rdata` | 64 | 7 | 0..63 | —（不可注） |
| 16 | R | `{rresp[1:0], rlast}` | 3 | 3 | 0..2 | 3..5 |
| 17 | R | `rid` | 4 | 3 | 0..3 | 4..6 |

（id 站点的 DW 随 IDW 参数变化，EDCW 按 design_spec §4 阶梯推导。）

### 3.7 访问示例

地址 = `{实例号[7:0], 偏移[7:0]}`。以下序列取自 `sim/tb_edc_top.v`
（NM=1 / NS=1，实例 0 = SI 主端口，实例 1 = MI 从端口）：

```c
// 例 1: 读 ID（连通性自检, T1）
rd 0x00FC   -> 0xEDC01000     // 实例 0
rd 0x01FC   -> 0xEDC01001     // 实例 1

// 例 2: 实例 1 (MI) 站点 5 (W wdata) 注错数据位 5 (T5)
wr 0x0138, 0x00000020         // CFG_INJ_POS[5] bit5 (0x38 = 0x10+8*5)
wr 0x0100, 0x00F00000         // CFG_INJ_EN[0] 站点 5 的 nibble = 1111
                               //   (5/6=0 → 字 0 @0x00, 4*(5%6)=20 → bit[23:20])
/* ... 业务流量经过 ... */
rd 0x01A0   -> 0x00000020     // STA_ERR bit5 = 1
rd 0x01A4   -> 0x00000000     // STA_FAULT bit5 = 0 (注错屏蔽 fault 轨)
wr 0x01A8, 0x00000020         // CFG_IRQEN bit5 -> irq 输出
wr 0x01A0, 0x00000020         // RW1C 清除 STA_ERR bit5
// 收尾（注错仍开着错误会持续再置位, 必须先关）:
wr 0x01A8, 0x0
wr 0x0100, 0x00000000         // 站点 5 的 nibble 写 0000 (关)
wr 0x0138, 0x0                // CFG_INJ_POS[5] 清 0

// 例 3: 实例 0 (SI) 站点 15 (R rdata) 强制错, 验证 fault 轨 (T6)
wr 0x000C, 0x00008000         // CFG_INJ_FORCE bit15 (对应 INJ_EN nibble=0000)
rd 0x00A0   -> 0x00008000     // STA_ERR bit15 = 1
rd 0x00A4   -> 0x00008000     // STA_FAULT bit15 = 1 (双轨)
wr 0x000C, 0x0                // 撤销注错
wr 0x00A0, 0x00008000         // RW1C 清 ERR
wr 0x00A4, 0x00008000         // RW1C 清 FAULT

// 例 4: 越界实例号 (T7, NP=2)
rd 0x0F00   -> pready + pslverr (不产生 mbus 访问)

// 例 5: 寄存器奇偶自检 (T11, 实例 1)
// a) PERR0: mbus 域 cfg_en 包装 key 注错 (regsel=0)
wr 0x01B0, 0x0000001A         // CFG_REGST: key=0xA | REG_SELFTEST | REGSEL=0
rd 0x01AC   -> 0x00000011     // bit0 PAR_FAULT + bit4 PERR0 (bit1 PAR_FAULT_N=0)
wr 0x01AC, 0x00000010         // RW1C 清 PERR0
rd 0x01AC   -> 0x00000002     // 双轨恢复互补 (bit1=1), 无其它源
// b) PERR7: AXI 域 inj_en_q 影子 (regsel=7, 经命令通道注入)
wr 0x01B0, 0x00000E1A         // key | REG_SELFTEST | REGSEL=7
rd 0x01AC   -> 0x00000801     // bit11 PERR7 + bit0 PAR_FAULT
wr 0x01AC, 0x00000800         // RW1C 清 PERR7 (跨域命令)
rd 0x01AC   -> 0x00000002
// c) PAR_SELFTEST: 只置自测锁存 (有 fault 无 PERR 源, ESM 服务签名)
wr 0x01B0, 0x0000002A         // key | PAR_SELFTEST
rd 0x01AC   -> 0x00000001     // 仅 bit0 PAR_FAULT, 任何 PERR 都为 0
wr 0x01AC, 0x00000001         // bit0 W1C 清自测锁存
rd 0x01AC   -> 0x00000002
// d) 错误 key 被忽略
wr 0x01B0, 0x00000012         // key=0x2 ≠ 0xA, 无任何效果
rd 0x01AC   -> 0x00000002
```

```c
// 例 6: 命令在途奇偶 (T13, force 注入地址同步链 1bit 翻转)
force u_apb2mbus.addr_s2 = 0x0188      // 0x01A8(IRQEN) 在途变 0x0188(INJ_POS)
wr 0x01A8, 0x000000FF         // 坏命令: 写被门控, 不落任何寄存器
rd 0x01A8   -> 0x00000000     // IRQEN 完好
rd 0x0188   -> 0x00000000     // 也没有错写到 0x88
rd 0x01AC   -> 0x00040001     // bit18 PERR14 + bit0 PAR_FAULT (广播级损坏双实例置位)
wr 0x01AC, 0x00040000         // W1C bit18 (逐实例清)
wr 0x00AC, 0x00040000
rd 0x01AC   -> 0x00000002
```

注意：

- 例 5 的读回值含双轨位：`PAR_FAULT`/`PAR_FAULT_N` 互补（bit1 平时为
  1），两者同值即输出路径故障；
- RW1C 写后不要立即读回校验（约 2~3 mbus 周期延迟，§3.5；PERR 的
  AXI 域 W1C 还要经 2FF 回传，见 §3.8）；
- 全量写风格：cfg 寄存器是绝对量，改一位也要按目标值整字写，不存在
  读-改-写以外的置位/清位语义（RW1C 除外）；CFG_INJ_EN 是按 nibble
  接受/拒绝，无效码（非 1111/0000）整个 nibble 被忽略，不会部分写入；
- cfg 写应在业务流量空闲时进行（准静态假设，design_spec §11.2）。

### 3.8 寄存器奇偶保护机制

所有数据寄存器（非纯组合 RO）由 `edc_reg_wrap` 实例保护，机制与
hang_prot 参考设计一致：

- **存储 + 偶校验**：`data_q` 与 `par_q` 同拍载入，`par_q = ^data_q`；
  任意 1bit 翻转（数据或校验位）→ `par_err` 置位；
- **自检 key 注错**：`selftest_key` 只翻转 `par_q`（数据不动），
  模拟 1bit 错供软件诊断使用（REGST REGSEL 选择注入哪个包装器）；
- **自愈粘滞**：`flt_q` 与其反相复制 `flt_q_n` 同时翻转判错
  （`dup_err = flt_q_n != ~flt_q`）；`flt_q` 复位为 0、`flt_q_n` 复位
  为 1——SEU 打在该对上会自愈回 SET，不会永久卡死；
- **W1C 优先级**：`flt` 的清零优先于置位，`par_w1c_mask` 按 PERR
  分组跨域清除（mbus 侧写 STA_REGPAR → toggle 握手 → AXI 侧一次性
  应用并应答，随后 mask 清 0，同 §3.5 的一次性语义）。

**PERR 分组**（STA_REGPAR[17:4]，bit4+n 对应 PERR n；PERR14 例外在
bit18，位号公式 4+14 自然外延，既有位不变）：

| PERR | 域 | 覆盖对象 |
| --- | --- | --- |
| 0 | mbus | `cfg_en`（18 × 4bit 编码使能） |
| 1 | mbus | `cfg_force` |
| 2 | mbus | `cfg_irqen` |
| 3 | mbus | `cfg_pos`（INJ_POS 整组） |
| 4 | mbus | `clr_mask`（RW1C 合并暂存） |
| 5 | mbus | STA_ERR 的 mbus 侧镜像 |
| 6 | mbus | STA_FAULT 的 mbus 侧镜像 |
| 7 | AXI | `inj_en_q` 影子（编码使能解码前） |
| 8 | AXI | `inj_force_q` 影子 |
| 9 | AXI | `irqen_q` 影子 |
| 10 | AXI | `inj_pos_q` 影子 |
| 11 | AXI | `err_st` sticky |
| 12 | AXI | `fault_st` sticky |
| 13 | AXI | 在途命令负载奇偶锁存 `perr13_q` |
| 14 | mbus | 命令在途奇偶 `perr14_q`（APB→mbus 链，bit18） |

PERR 7..13 在 AXI 域产生，作为电平经 2FF（`pf_s1/pf_s2`）同步回 mbus
读出；跨域 W1C 由 `par_w1c_mask` 随命令通道下发、AXI 域一次性应用。

**在途命令奇偶（PERR13）**：mbus→AXI 的命令负载
（cfg 全量 + clr/w1c/st 负载）在源端算 1bit 偶校验 `par_pay`，与负载
同深度 2FF 到 AXI 域为 `par_pay_s2`，在 `cmd_pulse` 当拍校验
`(^cmd_pay_axi) != par_pay_s2` → 置 `perr13_q`（含反相复制）。这覆盖
了多 bit 负载跨 CDC 的准静态假设失效场景（亚稳或位偏斜导致负载
不一致），校验位本身坏了也会被发现。REGST 无法注入 PERR13（源端
无注入点），tb 用 force 翻转同步链 1 bit 验证了该通路（用例 T12）；
REGST 的 PAR_SELFTEST 位与此无关——它只置自测锁存（例 5c）。

**命令在途奇偶（PERR14）**：PERR13 的 APB→mbus 对应物。`apb2mbus` 在
APB 侧组合生成 `par = ^{paddr, pwrite, pwdata}`，经与 payload 3FF 同
深度（同沿采样）的独立链同步输出——ce 拍 `par` 与 `addr/wr/wdata`
必为同一代；本模块 ce 拍用收到的 `{addr, wr, wdata}` 重组比对，
`par_cmd_bad = ce && !par_ok` 置 `perr14_q`（含反相复制，W1C bit18
当拍清，不经 AXI 命令通道）。防的是「地址/命令在途 1bit 翻转 →
错位写 / 错实例读」——此前该通路仅靠内容级机制部分拦截（DC 60–70%，
SIL3 差距残余 #6）。要点：

- **所有实例都检查（不 gate sel）**：公共通路（apb2mbus 同步链或
  广播前）损坏 → 全实例置位；fanout 后局部损坏 → 仅该实例置位——
  置位模式本身即诊断信息；
- **失配 fail-safe**：全部写使能（各 wrapper `wr`、`w1c_wr`、
  `parwrc`、`regst_w`）与 `cmd_t` 翻转统一被 `wr_ok = sel && wr &&
  par_ok` 门控，坏命令不落任何寄存器、不产生 AXI 命令；读时
  `rdata` 驱 0，APB 读回 0（不交付错地址的数据）；
- REGST 无法注入 PERR14（校验在 apb2mbus 源端生成），tb 用 force
  翻转地址同步链 1 bit 验证（用例 T13：写偏移位验证门控、读实例位
  验证错实例读回 0）。

**局限**（design_spec §12）：

- 偶校验无法发现同一包装器内同时翻转 2bit（共模），靠周期性
  REGST 自检 + 置位优先兜底；PERR14 同理（addr 与 par 链各翻 1bit
  抵消，或 2bit 共落在 payload 链）；
- 2FF 同步第一级本身不受保护（标准做法，第一级亚稳传播概率已
  MTBF 级别）；第一级亚稳导致的伪 PERR 是安全方向失效；
- PERR14 的 `par` 覆盖 `pwdata`：APB 只保证写访问相内 PWDATA 稳定，
  读相内 master 翻转 PWDATA 会造成假 PERR14（安全方向，W1C 即清）；
  集成方应保证 PWDATA 全 access 相稳定；
- `par_ok` 检查点之后的组合译码/写使能逻辑不在覆盖内（需双份译码
  比较，SIL3 路 B 的项之一）；
- `reg_par_fault` 双轨输出供 ESM 侧做互补校验，irq 不参与双轨
  （通知级冗余）。
