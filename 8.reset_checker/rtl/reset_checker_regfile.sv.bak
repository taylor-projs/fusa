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
// REGISTER MAP (byte offsets; house standard layout - ID last, CFG_REGST
// second-to-last, STA_PAR third-to-last; see 10.dup_ctrl_regfile header):
//   0x04 CTRL    RW+key  [3:0] MODE one-hot (key = wdata[31:28] WKEY)
//   0x08 STAT    RO      live status image ([0]viol [1]div_a [2]div_b
//                        [3]cnt_full [8:4]cnt [9]EN [10]FI)
//   0x0C EV      RW1C    [0]DA [1]DB [2]ERR event stickies
//   0x10 STA_PAR RW1C/R  register parity status:
//     [0]   PAR_FAULT level (W1C clears ONLY the selftest latch)
//     [1]   PAR_FAULT_N (RO inverted rail; idle readback 0x2)
//     [5:2] PERR3..PERR0 (W1C): each bit clears its group sticky;
//           group = 2 + bit: 0 CTRL / 1 EV image / 2 STAT image / 3 CMD
//     [6]   REG_PROT (W1C, design-local write-protection sticky)
//   0x14 CFG_REGST W+key register parity selftest control (reads 0):
//     [3:0]  key, must be 4'b1010, else the whole write is rejected
//            (and latches REG_PROT like any keyed-register violation)
//     [4]    REG_SELFTEST pulse: parity injection into the [11:8] REGSEL
//            selected group (0..3, >3 silently ignored)
//     [5]    PAR_SELFTEST pulse: sets ONLY the selftest latch
//            ("fault without a source" ESM signature)
//   0xFC ID      RO      32'h5243_0001 ("RC" v1)
//
// REGISTER PARITY (FuSa, house standard): every SW-visible register is a
// reg_wrap instance (storage + even parity + selftest_key injection + own
// sticky flt with inverted duplicate) - the check lives with the storage:
//   PERR group (STA_PAR bit = 2 + group, 4 groups):
//     0  CTRL wrap (MODE[3:0])            3  CMD wrap (W=1, command
//     1  EV image wrap                       in-flight parity sticky body)
//     2  STAT image wrap
//   Image wraps (1/2) follow wr=1: an injected parity error self-restores
//   next cycle. The config wrap (0) holds: restore = rewrite the register
//   (the documented last step of the self-test flow). The CMD wrap (3)
//   self-restores on its own W1C (that write IS a wrap rewrite).
//
// CTRL MODE CODING (FuSa): the EN/FI configuration is a 4-bit ONE-HOT mode
// field, not two independent bits - the dangerous (EN=0, FI=1) combination
// (injection with the alarm masked = silent corruption) is structurally
// unrepresentable. One-hot also self-checks: a single bit flip off any
// legal code lands on an illegal code, so decode-level corruption is
// detectable (storage-level is the wrap parity - complementary layers):
//   4'b0001 NORMAL  EN=1 FI=0 (monitor on)      <- reset, fail-safe
//   4'b0010 INJECT  EN=1 FI=1 (self-test)
//   4'b0100 OFF     EN=0 FI=0 (masked, quiet)
//   others  illegal: write rejected + REG_PROT; decode backstop maps any
//   unreachable stored code to fail-safe (EN=1, FI=0 - never injects)
//
// WRITE PROTECTION: CTRL is keyed by wdata[31:28]==WKEY, CFG_REGST by the
// house key wdata[3:0]==4'b1010; a bad key on either, a write to RO
// (ID/STAT), an unknown offset or an illegal MODE value latches REG_PROT
// (STA_PAR[6], W1C) and rejects the write entirely.
//============================================================================
module reset_checker_regfile #(
    parameter logic [3:0]  WKEY     = 4'h5,     // key in wdata[31:28]
    parameter logic [3:0]  CTRL_RST = 4'b0001,  // MODE=NORMAL (EN=1 FI=0,
                                                // fail-safe on; one-hot)
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
    output logic                  rpar,          // ^rdata read-path even parity (mbus leaf contract)

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
    localparam logic [7:0] OFF_ID     = 8'hFC;   // RO (last: ID stays at tail)
    localparam logic [7:0] OFF_CTRL   = 8'h04;   // keyed: [3:0] MODE one-hot
    localparam logic [7:0] OFF_STAT   = 8'h08;   // RO live status
    localparam logic [7:0] OFF_EV     = 8'h0C;   // W1C [0]DA [1]DB [2]ERR
    localparam logic [7:0] OFF_STAPAR = 8'h10;   // W1C/R parity+protection status
    localparam logic [7:0] OFF_REGST  = 8'h14;   // keyed 1010: parity self-test

    localparam logic [31:0] ID_VAL = 32'h5243_0001;   // "RC" v1

    // CTRL MODE one-hot codes (see header): decode fail-safe for any
    // unreachable stored code (SEU backstop) - never injects, monitor on
    localparam logic [3:0] MODE_NORM = 4'b0001;   // EN=1 FI=0
    localparam logic [3:0] MODE_INJ  = 4'b0010;   // EN=1 FI=1
    localparam logic [3:0] MODE_OFF  = 4'b0100;   // EN=0 FI=0

    // STAT readback layout (== u_statimg word):
    //   [0]=viol [1]=div_a [2]=div_b [3]=cnt_full [8:4]=cnt [9]=EN [10]=FI

    //=========================================================================
    // 寄存器记录 (GRLIB two-process: r = 现态, rin = 输入, v = 次态)
    // 本地 sticky 锁存 + 反相冗余 (heal-to-SET)
    //=========================================================================
    typedef struct packed {
        logic [1:0] lst_q;        // [0]par_selftest [1]reg_prot (STA_PAR {0,6} lanes)
        logic [1:0] lst_qn;       // inverted duplicates
    } mb_reg_t;

    localparam mb_reg_t MB_REG_RST = '{
        lst_q  : 2'b00,
        lst_qn : 2'b11
    };

    mb_reg_t r_mb;
    mb_reg_t rin_mb;

    //=========================================================================
    // mbus command in-flight parity + selection + write classification
    //=========================================================================
    logic  sel;
    assign sel = ce && (addr[15:8] == IDX[7:0]);

    logic  par_ok;
    logic  par_bad;
    assign par_ok = (^{addr, wr, wdata}) == par;
    assign par_bad = ce && !par_ok;              // ALL commands checked
    // (house standard: the broadcast corruption is detected by every leaf,
    //  selected or not - int_prot/dup_ctrl/cmm same idiom)

    logic  wr_ok;
    assign wr_ok = sel && wr && par_ok;           // good-command write strobe
    logic  [7:0] offset;
    assign offset = addr[7:0];

    logic  key_ok;
    assign key_ok = sel & (wdata[31:28] == WKEY); // ! only selected cmd check.

    // read-only registers.
    logic  wr_ro;
    assign wr_ro = wr_ok && ((offset == OFF_ID) || (offset == OFF_STAT));
    logic  wr_known;
    assign wr_known = wr_ok && ((offset == OFF_CTRL  ) || (offset == OFF_EV    )
                             || (offset == OFF_STAPAR) || (offset == OFF_REGST ));
    logic  wr_keyed;
    assign wr_keyed = wr_ok && (offset == OFF_CTRL);

    // key err when write op (CTRL: WKEY at [31:28])
    logic  keyed_bad;
    assign keyed_bad = wr_keyed && !key_ok;

    // REGST house key ([3:0]=1010) violation: same protection event class
    logic  regst_key_bad;
    assign regst_key_bad = wr_ok && (offset == OFF_REGST)
                        && (wdata[3:0] != 4'b1010);

    // illegal MODE value (keyed, good key): rejected + REG_PROT, exactly
    // like a write-protection violation - the SW-caused coded-field fault
    logic  mode_ok;
    assign mode_ok  = (wdata[3:0] == MODE_NORM) || (wdata[3:0] == MODE_INJ)
                   || (wdata[3:0] == MODE_OFF );
    logic  mode_bad;
    assign mode_bad = wr_ok && (offset == OFF_CTRL) && key_ok && !mode_ok;

    logic  regprot_ev; // error collection
    // 1. write the read-only register.
    // 2. write the write rejected register.
    // 3. write the registers that key is not correct (CTRL WKEY / REGST 1010).
    // 4. control register write the illegal mode.
    assign regprot_ev = wr_ro || (wr_ok && !wr_known && !wr_ro)
                     || keyed_bad || regst_key_bad || mode_bad;

    logic  stapar_w1c;
    assign stapar_w1c = wr_ok && (offset == OFF_STAPAR);

    logic  regst_wr;
    logic  regst_st;
    logic  parst_ev;
    logic [3:0] regsel;
    assign regst_wr = wr_ok && (offset == OFF_REGST) && (wdata[3:0] == 4'b1010);
    assign regsel   = wdata[11:8];
    assign regst_st = regst_wr && wdata[4] && (regsel <= 4'd3); // 0..3, else ignore
    assign parst_ev = regst_wr && wdata[5];

    //=========================================================================
    // local sticky latches (set | heal-to-SET, per-bit W1C). Inverted
    // duplicates: an SEU-cleared bit self-heals back to SET. Per-bit rail
    // mismatch (bitwise XNOR) - a vector "!=" would collapse to a scalar
    // compare and only ever heal bit 0.
    //=========================================================================
    logic  [1:0] lst_dup;
    assign lst_dup = (r_mb.lst_qn ~^ r_mb.lst_q);

    logic  [1:0] lst_set;
    logic  [1:0] lst_clr;
    assign lst_set = {regprot_ev, parst_ev};          // {REG_PROT[6], PAR_SELFTEST[0]}
    assign lst_clr = {(stapar_w1c && wdata[6]),      // REG_PROT
                      (stapar_w1c && wdata[0])};      // PAR_SELFTEST latch (bit0)
    logic  [1:0] lst_nxt;
    assign lst_nxt = (r_mb.lst_q | lst_set | lst_dup) & ~lst_clr;

    //=========================================================================
    // config store strobe (keyed AND legal mode; a bad key or an illegal
    // MODE value rejects the whole write)
    //=========================================================================
    logic  sto_ctrl;
    assign sto_ctrl = wr_ok && (offset == OFF_CTRL) && key_ok && mode_ok;

    //=========================================================================
    // reg_wrap instances (mbus domain). PERR group = STA_PAR bit - 2.
    //=========================================================================
    logic [ 3:0] perr_w   ;      // group flt vector ([3] = cmd wrap)
    logic        cmd_r    ;      // PERR_CMD sticky body (cmd wrap readback)
    logic [ 3:0] ctrl_r   ;      // MODE one-hot storage
    logic [ 2:0] evimg_r  ;
    logic [10:0] statimg_r;

    reg_wrap #(
        .W    (4       ),
        .RESET(CTRL_RST)
    ) u_ctrl (
        .clk         (mbus_clk                    ),
        .rst_n       (mbus_rstn                   ),
        .wdata       (wdata[3:0]                  ),
        .wr          (sto_ctrl                    ),
        .rdata       (ctrl_r                      ),
        .selftest_key(regst_st && (regsel == 4'd0)),
        .flt         (perr_w[0]                   ),
        .flt_w1c     (stapar_w1c && wdata[2]      )
    );

    // image wraps follow every cycle: an injected parity error self-restores
    reg_wrap #(
        .W    (3 ),
        .RESET('0)
    ) u_evimg (
        .clk         (mbus_clk                          ),
        .rst_n       (mbus_rstn                         ),
        .wdata       ({sts_ev_err, sts_ev_db, sts_ev_da}),
        .wr          (1'b1                              ),
        .rdata       (evimg_r                           ),
        .selftest_key(regst_st && (regsel == 4'd1)      ),
        .flt         (perr_w[1]                         ),
        .flt_w1c     (stapar_w1c && wdata[3]            )
    );

    reg_wrap #(
        .W    (11),
        .RESET('0)
    ) u_statimg (
        .clk         (mbus_clk                                                               ),
        .rst_n       (mbus_rstn                                                              ),
        .wdata       ({cfg_fi, cfg_en, sts_cnt, sts_cnt_full, sts_div_b, sts_div_a, sts_viol}),
        .wr          (1'b1                                                                   ),
        .rdata       (statimg_r                                                              ),
        .selftest_key(regst_st && (regsel == 4'd2)                                           ),
        .flt         (perr_w[2]                                                              ),
        .flt_w1c     (stapar_w1c && wdata[4]                                                 )
    );

    // command in-flight parity sticky body (PERR3): par_bad sets, its own
    // W1C bit (STA_PAR[5]) is a wrap rewrite that recomputes the parity
    reg_wrap #(
        .W    (1   ),
        .RESET(1'b0)
    ) u_w_cmd (
        .clk         (mbus_clk                           ),
        .rst_n       (mbus_rstn                          ),
        .wdata       (par_bad                            ),
        .wr          (par_bad || (stapar_w1c && wdata[5])),
        .rdata       (cmd_r                              ),
        .selftest_key(regst_st && (regsel == 4'd3)       ),
        .flt         (perr_w[3]                          ),
        .flt_w1c     (stapar_w1c && wdata[5]             )
    );

    //=========================================================================
    // outputs
    //=========================================================================
    // MODE decode: fail-safe for any unreachable stored code (SEU
    // backstop) - OFF is the only code that disables the monitor, INJECT
    // the only one that injects; an illegal code keeps EN on and FI off
    assign cfg_en = (ctrl_r != MODE_OFF);
    assign cfg_fi = (ctrl_r == MODE_INJ);

    assign ev_da_w1c = wr_ok && (offset == OFF_EV) && wdata[0];
    assign ev_db_w1c = wr_ok && (offset == OFF_EV) && wdata[1];
    assign err_w1c   = wr_ok && (offset == OFF_EV) && wdata[2];

    // integrity event pin: wrap faults (incl. cmd) + cmd sticky + the
    // PAR_SELFTEST latch; REG_PROT is a write-protection protocol event
    // (SW-caused) and stays STA_PAR[6]-only (not on the fault rail)
    assign rchk_par_fault   = (|perr_w) || cmd_r || r_mb.lst_q[0];
    assign rchk_par_fault_n =  ~rchk_par_fault;

    //=========================================================================
    // read mux (combinational; bad-parity command reads back 0)
    //=========================================================================
    logic [31:0] rdata_mux;
    always_comb begin
        rdata_mux = 32'h0;
        case (offset)
            OFF_ID:     rdata_mux = ID_VAL;
            OFF_CTRL:   rdata_mux = {28'b0, ctrl_r};
            OFF_STAT:   rdata_mux = {21'b0, statimg_r};
            OFF_EV:     rdata_mux = {29'b0, evimg_r};
            OFF_STAPAR: rdata_mux = {25'b0,
                                     r_mb.lst_q[1],              // [6] REG_PROT
                                     perr_w[3] | cmd_r,           // [5] PERR3 CMD
                                     perr_w[2:0],                 // [4:2] PERR2..0
                                     rchk_par_fault_n,            // [1] rail_n
                                     rchk_par_fault};             // [0] PAR_FAULT
            OFF_REGST:  rdata_mux = 32'h0;
            default:    rdata_mux = 32'h0;
        endcase
    end
    assign rdata = (sel && par_ok) ? rdata_mux : 32'h0;
    // rpar leaf contract: unconditional combinational ^rdata (unselected
    // reads return 0 -> rpar=0, OR-merged net needs no extra enable;
    // checked by apb2mbus at the ce beat on reads)
    assign rpar = ^rdata;

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
