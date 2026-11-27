# FuSa 全仓 RTL 设计复查报告

> **日期**: 2026-11-24
> **范围**: 11 个交付 IP + `common_modules`(≈46 个 RTL 文件)
> **方法**: 静态只读评审,逐个对照各设计 `doc/` 规格、`fusa_ip_user_guide.md`、`.claude/skills/rtl-coding-style/SKILL.md` 强制规则(9 个并行评审,关键发现已人工抽验)
> **结论**: 共 **44 处问题**(43 RTL + 1 文档);多数为功能回归/覆盖率「全绿」也覆盖不到的类别 —— 未映射地址空间、SEU/注错边角、复位释放时序、计数器回绕/饱和极值

**说明**: `5.esm` 仅有规格章、无独立 RTL;`11.audio_sram` / `12.axi2sram_ctrl` 尚无用户指南章,按各自 `doc/` 评审。

---

## 0. 结论摘要

| 设计 | 发现数 | 最高严重级 |
|---|---|---|
| common_modules | 5 | 🔴 |
| 5.cmm | 11 | 🔴 |
| 12.axi2sram_ctrl | 6 | 🔴 |
| 1.hang_prot | 4 | 🔴 |
| 3.ia_bus_timeout | 7 | 🔴 |
| 2.parity/edc | 4 | 🟠 |
| 11.audio_sram | 2 | 🔴 |
| 9.int_prot | 2 | 🟠 |
| 10.dup_ctrl | 2 | 🟠 |
| 6.apb2mbus | 1 | 🟠 |
| 8.reset_checker | 0 (1 文档 nit) | 🟢 |

**跨设计系统性缺陷(优先修,一处修多处受益)**: 寄存器地址别名(4 仓)、`WR_DROPPED` 漏折 `esm_fault`(2 仓)、非法 ENA 仍执行 action 位(2 仓)、4bit 编码使能缺写回(3 仓)、`scan_mode` tie 死(2 仓)、Q/Q_n 自愈不完整(多仓)。

**本次复查派生动作**:
1. 新增永久规则 **26**(复位同步收编在单设计 core)—— 已写入 `rtl-coding-style/SKILL.md`。
2. hang_prot **AWPROT 丢弃** 已修复(补入 skid `reg_t`)。

---

## 1. 跨设计系统性缺陷

### 🔴 S1. 未映射地址别名可改写/读到活寄存器(4 个 regfile 同款)

根因: `wsel = addr[5:2]`, `range_ok` **从不检查 `addr[7:6]`**,故 `0x40/0x80/0xC0`(及每寄存器偏移镜像)别名到低段寄存器。越界/错址访问本应静默丢弃读 0,实际会写活寄存器(如关监测、清账本、触发自测)。

| 设计 | 位置 |
|---|---|
| hang_prot | `1.hang_prot/rtl/hang_prot_regfile.sv:381-388` |
| ia_bus_timeout | `3.ia_bus_timeout/rtl/ia_bus_timeo_regfile.sv:286-300` |
| audio_sram | `11.audio_sram/rtl/audio_sram_regfile.sv:246-257` |
| dup_ctrl | `10.dup_ctrl/rtl/dup_ctrl_regfile.sv:228-255` |

**修复**: `range_ok` 增加 `addr[7:6]==2'b00`(或精确 `wsel` 集合)判定。**cmm / axi2sram / parity / reset_checker 的 regfile 需一并核查是否同款**。

### 🔴 S2. `WR_DROPPED` 未折入 `esm_fault`(2 仓,违反规则 25)

忙丢是「监视器自身完整性故障」,按规则 25 必须走 `esm_fault`,但聚合漏了:

- parity: `2.parity/rtl/edc_regfile.sv:840-841` — `esm_fault = |fault_s2 | perr13 | perr14`,缺 `wr_dropped_q`。
- ia_bus_timeout: `3.ia_bus_timeout/rtl/ia_bus_timeo_regfile.sv:956-961` — 同样缺。

**危害**: 合法写被丢弃、`STA_MISC/STA_CDC` 置位,但 ESM 无上报,软件可 W1C 掉唯一指示。

### 🟠 S3. 非法 ENA 码字仍执行 action 位(2 仓,违反规则 11)

`SCMCNTRL`/`CFG_REGST` 的 `TO_CLR`/`SELFTEST`/`FU_SELFTEST`/`QSR_REL` 只验 key+action 位,**不验 `ena_codeword`**。非法 ENA(如 `0x5`)整写被拒,但动作照做:

- hang_prot: `1.hang_prot/rtl/hang_prot_regfile.sv:491-494,547-556`
- ia_bus_timeout: `3.ia_bus_timeout/rtl/ia_bus_timeo_regfile.sv:533,616-622`

### 🟠 S4. 4bit 编码使能缺「纠 1bit + 写回」(3 仓,违反规则 11)

多数 regfile 有 `dec4()` 纠错**读出面**,但缺把纠正码**写回存储**的自愈路径(SEU 翻转后停留在非法码,STA_PAR 清后持续重报):

- cmm: `5.cmm/rtl/cmm_top.sv:257-265,366-380`
- parity: `2.parity/rtl/edc_regfile.sv:463-530`(影子无 `dec4.fix`)
- axi2sram: `12.axi2sram_ctrl/rtl/axi2sram_ctrl_regfile.sv:608-658`(AXI 域影子无写回)

### 🟠 S5. `scan_mode` tie 死 / 未拉顶层(违反规则 19)

- parity: `2.parity/rtl/edc_regfile.sv:204-210` — `u_rst_sync.scan_mode = 1'b0`。
- cmm: `5.cmm/rtl/cmm_top.sv:89-154` — 用 `sync_2dff` 而非 `rst_sync`,无 scan_mode 端口。
- common_modules: `rst_sync` ASIC 分支仅支持 2 级释放,`SYNC_LVL_NUM=3` 时 elaboration `$error` 直接建不起来(`common_modules/rst_sync.sv:76-89`)。

### 🟠 S6. Q/Q_n 自愈不完整 / W1C 抹掉自愈事件(违反规则 12)

- ia_bus_timeout: 失配只报错,**不清 0 自愈**、不复贴副本(`3.ia_bus_timeout/rtl/ia_bus_timeo_mon.sv:488-592`)。
- apb2mbus: watchdog `h_dup` 失配与 ACK 同拍被 `!rdy` 压制,完整性告警整拍丢失(`6.apb2mbus/rtl/apb2mbus.sv:315,345-371`)。
- cmm: `freq_deb/psc_deb/never_deb/aw_run/aw_hold` **根本没有** Q/Q_n 副本(`5.cmm/rtl/cmm_core.sv:239-251,403-425`)。
- common_modules: `reg_wrap`/`reg_wrap_secded` 的 W1C 可把「应自愈到 SET」的双轨失配抹成清态(`common_modules/reg_wrap.sv:113-121`)。

---

## 2. 各设计独立发现

### 1.hang_prot(4)

1. 🔴 **复位释放不同步 → 丢写响应**(详见 §3.1,由规则 26 覆盖): shim 走裸 `rstn`、monitor 走 3 级 `rstn_s`,释放后 3 拍 shim 已收事务而 monitor 丢握手,`wr_otd` 恒 0 → 真实 B 被当幻影吞掉,主设备永久挂死无告警。`1.hang_prot/rtl/hang_prot_core.sv:199-208,647-653`
2. 🟠 **AWPROT 收了不转发不存**(详见 §3.2,**已修复**): 写保护属性丢失。`1.hang_prot/rtl/hang_prot_mcu2main_top.sv:97` 等。
3. 🟠 寄存器别名(见 S1)。
4. 🟠 非法 ENA 执行 action(见 S3)。

### 2.parity / edc(4)

1. 🟠 **DW=1 的 WLAST 码距只有 2**: `edc=data`、检查仅 `data!=edc`,`11→00` 双翻转静默通过 → WLAST 损坏早/晚终结突发。`2.parity/rtl/nuclei300_edc_gen.sv:66-67,161-164`
2. 🟠 `WR_DROPPED` 漏 esm_fault(见 S2)。
3. 🟠 编码使能无写回(见 S4)。
4. 🟠 scan_mode tie 死(见 S5)。

### 3.ia_bus_timeout(7)

1. 🔴 **计数器回绕成「活超时盲窗」**: 4 个 16bit 计数器 `FFFF→0` 不饱和,W1C 清后源仍活但重报要再等 ~65534 拍。`3.ia_bus_timeout/rtl/ia_bus_timeo_mon.sv:498-588`
2. 🟠 非法 ENA 执行 action(见 S3)。
3. 🟠 `WR_DROPPED` 漏 esm_fault(见 S2)。
4. 🟠 寄存器别名(见 S1)。
5. 🟠 Q/Q_n 无清 0 自愈(见 S6)。
6. 🟡 **互补轨各自过 CDC → 虚假 rail_fault**: `err_event/_n` 独立采样,聚合器把每拍单比特失配当永久故障,无两拍确认/瞬态滤波。`3.ia_bus_timeout/rtl/ia_bus_timeo_regfile.sv:723-727`(PLAUSIBLE)
7. 🟠 `rst_sync` ASIC 分支 `SYNC_LVL_NUM=3` 建不起来(见 S5)。

### 5.cmm(11)

1. 🔴 **饱和致过频盲点**: 边沿计数饱和在 4095,而 `WIN_HI=4095` 也被当合法上限 → 显著过快时钟每窗都「过」,`cmm_win_calc.py --sat 1.0` 会合法产出该配置。`5.cmm/rtl/cmm_core.sv:289-372`
2. 🔴 **非法 EN 写部分更新合法 nibble**: `en_illegal` 只报 REG_PROT 不拦 `wr_fwd`,写 `0x5` 到 ch0 时其余 7 通道被写 0 → 一次「被拒」的写关掉 7 路监测。`5.cmm/rtl/cmm_regfile.sv:309-383`
3. 🔴 **debounce 状态无 Q/Q_n**(见 S6)—— stuck 后静默停检。
4. 🟠 **busy-drop 仍有本地副作用**: `fustat_w1c/regst_st/parst_ev` 用 `wr_ok` 而非成功 `fwd_fire` 门控,dropped 写仍清本地位甚至抹掉自己的 WR_DROPPED。`5.cmm/rtl/cmm_regfile.sv:398-451`
5. 🟠 **计算器 NDEAD 截位 → 假 DEAD**: `NDEAD` 12bit,`cmm_win_calc.py` 对 `fdut=0.01MHz` 产出 10106,写入被截成 1914 → 健康时钟反复报 DEAD。`5.cmm/doc/cmm_win_calc.py:104-153`
6. 🟠 **`any_en` 含不存在通道**: `N_DUT<16` 时高 nibble 不可写且保持复位值 F → 全禁后 `GSTAT[9]` 恒 1、`REF_STALE` 仍武装、可误拉 `cfg_hang`。`5.cmm/rtl/cmm_regfile.sv:105,209-320`
7. 🟠 **NEVER_ARMED W1C 后重 assert**: `never_set=(never_deb==0)` 未以 `never_src` 门控;`N_DEB=0` 复位即报。`5.cmm/rtl/cmm_top.sv:216,508-520`
8. 🟠 编码使能无写回(见 S4)。
9. 🟠 **DBG0/DBG1 直入读 mux 无同步**: 异步多比特读面,读数撕裂+亚稳,污染诊断。`5.cmm/rtl/cmm_regfile.sv:885-945`
10. 🟡 `N_WIN` 截 16bit 无范围检查(`N_WIN=65537→WIN_LAST=0`)。`5.cmm/rtl/cmm_top.sv:231,449-456`(PLAUSIBLE)
11. 🟢 scan_mode 缺失(见 S5)。

### 6.apb2mbus(1)

1. 🟠 ACK 同拍压制 `h_dup` 完整性告警(见 S6)。

### 8.reset_checker — RTL 干净 ✅

仅 1 处文档 nit: `design.md §5.1` 说 CTRL/REGST 都用 `wdata[31:28]` 作 key,实际 CFG_REGST 用 `wdata[3:0]=4'b1010`。`8.reset_checker/doc/design.md:128-131`

### 9.int_prot(2)

1. 🟠 **迟到配对仍误报超时**: `diff_cnt` 在 `change_cnt` 归零那拍用旧非零值继续 `+1` 到 TIMEOUT-1 → 已配对完成却报 `spi_err`。`9.int_prot/rtl/int_prot_core.sv:201,243-250`
2. 🟠 **关使能不冻结在途超时**: `enable=0` 只挡新边沿,`diff_cnt` 继续数,关闭期间照报超时。`9.int_prot/rtl/int_prot_core.sv:193-211,234-250`

### 10.dup_ctrl(2)

1. 🟠 寄存器别名(见 S1)。
2. 🟡 **`ERR_SYNC_STAGE` 未作用于错误回程**: `err_st/err_raw` 恒用固定两级,与参数契约「统一作用于 req/ack/错误镜像/影子故障回程」不符。`10.dup_ctrl/rtl/dup_ctrl_regfile.sv:650-694`(PLAUSIBLE)

### 11.audio_sram(2)

1. 🟠 寄存器别名(见 S1)。
2. 🔴 **CFG_INJ 纠错写回只拼 28bit**: `{17'h0, inj_r[14:8], 4'hF}` 丢 key nibble、pos 左移错位 → 自愈本身把 image 写成 pos=0/key=1,与影子永久分叉且奇偶仍干净(已抽验确认)。`11.audio_sram/rtl/audio_sram_regfile.sv:848-851`

### 12.axi2sram_ctrl(6)

1. 🔴 **cmdq 毒化完成仍信被破坏的事务类型位 → AXI 死锁**: `cur_wr` 从损坏的 `nxt_wr` 载入,AR 翻转成 AW 后等永远不来的 W 拍,既不回 R 也不回 B。`12.axi2sram_ctrl/rtl/axi2sram_ctrl_core.sv:843-860`
2. 🔴 **rskip/bskip 毒化只强制 RESP=SLVERR,仍传损坏的 RLAST/RID/BID** → 提前 RLAST 断突发 / 缺末拍主设备干等。`12.axi2sram_ctrl/rtl/axi2sram_ctrl_core.sv:1055-1065`
3. 🟠 **合法 FIXED 突发按 INCR 执行**: `beat_addr()` 只特判 WRAP,其余全用 `a0+b*n`;两拍 FIXED 写第 N 行写 N、N+1 两行。`12.axi2sram_ctrl/rtl/axi2sram_ctrl_core.sv:182-201`
4. 🟠 **FSM「one-hot」检查用奇偶而非独热**: `st_bad=~(^r.st)` 漏 3/5 个 1 的非法态,多比特翻转后静默挂死不报 fault。`12.axi2sram_ctrl/rtl/axi2sram_ctrl_core.sv:558-565`
5. 🟠 **CFG_INJ1/2 读回丢 pos bit8**: 存储 `{13'h0,wdata[18:0]}` 丢 `wdata[19]`,写 pos=260 读回 pos=4。`12.axi2sram_ctrl/rtl/axi2sram_ctrl_regfile.sv:965-979`
6. 🟠 编码使能影子无写回(见 S4)。

### common_modules(5,基础单元,波及全仓)

1. 🔴 **`ASIC_SYNCELL` 分支不实现 `RST_VAL`**: 每 bit 同宏、只接 `.RN(rstn)`,混合复位值(如 `4'b1010` rail)在硬单元下无法实现 → 复位期 rail 非互补误触发。`common_modules/sync_2dff.sv:73-90`
2. 🔴 **缩短 SECDED 非法 syndrome 重算 ECC 掩盖损坏**: `W<32` 时指向不存在位号的 syndrome 被判可纠,随后用损坏数据重算 ECC、清 syndrome → 数据仍错但无检出。`common_modules/reg_wrap_secded.sv:138-199`
3. 🟠 **参数护栏被 `translate_off` 从综合移除**: 不支持的配置(如 `rst_sync ASIC+SYNC_LVL_NUM=3`、`reg_wrap_secded W>32`)综合时不报错。`common_modules/rst_sync.sv:76-89`
4. 🟠 W1C 可完全压制可纠 SECDED 的 `flt` 上报(纠错边沿同时清 flt,源被消掉不再重报)。`common_modules/reg_wrap_secded.sv:177-210`
5. 🟠 W1C 抹掉双轨失配自愈事件(见 S6)。

---

## 3. hang_prot 两处重点问题的深入分析

### 3.1 复位释放不同步 → 丢写响应

**代码事实**: `hang_prot_core`(监视器)用时序进程 `always_ff @(posedge clk or negedge rstn_s)`(`hang_prot_core.sv:647`),其中 `rstn_s` 来自 3 级 `rst_sync`(`:199-208`)。而 `hang_prot_recover`/`hang_prot_bdry_in`/`hang_prot_wskid` 均用裸 `rstn`(`recover.sv:659` / `bdry_in.sv:565` / `wskid.sv:467`)。顶层把同一个裸 `rstn` 直连 shim(`mcu2main_top.sv:332-333`)。两者在同一 aclk 上跑,却在不同边沿释放 → 约 3 拍「shim 已活、monitor 仍死」窗口。

**关键信号**: `wr_otd` 在监视器里,复位后为 0。B 转发/吸收完全由 `wr_otd_mon` 决定:

```systemverilog
// hang_prot_recover.sv
assign m_bvalid = r.mode_r ? bdum_en : (s_bvalid && (wr_otd_mon != '0));  // L750
assign s_bready = (r.mode_r || (wr_otd_mon == '0)) ? 1'b1 : m_bready;      // L787
```

**逐拍场景(复位释放后立刻单拍写)**:

| 拍 | 事件 |
|---|---|
| 0 | 裸 `rstn` 拉高,shim 立即释放;monitor 的 `rstn_s` 仍为 0 |
| 1 | `m_awvalid`+`m_awready` 握手完成,载荷进 skid;monitor 仍复位,`wr_otd` 保持 0 |
| 2 | `m_wvalid`+`wlast`,`m_wready`=1 → W 落 skid |
| 3 | skid 出 `s_aw`,下游回 `s_bvalid` |
| N | B 到达:`wr_otd_mon==0` → `m_bvalid=0`、`s_bready=1` → **B 被吸收为幻影** |
| N+∞ | 主设备永远等不到 B;monitor 从未见过这笔写 → 无超时、无 `esm_err`、无告警 |

**影响**: 静默死锁,无 ESM 事件 —— 恰好是 hang_prot 本应防止的场景。

**修复**: 见规则 26 —— 复位同步收编在 `hang_prot_core`,shim 改用 core 下发的同步复位(同一拍释放)。

### 3.2 AWPROT 收了不转发不存(已修复)

**代码事实**: 两个顶层声明 `input m_awprot`(`mcu2main_top.sv:97` / `main2mcu_top.sv:91`)但无任何 `s_awprot` 输出、无任何 assign,输入悬空。AR 路径有 `s_arprot=m_arprot` 组合直通(`mcu2main_top.sv:412`),但 AW 是 store-and-forward(skid 逐 slot 缓存),需逐 slot 存储 prot,而 `wskid` 的 `reg_t` 只锁 `awaddr/awlen/awsize/awburst` + 奇偶 `apar`,无 `awprot`。

**后果**: AXI4 `AWPROT[2:0]` = {指令/数据, 安全/非安全, 特权/非特权},下游从机(MPU/防火墙/SMMU)靠它做访问控制。prot 丢失 → 特权/安全事务被下游误判,功能失败或安全边界被击穿。

**修复(2026-11-24 已完成)**: 在 `hang_prot_wskid` 的 `reg_t` 增 `awprot_q[NSLOT-1:0][2:0]`,FILL 拍锁存、`apar` 偶校验折入 `(^m_awprot)`、READY 拍驱动 `s_awprot`;`recover`/`bdry_in`/两个顶层逐层新增端口并接通。数据流:

```
m_awprot(top) → recover/bdry_in → wskid 锁存 awprot_q[slot] → s_awprot → top s_awprot
```

---

## 4. 修复状态总表

| 项 | 状态 |
|---|---|
| hang_prot AWPROT 丢弃 | ✅ 已修复(2026-11-24) |
| 规则 26(复位同步收编 core) | ✅ 已写入 SKILL.md,待按落点应用到各设计 |
| S1 寄存器别名(4 仓) | ⬜ 待修 + 待扫 cmm/axi2sram/parity/reset_checker |
| S2 `WR_DROPPED` 漏 esm_fault | ⬜ 待修 |
| S3 非法 ENA 执行 action | ⬜ 待修 |
| S4 编码使能写回缺失 | ⬜ 待修 |
| S5 scan_mode tie 死 | ⬜ 待修 |
| S6 Q/Q_n 自愈不完整 | ⬜ 待修 |
| 各设计「静默失效」类 | ⬜ 待逐一 VM FI/边界激励复现确认 |
| PLAUSIBLE/NIT 类 | ⬜ 先核对规格意图再定 |

---

## 5. 建议下一步

1. **先修 S1 寄存器别名**(4 仓同款,一行 `addr[7:6]==0` 判定)—— 最易被软件 bug/攻击利用的「关监测」后门,修法统一,并扫其余 regfile。
2. **再修 S2/S3/S4/S5/S6**(规则 25/11/19/12 的成批违例)—— 「按规格对齐」而非新设计,工作量小、语义明确。
3. **规则 26 落地**: 从 hang_prot 起把 shim 复位对齐到 core 下发的 `rstn_s`(顺手修掉「丢写响应」),再推广到 parity/ia/cmm/audio_sram/axi2sram。
4. **各「静默失效」类**逐条在 VM 用 FI/边界激励复现确认(未映射地址、SEU 边角、复位释放时序、极值饱和),避免修复引入回归。

---

*本报告由静态评审生成,部分项为 PLAUSIBLE(标注者)需仿真/形式验证确认;门数/面积不在此报告范围。*
