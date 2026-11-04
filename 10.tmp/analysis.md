# top_pmu_apb_reg 设计分析(完整版)

> **对象**:`top_pmu_apb_reg.v`(2826 行,完整),Horizon 自动生成(Sigiriya PMU 寄存器堆,Parity script v0p3,版本 0.05)
> **方法**:人工通读 + `check_widths.py` 机器核对(`python3 check_widths.py top_pmu_apb_reg.v`,VM 上运行)
> `reg.v` 是首次贴入的截断残件,已被本文件取代,仅留档。

---

## 1. 概览

PMU 子系统 APB 从机寄存器堆,44 个寄存器(0x324~0x1414),三重 FuSa 机制:

1. **寄存器级 parity**:存储层 32 组 × 36 bit(32 数据 + 4 校验,每 8 bit 一组偶校验),读出经 decoder 检错;
2. **密码门控**:FUSA_CTRL / MISSIONINTMASK0 / MISSIONINTSTATUSSET0 / MISSIONINTSTATUS0 四寄存器要求 `passwd==32'h95f2d303`;
3. **FI 与错误上报**:parity FI(按 4 字节组注错校验)+ parity_invert 全局翻转脉冲 + lockstep FI,7 类错误 status/mask/err 三件套。

模块依赖:**`parity_enc` / `parity_dec` 两个子模块源码不在本文件中**,bypass/error 语义以下按端口名推断(见 §6-R5)。

## 2. 整体数据流

```
                    ┌──────────── 写通道 ────────────┐
APB(psel/penable/   │ hwr_* = apb_wr && 命中          │
paddr/pwrite/       │   (+passwd 门控 × 4 个)         │
pwdata)             ▼                                 │
   │        reg_data_*[32][32] 属性阵列(res/wr/hw/   │
   │        w1s/w1c/w0s/w0c/wt/rc + hw_wdata)        │
   │                ▼                                 │
   │        逐位写方程 reg_enc_data_in[i][j] ──► parity_enc ──► reg_enc_data[i](32b)
   │        (generate i=0..31, j=0..31)   (FI时bypass)    reg_enc_parity[i](4b)
   │                                                    ▲ reg_parity_update[i] 门控
   │                                                    ▼
   │                                              parity_dec ──► reg_dec_data_out[i]
   │        输出引脚 = reg_dec_data_out[i][field]  (bypass=~dec_en)  parity_dec_error[i]
   └──────────── 读通道:prdata_in 组合 mux(按 paddr[12:2] case)
                 → prdata 在 apb_rd 拍寄存(ACCESS 相 valid)
```

- `apb_wr = psel & penable & pwrite`(ACCESS 相),`apb_rd = psel & ~penable & ~pwrite`(SETUP 相);
- `pready=1`、`pslverr=0` 恒定:零等待,非法地址读返回 0、写静默吞掉,**无 PSLVERR 反馈**;
- `paddr[1:0]` 不参与译码(非对齐别名)。

## 3. 写通道细节

### 3.1 逐位写方程(优先级从高到低)

```
res → 0              (保留位恒 0,写忽略)
hw  → hw_wdata       (HW strobe 位:reg_data_hw[i][j] 本身就是 *_wr 选通信号)
w1s → pwdata|cur; w1c → ~pwdata&cur; w0s → ~pwdata|cur; w0c → pwdata&cur
wt  → ~cur           (写触发翻转)
wr  → pwdata         (普通 SW 可写位)
rc  → 0              (读清位)
default → cur        (保持)
```

- **B 位(SW+HW 双写)仲裁 = HW 优先**:hw strobe 有效的拍,HW 数据覆盖 SW 写;无 strobe 时 SW 正常写。B 位共 12 个:CMN_CFG[9]/[6](cmn_pchn_timeout_clr / cmn_int_req_mode_st_clr)、RCORE1~5_CFG[5](int_req_mode_st_clr)、DBG_RECOV_CFG[28:24](cfgl1cacheinvdis_clr)+[20:16](debug_recov_state_clr)。
- w1s/w1c/w0s/w0c/wt/rc 六类属性在本设计**全部未用**(全 0),纯生成器能力预留。

### 3.2 存储更新与 parity

- `reg_enc_data[i]`/`reg_enc_parity[i]` 复位装入 `reg_default_value[i][35:0]`(默认值及其校验由 32 个 `parity_enc` 实例在细化期算出);
- 更新使能:
  ```
  reg_parity_update[i] = ~fault_injection_en & (|w1s|w1c|w0s|w0c|wt|rc|wr|hw 任一)
                       |  fault_injection_en & (|reg_data_wr[i])      ← 仅剩 SW 写
                       |  parity_invert                              ← 全局翻转
  ```
- 正常写:parity ← `parity_enc_parity_out`(新数据的校验);
- **parity FI**:`parity_enc_bypass = fault_injection_en & |reg_data_wr[i]`,SW 写时编码器被旁路,存入的校验 = `parity_fault_injection[3:0]` 注入值 → 数据与校验失配,decoder 报错;
- **parity_invert 脉冲**(FUSA_CTRL[12] 写 1):
  - T0 拍写 FUSA_CTRL[12]=1 → `parity_invert`←1;
  - T1、T2 拍:`reg_parity_update` 全 1,**全部 32 组校验连续取反两次**(净效果:恢复原值),期间 `reg_parity_error = error_and`(32 组全错才算错,作 sanity);
  - T2 拍 `parity_invert_d`=1 → T2 末 `parity_invert` 自动清 0。即**自恢复的 3 拍全局注错脉冲**;
  - `parity_err_status` 在窗口内锁 1(仅 SW 可 W1C),`mission_int` 随之置位;
  - ⚠ 窗口内 SW 写寄存器:存入校验 = `~旧校验`(不是新数据校验),T2 再翻回后 = 旧校验,但数据已是新数据 → **持久性失配**(见 §6-R4)。

## 4. 读通道细节

- `prdata_in` 为纯组合 case(paddr[12:2]),**回读走 decoder 输出→输出引脚→mux 的往返**(保证读到的是受保护存储的现值);
- 纯 RO 状态寄存器(10 个)不占存储槽,组合直连输入:CHIP_TOP_1(qchannel/上下电状态)、CHIP_TOP_3/4(noc_lp_idle/idleack 两组)、CMN_LOW_POWER_HINT、RCORE_LOW_POWER_HINT(5×5bit)、DBG_RECOV_STATE、PMU_FSM_STATE(pmu_fsm_state[24:0]);
- 混合位:PWR_QCH_CTRL[2:0]、PCHANNEL_ERR[4:0]、RCORE_PCHANNEL_CONTROL_SW 的 pdeny/paccept 位同样是**活线直读**(非保留、无写源、不经存储);
- `prdata` 在 apb_rd 拍寄存 → ACCESS 相 valid,标准 APB 时序;
- PASSWORD 读恒返回 `32'h0badbeef`(复位哨兵),**真实 passwd 不可读**。

## 5. 寄存器地图(机器提取 + 人工标注)

deft 列 = 复位默认值;B = SW+HW 双写;→ 后为关键位含义。

| reg | 地址 | 名称 | 访问/位属性 | deft | 关键位 |
|---|---|---|---|---|---|
| 0 | 0x324 | CHIP_TOP_0 | RW 18 位散布 | 0x000108A0 | [27]xtl26m_en [25]pwr_qreqn [16]noc_lpc_eb=1 [11]dslp_ena=1 [7]bisr_n_soft_force=1 [5]mcu_iso=1 [0]soft_rst |
| — | 0x328 | CHIP_TOP_1 | RO 活线 | — | qactive/qdeny/qacceptn、上下电、bisr、noc 状态 |
| — | 0x32c | CHIP_TOP_3 | RO 活线 | — | noc_lp_idle[31:16]/idleack[15:0] |
| — | 0x330 | CHIP_TOP_4 | RO 活线 | — | noc_lp_idle_1/idleack_1 |
| 1 | 0x334 | CHIP_TOP_5 | RW 全 32 位 | 0x0 | noc_idlereq_backup_reg |
| 2 | 0x3d8 | CMN_CFG_REG | RW + B[9]/B[6] | 0x20 | [19]mode_st_restart [15:11]PSTATE [10]PREQ [9]pchn_timeout_clr(B) [6]int_req_mode_st_clr(B) [5]int_req_mode_st_en=1 |
| — | 0x3dc | CMN_LOW_POWER_HINT | RO 活线 | — | pdeny/paccept/pactive/config_flag/… |
| 3 | 0x3e0 | PCHANNEL_DLY_0 | RW[23:0] | 0x000F0F0F | 3×8bit 延迟 |
| 4 | 0x3e8 | CMN_PCHANNEL_DLY | RW | 0x0000FFFF | 32bit 无响应超时 |
| 5 | 0x1000 | PWR_QCH_CTRL | [3]RW + [2:0]RO 活线 | 0x8 | [3]aon_bridge_qreqn=1;[2:0] 活线状态 |
| 6 | 0x12f0 | COMMON_DLY_0 | RW[31:16] | 0x000F0000 | rst_bisr_assert_dly |
| 7 | 0x12f4 | COMMON_DLY_1 | RW | 0x001F001F | rst_deassert/assert_dly |
| 8 | 0x12f8 | COMMON_DLY_2 | RW | 0x002F0018 | cgm/iso_dly |
| 9 | 0x12fc | COMMON_DLY_3 | RW | 0x61A8001F | bisr_time_out=25000 / pwr_off_time_out |
| 10 | 0x1304 | COMMON_DLY_5 | RW | 0x04000400 | noc_lp_num / pwr_dly |
| 11 | 0x135c | BISR_BUFFER_ENABLE | [0]RW | 0x0 | bisr_buffer_en |
| 12 | 0x1360 | CLUSTER_CFG_REG | [2:0]RW | 0x7 | cluster2/1/0_soft_rst(复位=全在复位) |
| 13~17 | 0x1370~1380 | RCORE1~5_CFG_REG | 同构 + B[5] | 0x40 | [8]wdg_rst_trig_recov [7]wakeup_en [6]int_req_mode_st_en=1 [5]clr(B) [4]type_sel [3]soft_rst [2]dbgrstreq [1]warmrstreq [0]wakeup_req |
| — | 0x1384 | RCORE_LOW_POWER_HINT | RO 活线 | — | 5 核 × 5 状态位 |
| 18 | 0x1388 | PCHANNEL_ERR | [12:8]RW + [4:0]RO 活线 | 0x0 | err_clr(RW)/err_flag(活线) |
| 19 | 0x13b4 | DBG_RECOV_CFG | B[28:24]+B[20:16]+RW[12:8]+RW[4:0] | 0x0 | cfgl1cacheinvdis_clr(B)、recov_state_clr(B)、force_trig、auto_trig_en |
| 20 | 0x13b8 | DBG_RECOV_CFG2 | [4:0]RW | 0x0 | dbgrstreq_trig_recov_en |
| — | 0x13bc | DBG_RECOV_STATE | RO 活线 | — | wakeup_from_debug_recov[4:0] |
| 21 | 0x13c0 | RCORE_PCHANNEL_CONTROL_SW | 5×(pstate/preq RW + pdeny/paccept RO) + [0]RW | 0x00842108 | pstate_sw 复位全 1(AON 态?) |
| 22 | 0x13c4 | RCORE_DLY_CFG_0 | RW | 0x6D60000F | no_resp_timeout=0x6d60 / pre_action |
| 23 | 0x13c8 | RCORE_DLY_CFG_1 | RW | 0x000F001F | post_action / rst_assert |
| 24 | 0x13cc | RCORE_DLY_CFG_2 | RW[15:0] | 0x2F | rst_deassert |
| 25 | 0x13d0 | RCORE_DLY_CFG_3 | RW | 0x001F001F | recov_action / deny_threshold |
| 26 | 0x13d4 | RCORE_DLY_CFG_4 | RW | 0x001F001F | initial / debug_recov_dly |
| — | 0x13ec | PMU_FSM_STATE | RO 活线 | — | pmu_fsm_state[24:0] |
| 27 | 0x13f0 | PMU_FSM_SEL | [3:0]RW | 0x0 | FSM 选择(DFT 用) |
| 28~31 | 0x13f4~1400 | RESERVE_REG_0~3 | RW | 0x0 | IPC 保留 |
| — | 0x1404 | PASSWORD | W(读回 0BADBEEF) | 0BADBEEF | 解锁钥匙 |
| — | 0x1408 | FUSA_CTRL | RW+passwd | 0x0 | [0]dec_en [1]FI_en [3:2]lockstep_FI [11:8]parity_FI [12]invert |
| — | 0x140c | MISSIONINTMASK0 | RW+passwd | 0x7F(全屏蔽) | [6:0] 7 源 mask |
| — | 0x1410 | MISSIONINTSTATUSSET0 | W+passwd(读 0) | — | SW 强置 status |
| — | 0x1414 | MISSIONINTSTATUS0 | W1C+passwd | 0x0 | [6:0] status |

错误三件套时序(status 优先级 hw_wr > SW set > SW W1C;err = ~mask&status 打一拍):

| bit | 源 | mask 复位 |
|---|---|---|
| 6 | pd_top_noc_idlereq_time_out | 1 |
| 5 | pd_top_bisr_done_time_out | 1 |
| 4 | pd_top_bisr_busy_time_out | 1 |
| 3 | pd_top_pwr_off_time_out | 1 |
| 2 | top_pmu_signal_chk | 1 |
| 1 | lockstep_err | 1 |
| 0 | parity_err(含 SW 注入) | 1 |

## 6. 发现与风险清单

机器核对(✅ 全绿):32 组拼接位宽全 32;保留位无 SW/HW 写源;保留位默认值全 0。

**R1(意图确认)mission_int 只汇聚 parity_err 一路**。`mission_int <= ~parity_err_mask & parity_err_status`,其余 6 类错误只走各自 `*_err` 引脚,不进 mission_int;而 MASK0/STATUS0 却是 7 位全集。若 mission_int 预期是任务模式总中断,这是遗漏;若设计上各 err 独立上报、mission_int 仅表存储保护,则命名易误导。**建议与设计规格核对**。

**R2(FuSa 失效安全方向)复位后 parity 检错默认关闭**。`parity_decoder_bypass = ~parity_decoder_enable`,FUSA_CTRL[0] 复位 0 → decoder 旁路,且开启需要 passwd 解锁。复位到解锁之间的窗口内存储位翻转不可见(fail-silent)。安全侧默认应为"默认检错、可关"或至少上电即开。**建议确认是否由软件启动流程保证**。

**R3(FI 副作用)fault_injection_en=1 期间 HW 写被丢弃**。`reg_parity_update` 在 FI 模式只保留 `|reg_data_wr[i]`,12 个 B 位的 hw strobe(rcoreN_int_req_mode_st_clr_wr、cfgl1cacheinvdis_clr_wr、debug_recov_state_clr_wr)不再触发存储更新——FI 开着时这些硬件清除动作被静默丢弃。若非有意(FI 期间冻结 HW 路径),是功能缺陷;即使有意,SW 也要知道"开 FI 前先等 HW clr 完成"。

**R4(窗口竞争)parity_invert 脉冲内写寄存器 → 持久性失配**。invert 期间存入的校验是 `~旧校验`,两拍翻转后校验回到旧值而数据是新值;除非新数据与旧数据校验恰好相同,否则留下永久错误,parity_err_status 锁死直到 SW 清。作为"注入后自恢复"的设计,这个角落没被防护(可加"invert 窗口屏蔽 hwr_*"或"窗口内 parity 写入用 ~新校验")。

**R5(依赖)parity_enc/parity_dec 源码缺位**。bypass 时 parity_out=parity_in(直通注入)、dec_error 粒度为每寄存器 1 bit(wire parity_dec_error[31:0] 按寄存器索引)均为端口推断;`reg_dec_data_out` 在检错时是否仍直通数据(parity 只检不纠)需看实现。**拿到这两个模块后应补一份对应分析**。

**R6(机制提示)passwd 一次性写、长期有效**。无 auto-lock:写对一次后四个保护寄存器持续可写直到复位;读不回真值(安全 OK)。门控为组合逻辑,写 FUSA_CTRL 当拍 passwd 必须已生效(需两条独立 APB 写)。

**R7(协议行为)非法访问无反馈**。pready 恒 1、pslverr 恒 0、未映射地址读 0 写吞;paddr[1:0] 不译码。APB 协议合法,但总线上层无法察觉配置写丢——测试点而非缺陷。

**R8(覆盖率视角,结合本项目经验)**:保留位(res=1)与 RO 活线位在存储层恒 0,toggle 只能靠复位打 0→0 之外的翻转不可达;`reg_data_wt/rc` 等全 0 属性网络的常量位同理。若后续做 toggle 覆盖率,需按 urg 排除流程处理(tgl_struct_excl.el 模式可复用)。

**R9(小观察)**:CHIP_TOP 命名跳号(_0/_1/_3/_4/_5,无 _2),序号≠地址序;MISSIONINTSTATUSSET0 读回全 0;`hwr_MIssionIntStatus0` 清除支路 `if(pwdata[k]) status<=~pwdata[k]` 写法冗余(恒 0),生成器风格问题无功能影响。

## 7. 验证建议(按优先级)

1. **passwd 通路**:错误密码写 4 保护寄存器无效;正确密码后生效;同拍"写密码+写配置"无效(组合门控);读 PASSWORD 恒 0BADBEEF。
2. **parity FI 全场景**:dec_en=1 + FI_en=1 + 16 种 parity_fault_injection 图样(含全 0=无错)× 写任一寄存器 → parity_dec_error/parity_err_status/mission_int;FI 期间写只影响被写寄存器(bypass 条件含 `|reg_data_wr[i]`)。
3. **parity_invert 脉冲**:status 锁存与自恢复;invert 窗口内叠加写寄存器(R4 场景)固化对比;invert 与 FUSA_CTRL 再写的竞争(T2 拍写优先)。
4. **B 位仲裁**:hw strobe 与 SW 写同拍 → HW 胜;FI 模式下 hw strobe 丢弃(R3);DBG_RECOV_CFG 两组 10 个 B 位逐一覆盖。
5. **错误三件套**:hw set > SW set > W1C 优先级;mask 复位全 1 → err=0;unmask 后 err 打一拍跟上;SW set 强置。
6. **默认值回归**:上电读回 32 组 deft(含 parity 一致 → 无误报); COMMON_DLY_3=0x61A8001F 等。
7. **只读活线寄存器**:输入抖动即时反映、不受写影响;PWR_QCH/PCHANNEL_ERR 混合位读回。
8. **APB 边界**:非对齐地址、未映射地址、back-to-back 读写、prdata 保持到下一次 apb_rd。

## 8. 附录:机器提取位属性表

见 `check_widths.py` 输出(每寄存器 R/W/H/B 位段 + deft + HW 源),本文 §5 已整合。R=保留 W=SW 写 H=仅 HW 写 B=双写 .=RO 活线/无源。
