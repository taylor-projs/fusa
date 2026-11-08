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
     │               │        │  +锁存命令/翻转req_t]                  │
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
- ce 拍（M4）选中的 `edc_regfile` 在 M4 末上升沿**写寄存器**（`sel && wr`）；
  跨域寄存器的写另经锁存 + `req_t` 翻转下发命令到 mod 域（见 §3.5）；
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
握手往返延迟（cfg 生效、RW1C 清除 ≈ 3 mod + 2 mbus 拍，见 §3.5）。

## 3. edc_regfile 寄存器说明

### 3.1 模块功能

`edc_regfile` 是 `EDC_GEN_CHK` 实例内的寄存器文件，**双时钟域**
（mbus 24MHz + mod_clk = axi_clk），全部 CDC 收编在模块内（结构与
`ia_bus_timeo_regfile` 相同）：

- cfg 寄存器（INJ_EN / INJ_FORCE / INJ_POS / IRQEN）+ `sel` 实例译码 +
  组合读 mux（与 `ce` 同拍）；
- RW1C 清除：写数据经握手（锁存 + `req_t`）下发，mod 域 `req_edge`
  拍一次性掩码清除（无 mbus 域累加寄存器）；
- sta 回读：mod 域粘滞电平 `err/fault/irq` 经 2FF 同步后参与读 mux；
- 命令管理：mbus 侧锁存 `{wsel_q, wdata_q}` + `req_t` 翻转，
  `cdc_busy = (req_t != ack_s2)`，忙时写丢弃并置 WR_DROPPED（0xB4[1]）；
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
| 0xAC | STA_PAR | RW1C/R | 0x2 | 寄存器奇偶状态（见 §3.8；bit1 为反轨，复位常读 0x2） |
| 0xB0 | CFG_REGST | W(key) | — | 寄存器奇偶自测控制，[3:0] key=0xA，读回 0 |
| 0xB4 | STA_MISC | R/W1C | 0x0 | [0] CFG_BUSY (RO) 握手在途；[1] WR_DROPPED (W1C) 忙时写被丢 |
| 0xFC | ID | RO | 0xEDC01000\|IDX | 实例标识 |
| 其余 | — | — | — | 保留：读 0，写忽略（无握手副作用） |

`[17:0]` 寄存器的 bit s 对应全局站点 s（见 §3.6）；[31:18] 保留，读 0、
写忽略。**跨域寄存器（EN/FORCE/IRQEN/STA_ERR/STA_FAULT/STA_PAR 的
W1C、REGST）的每次写是一条握手命令**：锁存 `{wsel, wdata}` + 翻转
`req_t`，忙时（上一条未应答）被丢弃并置 WR_DROPPED（§3.5）；INJ_POS
与 ID/保留地址为 mbus 本地操作，不占握手。

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
- 写副作用：经握手下发（锁存 + `req_t`，`req_edge` 拍载入 mod 域
  影子，§3.5）；mbus 图像 = mod 影子的同步镜像（单一事实源在 mod）；
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
- 写为 **mbus 本地操作**（准静态直出到站点引擎，不占握手、不会忙丢）；
  软件协议先写 pos 后开 en。

#### STA_ERR（0xA0，RW1C）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [17:0] | err[s] | 读：mod 域 `err_st` 的 2FF 同步值（含注错错误）。写：写 1 的位经握手（锁存 + `req_t`）在 mod 域 `req_edge` 拍一次性掩码清除 |

- 读值是同步后的电平，非瞬时采样——mod 域 `err_st` 本身为粘滞位，
  置位后保持到被清除；
- RW1C 写后约 3 mod + 2 mbus 拍（握手往返 + 回读同步）内读回仍可能
  为 1；写前应轮询 0xB4[0] CFG_BUSY（design_spec §8.2/§12）；
- 若错误源仍在（如注错仍使能且流量持续），清除后会再次置位，属预期；
- 写 0 的位无效；清除即一条握手命令（忙时被丢 → WR_DROPPED）。

#### STA_FAULT（0xA4，RW1C）

与 STA_ERR 结构相同，对应 fault 轨：

- `fault_st[s]` 置位条件：站点 s 出现 syndrome 错 **且 `inj_en[s]=0`**
  （organic 错误）；
- 注错使能的站点 fault 轨被屏蔽，读回恒 0；
- RW1C 语义、延迟、再置位行为同 STA_ERR。

#### CFG_IRQEN（0xA8，RW，复位 0）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [17:0] | irqen[s] | 1 = 站点 s 的 err 参与实例中断：`irq = |(err_st & irqen)`（mod 域计算，2FF 回 mbus 域输出） |
| [31:18] | — | 保留，读 0 写忽略 |

- 只影响本实例 `irq` 输出，不影响 `esm_err`/`esm_fault`（二者无条件
  汇聚到 ESM）；
- 写经握手下发（mod 域影子为单一事实源，mbus 图像为镜像）。

#### STA_PAR（0xAC，RW1C/R，复位 0x2）

寄存器奇偶校验状态（详见 §3.8）：

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [0] | PAR_FAULT | 读：电平 = 所有 PERR 源之或 + 自测锁存。写 1：只清自测锁存（源仍置时读回保持 1） |
| [1] | PAR_FAULT_N | RO 反轨（双轨 ESM 输出 `reg_par_fault_n` 的回读），正常时 = ~bit0 |
| [16:2] | PERR14..PERR0 | W1C：**bit = 2 + 组号**。每位清除对应寄存器的奇偶粘滞。mbus 域组（0..6/13/14）当拍生效；mod 域组（7..9/11/12）经握手 `req_edge` 译码清除（一个 SW 写，两域同步）；组 4/10 退役（恒 0） |
| [31:17] | — | 保留，读 0 |

- 无故障时读回 0x2（反轨 bit1 常为 1）；
- 每个源在**自己的 PERR 位**上清除，"电平保持到无未清源"是单一事实源；
- W1C 即一条握手命令（忙时被丢 → WR_DROPPED，先轮询 CFG_BUSY）。

#### CFG_REGST（0xB0，W，读回 0）

寄存器奇偶自测控制。**写保护**：`wdata[3:0]` 必须为 4'b1010（key），
否则整写忽略（无握手副作用）——防软件误触发。

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [3:0] | KEY | 必须为 4'b1010 |
| [4] | REG_SELFTEST | 脉冲：对 REGSEL 选中的组注入校验错（只翻校验位，数据不污染） |
| [12:9] | REGSEL | 目标组号：0..3/5/6 本域（mbus）当拍注入；7..9/11/12 经握手在 mod 域注入；4/10 退役无目标；13/14 无注入点（忽略） |
| [5] | PAR_SELFTEST | 脉冲：只置自测锁存（"有 fault 无源"= ESM 服务程序的自检签名） |
| 其余 | — | 忽略 |

- mbus 域跟随型寄存器（镜像/sticky）注入后下一拍自恢复（wr=1），
  粘滞已锁存需 W1C；RW 型（cfg）注入保持到该寄存器下次重写；
- 自测序列建议：REG_SELFTEST → 读 STA_PAR 验证 PERR/PAR_FAULT
  （及 ESM 双轨）→ 恢复（重写目标寄存器或等跟随自恢复）→ W1C。
  mod 域组的注入/W1C 各占一条握手命令，相邻操作间轮询 CFG_BUSY。

#### STA_MISC（0xB4，R/W1C，复位 0）

跨域握手状态（ia 式一次一条命令协议的 SW 契约寄存器）：

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [0] | CFG_BUSY | RO：握手在途（`cdc_busy = req_t != ack_s2`）。1 = 上一条命令尚未被 mod 域应答，此时再写跨域寄存器会被丢弃 |
| [1] | WR_DROPPED | RW1C：忙时到达的跨域写被丢弃的粘滞记录（显性化，不无声吞写） |
| 其余 | — | 读 0 |

- SW 契约：相邻跨域写之间轮询 bit0 直到 0（或按握手往返
  ≈ 3 mod + 2 mbus 拍间隔写）；mbus 叶端零等待不反压，丢写只记
  不拦；
- bit1 置位 = 有写未生效，服务程序应重写并检查；INJ_POS/ID 等
  mbus 本地寄存器不会触发。

#### ID（0xFC，RO）

| 位 | 字段 | 说明 |
| --- | --- | --- |
| [31:0] | id | `32'hEDC0_1000 \| IDX`，如 IDX=0 → 0xEDC01000，IDX=1 → 0xEDC01001 |

只读；写忽略（无副作用，不占握手）。软件可用低 8bit 反查实例号，
常用于总线连通性自检（tb 用例 T1）。

### 3.5 写副作用与命令下发时序

跨域寄存器（EN/FORCE/IRQEN 写、STA_ERR/STA_FAULT/STA_PAR 的 W1C、
REGST 注错）每次写 = 一条握手命令（ia 式一次一条 toggle 协议）：

```
mbus 域 (24MHz)                              mod 域 (mod_clk = axi_clk)
──────────────────────                        ──────────────────────
ce 拍: 锁存 {wsel_q, wdata_q}
       (在途期间保持稳定)
       req_t 翻转 ───── sync_2dff ──────────▶ req_t_s2
                                              sync_dff 延迟拍 d
                                              req_edge = s2 ^ d
                                              req_edge 拍 (用锁存值译码):
                                                en_word_e/force_word_e/irqen_word_e:
                                                  影子 <= wdata_q (reg_wrap 载入)
                                                err_w1c_e/fault_w1c_e/par_w1c_e:
                                                  sticky <= (sticky & ~wdata_q) | site_err (置位优先)
                                                reg_st_e: mod 域组注错
                                              然后 ack_t 翻转
                ◀──── sync_2dff ──────────── ack_t
cdc_busy = (req_t != ack_s2):
  忙时到达的新写被丢弃 -> wr_dropped_q 置位 (0xB4[1])
```

- **多位数据靠稳定传输**：只同步 `req_t` 一个 bit，负载是 mbus 侧锁存
  值（在途期间不变），mod 域 `req_edge` 拍采样锁存值译码——没有并行
  负载同步链；
- **一次一条命令**：`cdc_busy` 期间的新写被**丢弃**（不反压、不合并），
  置 WR_DROPPED 显性化；SW 契约 = 相邻跨域写之间轮询 0xB4[0] CFG_BUSY
  （例中相邻写间隔天然大于握手往返，勿背靠背快写）；
- **置位优先**：`req_edge` 拍若站点同时来新错，置位不被清除吃掉；
- cfg 生效延迟 ≈ ce 拍 + mod 侧 2FF + 边沿检测（约 2~3 个 mod_clk）
  + ack 回程；cfg 配置仍应在业务流量空闲时进行（pos 准静态协议，
  design_spec §11）。

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
// a) PERR0: mbus 域 cfg_en 图像 key 注错 (regsel=0)
wr 0x01B0, 0x0000001A         // CFG_REGST: key=0xA | REG_SELFTEST | REGSEL=0
rd 0x01AC   -> 0x00000005     // bit0 PAR_FAULT + bit2 PERR0 (bit1 PAR_FAULT_N=0)
wr 0x01AC, 0x00000004         // RW1C 清 PERR0 (bit = 2+组号)
rd 0x01AC   -> 0x00000002     // 双轨恢复互补 (bit1=1), 无其它源
// b) PERR7: mod 域 inj_en_q 影子 (regsel=7, 经握手注入)
wr 0x01B0, 0x00000E1A         // key | REG_SELFTEST | REGSEL=7
rd 0x01AC   -> 0x00000201     // bit9 PERR7 + bit0 PAR_FAULT
wr 0x01AC, 0x00000200         // RW1C 清 PERR7 (经握手跨域清)
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
rd 0x01AC   -> 0x00010001     // bit16 PERR14 + bit0 PAR_FAULT (广播级损坏双实例置位)
wr 0x01AC, 0x00010000         // W1C bit16 (逐实例清)
wr 0x00AC, 0x00010000
rd 0x01AC   -> 0x00000002
```

注意：

- 例 5 的读回值含双轨位：`PAR_FAULT`/`PAR_FAULT_N` 互补（bit1 平时为
  1），两者同值即输出路径故障；PERR 位号 = 2 + 组号（PERR0=bit2 …
  PERR14=bit16）；
- 跨域写（含 RW1C/REGST）之间轮询 `0xB4[0]` CFG_BUSY：忙时写被丢弃
  并置 WR_DROPPED（例中相邻写经 APB 往返天然间隔足够）；
- RW1C 写后不要立即读回校验（mod 域组清除要等握手往返 + 2FF 回传，
  §3.5/§3.8）；
- 全量写风格：cfg 寄存器是绝对量，改一位也要按目标值整字写，不存在
  读-改-写以外的置位/清位语义（RW1C 除外）；CFG_INJ_EN 是按 nibble
  接受/拒绝，无效码（非 1111/0000）整个 nibble 被忽略，不会部分写入；
- cfg 写应在业务流量空闲时进行（准静态假设，design_spec §11.2）。

### 3.8 寄存器奇偶保护机制

所有数据寄存器（非纯组合 RO）由 `reg_wrap` 实例保护，机制与
hang_prot 参考设计一致：

- **存储 + 偶校验**：`data_q` 与 `par_q` 同拍载入，`par_q = ^data_q`；
  任意 1bit 翻转（数据或校验位）→ `par_err` 置位；
- **自检 key 注错**：`selftest_key` 只翻转 `par_q`（数据不动），
  模拟 1bit 错供软件诊断使用（REGST REGSEL 选择注入哪个包装器）；
- **自愈粘滞**：`flt_q` 与其反相复制 `flt_q_n` 同时翻转判错
  （`dup_err = flt_q_n != ~flt_q`）；`flt_q` 复位为 0、`flt_q_n` 复位
  为 1——SEU 打在该对上会自愈回 SET，不会永久卡死；
- **W1C 优先级**：`flt` 的清零优先于置位；跨域组的 W1C（mod 域组
  7/8/9/11/12）经握手（锁存 + `req_t`）在 mod 域 `req_edge` 拍一次性
  应用（§3.5 同一握手通道，一个 SW 写两域同步清除）。

**PERR 分组**（STA_PAR[16:2]，**bit = 2 + 组号**；PERR14 落 bit16，
2026-11-06 起无保留位）：

| PERR | 域 | 覆盖对象 |
| --- | --- | --- |
| 0 | mbus | `cfg_en` 图像（18 × 4bit 编码使能，mod 影子镜像） |
| 1 | mbus | `cfg_force` 图像（mod 影子镜像） |
| 2 | mbus | `cfg_irqen` 图像（mod 影子镜像） |
| 3 | mbus | `cfg_pos`（INJ_POS 整组，mbus 本体） |
| 4 | — | **退役**（原 clr_mask：W1C 改锁存 + req_edge 一次性掩码后无累加寄存器；bit6 恒 0） |
| 5 | mbus | STA_ERR 的 mbus 侧镜像 |
| 6 | mbus | STA_FAULT 的 mbus 侧镜像 |
| 7 | mod | `inj_en_q` 影子（编码使能解码前） |
| 8 | mod | `inj_force_q` 影子 |
| 9 | mod | `irqen_q` 影子 |
| 10 | — | **退役**（原 inj_pos_q 影子：pos 准静态直出后无 mod 域影子；bit12 恒 0） |
| 11 | mod | `err_st` sticky |
| 12 | mod | `fault_st` sticky |
| 13 | mbus | 在途写锁存奇偶 `perr13_q`（`{wsel_q, wdata_q}` 锁存通道） |
| 14 | mbus | 命令在途奇偶 `perr14_q`（APB→mbus 链，bit16） |

PERR 7/8/9/11/12 在 mod 域产生，作为电平经 2FF（`pf_s1/pf_s2`）同步
回 mbus 读出；跨域 W1C 经握手 `req_edge` 译码在 mod 域一次性应用。

**在途写锁存奇偶（PERR13）**：稳定传输协议依赖「在途期间
`{wsel_q, wdata_q}` 锁存值不变」；对该锁存整体算 1bit 偶校验 `par_pay`，
在 **mbus 域本地**比对（锁存拍与检查拍一致）——锁存窗口内的寄存器
位翻转（SEU / 命令译码毛刺锁进错误值）被检出，mod 域拿到的必是
通过校验的那一代数据。REGST 无法注入 PERR13（源端无注入点），
tb 用 force 破坏在途锁存通道验证该通路（用例 T12）；REGST 的
PAR_SELFTEST 位与此无关——它只置自测锁存（例 5c）。

**命令在途奇偶（PERR14）**：PERR13 的 APB→mbus 对应物。`apb2mbus` 在
APB 侧组合生成 `par = ^{paddr, pwrite, pwdata}`，经与 payload 3FF 同
深度（同沿采样）的独立链同步输出——ce 拍 `par` 与 `addr/wr/wdata`
必为同一代；本模块 ce 拍用收到的 `{addr, wr, wdata}` 重组比对，
`par_cmd_bad = ce && !par_ok` 置 `perr14_q`（含反相复制，W1C bit16
当拍清，不经握手通道）。防的是「地址/命令在途 1bit 翻转 →
错位写 / 错实例读」——此前该通路仅靠内容级机制部分拦截（DC 60–70%，
SIL3 差距残余 #6）。要点：

- **所有实例都检查（不 gate sel）**：公共通路（apb2mbus 同步链或
  广播前）损坏 → 全实例置位；fanout 后局部损坏 → 仅该实例置位——
  置位模式本身即诊断信息；
- **失配 fail-safe**：全部写使能（各 wrapper `wr`、`w1c_wr`、
  `parwrc`、`regst_w`）与 `req_t` 翻转/锁存装载统一被
  `wr_ok = sel && wr && par_ok` 门控，坏命令不落任何寄存器、不产生
  跨域命令；读时 `rdata` 驱 0，APB 读回 0（不交付错地址的数据）；
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
