// ============================================================================
// tb_equiv_regfile: edc_regfile 与 edc_regfile_leons 的逐拍等价性验证
//
//   两个模块端口完全一致, 施加相同随机激励, 每个 posedge 比较全部输出.
//   任一输出不一致即报错, 验证 struct 风格重构不改变功能/面积.
// ============================================================================
`timescale 1ns/1ps

module tb_equiv_regfile;
   parameter integer NSITES = 18;
   parameter integer IDX    = 0;

   reg         clk = 0;
   reg         rstn = 0;
   reg         ce, wr, ack;
   reg  [15:0] addr;
   reg  [31:0] wdata;
   reg  [6:0]  par_flt_axi;
   reg  [NSITES-1:0] err_axi, fault_axi;
   reg         irq_axi;

   always #10 clk = ~clk;

   // ---------------- 参考 (原设计) ----------------
   wire [31:0]           a_rdata;
   wire [NSITES*4-1:0]   a_cfg_en;
   wire [NSITES-1:0]     a_cfg_force, a_cfg_irqen, a_clr_mask;
   wire [NSITES*64-1:0]  a_cfg_pos;
   wire                  a_cmd_t;
   wire [13:0]           a_par_w1c_mask;
   wire                  a_par_st_req;
   wire [3:0]            a_par_st_sel;
   wire                  a_par_pay;
   wire                  a_esm_err, a_esm_err_n, a_esm_fault, a_esm_fault_n;
   wire                  a_irq, a_reg_par_fault, a_reg_par_fault_n;

   edc_regfile #(.IDX(IDX), .NSITES(NSITES)) u_ref (
      .mbus_clk       (clk               ),
      .mbus_rstn      (rstn              ),
      .ce             (ce                ),
      .wr             (wr                ),
      .addr           (addr              ),
      .wdata          (wdata             ),
      .par            (^{addr, wr, wdata}),  // 命令在途奇偶 (不接则写全被 par_ok 门控)
      .rdata          (a_rdata           ),
      .cfg_en         (a_cfg_en          ),
      .cfg_force      (a_cfg_force       ),
      .cfg_irqen      (a_cfg_irqen       ),
      .cfg_pos        (a_cfg_pos         ),
      .clr_mask       (a_clr_mask        ),
      .cmd_t          (a_cmd_t           ),
      .ack            (ack               ),
      .par_flt_axi    (par_flt_axi       ),
      .par_w1c_mask   (a_par_w1c_mask    ),
      .par_st_req     (a_par_st_req      ),
      .par_st_sel     (a_par_st_sel      ),
      .par_pay        (a_par_pay         ),
      .err_axi        (err_axi           ),
      .fault_axi      (fault_axi         ),
      .irq_axi        (irq_axi           ),
      .esm_err        (a_esm_err         ),
      .esm_err_n      (a_esm_err_n       ),
      .esm_fault      (a_esm_fault       ),
      .esm_fault_n    (a_esm_fault_n     ),
      .irq            (a_irq             ),
      .reg_par_fault  (a_reg_par_fault   ),
      .reg_par_fault_n(a_reg_par_fault_n )
   );

   // ---------------- 被测 (struct 风格重构) ----------------
   wire [31:0]           b_rdata;
   wire [NSITES*4-1:0]   b_cfg_en;
   wire [NSITES-1:0]     b_cfg_force, b_cfg_irqen, b_clr_mask;
   wire [NSITES*64-1:0]  b_cfg_pos;
   wire                  b_cmd_t;
   wire [13:0]           b_par_w1c_mask;
   wire                  b_par_st_req;
   wire [3:0]            b_par_st_sel;
   wire                  b_par_pay;
   wire                  b_esm_err, b_esm_err_n, b_esm_fault, b_esm_fault_n;
   wire                  b_irq, b_reg_par_fault, b_reg_par_fault_n;

   edc_regfile_leons #(.IDX(IDX), .NSITES(NSITES)) u_dut (
      .mbus_clk       (clk              ),
      .mbus_rstn      (rstn             ),
      .ce             (ce               ),
      .wr             (wr               ),
      .addr           (addr             ),
      .wdata          (wdata            ),
      .rdata          (b_rdata          ),
      .cfg_en         (b_cfg_en         ),
      .cfg_force      (b_cfg_force      ),
      .cfg_irqen      (b_cfg_irqen      ),
      .cfg_pos        (b_cfg_pos        ),
      .clr_mask       (b_clr_mask       ),
      .cmd_t          (b_cmd_t          ),
      .ack            (ack              ),
      .par_flt_axi    (par_flt_axi      ),
      .par_w1c_mask   (b_par_w1c_mask   ),
      .par_st_req     (b_par_st_req     ),
      .par_st_sel     (b_par_st_sel     ),
      .par_pay        (b_par_pay        ),
      .err_axi        (err_axi          ),
      .fault_axi      (fault_axi        ),
      .irq_axi        (irq_axi          ),
      .esm_err        (b_esm_err        ),
      .esm_err_n      (b_esm_err_n      ),
      .esm_fault      (b_esm_fault      ),
      .esm_fault_n    (b_esm_fault_n    ),
      .irq            (b_irq            ),
      .reg_par_fault  (b_reg_par_fault  ),
      .reg_par_fault_n(b_reg_par_fault_n)
   );

   // ---------------- 逐拍比较 ----------------
   integer errors = 0;
   integer cyc = 0;
   integer seed = 12345;

   task chk(input ok, input [8*40-1:0] name);
      begin
         if (!ok) begin
            errors = errors + 1;
            $display("MISMATCH @%0t: %0s", $time, name);
         end
      end
   endtask

   always @(posedge clk) begin
      if (!rstn) begin
         cyc <= 0;
      end else begin
         cyc <= cyc + 1;
         // 组合输出比较 (所有寄存器输出)
         chk(a_rdata         === b_rdata,         "rdata");
         chk(a_cfg_en        === b_cfg_en,        "cfg_en");
         chk(a_cfg_force     === b_cfg_force,     "cfg_force");
         chk(a_cfg_irqen     === b_cfg_irqen,     "cfg_irqen");
         chk(a_cfg_pos       === b_cfg_pos,       "cfg_pos");
         chk(a_clr_mask      === b_clr_mask,      "clr_mask");
         chk(a_cmd_t         === b_cmd_t,         "cmd_t");
         chk(a_par_w1c_mask  === b_par_w1c_mask,  "par_w1c_mask");
         chk(a_par_st_req    === b_par_st_req,    "par_st_req");
         chk(a_par_st_sel    === b_par_st_sel,    "par_st_sel");
         chk(a_par_pay       === b_par_pay,       "par_pay");
         chk(a_esm_err       === b_esm_err,       "esm_err");
         chk(a_esm_err_n     === b_esm_err_n,     "esm_err_n");
         chk(a_esm_fault     === b_esm_fault,     "esm_fault");
         chk(a_esm_fault_n   === b_esm_fault_n,   "esm_fault_n");
         chk(a_irq           === b_irq,           "irq");
         chk(a_reg_par_fault === b_reg_par_fault, "reg_par_fault");
         chk(a_reg_par_fault_n=== b_reg_par_fault_n, "reg_par_fault_n");
      end
   end

   // ---------------- 随机激励 ----------------
   integer i;
   reg [31:0] rnd;
   initial begin
      ce = 0; wr = 0; addr = 0; wdata = 0; ack = 0;
      par_flt_axi = 0; err_axi = 0; fault_axi = 0; irq_axi = 0;

      repeat (5) @(negedge clk);
      rstn = 1;
      repeat (5) @(negedge clk);

      // 覆盖各种访问 + 随机
      for (i = 0; i < 20000; i = i + 1) begin
         rnd = $random(seed);
         ce  = 1'b1;
         wr  = rnd[0];
         addr[7:0] = $random(seed) & 8'hFF;
         addr[15:8] = 0;                       // 实例号 = IDX
         wdata = $random(seed);
         ack  = rnd[16];
         par_flt_axi = rnd[23:17];
         err_axi   = $random(seed) & {NSITES{1'b1}};
         fault_axi = $random(seed) & {NSITES{1'b1}};
         irq_axi   = rnd[24];
         @(negedge clk);
      end

      if (errors == 0) $display("EQUIVALENCE PASSED: edc_regfile == edc_regfile_leons (%0d cycles)", cyc);
      else $display("EQUIVALENCE FAILED: %0d mismatches", errors);
      $finish;
   end

   initial begin
      #5000000;
      $display("TIMEOUT");
      $finish;
   end
endmodule
