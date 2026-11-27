# FuSa 寄存器表标准块（注错 / 状态 / 清除 / 屏蔽）— 固化定义 v1.0

> 目的：所有采用 horizon reg_gen_parity 奇偶加固流程的 regfile，
> **0x04~0x14 的 FuSa 标准块完全一致**（寄存器名、偏移、字段、属性、
> 复位值逐行固定），不同设计只替换功能寄存器区与扩展故障位，脚本
> （excel2rdl.py / rdl2reg.py / rdl2def.py）对所有设计通用。
>
> 依据：Horizon J6B-fusa 既有块（taylor_v3.xlsx / taylor_v3.v 实测生成
> 结果）抽出的固定部分。表头 `ECC_OFFSET = 0x4` 固定。

## 1. Excel 表固定行（**v1.1 起由工具自动追加，不再手抄**）

> **自动追加模式（推荐）**：xlsx 只写功能寄存器（offset < ECC_OFFSET）+
> 可选 `ExtInt` sheet（每行一个扩展故障）——excel2rdl.py 检测到表内没有
> PASSWORD 时，自动按本节定义在 ECC_OFFSET 处追加标准块；`gen_regfile.sh`
> 一条命令产出 `xx.rdl` + `xx_apb_regfile.v`。表内已写 PASSWORD 的旧式
> 全量表仍然兼容（不再追加）。`xlsx_materialize.py` 可把追加结果物化回
> 全量表行喂 perl（字节级等价已回归验证）。下面各行仍是追加内容的
> 权威定义：

表头区（1~5 行）固定值：`BASE_ADDR:0x0`、`ADDR_WIDTH=<按设计>`、`APB3`、
`REG_NUM=<按设计>`、**`ECC_OFFSET:0x04`（固定）**（perl 单格格式；第 7 行
`registers group` 分节行为 perl 必需——perl 无条件跳过列头后第一行）。

标准块从 **0x04** 开始，占据寄存器表尾部（功能寄存器只允许放在 ECC_OFFSET
以下，或整体把标准块上移并同步改 ECC_OFFSET，推荐保持 0x4 起始不动）。

| Offset | Register Name | SubBits | Field Name | Attribute | DefaultValue | Description |
|---|---|---|---|---|---|---|
| 04h | PASSWORD | [31:0] | passwd | RW | 32'h0badbeef | 写钥匙；写入 32'h95f2d303 解锁 0x08~0x14 写 |
| 08h | FUSA_CTRL | [31:13] | reserved | RO | 0 | reserved |
| 08h |  | [12] | parity_invert | RW | 1'b0 | 奇偶反转注入（SW 触发，2cycle 窗口，全部 bank 同时报错） |
| 08h |  | [11:8] | parity_fault_injection | RW | 4'b0 | 直接注入 parity 码型（配合 fault_injection_en） |
| 08h |  | [7:4] | reserved | RO | 0 | reserved |
| 08h |  | [3:2] | lockstep_fault_injection | RW | 2'b0 | lockstep 比较注错码型（输出给比较器侧） |
| 08h |  | [1] | fault_injection_en | RW | 1'b0 | 注错总使能（parity 码型注入门控） |
| 08h |  | [0] | parity_decoder_enable | RW | 1'b0 | parity 解码使能；0=decoder 旁路（fail-visible 验证用） |
| 0ch | MIssionIntStatusSet0 | [31:N+1] | reserved | RO | 0 | reserved（N=扩展故障数，见 §2） |
| 0ch |  | [N:1] | `<int>_set` | WO | 1'b0 | 各扩展故障软件置位触发（每故障 1 bit，位置三寄存器一致） |
| 0ch |  | [0] | parity_err_set | WO | 1'b0 | 奇偶错误软件置位（模拟故障） |
| 10h | MIssionIntStatus0 | [31:N+1] | reserved | RO | 0 | reserved |
| 10h |  | [N:1] | `<int>_status` | W1C | 1'b0 | 各扩展故障粘滞状态（硬件置位优先于 W1C） |
| 10h |  | [0] | parity_err_status | W1C | 1'b0 | 奇偶错误状态（reg_parity_error 硬件置位） |
| 14h | MIssionIntMask0 | [31:N+1] | reserved | RO | 0 | reserved |
| 14h |  | [N:1] | `<int>_mask` | RW | 1'b0 | 各扩展故障屏蔽 |
| 14h |  | [0] | parity_err_mask | RW | 1'b0 | 奇偶错误屏蔽（mission_int 门控） |

taylor_v3 实例（N=6，bit6→bit1：pd_top_noc_idlereq_time_out /
pd_top_bisr_done_time_out / pd_top_bisr_busy_time_out /
pd_top_pwr_off_time_out / top_pmu_signal_chk_err / lockstep_err）即本
模板的填充样例。

## 2. 扩展故障位分配规则（标准化）

- **bit0 恒为 parity_err**（set/status/mask 三寄存器同位）。
- 扩展故障从 **bit1 向上逐位分配**，每个故障源 `<int>` 占 1 bit，在
  Set/Status/Mask 三个寄存器中**位置一致**（软件按同一 bit 号操作三处）。
- 多 bit 故障源（如总线错误计数）可占连续多位，三寄存器同宽同位。
- 上限：N ≤ 31；剩余高位一律 reserved/RO。
- 生成器约定：字段名 = `<故障源信号名>` + `_set` / `_status` / `_mask`
  后缀（`_status` 后缀同时是 ext_int 端口派生依据，不得改名）。

## 3. 故障种类与产生方法（标准化，六类）

| # | 故障种类 | 注入方法 | 硬件效果 |
|---|---|---|---|
| F1 | parity 翻转注错 | FUSA_CTRL.parity_invert 写 1 一拍 | 存储侧 parity 取反 2cycle 窗口 → reg_parity_error **全 bank 同时**报（and 语义）→ parity_err_status 置位 → mission_int |
| F2 | parity 码型注错 | parity_fault_injection[3:0] 设码型 + fault_injection_en=1 | 写操作时 enc bypass，按码型直写 parity → 后续解码报错（单 bank，or 语义） |
| F3 | 解码器断开 | parity_decoder_enable=0 | parity_decoder_bypass=1，故障不纠不检（fail-visible 演练） |
| F4 | lockstep 注错 | lockstep_fault_injection[1:0] 设码型 | 码型输出到 lockstep 比较器侧（设计侧消费） |
| F5 | 软件模拟置位 | MIssionIntStatusSet0 对应位写 1 | 对应 `_status` 置 1（无需真实故障，诊断/TB 用） |
| F6 | 真实故障输入 | 设计内部监视点接 `<int>_status_wr/_in` 输入 | 置位对应 `_status`（硬件置位优先于 W1C 粘滞） |

**清除（标准化）**：`MIssionIntStatus0` W1C——写 1 清对应位；写 0 无
动作；硬件置位与清除同拍竞争时**置位优先**（粘滞语义）。

**屏蔽（标准化）**：`<int>_mask`=1 时对应 `<int>_err` 输出压制；
`parity_err_mask`=1 压制 mission_int。mask 只压输出，不清状态。

**输出（标准化）**：每个故障源打拍输出 `<int>_err = ~mask & status`；
`mission_int = ~parity_err_mask & parity_err_status`（打拍）。
按 rtl-coding-style 规则 13，给 ESM 的 err 一律双轨（err/err_n）。

## 4. 写保护（标准化）

- 0x04 PASSWORD 本身不设防（首个 ECC 寄存器）。
- 0x08~0x14 所有写操作必须 `passwd == 32'h95f2d303`（写 PASSWORD 解锁，
  复位值 32'h0badbeef = 上锁态）。
- 功能寄存器区（< ECC_OFFSET）不受 passwd 门控。

## 5. 与工具链的关系

- **v1.1**：功能寄存器-only xlsx（+ ExtInt sheet）→ excel2rdl.py 自动
  追加本块 → rdl2reg.py 生成 RTL；`bash gen_regfile.sh xx_apb_regfile.xlsx`
  一条命令产出 `xx.rdl` + `xx_apb_regfile.v`（自检 PASS/FAIL）。
- 本块行原样出现在 xlsx 中（旧式全量表）→ excel2rdl.py 原样转成 RDL，
  不再追加（角色识别沿用名字约定：`PASSWORD` / `^FUSA_CTRL` / `Set\d*$` /
  `Status\d*$` / `Mask\d*$` / `_status`·`_set`·`_mask` 后缀，perl 与
  python 生成器同规）。
- 新设计只需：功能寄存器行 + ExtInt sheet 每行一个故障源（§2 规则自动
  分配位序）；FUSA_CTRL 注错字段全保留、位不动。

## 6. v2 手绘三寄存器 FuSa 块（n/m 占位，手写全量表）

v2 草案（实例见 tests_edge `TestV2FuSa` / 回归 `taylor_v2`）：ECC_OFFSET=0x10，
FUSA_CTRL@0x10 / STA_PAR@0x14 / CFG_REGST@0x18，直接手写进 xlsx
（**不再追加** v1.0 标准块——表内出现 ≥ECC_OFFSET 的寄存器即判定手写全量表）。

- **占位符**：`[31:n]`、`[n-1:4]`、字段名 `reg<m-1>~reg0_par_err_sta`、
  复位值 `<m>''b0` 由 excel2rdl.py 自动定尺寸：**m = parity bank 成员数**
  （非 RO/RES 且非 PASSWORD/Set*/Status* 的全部寄存器，功能寄存器 +
  FUSA_CTRL/STA_PAR/CFG_REGST 本身），**n = m+4**（上限 m=27）。v2 实例：
  5 个 bank 成员 → `reserved[31:9]` + `reg_par_err_sta[8:4]`。
- **[3:2] 必须显式写 reserved 行**：手绘表 [31:n]/[n-1:4]/[1]/[0] 少了
  [3:2]，加载器按"缺 bit 区间名"报错拒绝，补 `reserved [3:2] RO 0`
  两行即过（STA_PAR 与 CFG_REGST 各一行）。
- **FUSA_CTRL v2 形态**：`fault_inj_en[3:0] RW 4'hf`（默认全使能）；
  无 v1.0 的 legacy 控制字段时生成器把 `parity_invert` 等五根旧控制线
  安全常值化（decoder 恒使能、无码型注入）——RTL 确定性可综合。
- **STA_PAR**：`reg_par_err_sta[n-1:4]` W1C（每 bank 成员 1 bit 粘滞
  奇偶错），硬件置位走生成器自带的 `<field>_wr/_in` 输入口（hw 置位
  优先于 W1C）；`par_fault_n_sta[1]`（复位 1）/`par_fault_sta[0]`（复位
  0）为奇偶故障正/反状态位。各成员 `parity_dec_error` 消费逻辑（谁拉
  `reg_par_err_sta_wr`）属设计侧后续工作，端口已备好。
- **CFG_REGST**：`par_selftest_reg_sel[n-1:4]` + `reg_selftest_en[1]` +
  `par_selftest_en[0]`，全 WO（写读回 0，存 bank 受 parity 保护）；
  自检执行逻辑（选中寄存器的 parity 复算/比对）属设计侧后续工作。
- **无 PASSWORD**：v2 地图无 passwd 门控（perl 原逻辑会引用未声明的
  `passwd` 直接编译错，python 版改为不加门控）。
