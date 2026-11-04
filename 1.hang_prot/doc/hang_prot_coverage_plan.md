# hang_prot 代码覆盖率收敛清单（TB-A / TB-B）

目标：两个集成 top（`hang_prot_mcu2main_mon`（原 a_wrap）/
`hang_prot_main2mcu_mon`（原 b_wrap））在语句 (statement)、
分支 (branch)、条件 (condition)、FSM、翻转 (toggle) 各项上尽可能 100%。
执行方式：在有仿真器的机器上，于 `sim/` 目录运行
`vsim -c -do run_tb_a.do`、`vsim -c -do run_tb_b.do`（Questa），或启用
`run_all.sh` 里对应 VCS/Xcelium 块。合并两个 UCDB/VDB 后看总报告
（建议把 `tb_hang_prot_gen_wrap.sv` 一并纳入 merge，它补齐寄存器模型覆盖）。

## 1. 模块 × 指标 → 激励映射

| 模块 | 覆盖手段（TB/阶段） | 预期可达 |
|---|---|---|
| hang_prot_wskid | TB-A P3(双槽重叠)/P4(孤儿W)/P8(2b死在REPLAY→s_force)/P10(注错)；TB-B P2/P4(1a FILL卡死)/P5(1b)/P6(QSR中REPLAY)/P7(块内孤儿)/P8(注错) | 100% 语句/分支/FSM |
| hang_prot_recover | TB-A P5–P8（2a/2b 读写挂起→自动退出）、P10 | 100%（s_in_rst 三条路径：强制进入/s_force槽清除/延迟退出全部走到） |
| hang_prot_bdry_in | TB-B P3–P8（读1b/写1a/写1b/延迟退出/块内孤儿/注错） | 100% 语句/分支 |
| hang_prot_core（原 gen） | 两 TB 的 r2a/r2r 超时 + tb_hang_prot_gen_wrap（阈值编程/W1C/读回） | ≈100% |
| regfile / reg_wrap | 两 TB 的 mbus 配置、SCMCNTRL 键控（QSR_REL/TO_CLR）、SCMOTD 读回；gen TB 的 W1C | 见 §3 缺口 |

## 2. FSM / 关键分支点核对

- wskid 每槽 4 态（FREE/FILL/READY/REPLAY）：`cg_slot`（两 TB 均有）+
  cross 已对 (fill,replay) 组合采样；TB-A P3 的双槽重叠专门产生 slot0=REPLAY∧slot1=FILL。
- recover 的 mode_r 进/出：TB-A 每个挂起场景进一次、`wait_auto_exit` 出一次；
  `s_in_rst` 延迟退出仅 TB-A 的 esm_main_reset 序列（2b）走到。
- bdry_in 的 `quiesce_exit` 四个条件各需独立为假一次：
  - `s_rvalid=1`（island R 未完）→ TB-B P3 在 R 吸收完前写 QSR（P3/P6 时序天然覆盖）；
  - `s_bvalid=1` → TB-B P5；
  - `wsk_quiesce_ok=0`（REPLAY 在途）→ TB-B P6；(注错非法码) → TB-B P8；
  - `qrel_pend` 置位但其余未满足 → P8 第一段（50 拍不退出检查）。
- `bdum_en` 的三分支：bp==wm（TB-B P4，无 dummy B）、bp!=wm（P5）、wr_otd==0
  （P4 复位后新写完成前的窗口）。

## 3. 已知缺口与补法（不补则该项到不了 100%）

| 缺口 | 位置 | 补充激励（建议追加为 TB 的 P11，或waiver） |
|---|---|---|
| 寄存器奇偶错路径 | reg_wrap/regfile `reg_par_fault` | 注错：force `u_dut.u_hang_prot_regfile.<par_reg>` 的存储位翻转 1 拍，读回触发 parity 报警；tb_hang_prot_gen_wrap 若已有则直接merge |
| FU 自测路径 | regfile `selftest_key/fu_selftest` | mbus 写 SCMCNTRL selftest 键控字，确认 fu_fault 置位与 W1C 清除 |
| CDC toggle 握手反方向 | regfile 同步器 | 正常 mbus 读写已覆盖主向；反向（aclk 侧状态→mbus 读）由 SCMOTD/状态读回覆盖 |
| m_wready 溢出保护分支 | wskid `fill_cnt == WSKID_BEATS` | TB 中 WSKID_BEATS=8 而最长 burst len=7：把某次写 len 设为 >WSKID-1 且不回 WLAST 的保护分支仅在参数故意调小（如 WSKID_BEATS=2, len=3）的第三套编译里可达——建议waiver（协议非法配置）或加参数变体编译 |
| dummy R 的 `rdum_last` 长 burst 溢出 | bdry_in rbeat_cnt | TB-B P3 用 len=3；P6 用 len=7 已采到 b8 bin |
| AXI 低位字段（prot/cache 等未接字段） | wrap 端口 | toggle 常见残留：建议按项目惯例对纯 pass-through 始终为常量的位做 toggle waiver |

## 4. 收敛操作

1. 跑两个 TB，`coverage save` 出 cov_a.ucdb / cov_b.ucdb。
2. `vsim -c -viewcov` 或 `vcover merge cov_all.ucdb cov_a.ucdb cov_b.ucdb`
   合并（连同 gen_wrap TB 的库）。
3. 按百分比对未达项查 §1 表定位该加哪个阶段；
   无法合法到达的按 §3 做 waiver（尤其常量位 toggle）。
4. 断言覆盖：TB 内 SVA（a_r_hold/a_b_hold/a_qsr_withdraw/a_island_drain/
   a_block_stall 与 TB-A 对应组）应全部 fired ≥1 且无 FAIL。

## 5. 本机 iverilog 功能仿真结果（2026-10）

WSL Ubuntu + iverilog（`sim/run_iverilog.sh a|b|both`，VCD 可用 WaveTrace
扩展查看）。iverilog 不支持代码覆盖/SVA/covergroup（TB 中已用
`ifndef IVERILOG` 隔离），本流程只做功能自检，结果：

- **TB-A（mcu2main_mon：NIC 活在 m / main 死在 s）：PASS，P1..P13 全部干净**
  （P11 = FuSa v3.1 注错：mode_r 轨失配强制进入/自愈退出；FIFO 指针副本
  失配强制进入 + 活失配期间退出阻塞。P12 = v3.2 mcore 感知类 remap：
  正常模式下 mcore id（全匹配 MCORE_MASTER_IDS）与非 mcore id 共 4 笔
  交织，逐 burst 校验还原 rid/次序/拍数（记分板 rb_rid_q/rb_beats_q）；
  3 类同时在途 + slv 死亡 → dummy 引擎按类排空，真实+dummy 总拍数
  = len+1，各类还原各自事务的 rid。P13 = v3.2 `s_in_rst` 轨对失配
  注入：翻转单轨 → 强制进入受控态 + skid_fault；失配存活期间 idle
  账本也不重开通路（退出阻塞）；heal → 自动退出，skid_fault 保持粘滞）。
- **TB-B（main2mcu_mon：main 可死于 m / island 活在 s）：PASS，P1..P9 全部干净**
  （P9 = FuSa v3.1 注错：blk_r 轨失配、aw 指针副本失配 + QSR 退出阻塞）。
- P8/P10 的注错阶段会打印 `[hang_prot_wskid] slot state not one-hot` ——
  这是 DUT 自检**正确检出**注入的非法槽编码，非失败。

**流程坑（已修，务必吸取）——陈旧 .vvp 两次咬人**：
① `run_iverilog.sh` 曾引用已改名的 `regfile.sv`（实际为
`hang_prot_regfile.sv`），iverilog 编译失败被 `2>/dev/null` 吞掉，`vvp`
照跑**旧 a.vvp/b.vvp**；② v3.2 改造时一段脚本化批量编辑用
`Set-Content -Encoding UTF8` 写回 .sv——Windows PowerShell 5.1 的该开关
**写 BOM**，iverilog 解析失败（"Unable to find the root module"），而
`.vvp` 非空检查照样放行旧二进制，"PASS P1..P11" 又是陈旧结果。现脚本
已改为：**编译前 `rm -f` 旧 .vvp**（iverilog 失败不删除输出）+ 编译错误
不重定向 + `.vvp` 非空门（"compile FAILED"即中止该腿）。run_tb_a.do /
run_tb_b.do / run_all.sh 中同类错误引用一并修正。**任何一次源码改动后，
先确认 PASS 字串里的阶段号变了再信结果；永远不要用
`Set-Content -Encoding utf8` 写 .sv（用无 BOM 的
`[System.IO.File]::WriteAllText` 或编辑工具）。**

bring-up 过程中发现并修复的问题全部为 TB 侧（RTL 无功能缺陷），但三条
BFM/注错教训值得沉淀（TB-A/TB-B 均已按此加固）：

1. **（v3.3 mbus 化后更新）mbus 零等待，依赖写前必须轮询 CFG_BUSY**：
   regfile 的 mbus→aclk CDC toggle 握手期间 `SCMIAFUSTAT[4]` CFG_BUSY=1，
   期间到达的有效写被**丢弃**（`[5]` WR_DROPPED sticky）而非阻塞——TB 的
   `mb_wr_wait`（写后轮询 CFG_BUSY）替代了 APB 时代的 pready 阻塞等待；
   旧的"penable 后 #1 再采 pready"陷阱随 APB 一起移除。
2. **响应方 VALID 必须"在 posedge 确认握手后才撤销"**：在 negedge 采样
   ready 就推进，会在"同 delta 内 stimulus 拉低 m_rready/m_bready（main
   死亡）"的竞态下零宽度脉冲丢拍（rd_pend 永久卡 1）。r_resp/b_resp 均已
   改为 posedge 握手确认式。
3. **SCMOTD 读回有 CDC 时延**：TO_CLR 后立刻读会读到同步链上的旧值
   （regfile 头注释已声明"re-read resolves"）——check_otd_zero 已加
   settle 等待；真实 SW 亦应重读。
4. **（v3.1 注错新增）指针副本注错必须用全宽真补码** heal
   （`aw_bp_n = ~aw_bp`）：指针经回绕空闲值未必为 0，固定字面量
   （如 `1'b1` ≠ 3'b111）会留下残余失配，"heal 后退不出"实际是注错
   未愈。
5. **（v3.2 新增）TB 里用 `always @(*)` 派生的双轨信号必须带初始化器**
   （`logic s_in_rst_n = 1;`）：iverilog 在 time-0 不保证先跑变量
   初始化器再唤醒 @(*)，无初始化器时该信号为 X，X 经轨比较
   （`!=`）→ int_dis=X → mode_r=X，整个 DUT 从第一拍起 X 污染
   （表现：所有场景 WDT 超时、m_arready 恒非 1）。

### 设计侧观察（已加固）

- **QSR_REL 在非隔离态写入会残留 qrel_pend**（bdry_in 的 qrel_pend 原来只看
  脉冲不看 blk_r）：SW 违反契约（文档 §8.4）提前写 QSR，下一次隔离会在进入
  后约 1 拍自动退出（TB-B P6 调试中实测）。**已加固**：`qrel_pend` 置位加
  `blk_r` 门控（hang_prot_bdry_in.sv），隔离外的 QSR 脉冲被忽略；TB 复跑
  全 PASS，无需改 TB。
- 孤儿 W 在隔离中 STALL 不下沉、REPLAY 在两种模式都跑完、退出时
  force_clear + FIFO 清零 + sk_fault 粘滞：均按设计预期工作（TB-B
  P4/P6/P7/P8 验证）。
