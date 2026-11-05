`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - mbus leaf register file + CDC
// (ref: TI Hercules RM57Lx TRM SPNU562A ch.3 SCM register model:
//  SCMCNTRL / SCMTHRESHOLD / SCMIASTAT / SCMIAERR0STAT / SCMIAERR1STAT)
//
// mbus LEAF (zero-wait, mbus_clk domain; protocol per apb2mbus):
//   ce single-cycle pulse, wr, addr[15:8]=instance (== IDX) / [7:0]=byte
//   offset, wdata, par = ^{addr,wr,wdata} command in-flight parity (checked
//   at EVERY ce regardless of instance decode - a corrupted address cannot
//   be trusted to select, so all leaves flag a broadcast-path corruption;
//   cf. edc_regfile/cmm_regfile). Bad-parity command: writes blocked, read
//   returns 0, PERR_CMD latched (SCMREGPARSTAT[14]). rdata combinational,
//   0 when not selected / bad parity (distributed OR-bus at integration).
//   There is NO wait / error channel on mbus: unaligned, out-of-range and
//   RO-target writes are dropped silently (SW bug; the old APB pslverr
//   cases), and a config write arriving while the CDC handshake is busy is
//   DROPPED with sticky SCMIAFUSTAT[5] WR_DROPPED - SW contract: poll
//   SCMIAFUSTAT[4] CFG_BUSY (or space writes by the handshake round trip)
//   before dependent config writes.
//
// REGISTER MAP (32-bit words, word-aligned mbus accesses only):
//   OFF   NAME          ACC   RESET       DESCRIPTION
//   0x00  SCMIAERR0STAT W1C/R 0x00000000  [NUM_IA-1:0] req2accept timeout
//                                            status (sticky, W1C)
//   0x04  SCMIAERR1STAT W1C/R 0x00000000  [NUM_IA-1:0] req2resp timeout
//                                            status (sticky, W1C)
//   0x08  SCMIASTAT     R     -           [NUM_IA-1:0] IA activity
//                                            (pending transactions)
//   0x0C  SCMOTD        R     -           [NUM_IA*OTD_W-1:0] per-IA
//                                            outstanding depth
//   0x10  SCMCNTRL      W/R   0x0000000F  [7:4]  KEY - must be 4'b1010
//                                            [3:0]  ENA - coded enable
//                                                   0xF on / 0x0 off
//                                                   (invalid codes are
//                                                   rejected by monitor)
//                                            [8]    TO_CLR      (pulse)
//                                            [9]    SELFTEST    (pulse)
//                                            [10]   FU_SELFTEST (pulse)
//                                            [11]   PAR_SELFTEST (pulse)
//                                            [12]   QSR_REL (pulse):
//                                                   quiesce release of the
//                                                   INBOUND boundary unit
//                                                   (hang_prot_bdry_in):
//                                                   SW exits the quarantine
//                                                   with main held in reset,
//                                                   then TO_CLR + W1C finish
//                                                   the service sequence
//                                            [20]   REG_SELFTEST (pulse):
//                                                   per-register parity
//                                                   injection, register
//                                                   selected by [19:16]
//                                                   REGSEL (0..8 =
//                                                   0x4*k); readback 0
//                                            action bits are write-pulse
//                                            only, read back 0; reads show
//                                            [3:0] = ena_rd code
//   0x14  SCMTHRESH0    W/R   0x0000_000F [15:0] REQ2ACCEPT_MAX
//   0x18  SCMTHRESH1    W/R   0x0000_00FF [15:0] REQ2RESP_MAX
//   0x1C  SCMIAFUSTAT   W1C/R 0x00000000  [0] FU_FAULT (W1C)
//                                            [1] FU_FAULT_N, [2] ERR_EVENT,
//                                            [3] ERR_EVENT_N (RO dual rails)
//                                            [4] CFG_BUSY (RO): config CDC
//                                                handshake in flight; poll
//                                                before dependent config
//                                                writes (mbus leaf has no
//                                                wait states)
//                                            [5] WR_DROPPED (W1C, sticky):
//                                                a write arrived while busy
//                                                and was dropped
//   0x20  SCMIAFUSRC    W1C/R 0x00000000  [4+3*NUM_M-1:0] fault sources
//                                            (nonzero write clears
//                                            FU_FAULT + FUSRC; a live
//                                            source re-sets next cycle)
//                                            [3+3*NUM_M] OTDSAT: outstanding
//                                            ledger saturated (depth hit
//                                            OTD_MAX mid-handshake) ->
//                                            depth under-counts; do a
//                                            quiesce + TO_CLR restart
//   0x24  SCMREGPARSTAT W1C/R 0x00000000  register parity status:
//                                            [0]    PAR_FAULT (level) ->
//                                                   ESM dual rail
//                                                   reg_par_fault/_n =
//                                                   OR of all PERR bits
//                                                   + self-test latch;
//                                                   writing [0] clears
//                                                   ONLY the latch
//                                            [1]    PAR_FAULT_N (RO)
//                                            [13:4] PERR9..PERR0 (W1C)
//                                                   per-register parity
//                                                   error, bit k =
//                                                   register at 0x4*k
//                                                   (4..6 = mbus image |
//                                                   aclk shadow); each
//                                                   bit clears its
//                                                   register's own
//                                                   reg_wrap sticky in
//                                                   BOTH domains;
//                                                   PERR9 = in-flight
//                                                   write-latch parity
//                                                   (any register)
//                                            [14]   PERR_CMD (W1C): command
//                                                   in-flight parity error
//                                                   at a ce (par !=
//                                                   ^{addr,wr,wdata})
//
// REGISTER PARITY (FuSa): every register lives in ITS OWN clock domain
//  as an independent reg_wrap instance (see reg_wrap.sv) = storage +
//  even parity + selftest_key injection + own fault sticky {flt,
//  flt_w1c} - the check lives with the storage it protects, no external
//  fault-source plumbing:
//     a. mbus_clk image wrappers (u_r_iaerr0..u_r_fusrc): the s2 stage of every
//        SW-readable register (exactly what SW reads), wr=1 follow
//     b. aclk config wrappers (u_c_ena/u_c_thresh0/u_c_thresh1): SCMCNTRL.ENA /
//        SCMTHRESH0 / SCMTHRESH1 shadows written through the CDC
//        handshake (req_edge decode); cfg_ena / cfg_req2accept_max /
//        cfg_req2resp_max are their rdata outputs; their flt is
//        2FF-synced into mbus_clk for aggregation and PERR readback
//     c. in-flight write latch {wsel, wdata}: parity latched at
//        wr_fire, checked through the CDC stability window -> latch
//        bit PERR9 (transient window, sticky needed)
//     d. command in-flight parity (par pin): checked combinationally at
//        every ce -> latch bit PERR_CMD (sticky, W1C bit [14])
//  PAR_FAULT = OR of all per-register stickies + latches: level while
//  any source is set. Each source is cleared at its OWN PERR bit; the
//  W1C write reaches BOTH domains (mbus: same-cycle wdata decode;
//  aclk: req_edge decode of the same write) so nothing de-synchronizes.
//  Injection (selftest_key) is decoded per domain: mbus images on
//  wr_fire, aclk shadows on req_edge - REG_SELFTEST/REGSEL (SCMCNTRL
//  [20]/[19:16], keyed) selects the register; for regsel 4..6 BOTH the
//  image and the shadow are injected (image self-restores next cycle
//  since wr=1; shadow holds until the register is rewritten - the
//  restore step of the test sequence).
//  SCMCNTRL[11] PAR_SELFTEST (keyed pulse) sets the latch with NO PERR
//  source - "fault, no source" identifies the self-test pattern in the
//  ESM service routine.
//  Fail-visible notes: 2FF-sync metastability can rarely raise a
//  spurious PERR (safe direction, SW W1C); residual common-mode
//  (datum+parity flipped together) is bounded by periodic
//  PAR_SELFTEST / REG_SELFTEST + SW readback.
//
// CLOCK DOMAINS / CDC:
//   mbus_clk : mbus leaf, all SW-visible registers
//   aclk     : monitor domain (= ia_bus_aclk of the top level)
//   mbus->aclk: one-at-a-time toggle handshake. The write is latched
//              (addr+data) and held stable while in flight; the aclk side
//              decodes it, applies updates/pulses, and toggles ack. The
//              mbus leaf cannot stall (zero-wait, no back-pressure), so a
//              write arriving while the handshake is busy is DROPPED
//              (sticky WR_DROPPED, SCMIAFUSTAT[5]); multi-bit data crosses
//              by STABILITY, not Gray coding.
//   aclk->mbus: 2-flop synchronizers. Sticky status bits (IAERR0/1,
//              FUSTAT, FUSRC) are per-bit independent -> always coherent.
//              SCMOTD / SCMIASTAT / thresholds / ena_rd are dynamic
//              multi-bit values: a read racing a change may sample
//              incoherently (observability only - re-read resolves; TI
//              periodic SW readback is not single-shot, so this is safe).
//   All synchronizer chains instantiate the standard sync cell wraps
//   (fusa 单一源 common_modules/sync_2dff.sv / sync_dff.sv - FuSa-wide CDC rule);
//   the aclk domain reset is active-high, adapted at the cell rstn port.
//
// RESET:
//   mbus_rstn (mbus_clk domain, async assert) and rst (aclk domain, async
//   assert) MUST be asserted together at system level so the CDC toggle
//   handshake starts aligned. An mbus-only reset while aclk runs would
//   de-synchronize the handshake - system-level constraint, documented
//   here (cf. TI: safety peripherals are reset as one block).
//
// SW USAGE NOTES (TI semantics preserved):
//   - restart counters : write SCMCNTRL = 0x1A0 (KEY=0xA, ENA=0xF
//     keep-on, TO_CLR=1) - keep ENA=0xF in action writes so the enable
//     code is not changed by the action.
//   - W1C always has CPU priority over concurrent error set (TRM 3.2.2)
//   - thresholds take effect via the monitor's keyed cfg port; the
//     regfile presents the 0xA key by construction, privilege is enforced
//     at the SoC bus/MPU level (config space must be privileged-only).
//   - mbus leaf zero-wait contract: before a dependent config write, poll
//     SCMIAFUSTAT[4] CFG_BUSY (or space writes by one handshake round
//     trip, ~3 aclk + ~2 mbus cycles); a dropped write sets
//     SCMIAFUSTAT[5] WR_DROPPED (W1C).
//============================================================================
module hang_prot_regfile #(
    parameter int          NUM_M          = 4,
    parameter int          NUM_IA         = 2*NUM_M,
    parameter int          OTD_MAX        = 8,
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F,
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF,
    parameter int          IDX            = 0
)(
    // ---- mbus leaf (mbus_clk domain) ---------------------------------------
    input  logic                     mbus_clk,
    input  logic                     mbus_rstn,      // async, active-low
    input  logic                     ce,             // single-cycle chip enable
    input  logic                     wr,             // 1=write, 0=read
    input  logic [15:0]              addr,           // [15:8]=instance, [7:0]=byte offset
    input  logic [31:0]              wdata,
    input  logic                     par,            // ^({addr, wr, wdata})
    output logic [31:0]              rdata,          // combinational, zero-wait

    // ---- monitor domain (aclk) ---------------------------------------------
    input  logic                     aclk,
    input  logic                     rst,            // async, active-high

    // ---- to monitor (aclk domain) ------------------------------------------
    output logic                     cfg_wr,         // 1-aclk-cycle load pulse
    output logic [3:0]               cfg_key,        // constant 4'b1010
    output logic [3:0]               cfg_ena,        // shadowed enable code
    output logic [15:0]              cfg_req2accept_max,
    output logic [15:0]              cfg_req2resp_max,
    output logic                     to_clear,       // 1-aclk-cycle pulses
    output logic                     selftest_key,
    output logic                     fu_selftest,
    output logic [NUM_IA-1:0]        r2a_w1c,
    output logic [NUM_IA-1:0]        r2r_w1c,
    output logic                     fu_w1c,
    output logic                     qsr_rel,        // keyed SCMCNTRL[12] pulse
                                                      // -> inbound boundary unit
                                                      // (hang_prot_bdry_in);
                                                      // leave unconnected when
                                                      // no inbound unit present

    // ---- from monitor (aclk domain) ----------------------------------------
    input  logic [NUM_IA-1:0]        r2a_err_status,
    input  logic [NUM_IA-1:0]        r2r_err_status,
    input  logic [NUM_IA-1:0]        ia_active,
    input  logic [NUM_IA*OTD_W-1:0]  otd,
    input  logic [15:0]              thr_rd_r2a,     // effective readback
    input  logic [15:0]              thr_rd_r2r,
    input  logic [3:0]               ena_rd,
    input  logic                     err_event,
    input  logic                     err_event_n,
    input  logic                     fu_fault,
    input  logic                     fu_fault_n,
    input  logic [4+3*NUM_M-1:0]     fu_src,

    // ---- register parity fault to ESM (mbus_clk domain, dual rail) ----
    // own event, separate from err_event / fu_fault: a corrupted
    // SW-visible register is a distinct failure mode
    output logic                     reg_par_fault,
    output logic                     reg_par_fault_n
);

    localparam int OTD_BW   = NUM_IA*OTD_W;
    localparam int FU_SRC_W = 4 + 3*NUM_M;

    // elaboration checks: everything must fit into 32-bit RDATA
    generate
        if (IDX > 255) begin : chk_idx
            $error("IDX must fit into addr[15:8]");
        end
        if (NUM_IA > 32) begin : chk_ia
            $error("NUM_IA must be <= 32 (SCMIAERR/SCMIASTAT width)");
        end
        if (OTD_BW > 32) begin : chk_otd
            $error("NUM_IA*OTD_W must be <= 32 (SCMOTD width)");
        end
        if (FU_SRC_W > 32) begin : chk_fusrc
            $error("4+3*NUM_M must be <= 32 (SCMIAFUSRC width)");
        end
    endgenerate

    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process, 双时钟域):
    //   r_mb (mbus_clk 域): CDC 写锁存 + WR_DROPPED 粘滞 + SCMREGPARSTAT
    //                       3-bit 锁存 (dual rail)
    //   r_a  (aclk 域)    : CDC ack toggle + 动作脉冲寄存器 + cfg_wr 延迟
    //   每域一个 comb (v = r; ...; rin = v) + 一个 seq (复位装载 / r <= rin)
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic        req_t;         // CDC 请求 toggle
        logic [3:0]  wsel_q;        // 在飞写: 寄存器选择
        logic [31:0] wdata_q;       // 在飞写: 数据
        logic        wpar_q;        // {wsel_q,wdata_q} 偶校验 (在飞检查)
        logic        wr_dropped_q;  // SCMIAFUSTAT[5] 粘滞
        logic [2:0]  par_lq;        // {PERR_CMD, PERR9, PAR_SELFTEST} 锁存
        logic [2:0]  par_lq_n;      // inverted duplicate rail
    } reg_mb_t;

    localparam reg_mb_t REG_MB_RST = '{
        default  : '0,
        par_lq_n : 3'b111
    };

    reg_mb_t r_mb;
    reg_mb_t rin_mb;

    typedef struct packed {
        logic              ack_t;          // CDC 应答 toggle
        logic              to_clear_q;     // 1-aclk-cycle 动作脉冲
        logic              selftest_q;
        logic              fu_selftest_q;
        logic              fu_w1c_q;
        logic              qsr_rel_q;
        logic [NUM_IA-1:0] r2a_w1c_q;
        logic [NUM_IA-1:0] r2r_w1c_q;
        logic              cfg_wr_q;       // registered cfg 加载脉冲
    } reg_a_t;

    localparam reg_a_t REG_A_RST = '{default: '0};

    reg_a_t r_a;
    reg_a_t rin_a;

    //--------------------------------------------------------------------------
    // mbus leaf decode (zero-wait, no wait/error channel; word-aligned,
    // 10 registers 0x00..0x24)
    //--------------------------------------------------------------------------
    logic [3:0] wsel;
    logic       inst_ok;
    logic       align_ok;
    logic       range_ok;
    logic       ro_reg;
    logic       addr_ok;
    assign wsel     =  addr[5:2];
    assign inst_ok  = (addr[15:8] == IDX[7:0]);
    assign align_ok = (addr[1:0] == 2'b00);
    assign range_ok = (wsel <= 4'd9);   // 0x00..0x24
    assign ro_reg   = (wsel == 4'd2) || (wsel == 4'd3);  // IASTAT/OTD
    assign addr_ok  =  inst_ok && align_ok && range_ok;

    // command in-flight parity: checked on EVERY ce, regardless of the
    // instance decode - a corrupted command must never silently select a
    // different victim register
    logic       par_bad;
    assign par_bad  = ce && (par != (^({addr, wr, wdata})));

    logic       ce_wr;
    logic       ce_rd;
    assign ce_wr    = ce &&  wr;
    assign ce_rd    = ce && !wr;
    // writes with bad parity, wrong instance, bad/RO offset: ignored
    logic       wr_ok;
    assign wr_ok    = ce_wr && addr_ok && !ro_reg && !par_bad;
    logic cdc_busy;
    // the mbus leaf cannot stall: a valid write while the CDC handshake is
    // busy is DROPPED (sticky SCMIAFUSTAT[5]); SW polls SCMIAFUSTAT[4]
    logic       wr_drop;
    logic       wr_fire;
    assign wr_drop  = wr_ok && cdc_busy;
    assign wr_fire  = wr_ok && !cdc_busy;

    //--------------------------------------------------------------------------
    // mbus -> aclk: toggle handshake, ONE write in flight, data stable
    // (req_t/wsel_q/wdata_q/wpar_q are r_mb record fields; the next-state
    //  logic lives in the mbus comb process below)
    //--------------------------------------------------------------------------
    logic        ack_t_s2;

    // ack toggle sync (2-flop) back into mbus_clk - sync cell wrap:
    // the metastability-absorbing s1 stays inside the cell, only the
    // resolved s2 is consumed (cdc_busy / wr_inflight below)
    sync_2dff #(.WIDTH(1)) u_ack_sync (
        .clk  (mbus_clk ),
        .rstn (mbus_rstn),
        .d    (r_a.ack_t),
        .q    (ack_t_s2 )
    );

    assign cdc_busy = (r_mb.req_t != ack_t_s2);

    //--------------------------------------------------------------------------
    // WR_DROPPED sticky (SCMIAFUSTAT[5]): set when a valid write is dropped
    // because the CDC handshake is busy. W1C by an ACCEPTED write to 0x1C
    // bit[5] (set and clear are mutually exclusive: a write dropped due to
    // busy is not decoded, an accepted write was not dropped).
    //--------------------------------------------------------------------------
    logic fustat_w1c;
    assign fustat_w1c = wr_fire && (wsel == 4'd7);

    //--------------------------------------------------------------------------
    // aclk domain: request 2-flop sync + registered edge detect (metastable
    // glitch-tolerant), decode, apply, ack toggle - sync cell wraps; the
    // cells take active-low rstn, the aclk reset is active-high -> local
    // inversion (async assert / sync release both preserved)
    //--------------------------------------------------------------------------
    logic rstn_a;
    assign rstn_a = ~rst;
    logic req_t_s2, req_t_d;
    sync_2dff #(.WIDTH(1)) u_req_sync (
        .clk  (aclk      ),
        .rstn (rstn_a    ),
        .d    (r_mb.req_t),
        .q    (req_t_s2  )
    );
    sync_dff #(.WIDTH(1)) u_req_dly (
        .clk  (aclk     ),
        .rstn (rstn_a   ),
        .d    (req_t_s2 ),
        .q    (req_t_d  )
    );
    logic req_edge;
    assign req_edge = req_t_s2 ^ req_t_d;

    // every request is acked, including no-op decodes (invalid key etc.)
    // (ack_t toggle lives in the aclk comb process below)

    // SCMCNTRL local key check + enable codeword check (double gate: the
    // monitor re-checks both - defense in depth)
    logic scmcntrl_key_ok;
    logic ena_codeword;
    assign scmcntrl_key_ok = (r_mb.wdata_q[7:4] == 4'b1010);
    assign ena_codeword    = (r_mb.wdata_q[3:0] == 4'b1111)
                             || (r_mb.wdata_q[3:0] == 4'b0000);

    //--------------------------------------------------------------------------
    // Config shadow registers (aclk): each is a reg_wrap instance IN THE
    // aclk DOMAIN (storage + parity + selftest + own sticky; the check
    // lives with the storage). Written through the CDC handshake
    // (req_edge decode, data stable). Reset = monitor reset values. Any
    // threshold write re-presents the FULL config to the monitor
    // (rewrite of unchanged values is idempotent), so the monitor's
    // keyed port always sees a coherent {ena, thr_a, thr_r} triple.
    //--------------------------------------------------------------------------
    logic [ 3:0] ena_sh;      // rdata of u_c_ena  (-> cfg_ena)
    logic [15:0] thr_a_sh;    // rdata of u_c_thresh0  (-> cfg_req2accept_max)
    logic [15:0] thr_r_sh;    // rdata of u_c_thresh1  (-> cfg_req2resp_max)
    logic       flt4_a, flt5_a, flt6_a;    // aclk stickies (synced below)

    // write decodes (aclk): SCMCNTRL needs key + ENA codeword (double
    // gate: the monitor re-checks both - defense in depth)
    logic cfg4_wr;
    logic cfg5_wr;
    logic cfg6_wr;
    assign cfg4_wr = req_edge && (r_mb.wsel_q == 4'd4) && scmcntrl_key_ok
                     && ena_codeword;
    assign cfg5_wr = req_edge && (r_mb.wsel_q == 4'd5);
    assign cfg6_wr = req_edge && (r_mb.wsel_q == 4'd6);

    // aclk-domain W1C / injection decodes of the SAME SW writes that
    // reach the mbus domain directly: the 0x24 W1C and the keyed
    // REG_SELFTEST both cross via the handshake, so every clear /
    // injection is applied in BOTH domains from one SW write
    logic par_wrc_a;
    logic reg_st_a;
    assign par_wrc_a   = req_edge && (r_mb.wsel_q == 4'd9);
    assign reg_st_a    = req_edge && (r_mb.wsel_q == 4'd4) && scmcntrl_key_ok
                         && r_mb.wdata_q[20] && (r_mb.wdata_q[19:16] <= 4'd8);

    //--------------------------------------------------------------------------
    // aclk 域组合进程: ack toggle + 动作脉冲 + cfg_wr 延迟 下一拍值
    //   (原 ack_ff / pulse_ff / cfg_wr_ff 三个 always_ff 合并; 条件全部读
    //    现态 r_a/r_mb 或组合线, 写全部落 v_a - 三者字段互不相交, NBA 语义
    //    保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb_a
        reg_a_t v_a;

        v_a = r_a;

        // CDC 应答 toggle: 每个请求都应答 (包括 no-op 译码)
        if (req_edge) begin
            v_a.ack_t = ~r_a.ack_t;
        end

        // 动作脉冲 (set on decoded request, auto-clear 下一拍):
        // to_clear / selftest / fu_selftest 只来自 key'd SCMCNTRL 位
        v_a.to_clear_q    = req_edge && (r_mb.wsel_q == 4'd4)
                            && scmcntrl_key_ok && r_mb.wdata_q[8];
        v_a.selftest_q    = req_edge && (r_mb.wsel_q == 4'd4)
                            && scmcntrl_key_ok && r_mb.wdata_q[9];
        v_a.fu_selftest_q = req_edge && (r_mb.wsel_q == 4'd4)
                            && scmcntrl_key_ok && r_mb.wdata_q[10];
        v_a.qsr_rel_q     = req_edge && (r_mb.wsel_q == 4'd4)
                            && scmcntrl_key_ok && r_mb.wdata_q[12];
        if (req_edge && (r_mb.wsel_q == 4'd0)) begin
            v_a.r2a_w1c_q = r_mb.wdata_q[NUM_IA-1:0];
        end else begin
            v_a.r2a_w1c_q = '0;
        end
        if (req_edge && (r_mb.wsel_q == 4'd1)) begin
            v_a.r2r_w1c_q = r_mb.wdata_q[NUM_IA-1:0];
        end else begin
            v_a.r2r_w1c_q = '0;
        end
        v_a.fu_w1c_q      = req_edge &&
                            ((r_mb.wsel_q == 4'd7 && r_mb.wdata_q[0])
                             || (r_mb.wsel_q == 4'd8 && (|r_mb.wdata_q)));

        // Monitor-facing config pulse: REGISTERED by one aclk cycle. The
        // shadows (u_c_ena/5/6) update via NBA at req_edge; a combinational
        // cfg_wr would pulse in that same cycle, so the monitor would
        // sample cfg_ena/cfg_thr BEFORE the shadow settles - the config
        // bus then lags exactly one write behind. One write per CDC
        // handshake, so the 1-cycle delay is always collision-free.
        v_a.cfg_wr_q = cfg4_wr | cfg5_wr | cfg6_wr;

        rin_a = v_a;
    end

    //--------------------------------------------------------------------------
    // aclk 域时序进程: 只做复位装载与 r_a <= rin_a
    //--------------------------------------------------------------------------
    always_ff @(posedge aclk or posedge rst) begin : seq_a
        if (rst) begin
            r_a <= REG_A_RST;
        end else begin
            r_a <= rin_a;
        end
    end

    reg_wrap #(
        .W                (4                                    ),
        .RESET            (4'b1111                              )
    ) u_c_ena (                                   // SCMCNTRL.ENA shadow
        .clk               (aclk                                 ),
        .rst_n             (rstn_a                               ),
        .wdata             (r_mb.wdata_q[3:0]                    ),
        .wr                (cfg4_wr                              ),
        .rdata             (ena_sh                               ),
        .selftest_key      (reg_st_a && (r_mb.wdata_q[19:16] == 4'd4)),
        .flt               (flt4_a                               ),
        .flt_w1c           (par_wrc_a && r_mb.wdata_q[8]         )
    );
    reg_wrap #(
        .W                (16                                   ),
        .RESET            (REQ2ACCEPT_RST                       )
    ) u_c_thresh0 (                                   // SCMTHRESH0 shadow
        .clk               (aclk                                 ),
        .rst_n             (rstn_a                               ),
        .wdata             (r_mb.wdata_q[15:0]                   ),
        .wr                (cfg5_wr                              ),
        .rdata             (thr_a_sh                             ),
        .selftest_key      (reg_st_a && (r_mb.wdata_q[19:16] == 4'd5)),
        .flt               (flt5_a                               ),
        .flt_w1c           (par_wrc_a && r_mb.wdata_q[9]         )
    );
    reg_wrap #(
        .W                (16                                   ),
        .RESET            (REQ2RESP_RST                         )
    ) u_c_thresh1 (                                   // SCMTHRESH1 shadow
        .clk               (aclk                                 ),
        .rst_n             (rstn_a                               ),
        .wdata             (r_mb.wdata_q[15:0]                   ),
        .wr                (cfg6_wr                              ),
        .rdata             (thr_r_sh                             ),
        .selftest_key      (reg_st_a && (r_mb.wdata_q[19:16] == 4'd6)),
        .flt               (flt6_a                               ),
        .flt_w1c           (par_wrc_a && r_mb.wdata_q[10]        )
    );

    assign cfg_key            = 4'b1010;   // by construction, TI SCMCNTRL key
    assign cfg_ena            = ena_sh;
    assign cfg_req2accept_max = thr_a_sh;
    assign cfg_req2resp_max   = thr_r_sh;

    //--------------------------------------------------------------------------
    // One-aclk-cycle action pulses (set on decoded request, auto-clear).
    // to_clear / selftest / fu_selftest come only from key'd SCMCNTRL bits.
    // (pulse regs + the registered cfg_wr_q live in the aclk record above)
    //--------------------------------------------------------------------------
    assign cfg_wr      = r_a.cfg_wr_q;
    assign to_clear     = r_a.to_clear_q   ;
    assign selftest_key = r_a.selftest_q   ;
    assign fu_selftest  = r_a.fu_selftest_q;
    assign r2a_w1c      = r_a.r2a_w1c_q    ;
    assign r2r_w1c      = r_a.r2r_w1c_q    ;
    assign fu_w1c       = r_a.fu_w1c_q     ;
    assign qsr_rel      = r_a.qsr_rel_q    ;

    //--------------------------------------------------------------------------
    // aclk -> mbus: 2-flop synchronizers.
    //   sticky status bits are per-bit independent (always coherent);
    //   IA/OTD/threshold/ena readbacks are dynamic multi-bit values
    //   (observability: a read racing a change may be incoherent, re-read
    //   resolves it - SW readback is periodic, not single-shot)
    //--------------------------------------------------------------------------
    logic [NUM_IA-1:0]   r2a_st_s1, r2a_st_s2, r2r_st_s1, r2r_st_s2;
    logic [NUM_IA-1:0]   ia_act_s1, ia_act_s2;
    logic [OTD_BW-1:0]   otd_s1, otd_s2;
    logic [15:0]         thr_a_s1, thr_a_s2, thr_r_s1, thr_r_s2;
    logic [3:0]          ena_s1, ena_s2;
    logic [3:0]          rail_s1, rail_s2;   // {EV_N,EV,FU_N,FU}
    logic [FU_SRC_W-1:0] fusrc_s1, fusrc_s2;
    // s2 images are the reg_wrap instance outputs (storage + parity +
    // fault sticky, see REGISTER PARITY section below)

    // first sync stage only (s1); the second stage IS the reg_wrap cell.
    // s1 = metastability absorption stage -> sync_dff cell wraps
    sync_dff #(.WIDTH(NUM_IA))   u_r2a_st_sync (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(r2a_err_status), .q(r2a_st_s1));
    sync_dff #(.WIDTH(NUM_IA))   u_r2r_st_sync (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(r2r_err_status), .q(r2r_st_s1));
    sync_dff #(.WIDTH(NUM_IA))   u_ia_act_sync (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(ia_active),      .q(ia_act_s1));
    sync_dff #(.WIDTH(OTD_BW))   u_otd_sync    (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(otd),            .q(otd_s1));
    sync_dff #(.WIDTH(16))       u_thr_a_sync  (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(thr_rd_r2a),     .q(thr_a_s1));
    sync_dff #(.WIDTH(16))       u_thr_r_sync  (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(thr_rd_r2r),     .q(thr_r_s1));
    sync_dff #(.WIDTH(4))        u_ena_sync    (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(ena_rd),         .q(ena_s1));
    sync_dff #(.WIDTH(4))        u_rail_sync   (
        .clk(mbus_clk), .rstn(mbus_rstn),
        .d({err_event_n, err_event, fu_fault_n, fu_fault}),   .q(rail_s1));
    sync_dff #(.WIDTH(FU_SRC_W)) u_fusrc_sync  (
        .clk(mbus_clk), .rstn(mbus_rstn), .d(fu_src),         .q(fusrc_s1));

    //--------------------------------------------------------------------------
    // REGISTER PARITY (FuSa): every register is a reg_wrap instance in
    // its own clock domain - see header. mbus-domain image wrappers
    // below; aclk config wrappers above (u_c_ena/u_c_thresh0/u_c_thresh1).
    // (reg_wrap/sync cells: fusa 单一源 common_modules/, 统一异步低有效
    //  rst_n - aclk 域高有效复位经 rstn_a = ~rst 适配。)
    //--------------------------------------------------------------------------

    logic r0_flt, r1_flt, r2_flt, r3_flt, r4_flt, r5_flt,
          r6_flt, r7_flt, r8_flt;

    // aclk config-wrapper stickies -> 2FF sync into mbus_clk
    // (per-bit independent, always coherent) - sync cell wrap
    logic flt4_s2, flt5_s2, flt6_s2;
    sync_2dff #(.WIDTH(3)) u_flt_sync (
        .clk  (mbus_clk ),
        .rstn (mbus_rstn),
        .d    ({flt4_a , flt5_a , flt6_a }),
        .q    ({flt4_s2, flt5_s2, flt6_s2})
    );

    // (c) in-flight write-latch parity: {wsel_q, wdata_q} are stable from
    // wr_fire until the ack returns, so this check runs entirely in the
    // mbus domain - a corrupted latch (wrong threshold/key/w1c delivered
    // to the aclk side) is flagged while the write is still in flight;
    // latched as PERR9 (transient window, sticky needed)
    logic wr_inflight;
    logic wpar_err;
    assign wr_inflight = (r_mb.req_t != ack_t_s2);
    assign wpar_err    = wr_inflight
                         && (((^r_mb.wsel_q) ^ (^r_mb.wdata_q)) != r_mb.wpar_q);

    // SCMREGPARSTAT W1C decode (mbus side; aclk side = par_wrc_a above):
    // wdata[12:4] clear PERR0..8 at their source register, wdata[13]
    // clears PERR9, wdata[14] clears PERR_CMD, wdata[0] clears the
    // PAR_SELFTEST latch
    logic par_wrc;
    assign par_wrc = wr_fire && (wsel == 4'd9);

    // per-register parity INJECTION decode (mbus images; aclk shadows =
    // reg_st_a above): keyed REG_SELFTEST/REGSEL, one wr_fire pulse
    // flips the selected wrapper's parity bit. Image wrappers are wr=1
    // every cycle, so the injected bad parity self-restores on the NEXT
    // cycle (par_err is high exactly 1 cycle, the sticky latches it) -
    // after W1C the fault stays clear without re-writing the register.
    logic reg_selftest;
    assign reg_selftest = wr_fire && (wsel == 4'd4)
                          && (wdata[7:4] == 4'b1010) && wdata[20]
                          && (wdata[19:16] <= 4'd8);

    //---- mbus-domain image wrappers (r2 = second sync stage + parity) --
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r_iaerr0 (                                   // 0x00 SCMIAERR0STAT
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (r2a_st_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (r2a_st_s2                            ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd0)),
        .flt               (r0_flt                               ),
        .flt_w1c           (par_wrc && wdata[4]                 )
    );
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r_iaerr1 (                                   // 0x04 SCMIAERR1STAT
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (r2r_st_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (r2r_st_s2                            ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd1)),
        .flt               (r1_flt                               ),
        .flt_w1c           (par_wrc && wdata[5]                 )
    );
    reg_wrap #(
        .W                (NUM_IA                               )
    ) u_r_iastat (                                   // 0x08 SCMIASTAT (RO)
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (ia_act_s1                            ),
        .wr                (1'b1                                 ),
        .rdata             (ia_act_s2                            ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd2)),
        .flt               (r2_flt                               ),
        .flt_w1c           (par_wrc && wdata[6]                 )
    );
    reg_wrap #(
        .W                (OTD_BW                               )
    ) u_r_otd (                                   // 0x0C SCMOTD (RO)
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (otd_s1                               ),
        .wr                (1'b1                                 ),
        .rdata             (otd_s2                               ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd3)),
        .flt               (r3_flt                               ),
        .flt_w1c           (par_wrc && wdata[7]                 )
    );
    reg_wrap #(
        .W                (4                                    )
    ) u_r_cntrl (                                   // 0x10 SCMCNTRL.ENA image
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (ena_s1                               ),
        .wr                (1'b1                                 ),
        .rdata             (ena_s2                               ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd4)),
        .flt               (r4_flt                               ),
        .flt_w1c           (par_wrc && wdata[8]                 )
    );
    reg_wrap #(
        .W                (16                                   )
    ) u_r_thresh0 (                                   // 0x14 SCMTHRESH0 image
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (thr_a_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (thr_a_s2                             ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd5)),
        .flt               (r5_flt                               ),
        .flt_w1c           (par_wrc && wdata[9]                 )
    );
    reg_wrap #(
        .W                (16                                   )
    ) u_r_thresh1 (                                   // 0x18 SCMTHRESH1 image
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (thr_r_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (thr_r_s2                             ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd6)),
        .flt               (r6_flt                               ),
        .flt_w1c           (par_wrc && wdata[10]                )
    );
    reg_wrap #(
        .W                (4                                    )
    ) u_r_fustat (                                   // 0x1C SCMIAFUSTAT rails
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (rail_s1                              ),
        .wr                (1'b1                                 ),
        .rdata             (rail_s2                              ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd7)),
        .flt               (r7_flt                               ),
        .flt_w1c           (par_wrc && wdata[11]                )
    );
    reg_wrap #(
        .W                (FU_SRC_W                             )
    ) u_r_fusrc (                                   // 0x20 SCMIAFUSRC image
        .clk               (mbus_clk                              ),
        .rst_n             (mbus_rstn                             ),
        .wdata             (fusrc_s1                             ),
        .wr                (1'b1                                 ),
        .rdata             (fusrc_s2                             ),
        .selftest_key      (reg_selftest && (wdata[19:16] == 4'd8)),
        .flt               (r8_flt                               ),
        .flt_w1c           (par_wrc && wdata[12]                )
    );

    //--------------------------------------------------------------------------
    // SCMREGPARSTAT (0x24) itself: the wrapper stickies ARE the PERR
    // bits. Only the PAR_SELFTEST latch, PERR9 (in-flight write-path
    // parity) and PERR_CMD (mbus command parity) are stored here, as a
    // 3-bit latch with inverted duplicates (heal-to-SET - a parity
    // monitor cannot meaningfully parity-protect its own status bits):
    //   par_lq = {PERR_CMD, PERR9 (wpar), PAR_SELFTEST}
    //   bit2 set by any ce with bad command parity, cleared by wdata[14];
    //   bit1 set by any in-flight latch parity error, cleared by
    //   wdata[13]; bit0 set by PAR_SELFTEST, cleared by wdata[0]
    // "fault, no source" after a self-test is the ESM service signature.
    //--------------------------------------------------------------------------
    logic selftest_pls;
    assign selftest_pls = wr_fire && (wsel == 4'd4) && (wdata[7:4] == 4'b1010)
                          && wdata[11];

    logic [2:0] par_l_dup_f;
    assign par_l_dup_f = (r_mb.par_lq_n != ~r_mb.par_lq);

    //--------------------------------------------------------------------------
    // mbus 域组合进程: CDC 写锁存 + WR_DROPPED 粘滞 + SCMREGPARSTAT 锁存
    //   下一拍值 (默认保持; 原 mbus_cdc_ff / wr_drop_ff / par_latch_ff 三个
    //   always_ff 合并, 字段互不相交, NBA 语义保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb_mb
        reg_mb_t v_mb;

        v_mb = r_mb;

        // CDC 写锁存 (toggle handshake, 在飞期间数据稳定)
        if (wr_fire) begin
            v_mb.req_t   = ~r_mb.req_t;
            v_mb.wsel_q  =  wsel;
            v_mb.wdata_q =  wdata;
            v_mb.wpar_q  = (^wsel) ^ (^wdata);
        end

        // WR_DROPPED 粘滞: set 优先于 W1C clear (二者互斥, 见上文注释)
        if (wr_drop) begin
            v_mb.wr_dropped_q = 1'b1;
        end else if (fustat_w1c && wdata[5]) begin
            v_mb.wr_dropped_q = 1'b0;
        end

        // SCMREGPARSTAT 3-bit 锁存 (dual rail): W1C clear / 新事件 set /
        // dup 失配自愈到 SET (heal-to-SET, 事件绝不静默丢失)
        if (par_wrc) begin
            v_mb.par_lq = r_mb.par_lq & ~{wdata[14], wdata[13], wdata[0]};
        end
        v_mb.par_lq   = v_mb.par_lq | {par_bad, wpar_err, selftest_pls};
        if (par_l_dup_f != '0) begin
            v_mb.par_lq = v_mb.par_lq | 3'b111;
        end
        v_mb.par_lq_n = ~v_mb.par_lq;

        rin_mb = v_mb;
    end

    //--------------------------------------------------------------------------
    // mbus 域时序进程: 只做复位装载与 r_mb <= rin_mb
    //--------------------------------------------------------------------------
    always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : seq_mb
        if (!mbus_rstn) begin
            r_mb <= REG_MB_RST;
        end else begin
            r_mb <= rin_mb;
        end
    end

    // ESM event: level, dual rail. Level = OR of all wrapper stickies -
    // mbus images r0..r8 (r4/r5/r6 are readback images, their config
    // twins are the aclk shadows) + synced aclk shadows + the latch.
    // Each source clears at its own PERR bit in BOTH domains, so the
    // event stays up exactly as long as an uncleared source exists
    // (single source of truth).
    logic perr4;
    logic perr5;
    logic perr6;
    assign perr4 = r4_flt | flt4_s2;   // 0x10: image + ENA shadow
    assign perr5 = r5_flt | flt5_s2;   // 0x14: image + THRESH0 shadow
    assign perr6 = r6_flt | flt6_s2;   // 0x18: image + THRESH1 shadow
    assign reg_par_fault   = r0_flt | r1_flt | r2_flt | r3_flt
                              | perr4 | perr5 | perr6
                              | r7_flt | r8_flt
                              | (|r_mb.par_lq);
    assign reg_par_fault_n = ~reg_par_fault;

    //--------------------------------------------------------------------------
    // RDATA mux (combinational, zero-wait; all sources are stable
    // mbus_clk-domain flops). Gated: only a valid read of this instance
    // with good command parity returns data - anything else reads 0
    // (bad parity must never leak a corrupted-address read result).
    //--------------------------------------------------------------------------
    always_comb begin : rdata_mux
        rdata = 32'b0;
        if (ce_rd && addr_ok && !par_bad) begin
            case (wsel)
                4'd0:    rdata = {{(32-NUM_IA){1'b0}}, r2a_st_s2};
                4'd1:    rdata = {{(32-NUM_IA){1'b0}}, r2r_st_s2};
                4'd2:    rdata = {{(32-NUM_IA){1'b0}}, ia_act_s2};
                4'd3:    rdata = {{(32-OTD_BW){1'b0}}, otd_s2};
                4'd4:    rdata = {28'b0, ena_s2};
                4'd5:    rdata = {16'b0, thr_a_s2};
                4'd6:    rdata = {16'b0, thr_r_s2};
                4'd7:    rdata = {26'b0, r_mb.wr_dropped_q, cdc_busy, rail_s2};
                4'd8:    rdata = {{(32-FU_SRC_W){1'b0}}, fusrc_s2};
                4'd9:    rdata = {17'b0, r_mb.par_lq[2], r_mb.par_lq[1], r8_flt, r7_flt,
                                  perr6, perr5, perr4, r3_flt, r2_flt, r1_flt,
                                  r0_flt, 2'b00, reg_par_fault_n,
                                  reg_par_fault};
                default: rdata = 32'h0;
            endcase
        end
    end

endmodule
