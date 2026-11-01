# apb2mbus — APB3 slave → mbus master 桥 (MCP 直采 CDC + FuSa hang 保护)

X7A MCU System / TR4 / MCUSys / FuSa。APB3 从端到 mbus 主端的 CDC 桥，
源自 `2.parity` 仓 (此处为独立归档副本, 原始文件仍在 `2.parity/rtl`)。

- CDC 为 **MCP 直采结构**: 数据通路 (addr/wdata/wr/par/rdata) 直采静态
  保持电平, 不加同步 FF; 同步 FF 只留给两个单 bit 控制 toggle, 一律例化
  标准 `sync_2dff` + `sync_dff` 单元 (FPGA / ASIC 仿真 / ASIC 后端工艺
  cell 三分支, 便于后端替换 hardened sync cell)。
- **命令在途偶校验** `par_q = ^{addr, wr, wdata}`: req_fire 当拍与
  payload 同沿锁存 (APB 域) 后静态直采, 叶端重组比对查在途 1bit 损坏
  (门写 + PERR); 保持寄存器在途 SEU 亦可检出。
- **APB 域 hang 看门狗**: mbus 侧死亡/CDC 断链时 HANG_TO 拍后强制完成
  (pready + SLVERR, CPU 收 bus error 而不是总线挂死), hang_evt 双轨
  脉冲送 ESM; DRAIN 态消化迟到 ack, 链路自愈。
- 越界实例 (paddr[15:8] ≥ NP): 立即 pready + pslverr, 不发起 mbus 传输。

## 目录

| 路径 | 内容 |
|------|------|
| `rtl/` | `apb2mbus.sv` · `sync_2dff.sv` / `sync_dff.sv` (标准同步单元, 三分支) |
| `sim/` | `tb_apb2mbus.sv` (hang 看门狗专项, 28 checks) · `run_vcs.sh` (VCS+Verdi, 在 Rocky VM 跑) · `run_iverilog.sh` (WSL iverilog 兜底) |
| `doc/` | `apb2mbus_design.md` (设计说明: MCP CDC 结构 / hang 看门狗 / SDC 要求 / 参数 / 验证) |

## 仿真

```bash
# Rocky VM (VCS+Verdi, 正式流程)
cd sim && bash run_vcs.sh          # 编译 + 仿真, 产物 obj_vcs/
       bash run_vcs.sh verdi       # Verdi 打开波形
```

相关: 叶端寄存器文件见 `2.parity/rtl/edc_regfile.sv` (parity 比对/PERR14)
与 `5.cmm/rtl/cmm_regfile.sv` (PERR_CMD)。

2026/11/01
五个模块都过了一遍。只列我核对过代码、认为该改的问题。风格和注释不算。

1. hang_prot_wskid.sv:357-376, 441
高。WSKID_BEATS=16 时 fill_cnt 是 5 bit，缓冲只有 [0:15]。正常模式最后一拍 fill_cnt=15、wlast=0 时，m_wready 条件是 fill_cnt < 16，仍然为 1。这一拍会写 wbuf[15]，然后 fill_cnt 加到 16。再来一拍非 wlast，索引 16，越界。
改法: 缓冲深度改成 WSKID_BEATS+1，或者 m_wready 在 fill_cnt==WSKID_BEATS-1 且 !m_wlast 时拉低。awlen 也要在入口拦住，awlen+1 > WSKID_BEATS 直接不收。

2. hang_prot_core.sv:379 以及同文件 386/435/442，ia_bus_timeo_core.sv 同样写法
中。比较写成 cnt >= thr-1。thr=1 时第一拍 stall 就超时，实际允许的 stall 拍数比配置少 1。thr=0 有保护，不会下溢。
改法: (cnt + 1 >= thr) && (thr != 0)。双轨那路同样改。

3. hang_prot_core.sv:497-505, 542-550，ia_bus_timeo_core.sv 同样
中。rd_otd/wr_otd 到 OTD_MAX 后，同拍又有新请求又有完成，两个分支都不进，计数停在上限。之后只有新请求、没有完成时也不再加。真实 outstanding 被丢掉，挂死可能看不见。
改法: 饱和时同拍握手可以保持，但必须单独锁存 otd_sat，当 FuSa 事件报出去。不能把饱和当成正常深度。

4. cmm_top.sv:296-297, 389-396
高。fail_set 只在 FSM_RUN 采样，dead_set 在 FSM_ARM 也采样。使能通道在 ARM 窗口里 clk_dut 还没起来，dead_q 会被锁住。window_fire 进 RUN 后，下一拍 alarm_any 直接进 ERR。tst_clr 也是回到 ARM，清不掉这个路径。
改法: dead_set 与 fail_set 一样，只在 FSM_RUN 采样。ARM 窗口只丢弃起振期的 dead_lvl。

5. apb2mbus.sv:206, 269-274, 315-316
高。timeout 后 drain=1，迟到 ack 还没回来。这段时间 CPU 再发一笔，pready 靠 drain 快速失败，但 ce_reg 被赋成 acc=1。迟到 ack 清掉 drain 的同一拍，ce_reg 的 if (rdy) 分支把它清 0，这一拍没事。下一拍如果 CPU 还按着 psel/penable 重试，ce_reg 又被写成 1，req_fire 要 !ce_reg，发不出去。pready 此时也不再为 1，APB 挂死。
改法: ce_reg 的保持条件改成 v.ce_reg = acc && !rdy && !to_fire && !r_apb.drain; drain 期间和 timeout 当拍都不要把 ce_reg 记成“这笔已经发出”。

6. edc_site.sv:88-104
高。同一条 AW/AR/W 被拆成多个 edc_site，每个 site 自己有 1-deep skid。握手只接了第一个 site 的 o_ready/o_valid，其余 site 的 ready/valid 悬空。各 site 的 i_ready 是同一个下游 ready。复位后 vld_q 都是 0 时还能对齐；一旦某个 site 的 vld_q 因 SEU 或综合后不等价逻辑单独变成 1，这条通道的 payload 和 user EDC 会差一拍，CHK 侧会把好事务报成 EDC 错，或者把坏事务漏掉。
改法: 一条通道只用一个 skid，payload 和 EDC 在同一个 always_ff 里一起打拍。edc_site 不要各自持有 valid。

7. nuclei300_edc_gen.sv:13-16 对比 nuclei300_edc_chk 里的 t_dat
高。DW>64 时，生成端 t_dat = i_dat[63:0]，高位丢掉。检查端 t_dat = i_dat，位宽不够，高位被截断的方向和生成端不一致时，高位翻转既不进 EDC，也不进 syndrome。wdata 目前是 64，暂时碰不到；IDW 或地址一旦超过 64，保护是空的。
改法: DW>64 直接 elaboration $fatal。或者按 64bit 切片做多组 EDC，检查端用同样切片。

不建议按上次初稿改的:

cmm 的 ecnt_flt_w 清零不是 bug。注释写了要在 window_fire 清，freq_bad 用的是当拍的 r_ref.ecnt_flt_w，NBA 之后才清，窗口毒化采得到。
apb 读操作把 pwdata 算进 par，和叶端 ^{addr,wr,wdata} 是同一公式。读的时候 wdata 不参与译码，奇偶只保护在途总线，不是功能错。
🔄 Switched to fallback model: gemini-3.5-flash via gemini → x-ai/grok-4.7 via openrouter
ia_bus_timeout / hang_prot regfile 在 cdc_busy 时丢写并置 WR_DROPPED，这是协议选择，不是静默丢。缺的是 aclk 域没有 CFG_HANG，单边复位会把 req/ack 卡死。这条算集成约束，文件头已经写了同复位假设

