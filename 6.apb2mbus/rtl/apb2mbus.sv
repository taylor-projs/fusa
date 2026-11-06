// ============================================================================
// apb2mbus: APB3 slave -> mbus master 桥 (APB clk <-> mbus 24MHz)
//           MCP 直采 CDC + FuSa hang 看门狗
//
// ======================= CDC 结构 (MCP: 静态数据直采 + toggle 同步) =======
// 数据通路一律直采"静止的电平", 不加同步 FF; 同步 FF 只用于两个单 bit
// 控制 toggle, 且一律例化标准 sync 单元 (业界惯例, 便于后端替换 hardened
// sync cell; 单元见 rtl/sync_2dff.sv / rtl/sync_dff.sv, 含 FPGA /
// ASIC 仿真 / ASIC 后端工艺 cell 三分支):
//
//   APB 域                                mbus 域 24MHz
//   -------------------------             ------------------------------
//   acc    = psel & penable               req_flag → sync_2dff → flag_s2
//   ce_reg : acc 打拍, rdy 当拍清 0                    → sync_dff → flag_s3
//   req_flag: acc 上升沿翻转 (toggle)     ce_flag: s2!=s3 下一拍置 1, 单拍
//   保持寄存器: req_fire 当拍锁存             (零等待自完成)
//     paddr_q/pwdata_q/pwrite_q/par_q     ce 当拍: 采样 rdata → rdat_cap,
//   addr/wdata/wr/par 直采保持寄存器 ────────►  翻转 ack_flag
//   ack_flag → sync_2dff → ack_s2            叶端 ce 拍捕获
//            → sync_dff  → ack_s3
//   rdy = s2^s3 → pready
//   prdata 直采 rdat_cap ◄────────────────
//
// 直采安全 (MCP 三不变量) — 多比特跨域只有被链逐级采样才有代际错位; 直采
// 静态电平时亚稳态由时间排除, 不由 FF 级数排除:
//   1) 最多一笔在途 (ce_reg 边沿检测 + drain 屏蔽) -> 保持寄存器从
//      req_fire 到下一笔 req_fire 全程静止;
//   2) ce 距 req_flag 翻转 >= 3 个 mbus 拍 (flag 同步链) -> 叶端 ce 拍
//      捕获时 payload/par 已静止 >= 3 拍; 下一笔 req_fire 必在 rdy (即
//      ce) 之后 -> ce 拍后也不动. 捕获沿前后 +-3 拍无跳变;
//   3) rdat_cap 自 ce 拍静止; rdy (ack 同步链) 距 ce >= 2 个 apb 拍 ->
//      主设备采 prdata 时 rdat_cap 早已静止 (超时/越界/drain 路径输出 0).
//
// 演进说明: 早期为与 sysm_msync 同构的链式版 (payload/par 3FF, rdat 2FF,
// ack 4FF — 4FF 是为给 2FF rdat 链让出 1 稳定拍). 引入保持寄存器后
// payload 与 flag 同沿翻转, 链间存在跨代混采的理论窗口 (flag 链领先
// payload 链一代时 ce 携带旧负载, 且 par 同源同深度未必兜住); MCP 直采
// 从结构上消除该窗口 (无链可落后), 并省 ~215 FF. 代价: 直采跨域路径需
// SDC set_max_delay -datapath_only 约束 + CDC 工具 MCP 声明 (窗口极宽,
// 见 doc/apb2mbus_design.md §3.5).
//
// ======================= 越界 / 奇偶 / hang 看门狗 ========================
// 越界实例: paddr[15:8] >= NP 时不发起 mbus 传输, 直接 pready + pslverr.
//
// 命令在途奇偶 (FuSa): par_q 与 payload 在 req_fire 同一沿锁存 (APB 域),
// 同为静态直采 -> 叶端 ce 拍比对时必为同一代. 叶端 (edc_regfile) 用收到
// 的负载重组比对, 失配 = 在途 1bit 损坏 -> 门掉写 + PERR14 (见 edc_regfile
// 文件头与 design_spec §8.6). 保护边界 = req_fire 锁存点之后: 保持寄存器
// 在途 SEU = payload 坏/par_q 好 -> 失配检出. 注意 par 与 payload 必须
// 同代直达 (要么都走链要么都直采, 混搭会跨代错位).
//
// APB 域 HANG 看门狗 (bus-level hang protection, 业界惯例 = 桥/互连层兜底):
//   mbus 叶端全部零等待 (组合读/单拍写), mbus 传输本身永不 hang; 唯一
//   的 hang 源是 CDC 链路: mbus_clk 死/停顿、mbus 域复位卡死、广播通路
//   断 -> ack toggle 永不返回 -> rdy 永不置位 -> pready 永久拉低, CPU
//   总线挂死. 该故障只能在 apb_clk 域检测 (看门狗计数必须依赖一个
//     对端死掉时仍然存活的时钟), 故做在本桥内而不是各叶端:
//   * req 发出 (req_flag 翻转) 后 ack 未在 HANG_TO 个 apb_clk 内返回
//     -> to_fire: 当拍完成该笔 APB (pready=1, pslverr=1), CPU 收
//     bus error 而不是挂死; hang_evt 单拍脉冲 (双轨) 送 ESM.
//   * DRAIN 重对齐: timeout 后被延误的 ack 可能迟到 (如 mbus_clk 抖动),
//     迟到 toggle 若被误认为下一笔的 ack 会造成 rdata 错位 -> 进入
//     drain: 屏蔽新 req 发起, 新访问立即 pready+pslverr 快速失败,
//     直到迟到 ack 到达被消化, 链路自动恢复正常 (toggle 重新对齐).
//     mbus 侧永久死亡时 drain 保持, 后续访问全部快速 SLVERR, 不 hang.
//   * 计数器双轨 + 双比较 OR 触发 (同 ia_bus_timeo_core/cmm_regfile 的
//     看门狗惯例): 任一单点翻转立即强发事件 (fail-visible, 永不漏报).
//   * HANG_TO 取值: 正常往返 ≈ 3 拍 mbus (req 同步链) + 1 拍 ce
//     + 3 拍 apb (ack 同步链); 按最慢 mbus/最快 apb 折算后留 >=4x 裕量.
//     默认 64 拍 (mbus 24MHz / apb_clk >= 50MHz 时约 5x).
//   * timeout 后该笔访问实际可能已在 mbus 侧生效 (迟到完成), SW 恢复
//     流程: 收 SLVERR/hang_evt 后对目标寄存器重新读写确认 (与 PCIe
//     completion timeout 语义一致: 超时 = 完成状态未知).
//   * 复位假设: apb/mbus 同块复位 (同时断言/释放). 单边复位会使 req/ack
//     toggle 对错: 仅 mbus 域复位 -> req_flag 残留, 复位释放后 ce 重放
//     (写命令可能重复生效); 仅 apb 域复位 -> spurious ce/rdy 脉冲. 若系统
//     需分域复位, 须额外加 toggle 重对齐机制 (当前架构假设不支持).
// ============================================================================
module apb2mbus #(
   // 注: 不设 AW/DW 参数 — mbus 协议定宽 (addr[15:8]=实例号 / [7:0]=偏移,
   // 数据 32b), 参数化只会允许破坏译码的非法配置, 徒增审查面
   parameter integer NP      = 2,     // mbus 实例数 (地址译码越界判断)
   parameter integer HANG_TO = 64     // hang 看门狗阈值 [apb_clk 拍]
)(
   // ---------------- APB3 (apb_clk) ----------------
   input  logic           apb_clk,
   input  logic           apb_rstn,
   input  logic [15:0]    apb_paddr,
   input  logic           apb_psel,
   input  logic           apb_penable,
   input  logic           apb_pwrite,
   input  logic [31:0]    apb_pwdata,
   output logic [31:0]    apb_prdata,
   output logic           apb_pready,
   output logic           apb_pslverr,

   // ---------------- mbus (mbus_clk = 24MHz) ----------------
   input  logic           mbus_clk,
   input  logic           mbus_rstn,
   output logic           ce,
   output logic           wr,
   output logic [15:0]    addr,
   output logic [31:0]    wdata,
   output logic           par,        // 命令负载偶校验 (req_fire 同沿锁存直采)
   input  logic [31:0]    rdata,

   // ---------------- hang 事件 (apb_clk 域, 送 ESM) ----------------
   output logic           hang_evt,   // timeout 单拍脉冲
   output logic           hang_evt_n  // 双轨反相 (传输完整性, ESM 侧校验)
);

   // hang 看门狗计数位宽
   localparam integer HCW = (HANG_TO > 1) ? $clog2(HANG_TO+1) : 1;
   localparam [HCW-1:0] HANG_LAST = HANG_TO-1;
   // NP 无符号化 (要求 NP<=256): 供 inst_bad 比较, 避免与有符号 integer 混比
   localparam logic [8:0] NP_UB = NP;

   // 参数合法性检查 (elaboration 期一次, 无硬件开销):
   //   NP>256 -> NP_UB 截断, inst_bad 译码静默错; NP<1 -> 无实例无意义
   //   HANG_TO<2 -> HANG_LAST<=0 退化, 看门狗 req 一发出即误触发
   //   (HANG_TO 不设上限: 大值只是计数器宽几级, 无功能错误; 下限之外的
   //    裕量要求 = ">=4x 正常往返", 依赖时钟比, elaboration 拿不到, 属集成评审)
`ifndef SYNTHESIS
   initial begin
      assert (NP >= 1 && NP <= 256)
         else $fatal(1, "apb2mbus: NP=%0d out of range [1,256]", NP);
      assert (HANG_TO >= 2)
         else $fatal(1, "apb2mbus: HANG_TO=%0d must be >= 2", HANG_TO);
   end
`endif

   // ------------------------------------------------------------------
   // 寄存器记录 (每时钟域一份) 与复位常量
   // ------------------------------------------------------------------
   typedef struct packed {
      logic [HCW-1:0] hang_cnt;    // hang 计数器 (req 在途期间计数)
      logic [HCW-1:0] hang_cnt_n;  // 双轨反相 (fail-visible)
      logic           wait_ack;    // req 已发出, ack 未归
      logic           drain;       // timeout 后等迟到 ack 重对齐
      logic           hang_evt;    // timeout 单拍脉冲 -> ESM
      logic           hang_evt_n;  // 双轨反相
      logic           ce_reg;      // acc 打拍; rdy 当拍清 0, 同一笔不重复触发
      logic           req_flag;    // 请求 toggle -> mbus 域
      logic [15:0]    paddr_q;     // 请求保持寄存器 (MCP 直采负载)
      logic [31:0]    pwdata_q;
      logic           pwrite_q;
      logic           par_q;       // 命令负载偶校验 (req_fire 同沿锁存)
   } apb_reg_t;

   typedef struct packed {
      logic           ce_flag;     // 单拍 ce (零等待自完成)
      logic           ack_flag;    // 应答 toggle -> APB 域
      logic [31:0]    rdat_cap;    // 读数据锁存 (ce 拍)
   } mbus_reg_t;

   localparam apb_reg_t APB_REG_RST = '{
      hang_cnt   : {HCW{1'b0}},
      hang_cnt_n : {HCW{1'b1}},
      wait_ack   : 1'b0,
      drain      : 1'b0,
      hang_evt   : 1'b0,
      hang_evt_n : 1'b1,
      ce_reg     : 1'b0,
      req_flag   : 1'b0,
      paddr_q    : 16'b0,
      pwdata_q   : 32'b0,
      pwrite_q   : 1'b0,
      par_q      : 1'b0      // ^{16'b0, 1'b0, 32'b0} = 0, 复位态自洽
   };

   localparam mbus_reg_t MBUS_REG_RST = '{
      ce_flag  : 1'b0,
      ack_flag : 1'b0,
      rdat_cap : 32'b0
   };

   apb_reg_t  r_apb;
   apb_reg_t  rin_apb;
   mbus_reg_t r_mb;
   mbus_reg_t rin_mb;

   // ------------------------------------------------------------------
   // 纯组合 helper 信号
   // ------------------------------------------------------------------
   logic acc;
   logic inst_bad;
   logic rdy;
   logic req_fire;
   logic to_fire;
   logic h_fire_a;
   logic h_fire_b;
   logic h_dup;

   logic ack_s2;                  // ack toggle: sync 输出
   logic ack_s3;                  // ack toggle: 边沿检测延迟级
   logic flag_s2;                 // req toggle: sync 输出
   logic flag_s3;                 // req toggle: 边沿检测延迟级

   assign acc      = apb_psel && apb_penable;
   assign inst_bad = ({1'b0, apb_paddr[15:8]} >= NP_UB);
   assign rdy      = ack_s2 ^ ack_s3;

   // 本拍发起新 req: acc 上升沿, 非越界, 非 drain (越界实例不发起 mbus
   // 传输; drain 屏蔽新请求, 保证 toggle 链上最多一笔在途, 迟到 ack
   // 不会错位)
   assign req_fire = acc && !r_apb.ce_reg && !inst_bad && !r_apb.drain;

   // 看门狗触发: 计数器双轨 + 双比较 OR (任一单点翻转立即强发,
   // fail-visible, 永不漏报). rdy 同拍优先 (边界拍正常完成, 不误报;
   // 见 ia_bus_timeo_core "boundary-cycle guard")
   assign h_fire_a = (  r_apb.hang_cnt    >= HANG_LAST);
   assign h_fire_b = ((~r_apb.hang_cnt_n) >= HANG_LAST);
   assign h_dup    = (  r_apb.hang_cnt_n != ~r_apb.hang_cnt);
   assign to_fire  = r_apb.wait_ack && !rdy && (h_fire_a | h_fire_b | h_dup);

   // ------------------------------------------------------------------
   // ack 回程 = sync_2dff (s1 吸收亚稳态, s2 有一整拍解析时间再扇出)
   // + sync_dff (边沿检测延迟级), rdy = s2 ^ s3. 这是干净边沿检测的下限:
   // 少用一级会把未解析的 s1 组合扇出到 pready/ce_reg/wait_ack/drain
   // 四个消费者, 造成同拍采样分歧. rdat 直采后无需再多级让路.
   // ------------------------------------------------------------------
   sync_2dff #(.WIDTH(1)) u_ack_sync (
      .clk (apb_clk      ),
      .rstn(apb_rstn     ),
      .d   (r_mb.ack_flag),
      .q   (ack_s2       )
   );
   sync_dff  #(.WIDTH(1)) u_ack_dly (
      .clk (apb_clk ),
      .rstn(apb_rstn),
      .d   (ack_s2  ),
      .q   (ack_s3  )
   );

   // =========================================================================
   // APB 域组合进程: hang 看门狗 + 请求发起 + 保持寄存器的下一拍值
   // =========================================================================
   always_comb begin : apb_comb
      apb_reg_t v_apb;

      v_apb = r_apb;

      // hang 计数器: req 在途 (wait_ack) 期间计数, 空闲清零 (双轨)
      if (!r_apb.wait_ack) begin
         v_apb.hang_cnt   = {HCW{1'b0}};
         v_apb.hang_cnt_n = {HCW{1'b1}};
      end else begin
         v_apb.hang_cnt   =   r_apb.hang_cnt + 1'b1;
         v_apb.hang_cnt_n = ~(r_apb.hang_cnt + 1'b1);
      end

      // wait_ack: req_fire 置位, rdy / to_fire 清零
      if (req_fire) begin
         v_apb.wait_ack = 1'b1;
      end else if (rdy || to_fire) begin
         v_apb.wait_ack = 1'b0;
      end

      // drain: timeout 置位, 迟到 ack (rdy 脉冲) 消化后清 0
      if (to_fire) begin
         v_apb.drain = 1'b1;
      end else if (rdy) begin
         v_apb.drain = 1'b0;
      end

      v_apb.hang_evt   =   to_fire;
      v_apb.hang_evt_n = ~ to_fire;

      // ce_reg = rdy ? 0 : acc (同一笔不重复触发)
      if (rdy) begin
         v_apb.ce_reg = 1'b0;
      end else begin
         v_apb.ce_reg = acc;
      end

      // req_flag: acc 上升沿翻转 toggle
      if (req_fire) begin
         v_apb.req_flag = ~r_apb.req_flag;
      end

      // 请求保持寄存器: req_fire 当拍锁存 payload + 命令奇偶 par_q.
      // 在途 toggle 无法撤回 (cancel 信号同样过不了死掉的时钟域), 超时被延误
      // 的请求一定会迟到完成; 保持寄存器保证迟到完成携带的是原地址/数据/写
      // 使能, 消除"迟到写携带当前引脚值误写他址"的窗口. par_q 与 payload 同
      // 沿同源锁存 -> ce 拍 par 与 addr/wr/wdata 必为同一代 (直采对齐, 无链
      // 可落后); 且保持寄存器在途 SEU -> payload 坏/par_q 好 -> 叶端失配检出.
      if (req_fire) begin
         v_apb.paddr_q  = apb_paddr;
         v_apb.pwdata_q = apb_pwdata;
         v_apb.pwrite_q = apb_pwrite;
         v_apb.par_q    = ^{apb_paddr, apb_pwrite, apb_pwdata};
      end

      rin_apb = v_apb;
   end

   // ------------------------------------------------------------------
   // APB 域时序进程: 只做复位装载与 r <= rin
   // ------------------------------------------------------------------
   always_ff @(posedge apb_clk or negedge apb_rstn) begin : apb_seq
      if (!apb_rstn) begin
         r_apb <= APB_REG_RST;
      end else begin
         r_apb <= rin_apb;
      end
   end

   // ------------------------------------------------------------------
   // APB 域输出
   // ------------------------------------------------------------------
   // pready: 正常 ack / 越界即回 / timeout 强制完成 / drain 快速失败.
   // 各支路统一 acc 限定: pready 本就只在 acc (psel&penable) 期间被采样,
   // 规范内行为等价; 限定后空闲拍恒 0, fault 态 spurious rdy 也不会在
   // 总线空闲时误抬 pready
   assign apb_pready  = acc && ((rdy && !r_apb.drain) || inst_bad || to_fire || r_apb.drain);
   assign apb_pslverr = acc && (inst_bad || to_fire || r_apb.drain);

   // 读数据直采: rdat_cap 自 ce 拍静止, rdy 距 ce >= 2 个 apb 拍 (不变量 3)
   assign apb_prdata  = (rdy && !r_apb.drain) ? r_mb.rdat_cap : 32'b0;

   assign hang_evt    = r_apb.hang_evt;
   assign hang_evt_n  = r_apb.hang_evt_n;

   // =========================================================================
   // mbus 域: 只剩单 bit 控制 —— 请求 toggle 同步 + ce 生成 + 读采样 + ack
   // (payload/par 无链, 直采保持寄存器, 见文件头 MCP 三不变量)
   // =========================================================================
   // 请求 toggle = sync_2dff (亚稳态吸收+解析) + sync_dff (边沿检测延迟级)
   sync_2dff #(.WIDTH(1)) u_req_sync (
      .clk (mbus_clk      ),
      .rstn(mbus_rstn     ),
      .d   (r_apb.req_flag),
      .q   (flag_s2       )
   );
   sync_dff  #(.WIDTH(1)) u_req_dly (
      .clk (mbus_clk ),
      .rstn(mbus_rstn),
      .d   (flag_s2  ),
      .q   (flag_s3  )
   );

   // ------------------------------------------------------------------
   // mbus 域组合进程: ce 生成 + 读采样 + ack 翻转的下一拍值
   // ------------------------------------------------------------------
   always_comb begin : mbus_comb
      mbus_reg_t v_mb;

      v_mb = r_mb;

      // ce: 请求边沿 (s2 尚未追上 s3) 的下一拍置 1; 单拍自回 0
      // (零等待: 等价参考中 rdy 自环立即接受). 此时距 req_fire 已
      // >= 3 个 mbus 拍, 保持寄存器 payload/par 早已静止 (不变量 2).
      if (flag_s2 != flag_s3) begin
         v_mb.ce_flag = 1'b1;
      end else begin
         v_mb.ce_flag = 1'b0;
      end

      // ce 当拍完成: 采样读数据 + 翻转 ack
      if (r_mb.ce_flag) begin
         v_mb.rdat_cap = rdata;
         v_mb.ack_flag = ~r_mb.ack_flag;
      end

      rin_mb = v_mb;
   end

   // ------------------------------------------------------------------
   // mbus 域时序进程: 只做复位装载与 r <= rin
   // ------------------------------------------------------------------
   always_ff @(posedge mbus_clk or negedge mbus_rstn) begin : mbus_seq
      if (!mbus_rstn) begin
         r_mb <= MBUS_REG_RST;
      end else begin
         r_mb <= rin_mb;
      end
   end

   // payload/par 直采保持寄存器 (静态 MCP 电平, 无同步链)
   assign ce    = r_mb.ce_flag;
   assign wr    = r_apb.pwrite_q;
   assign addr  = r_apb.paddr_q;
   assign wdata = r_apb.pwdata_q;
   assign par   = r_apb.par_q;

endmodule
