`timescale 1ns/1ps
//============================================================================
// hang_prot_mcu2main_top - SCENARIO 2 integration top (Unit A, OUTBOUND,
// former hang_prot_a_wrap):
//   island NIC (ALIVE master) on the m side
//     -> main domain IC (can die; ESM-resettable) on the s side
//
// Thin integration wrapper around hang_prot_top (monitor + regfile +
// hang_prot_recover shim): provides the scenario-named boundary for the
// TB / SoC integration and the ESM contract surface. ADB400 slot is
// reserved on the s boundary (this unit sits on the ISLAND clock/reset
// tree; the ADB400 performs the CDC toward main - not modeled here, the
// TB's slave BFM plays main directly in the island domain).
//
// ESM CONTRACT (5-channel-idle on main revive, doc §8.5):
//   1. hang detected (STA_RCV.ACTIVE=1, DONE not arriving)
//      -> SW/ESM asserts main rst AND opens the sl_sw_rst_on window (0x2C)
//   2. unit drains: dummy R/B retire the NIC's in-flight; a REPLAY slot
//      stuck on the dead main is force-cleared once wr_otd==0
//   3. ESM releases main rst (main revives: all 5 s-side channels idle -
//      the unit drives no VALID while sl_sw_rst_on is up)
//   4. window closed (0x2C=0xA0) -> recover_exit -> path reopens the next cycle
//      (the NIC's held awvalid handshakes immediately)
// SW service: W1C the sticky status (+ optional TO_CLR) after exit.
//
// FuSa v3.1 (SIL2): all mechanisms live below this thin wrapper
//   (gen_wrap edge-flop rail + recover mode_r rail + ID-FIFO parity +
//   wskid one-hot/payload-parity/counter dups); the dual-rail status
//   skid_fault/_n passes through; recovery status is register-visible
//   (v3.3: regfile 0x30 STA_RCV, pins retired).
//   v3.5: 原 hang_prot_top (generic 单主单元) 已并入本文件 —— mcu2main
//         即完整单元 (regfile + monitor + recover shim), 无壳层; TB_GEN
//         直接例化本模块。模块层次路径降一层 (u_dut.u_hang_prot_recover..)。
//============================================================================
module hang_prot_mcu2main_top #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0,       // mbus instance index
    parameter int          AXI_ID_W       = 4,       // AXI id width
    // ---- mcore-aware read classes (v3.2, island NIC aggregates several
    //      masters: each mcore identified by its full m_arid, gets its OWN
    //      forwarded read id; all other masters share AR_ID_REMAP) ---------
    parameter int                            N_MCORE = 2,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_MASTER_IDS = '0,
    parameter logic [N_MCORE*AXI_ID_W-1:0]   MCORE_REMAP_IDS  = '0,
    parameter logic [AXI_ID_W-1:0] AR_ID_REMAP = '0, // OTHER masters -> this
    parameter logic [AXI_ID_W-1:0] AW_ID_REMAP = '0, // all AWs -> this id
    parameter int          AXI_ADDR_W     = 32,
    parameter int          AXI_DATA_W     = 32,
    parameter int          WSKID_BEATS    = 16,      // max W burst beats
    parameter int          NSLOT          = 2       // W skid ring depth (v2.4)
)(
    // ---- mbus leaf (mbus_clk domain) ---------------------------------------
    input  logic                 mbus_clk,
    input  logic                 mbus_rstn,        // async, active-low
    input  logic                 mbus_ce,          // single-cycle chip enable
    input  logic                 mbus_wr,          // 1=write, 0=read
    input  logic [15:0]          mbus_addr,        // [15:8]=instance, [7:0]=offset
    input  logic [31:0]          mbus_wdata,
    input  logic                 mbus_par,         // ^({addr, wr, wdata})
    output logic [31:0]          mbus_rdata,       // combinational, zero-wait
    output logic                 mbus_rpar,        // ^mbus_rdata read-path even parity

    // ---- island clock / reset ----------------------------------------------
    input  logic                 ia_bus_aclk,
    input  logic                 rstn,             // async, active-low
    input  logic                 scan_mode,        // DFT: bypass core reset sync
    // ---- ESM: main-domain reset hold (LEVEL, aclk domain, DUAL RAIL v3.2) --
    //   ESM must drive the pair complementarily (same reset-held source);
    //   a stuck-at on either wire is detected 1 cycle later and fails
    //   toward containment (path closed) + sticky sk_fault.

    // ---- AXI4 m side (island NIC = master; unit = slave) -------------------
    input  logic                 m_arvalid,
    output logic                 m_arready,
    input  logic [AXI_ID_W-1:0]  m_arid,
    input  logic [AXI_ADDR_W-1:0] m_araddr,
    input  logic [7:0]           m_arlen,
    input  logic [2:0]           m_arsize,
    input  logic [1:0]           m_arburst,
    input  logic [2:0]           m_arprot,
    output logic                 m_rvalid,
    output logic [AXI_ID_W-1:0]  m_rid,
    output logic [AXI_DATA_W-1:0] m_rdata,
    output logic [1:0]           m_rresp,
    output logic                 m_rlast,
    input  logic                 m_rready,
    input  logic                 m_awvalid,
    output logic                 m_awready,
    input  logic [AXI_ID_W-1:0]  m_awid,
    input  logic [AXI_ADDR_W-1:0] m_awaddr,
    input  logic [7:0]           m_awlen,
    input  logic [2:0]           m_awsize,
    input  logic [1:0]           m_awburst,
    input  logic [2:0]           m_awprot,
    input  logic                 m_wvalid,
    output logic                 m_wready,
    input  logic [AXI_DATA_W-1:0] m_wdata,
    input  logic [AXI_DATA_W/8-1:0] m_wstrb,
    input  logic                 m_wlast,
    output logic                 m_bvalid,
    output logic [AXI_ID_W-1:0]  m_bid,
    output logic [1:0]           m_bresp,
    input  logic                 m_bready,

    // ---- AXI4 s side (main domain IC = slave; unit = master) ---------------
    output logic                 s_arvalid,
    input  logic                 s_arready,
    output logic [AXI_ID_W-1:0]  s_arid,
    output logic [AXI_ADDR_W-1:0] s_araddr,
    output logic [7:0]           s_arlen,
    output logic [2:0]           s_arsize,
    output logic [1:0]           s_arburst,
    output logic [2:0]           s_arprot,
    input  logic                 s_rvalid,
    input  logic [AXI_ID_W-1:0]  s_rid,
    input  logic [AXI_DATA_W-1:0] s_rdata,
    input  logic [1:0]           s_rresp,
    input  logic                 s_rlast,
    output logic                 s_rready,
    output logic                 s_awvalid,
    input  logic                 s_awready,
    output logic [AXI_ID_W-1:0]  s_awid,
    output logic [AXI_ADDR_W-1:0] s_awaddr,
    output logic [7:0]           s_awlen,
    output logic [2:0]           s_awsize,
    output logic [1:0]           s_awburst,
    output logic                 s_wvalid,
    output logic [AXI_DATA_W-1:0] s_wdata,
    output logic [AXI_DATA_W/8-1:0] s_wstrb,
    output logic                 s_wlast,
    input  logic                 s_wready,
    input  logic                 s_bvalid,
    input  logic [AXI_ID_W-1:0]  s_bid,
    input  logic [1:0]           s_bresp,
    output logic                 s_bready,

    // ---- ESM outputs (dual rail) --------------------------------------------
    output logic                 esm_err,
    output logic                 esm_err_n,
    output logic                 esm_fault,
    output logic                 esm_fault_n,
    output logic                 reg_par_fault,
    output logic                 reg_par_fault_n,
    output logic                 skid_fault,
    output logic                 skid_fault_n
);

    localparam int NUM_M  = 1;    // single master by design
    localparam int NUM_IA = 2*NUM_M;

    // ---- aclk-domain interconnect between regfile and monitor --------------
    logic                     cfg_wr;
    logic [3:0]               cfg_key, cfg_ena;
    logic [15:0]              cfg_req2accept_max, cfg_req2resp_max;
    logic                     to_clear, selftest_key, fu_selftest;
    logic [NUM_IA-1:0]        r2a_w1c, r2r_w1c;
    logic                     fu_w1c;

    logic [NUM_IA-1:0]        r2a_err_status, r2r_err_status, ia_active;
    logic                     sl_sw_rst_on;   // v3.3: regfile 0x2C -> recover
    logic                     recover_active; // v3.3: recover -> regfile 0x30
    logic                     recover_done;
    logic [NUM_IA*OTD_W-1:0]  otd;
    logic [15:0]              thr_rd_r2a, thr_rd_r2r;
    logic [3:0]               ena_rd;
    logic                     esm_err_i, esm_err_n_i;
    logic                     iflt_lvl;    // v3.6: regfile 在途命令奇偶事件
                                           // (mbus 域粘滞) -> 2FF -> esm_fault
    logic                     esm_fault_i, esm_fault_n_i;
    logic [4+3*NUM_M-1:0]     fu_src;

    // recovery control (aclk domain; recover_req generated below)
    logic [OTD_W-1:0]         rd_otd_mon, wr_otd_mon;
    logic sk_fault_i;
    logic sk_fault_n_i;   // u_hang_prot_recover boundary-integrity rails

    //--------------------------------------------------------------------------
    // Register file (mbus_clk <-> ia_bus_aclk CDC inside)
    //--------------------------------------------------------------------------
    hang_prot_regfile #(
        .NUM_M         (NUM_M         ),
        .NUM_IA        (NUM_IA        ),
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  ),
        .IDX           (IDX           )
    ) u_hang_prot_regfile (
        .mbus_clk (mbus_clk  ),
        .mbus_rstn(mbus_rstn ),
        .ce       (mbus_ce   ),
        .wr       (mbus_wr   ),
        .addr     (mbus_addr ),
        .wdata    (mbus_wdata),
        .par      (mbus_par  ),
        .rdata    (mbus_rdata),
        .rpar     (mbus_rpar ),

        .aclk(ia_bus_aclk),
        .rstn(rstn       ),

        .cfg_wr            (cfg_wr            ),
        .cfg_key           (cfg_key           ),
        .cfg_ena           (cfg_ena           ),
        .cfg_req2accept_max(cfg_req2accept_max),
        .cfg_req2resp_max  (cfg_req2resp_max  ),
        .to_clear          (to_clear          ),
        .selftest_key      (selftest_key      ),
        .fu_selftest       (fu_selftest       ),
        .r2a_w1c           (r2a_w1c           ),
        .r2r_w1c           (r2r_w1c           ),
        .fu_w1c            (fu_w1c            ),
        .qsr_rel           (                 ),
        .sl_sw_rst_on      (sl_sw_rst_on     ),

        .r2a_err_status(r2a_err_status),
        .r2r_err_status(r2r_err_status),
        .ia_active     (ia_active     ),
        .otd           (otd           ),
        .thr_rd_r2a    (thr_rd_r2a    ),
        .thr_rd_r2r    (thr_rd_r2r    ),
        .ena_rd        (ena_rd        ),
        .esm_err     (esm_err_i   ),
        .esm_err_n   (esm_err_n_i ),
        .esm_fault      (esm_fault_i    ),
        .esm_fault_n    (esm_fault_n_i  ),
        .fu_src        (fu_src        ),
        .recover_active(recover_active),
        .recover_done  (recover_done  ),

        .reg_par_fault  (reg_par_fault  ),
        .reg_par_fault_n(reg_par_fault_n),
        .iflt_lvl       (iflt_lvl       )
    );

    //--------------------------------------------------------------------------
    // Inline recovery shim (ia_bus_aclk domain) - owns the path
    //   recover_req = RISING EDGE of the monitor's sticky esm_err:
    //   arm once per timeout event. A level would oscillate between
    //   recover and pass-through every other cycle while the sticky is
    //   set (exit is automatic, the level is not); a new timeout after
    //   recovery produces a new rise -> re-arms.
    //   FuSa v3.1 (SIL2): the edge flop is INVERTED-DUPLICATED
    //   (esm_err_q_n). A rail mismatch (SEU on the edge flop):
    //     - forces a recover_req pulse THIS cycle (fail toward the
    //       contained state - a spurious recovery is the safe direction;
    //       a MISSED rise would leave the hang undrained)
    //     - latches a sticky dual-rail edge fault, aggregated into
    //       skid_fault/skid_fault_n (the boundary-integrity ESM group)
    //     - self-heals next cycle (both rails reload from esm_err_i),
    //       but the sticky latch remembers the event
    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    //   esm_err 边沿检测寄存器 (dual rail) + 粘滞 wrapper 边沿故障锁存
    //--------------------------------------------------------------------------
    typedef struct packed {
        logic esm_err_q;    // esm_err_i 的上一拍 (dual rail 真值)
        logic esm_err_q_n;  // inverted duplicate rail
        logic edgeflt_q;      // sticky edge-fault latch
        logic edgeflt_q_n;    // inverted duplicate rail
    } reg_t;

    localparam reg_t REG_RST = '{
        esm_err_q   : 1'b0,
        esm_err_q_n : 1'b1,
        edgeflt_q     : 1'b0,
        edgeflt_q_n   : 1'b1
    };

    reg_t r;
    reg_t rin;

    logic edge_dis;
    assign edge_dis = (r.esm_err_q_n != ~r.esm_err_q);

    //--------------------------------------------------------------------------
    // 组合进程: 下一拍值 (默认保持)
    //--------------------------------------------------------------------------
    always_comb begin : comb
        reg_t v;

        v = r;

        // esm_err 边沿寄存器: 跟随 esm_err_i (SEU 失配一拍自愈)
        v.esm_err_q   = esm_err_i;
        v.esm_err_q_n = ~esm_err_i;

        // 粘滞边沿故障锁存 (dual rail, rst-only)
        if (edge_dis) begin
            v.edgeflt_q   = 1'b1;
            v.edgeflt_q_n = 1'b0;
        end

        rin = v;
    end

    //--------------------------------------------------------------------------
    // 时序进程: 只做复位装载与 r <= rin
    //--------------------------------------------------------------------------
    always_ff @(posedge ia_bus_aclk or negedge rstn) begin : seq
        if (!rstn) begin
            r <= REG_RST;
        end else begin
            r <= rin;
        end
    end

    logic recover_req;
    assign recover_req = (esm_err_i && !r.esm_err_q) || edge_dis;

    assign rd_otd_mon  = otd[0*OTD_W +: OTD_W];   // read  stream of master 0
    assign wr_otd_mon  = otd[1*OTD_W +: OTD_W];   // write stream of master 0

    hang_prot_recover #(
        .OTD_MAX         (OTD_MAX         ),
        .OTD_W           (OTD_W           ),
        .AXI_ID_W        (AXI_ID_W        ),
        .N_MCORE         (N_MCORE         ),
        .MCORE_MASTER_IDS(MCORE_MASTER_IDS),
        .MCORE_REMAP_IDS (MCORE_REMAP_IDS ),
        .AR_ID_REMAP     (AR_ID_REMAP     ),
        .AW_ID_REMAP     (AW_ID_REMAP     ),
        .AXI_ADDR_W      (AXI_ADDR_W      ),
        .AXI_DATA_W      (AXI_DATA_W      ),
        .WSKID_BEATS     (WSKID_BEATS     ),
        .NSLOT           (NSLOT           )
    ) u_hang_prot_recover (
        .clk(ia_bus_aclk),
        .rstn(rstn       ),

        .recover_req(recover_req),
        .rd_otd_mon (rd_otd_mon ),
        .wr_otd_mon (wr_otd_mon ),
        .sl_sw_rst_on   (sl_sw_rst_on   ),

        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_arid   (m_arid   ),
        .m_arlen  (m_arlen  ),
        .m_rvalid (m_rvalid ),
        .m_rid    (m_rid    ),
        .m_rresp  (m_rresp  ),
        .m_rlast  (m_rlast  ),
        .m_rready (m_rready ),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_awid   (m_awid   ),
        .m_awaddr (m_awaddr ),
        .m_awlen  (m_awlen  ),
        .m_awsize (m_awsize ),
        .m_awburst(m_awburst),
        .m_wvalid (m_wvalid ),
        .m_wready (m_wready ),
        .m_wdata  (m_wdata  ),
        .m_wstrb  (m_wstrb  ),
        .m_wlast  (m_wlast  ),
        .m_bvalid (m_bvalid ),
        .m_bid    (m_bid    ),
        .m_bresp  (m_bresp  ),
        .m_bready (m_bready ),

        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_arid   (s_arid   ),
        .s_rvalid (s_rvalid ),
        .s_rid    (s_rid    ),  // v2.3: low CLSW bits = response class
        .s_rready (s_rready ),
        .s_rresp  (s_rresp  ),
        .s_rlast  (s_rlast  ),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_awid   (s_awid   ),
        .s_awaddr (s_awaddr ),
        .s_awlen  (s_awlen  ),
        .s_awsize (s_awsize ),
        .s_awburst(s_awburst),
        .s_wvalid (s_wvalid ),
        .s_wlast  (s_wlast  ),
        .s_wdata  (s_wdata  ),
        .s_wstrb  (s_wstrb  ),
        .s_wready (s_wready ),
        .s_bvalid (s_bvalid ),
        .s_bready (s_bready ),
        .s_bresp  (s_bresp  ),

        .recover_active  (recover_active  ),
        .recover_done    (recover_done    ),
        .sk_fault        (sk_fault_i      ),
        .sk_fault_n      (sk_fault_n_i    )
    );

    // skid_fault = aggregated BOUNDARY INTEGRITY fault (dual rail):
    //   recover unit (wskid one-hot/parity/dups + mode_r rail + FIFO
    //   parity/dups) OR this wrapper's edge-detector rail fault.
    //   Proper rail aggregation: OR of true rails, AND of false rails.
    assign skid_fault   = sk_fault_i | r.edgeflt_q;
    assign skid_fault_n = sk_fault_n_i & r.edgeflt_q_n;

    // payload pass-through: AR payload (addr/len/size/burst/prot) and the
    // read data path are combinational in the wrapper. The AW/W DATA path
    // lives INSIDE the shim (v2.1 store-and-forward skid: AW is held until
    // its complete W burst is buffered, then AW+W issued together; s_aw*
    // and s_wdata/wstrb are shim outputs). Dummy R beats carry zero data.
    assign s_araddr  = m_araddr;
    assign s_arlen   = m_arlen;
    assign s_arsize  = m_arsize;
    assign s_arburst = m_arburst;
    assign s_arprot  = m_arprot;
    // (s_awaddr/len/size/burst and s_wdata/s_wstrb are shim outputs - skid)

    // FuSa residual (v3.1, documented): m_rdata is muxed on recover_active.
    //   A stuck-at-0 on that rail would pass s_rdata on dummy beats - data
    //   integrity is end-to-end (island NIC/SoC check), the event is
    //   separately visible via the mode_r dual rail / recover_done pair.
    assign m_rdata   = recover_active ? '0 : s_rdata;

    // m_rid / m_bid come from the shim (ID FIFO restoration, both modes).
    // s_rid feeds the shim's per-class response routing (v2.3); s_bid
    // carries the remapped write id and is ignored.

    //--------------------------------------------------------------------------
    // Timeout monitor (ia_bus_aclk domain) - observes the m side of the shim
    //--------------------------------------------------------------------------
    hang_prot_core #(
        .NUM_M         (NUM_M         ),
        .NUM_IA        (NUM_IA        ),
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  )
    ) u_hang_prot_core (
        .clk      (ia_bus_aclk),
        .rstn     (rstn       ),
        .scan_mode(scan_mode  ),

        .axi_arvalid(m_arvalid),
        .axi_arready(m_arready),
        .axi_rvalid (m_rvalid ),
        .axi_rready (m_rready ),
        .axi_rlast  (m_rlast  ),
        .axi_awvalid(m_awvalid),
        .axi_awready(m_awready),
        .axi_wvalid (m_wvalid ),
        .axi_wready (m_wready ),
        .axi_wlast  (m_wlast  ),
        .axi_bvalid (m_bvalid ),
        .axi_bready (m_bready ),

        .cfg_wr            (cfg_wr            ),
        .cfg_key           (cfg_key           ),
        .cfg_ena           (cfg_ena           ),
        .cfg_req2accept_max(cfg_req2accept_max),
        .cfg_req2resp_max  (cfg_req2resp_max  ),

        .to_clear    (to_clear    ),
        .selftest_key(selftest_key),
        .fu_selftest (fu_selftest ),

        .r2a_w1c(r2a_w1c),
        .r2r_w1c(r2r_w1c),
        .fu_w1c (fu_w1c ),

        .r2a_err_status(r2a_err_status),
        .r2r_err_status(r2r_err_status),
        .ia_active     (ia_active     ),
        .otd           (otd           ),
        .thr_rd_r2a    (thr_rd_r2a    ),
        .thr_rd_r2r    (thr_rd_r2r    ),
        .esm_err     (esm_err_i   ),
        .esm_err_n   (esm_err_n_i ),
        .ena_rd        (ena_rd        ),
        .esm_fault      (esm_fault_i    ),
        .esm_fault_n    (esm_fault_n_i  ),
        .fu_src        (fu_src        )
    );

    // ESM dual-rail outputs (aclk domain):
    //   err 直出监视器; fault = 监视器完整性 | 在途命令奇偶事件
    //   (regfile iflt_lvl, mbus 粘滞电平经 2FF 同步, 三轨统一 2026-11-16)
    logic iflt_s2;
    sync_2dff #(
       .WIDTH(1)
    ) u_iflt_sync (
       .clk (ia_bus_aclk),
       .rstn(rstn       ),
       .d   (iflt_lvl   ),
       .q   (iflt_s2    )
    );

    assign esm_err   = esm_err_i;
    assign esm_err_n = esm_err_n_i;
    assign esm_fault    = esm_fault_i | iflt_s2;
    assign esm_fault_n  = ~esm_fault;


endmodule
