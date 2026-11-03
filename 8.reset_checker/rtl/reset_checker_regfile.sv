`timescale 1ns/1ps
//============================================================================
// reset_checker_regfile - reset checker register file: mbus leaf (single
// domain, mbus_clk) + config + status images + protection
//
// mbus LEAF (zero-wait; protocol per apb2mbus):
//   ce single-cycle pulse, wr, addr[15:8]=instance / [7:0]=byte offset,
//   wdata, par = ^{addr,wr,wdata} command in-flight parity (checked at ce).
//   Bad-parity command: writes blocked, read returns 0, PERR_CMD latched.
//   rdata combinational, 0 when not selected.
//
// SINGLE-DOMAIN SCOPE NOTE (layering): the reset-rail monitor engine (in
// reset_checker.sv) runs in THIS mbus_clk domain - no CDC handshake. The
// mbus clock of the safety island is the always-on sampling clock; its
// liveness is owned by the CMM layer (clock monitor), exactly like the
// regfile/CDC-brain liveness argument in cmm_regfile. What this module
// guards is the reset RAIL PAIR integrity, not the clock.
//
// REGISTER PARITY (FuSa): every SW-visible register is a reg_wrap instance
// (storage + even parity + selftest_key injection + own sticky flt with
// inverted duplicate) - the check lives with the storage:
//   PERR group bit (REGPAR[k+4]) / REGPAR bit:
//     [4]  CTRL wrap {EN,FI}              [16] PERR_CMD command parity
//     [5]  EV image wrap                  [17] PAR_SELFTEST latch
//     [6]  STAT image wrap                [18] REG_PROT write protection
//   Image wraps (5/6) follow wr=1: an injected parity error self-restores
//   next cycle. The config wrap (4) holds: restore = rewrite the register
//   (the documented last step of the self-test flow).
//
// WRITE PROTECTION: keyed registers (CTRL/REGST) need wdata[31:28]==
// WKEY; a bad key, a write to RO (ID/STAT) or an unknown offset latches
// REG_PROT and rejects the write entirely.
//============================================================================
module reset_checker_regfile #(
    parameter logic [3:0]  WKEY     = 4'h5,     // key in wdata[31:28]
    parameter logic [1:0]  CTRL_RST = 2'b01,    // EN=1 FI=0 (fail-safe on)
    parameter int          IDX      = 0         // mbus instance id
)(
    // ---- mbus (mbus_clk domain) -------------------------------------------
    input  logic                  mbus_clk,
    input  logic                  mbus_rstn,
    input  logic                  ce,
    input  logic                  wr,
    input  logic [15:0]           addr,
    input  logic [31:0]           wdata,
    input  logic                  par,
    output logic [31:0]           rdata,

    // ---- config out (same domain; engine runs on mbus_clk) -----------------
    output logic                  cfg_en,       // checker enable
    output logic                  cfg_fi,       // fault inject level

    // ---- W1C pulses -> engine stickies (1 mbus_clk cycle) ------------------
    output logic                  err_w1c,      // clear err sticky
    output logic                  ev_da_w1c,    // clear DIV_A event
    output logic                  ev_db_w1c,    // clear DIV_B event

    // ---- status in (same domain, engine registers) -------------------------
    input  logic                  sts_ev_da,
    input  logic                  sts_ev_db,
    input  logic                  sts_ev_err,   // verdict sticky (latched fire)
    input  logic                  sts_viol,     // live pair violation
    input  logic                  sts_div_a,
    input  logic                  sts_div_b,
    input  logic                  sts_cnt_full, // counter saturated (all-ones)
    input  logic [4:0]            sts_cnt,

    // ---- ESM integrity event (dual rail) ------------------------------------
    output logic                  rchk_par_fault,
    output logic                  rchk_par_fault_n
);

    //=========================================================================
    // Address map (byte offsets; addr[1:0] assumed 00 - word aligned by the
    // upstream apb2mbus bridge)
    //=========================================================================
    localparam logic [7:0] OFF_ID     = 8'h00;   // RO
    localparam logic [7:0] OFF_CTRL   = 8'h04;   // keyed: [0]EN [1]FI
    localparam logic [7:0] OFF_STAT   = 8'h08;   // RO live status
    localparam logic [7:0] OFF_EV     = 8'h0C;   // W1C [0]DA [1]DB [2]ERR
    localparam logic [7:0] OFF_REGPAR = 8'h10;   // W1C parity/protection status
    localparam logic [7:0] OFF_REGST  = 8'h14;   // keyed: parity self-test

    localparam logic [31:0] ID_VAL = 32'h5243_0001;   // "RC" v1

    // STAT readback layout (== u_statimg word):
    //   [0]=viol [1]=div_a [2]=div_b [3]=cnt_full [8:4]=cnt [9]=EN [10]=FI

    //=========================================================================
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    // 本地 sticky 锁存 + 反相冗余 (heal-to-SET)
    //=========================================================================
    typedef struct packed {
        logic [2:0] lst_q;        // [0]perr_cmd [1]par_selftest [2]reg_prot ({18,17,16} lanes)
        logic [2:0] lst_qn;       // inverted duplicates
    } mb_reg_t;

    localparam mb_reg_t MB_REG_RST = '{
        lst_q  : 3'b000,
        lst_qn : 3'b111
    };

    mb_reg_t r_mb;
    mb_reg_t rin_mb;

    //=========================================================================
    // mbus command in-flight parity + selection + write classification
    //=========================================================================
    logic sel;
    assign sel = ce && (addr[15:8] == IDX[7:0]);
    logic par_ok;
    assign par_ok = (^{addr, wr, wdata}) == par;
    logic par_bad;
    assign par_bad = ce && !par_ok;               // ALL commands checked
    logic wr_ok;
    assign wr_ok = sel && wr && par_ok;           // good-command write strobe
    logic [7:0] off;
    assign off = addr[7:0];

    logic key_ok;
    assign key_ok = (wdata[31:28] == WKEY);

    logic wr_ro;
    assign wr_ro = wr_ok && ((off == OFF_ID) || (off == OFF_STAT));
    logic wr_known;
    assign wr_known = wr_ok && ((off == OFF_CTRL) || (off == OFF_EV)
                                || (off == OFF_REGPAR) || (off == OFF_REGST));
    logic wr_keyed;
    assign wr_keyed = wr_ok && ((off == OFF_CTRL) || (off == OFF_REGST));
    logic keyed_bad;
    assign keyed_bad = wr_keyed && !key_ok;

    logic regprot_ev;
    assign regprot_ev = wr_ro || (wr_ok && !wr_known && !wr_ro) || keyed_bad;

    logic regpar_w1c;
    assign regpar_w1c = wr_ok && (off == OFF_REGPAR);
    logic regst_wr;
    assign regst_wr = wr_ok && (off == OFF_REGST) && key_ok;
    logic regst_st;
    assign regst_st = regst_wr && wdata[8] && (wdata[4:0] <= 5'd2);
    logic parst_ev;
    assign parst_ev = regst_wr && wdata[9];

    //=========================================================================
    // local sticky latches (set | heal-to-SET, per-bit W1C). Inverted
    // duplicates: an SEU-cleared bit self-heals back to SET. Per-bit rail
    // mismatch (bitwise XNOR) - a vector "!=" would collapse to a scalar
    // compare and only ever heal bit 0.
    //=========================================================================
    logic [2:0] lst_dup;
    assign lst_dup = (r_mb.lst_qn ~^ r_mb.lst_q);

    logic [2:0] lst_set;
    assign lst_set = {regprot_ev, parst_ev, par_bad};   // {18,17,16} lanes
    logic [2:0] lst_clr;
    assign lst_clr = {(regpar_w1c && wdata[18]),   // REG_PROT
                      (regpar_w1c && wdata[17]),   // PAR_SELFTEST
                      (regpar_w1c && wdata[16])};  // PERR_CMD
    logic [2:0] lst_nxt;
    assign lst_nxt = (r_mb.lst_q | lst_set | lst_dup) & ~lst_clr;

    //=========================================================================
    // config store strobe (keyed; a bad key rejects the whole write)
    //=========================================================================
    logic  sto_ctrl;
    assign sto_ctrl = wr_ok && (off == OFF_CTRL) && key_ok;

    //=========================================================================
    // reg_wrap instances (mbus domain). PERR group index = REGPAR bit 4+k.
    //=========================================================================
    logic [2:0] perr_w;      // group flt vector
    logic [1:0] ctrl_r;      // {FI, EN}
    logic [2:0] evimg_r;
    logic [10:0] statimg_r;

    reg_wrap #(
        .W     (2        ),
        .RESET (CTRL_RST )
    ) u_ctrl (
        .clk          (mbus_clk                        ),
        .rst_n        (mbus_rstn                       ),
        .wdata        (wdata[1:0]                      ),
        .wr           (sto_ctrl                        ),
        .rdata        (ctrl_r                          ),
        .selftest_key (regst_st && (wdata[4:0] == 5'd0)),
        .flt          (perr_w[0]                       ),
        .flt_w1c      (regpar_w1c && wdata[4]          )
    );

    // image wraps follow every cycle: an injected parity error self-restores
    reg_wrap #(
        .W     ( 3 ),
        .RESET ('0 )
    ) u_evimg (
        .clk          (mbus_clk                        ),
        .rst_n        (mbus_rstn                       ),
        .wdata        ({sts_ev_err, sts_ev_db, sts_ev_da} ),
        .wr           (1'b1                            ),
        .rdata        (evimg_r                         ),
        .selftest_key (regst_st && (wdata[4:0] == 5'd1)),
        .flt          (perr_w[1]                       ),
        .flt_w1c      (regpar_w1c && wdata[5]          )
    );

    reg_wrap #(
        .W     (11 ),
        .RESET ('0 )
    ) u_statimg (
        .clk          (mbus_clk                          ),
        .rst_n        (mbus_rstn                         ),
        .wdata        ({ctrl_r, sts_cnt, sts_cnt_full,
                        sts_div_b, sts_div_a, sts_viol}  ),
        .wr           (1'b1                              ),
        .rdata        (statimg_r                         ),
        .selftest_key (regst_st && (wdata[4:0] == 5'd2)  ),
        .flt          (perr_w[2]                         ),
        .flt_w1c      (regpar_w1c && wdata[6]            )
    );

    //=========================================================================
    // outputs
    //=========================================================================
    assign cfg_en = ctrl_r[0];
    assign cfg_fi = ctrl_r[1];

    assign err_w1c   = wr_ok && (off == OFF_EV) && wdata[2];
    assign ev_da_w1c = wr_ok && (off == OFF_EV) && wdata[0];
    assign ev_db_w1c = wr_ok && (off == OFF_EV) && wdata[1];

    // integrity event pin: wrap faults + PERR_CMD + PAR_SELFTEST; REG_PROT is
    // a write-protection protocol event (SW-caused) and stays REGPAR-only
    assign rchk_par_fault   = (|perr_w) || r_mb.lst_q[0] || r_mb.lst_q[1];
    assign rchk_par_fault_n =  ~rchk_par_fault;

    //=========================================================================
    // read mux (combinational; bad-parity command reads back 0)
    //=========================================================================
    logic [31:0] rdata_mux;
    always_comb begin
        rdata_mux = 32'h0;
        case (off)
            OFF_ID:     rdata_mux = ID_VAL;
            OFF_CTRL:   rdata_mux = {30'b0, ctrl_r};
            OFF_STAT:   rdata_mux = {21'b0, statimg_r};
            OFF_EV:     rdata_mux = {29'b0, evimg_r};
            OFF_REGPAR: rdata_mux = {13'b0, r_mb.lst_q, 9'b0, perr_w,
                                     2'b00, rchk_par_fault_n, rchk_par_fault};
            OFF_REGST:  rdata_mux = 32'h0;
            default:    rdata_mux = 32'h0;
        endcase
    end
    assign rdata = (sel && par_ok) ? rdata_mux : 32'h0;

    //=========================================================================
    // mbus 域组合进程: 本地 sticky 下一拍值 (默认保持)
    //=========================================================================
    always_comb begin : mb_comb
        mb_reg_t v_mb;

        v_mb = r_mb;

        v_mb.lst_q  =  lst_nxt;
        v_mb.lst_qn = ~lst_nxt;

        rin_mb = v_mb;
    end

    //=========================================================================
    // mbus 域时序进程: 只做复位装载与 r_mb <= rin_mb
    //=========================================================================
    always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : mb_seq
        if (!mbus_rstn) begin
            r_mb <= MB_REG_RST;
        end else begin
            r_mb <= rin_mb;
        end
    end

endmodule
