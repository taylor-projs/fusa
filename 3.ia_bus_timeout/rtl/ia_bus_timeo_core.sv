`timescale 1ns/1ps
//============================================================================
// Interconnect Timeout Monitor - independent mbus leaf IP (single AXI4 port)
// (ref: TI Hercules RM57Lx TRM SPNU562A ch.3 SCM / ch.4.3.5)
//
// 两级独立 IP 架构 (集成范例: 2.parity edc_core/edc_top):
//   本模块 = ia_bus_timeo_mon (单口 AXI4 超时监视核, 纯观测 tap) +
//            ia_bus_timeo_regfile (SCM 寄存器面, mbus leaf, CDC 内置)
//   打包成一个 mbus 接口的叶端 IP —— 系统集成时每个被监视的 AXI4
//   接口例化一份 (addr[15:8]=IDX 实例号), fault sticky 供 CPU 查询;
//   各实例的 ESM 双轨接 ia_bus_timeo_top 聚合器汇总送 ESM。
//
//   结构:
//     mbus_clk 域 : ia_bus_timeo_regfile (SCM 寄存器模型, mbus leaf)
//     axi_clk 域 : ia_bus_timeo_mon (超时监视 + FuSa 完整性层)
//     CDC        : 全部在 regfile 内 (mbus->aclk 单笔 toggle 握手送
//                  config/W1C/action; aclk->mbus 2FF 同步回状态)
//
//   ESM 双轨输出 (mbus_clk 域, 来自 regfile 的 rail_s2 寄存器面镜像,
//   奇偶保护存储 —— 聚合器同域直采, 不再另起同步链):
//     esm_err / esm_err_n      真实总线超时 (err_event 电平)
//     esm_fault / esm_fault_n  监视器完整性故障 (fu_fault 粘滞)
//     reg_par_fault / _n       寄存器面奇偶故障 (粘滞)
//   (路由到不同 ESM 组: 坏掉的监视器绝不与真实超时不可区分)
//
//   复位: mbus_rstn (mbus_clk 域) 与 axi_rstn (axi_clk 域) 必须在系统
//   级同时断言 (CDC 握手对齐, 见 regfile 头注释); 均为异步低有效;
//   mon 内部 rst_sync 做异步断言/同步释放, scan_mode 逐层拉到本顶层
//   (DFT 旁路, 8.reset_checker 惯例)。
//============================================================================
module ia_bus_timeo_core #(
    parameter int          OTD_MAX        = 8,       // outstanding saturation
    parameter int          OTD_W          = $clog2(OTD_MAX+1),
    parameter logic [15:0] REQ2ACCEPT_RST = 16'h000F, // SCMTHRESH0 reset
    parameter logic [15:0] REQ2RESP_RST   = 16'h00FF, // SCMTHRESH1 reset
    parameter int          IDX            = 0        // mbus instance index
)(
    // ---- mbus leaf (mbus_clk domain) ---------------------------------------
    input  logic            mbus_clk,
    input  logic            mbus_rstn,      // async, active-low
    input  logic            ce,             // single-cycle chip enable
    input  logic            wr,             // 1=write, 0=read
    input  logic [15:0]     addr,           // [15:8]=instance, [7:0]=offset
    input  logic [31:0]     wdata,
    input  logic            par,            // ^({addr, wr, wdata})
    output logic [31:0]     rdata,          // combinational, zero-wait
    output logic            rpar,           // ^rdata 回程偶校验 (mbus leaf 契约)

    // ---- monitor clock / reset ---------------------------------------------
    input  logic            axi_clk,
    input  logic            axi_rstn,       // async, active-low
    input  logic            scan_mode,      // DFT: bypass monitor reset sync

    // ---- AXI4 observation only (axi_clk domain, scalar taps) ---------------
    input  logic            axi_arvalid,    // read address request
    input  logic            axi_arready,    // read address accepted
    input  logic            axi_rvalid,     // read data beat (slave)
    input  logic            axi_rready,     // read data accepted (master)
    input  logic            axi_rlast,      // last beat of the burst
    input  logic            axi_awvalid,    // write address request
    input  logic            axi_awready,    // write address accepted
    input  logic            axi_wvalid,     // write data beat (master)
    input  logic            axi_wready,     // write data accepted (slave)
    input  logic            axi_wlast,      // last write data beat
    input  logic            axi_bvalid,     // write response (slave)
    input  logic            axi_bready,     // write response accepted (master)

    // ---- ESM outputs (mbus_clk domain, dual rail) ---------------------------
    output logic            esm_err,        // real bus timeout (level)
    output logic            esm_err_n,
    output logic            esm_fault,      // monitor integrity fault (sticky)
    output logic            esm_fault_n,
    output logic            reg_par_fault,  // register parity fault (sticky)
    output logic            reg_par_fault_n
);

    localparam int NUM_IA = 2;      // streams: RD bit0 / WR bit1

    // ---- aclk-domain interconnect between regfile and monitor --------------
    logic              cfg_wr;
    logic [3:0]        cfg_key, cfg_ena;
    logic [15:0]       cfg_req2accept_max, cfg_req2resp_max;
    logic              to_clear, selftest_key, fu_selftest;
    logic [NUM_IA-1:0] r2a_w1c, r2r_w1c;
    logic              fu_w1c;

    logic [NUM_IA-1:0]        r2a_err_status, r2r_err_status, ia_active;
    logic [NUM_IA*OTD_W-1:0]  otd;
    logic [15:0]              thr_rd_r2a, thr_rd_r2r;
    logic [3:0]               ena_rd;
    logic                     err_event_i, err_event_n_i;
    logic                     fu_fault_i, fu_fault_n_i;
    logic [6:0]               fu_src;

    //--------------------------------------------------------------------------
    // Register file (mbus_clk <-> axi_clk CDC inside)
    //--------------------------------------------------------------------------
    ia_bus_timeo_regfile #(
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  ),
        .IDX           (IDX           )
    ) u_ia_bus_timeo_regfile (
        .mbus_clk          (mbus_clk          ),
        .mbus_rstn         (mbus_rstn         ),
        .ce                (ce                ),
        .wr                (wr                ),
        .addr              (addr              ),
        .wdata             (wdata             ),
        .par               (par               ),
        .rdata             (rdata             ),
        .rpar              (rpar              ),

        .aclk              (axi_clk           ),
        .rstn              (axi_rstn          ),

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

        .r2a_err_status    (r2a_err_status    ),
        .r2r_err_status    (r2r_err_status    ),
        .ia_active         (ia_active         ),
        .otd               (otd               ),
        .thr_rd_r2a        (thr_rd_r2a        ),
        .thr_rd_r2r        (thr_rd_r2r        ),
        .ena_rd            (ena_rd            ),
        .err_event         (err_event_i       ),
        .err_event_n       (err_event_n_i     ),
        .fu_fault          (fu_fault_i        ),
        .fu_fault_n        (fu_fault_n_i      ),
        .fu_src            (fu_src            ),

        .reg_par_fault     (reg_par_fault     ),
        .reg_par_fault_n   (reg_par_fault_n   ),

        .esm_err           (esm_err           ),
        .esm_err_n         (esm_err_n         ),
        .esm_fault         (esm_fault         ),
        .esm_fault_n       (esm_fault_n       )
    );

    //--------------------------------------------------------------------------
    // Timeout monitor (axi_clk domain)
    //--------------------------------------------------------------------------
    ia_bus_timeo_mon #(
        .OTD_MAX       (OTD_MAX       ),
        .OTD_W         (OTD_W         ),
        .REQ2ACCEPT_RST(REQ2ACCEPT_RST),
        .REQ2RESP_RST  (REQ2RESP_RST  )
    ) u_ia_bus_timeo_mon (
        .clk               (axi_clk           ),
        .rstn              (axi_rstn          ),
        .scan_mode         (scan_mode         ),

        .axi_arvalid       (axi_arvalid       ),
        .axi_arready       (axi_arready       ),
        .axi_rvalid        (axi_rvalid        ),
        .axi_rready        (axi_rready        ),
        .axi_rlast         (axi_rlast         ),
        .axi_awvalid       (axi_awvalid       ),
        .axi_awready       (axi_awready       ),
        .axi_wvalid        (axi_wvalid        ),
        .axi_wready        (axi_wready        ),
        .axi_wlast         (axi_wlast         ),
        .axi_bvalid        (axi_bvalid        ),
        .axi_bready        (axi_bready        ),

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

        .r2a_err_status    (r2a_err_status    ),
        .r2r_err_status    (r2r_err_status    ),
        .ia_active         (ia_active         ),
        .otd               (otd               ),
        .thr_rd_r2a        (thr_rd_r2a        ),
        .thr_rd_r2r        (thr_rd_r2r        ),
        .err_event         (err_event_i       ),
        .err_event_n       (err_event_n_i     ),
        .ena_rd            (ena_rd            ),
        .fu_fault          (fu_fault_i        ),
        .fu_fault_n        (fu_fault_n_i      ),
        .fu_src            (fu_src            )
    );

endmodule
