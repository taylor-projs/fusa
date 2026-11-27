module mcusys_ciu_orig(
input             por_n,
input             pclk,
input             prstn,
input [31:0]      paddr,
input             pwrite,
input             psel,
input             penable,
input [31:0]      pwdata,
output reg [31:0] prdata,
output            pready,

// Group 0 registers (address 0x00)
output reg [15:0]  MGCR,
output reg         force_all_clk_on,

// Group 1 registers (address 0x04) - mcusys_aclk_ctrl
output reg [4:0]  mcusys_aclk_ctrl,
input             mcusys_aclk_fc_done,

// Group 2 registers (address 0x08) - mcusys_pclk_ctrl
output reg [4:0]  mcusys_pclk_ctrl,
input             mcusys_pclk_fc_done,

// Group 3 registers (address 0x0C) - mcusys_rv_core_clk_ctrl
output reg [4:0]  mcusys_rv_core_clk_ctrl,
input             mcusys_rv_core_clk_fc_done,

// Group 4 registers (address 0x10) - mcusys_m85_core0_clk_ctrl
output reg [4:0]  mcusys_m85_core0_clk_ctrl,
input             mcusys_m85_core0_clk_fc_done,

// Group 5 registers (address 0x14) - mcusys_m85_core1_clk_ctrl
output reg [4:0]  mcusys_m85_core1_clk_ctrl,
input             mcusys_m85_core1_clk_fc_done,

// Group 6 registers (address 0x18) - mcusys_m85_core2_clk_ctrl
output reg [4:0]  mcusys_m85_core2_clk_ctrl,
input             mcusys_m85_core2_clk_fc_done,

// Group 7 registers (address 0x1C) - mcusys_m85_core3_clk_ctrl
output reg [4:0]  mcusys_m85_core3_clk_ctrl,
input             mcusys_m85_core3_clk_fc_done,

// Group 8 registers (address 0x20)
output reg  rv_core_sw_rstn,

// Group 9 registers (address 0x24)
output reg  m85_core0_sw_rstn,

// Group 10 registers (address 0x28)
output reg  m85_core1_sw_rstn,

// Group 11 registers (address 0x2C)
output reg  m85_core2_sw_rstn,

// Group 12 registers (address 0x30)
output reg  m85_core3_sw_rstn,

// Group 13 registers (address 0x34)
output reg [31:0]  m85_core0_cfg0,

// Group 14 registers (address 0x38)
output reg [31:0]  m85_core0_cfg1,

// Group 15 registers (address 0x3C)
output reg [31:0]  m85_core0_cfg2,

// Group 16 registers (address 0x40)
output reg [25:0]  m85_core0_cfg_ns_systick,

// Group 17 registers (address 0x44)
output reg [25:0]  m85_core0_cfg_s_systick,

// Group 18 registers (address 0x48)
output reg [31:0]  m85_core0_cfg_s_vector,

// Group 19 registers (address 0x4C)
output reg [31:0]  m85_core0_cfg_ns_vector,

// Group 20 registers (address 0x50)
output reg [31:0]  m85_core0_cfg_dptarget_id,

// Group 21 registers (address 0x54)
output reg [31:0]  m85_core1_cfg0,

// Group 22 registers (address 0x58)
output reg [31:0]  m85_core1_cfg1,

// Group 23 registers (address 0x5C)
output reg [31:0]  m85_core1_cfg2,

// Group 24 registers (address 0x60)
output reg [25:0]  m85_core1_cfg_ns_systick,

// Group 25 registers (address 0x64)
output reg [25:0]  m85_core1_cfg_s_systick,

// Group 26 registers (address 0x68)
output reg [31:0]  m85_core1_cfg_s_vector,

// Group 27 registers (address 0x6C)
output reg [31:0]  m85_core1_cfg_ns_vector,

// Group 28 registers (address 0x70)
output reg [31:0]  m85_core1_cfg_dptarget_id,

// Group 29 registers (address 0x74)
output reg [31:0]  m85_core2_cfg0,

// Group 30 registers (address 0x78)
output reg [31:0]  m85_core2_cfg1,

// Group 31 registers (address 0x7C)
output reg [31:0]  m85_core2_cfg2,

// Group 32 registers (address 0x80)
output reg [25:0]  m85_core2_cfg_ns_systick,

// Group 33 registers (address 0x84)
output reg [25:0]  m85_core2_cfg_s_systick,

// Group 34 registers (address 0x88)
output reg [31:0]  m85_core2_cfg_s_vector,

// Group 35 registers (address 0x8C)
output reg [31:0]  m85_core2_cfg_ns_vector,

// Group 36 registers (address 0x90)
output reg [31:0]  m85_core2_cfg_dptarget_id,

// Group 37 registers (address 0x94)
output reg [31:0]  m85_core3_cfg0,

// Group 38 registers (address 0x98)
output reg [31:0]  m85_core3_cfg1,

// Group 39 registers (address 0x9C)
output reg [31:0]  m85_core3_cfg2,

// Group 40 registers (address 0xA0)
output reg [25:0]  m85_core3_cfg_ns_systick,

// Group 41 registers (address 0xA4)
output reg [25:0]  m85_core3_cfg_s_systick,

// Group 42 registers (address 0xA8)
output reg [31:0]  m85_core3_cfg_s_vector,

// Group 43 registers (address 0xAC)
output reg [31:0]  m85_core3_cfg_ns_vector,

// Group 44 registers (address 0xB0)
output reg [31:0]  m85_core3_cfg_dptarget_id,

// Group 45 registers (address 0xB4)
output reg [31:0]  mcusys_pll1_ctrl0,

// Group 46 registers (address 0xB8)
output reg [31:0]  mcusys_pll1_ctrl1,

// Group 47 registers (address 0xBC)
output reg [31:0]  mcusys_pll1_ctrl2,

// Group 48 registers (address 0xC0)
output reg [31:0]  mcusys_pll1_ctrl3,

// Group 49 registers (address 0xC4)
output reg [3:0]  mcusys_pll1_mon_config,

// Group 50 registers (address 0xC8)
output reg [7:0]  mcusys_pll1_div_en,
output reg        mcusys_pll1_pw_sw,

// Group 51 registers (address 0xCC)
output reg [31:0]  mcusys_rsvd0,

// Group 52 registers (address 0xD0)
output reg [31:0]  mcusys_rsvd1,

// Group 53 registers (address 0xD4)
output reg [31:0]  mcusys_rsvd2,

// Group 54 registers (address 0xD8)
output reg [3:0]  mcusys_rsvd3,

// Group 55 registers (address 0xDC)
output reg [7:0]  mcusys_rsvd4,

// Group 56 registers (address 0xE0)
output reg [31:0]  mcusys_rsvd5,

// Group 57 registers (address 0xE4)
output reg [31:0]  arqos_mcu_sys_fab,

// Group 58 registers (address 0xE8)
output reg [31:0]  awqos_mcu_sys_fab,

// Group 59 registers (address 0xEC)
output reg [31:0]  arqos_mcucore_sys_fab,

// Group 60 registers (address 0xF0)
output reg [31:0]  awqos_mcucore_sys_fab,

// Group 61 registers (address 0xF4)
output reg [11:0]  m85_core0_cfg_dclscorectl,

// Group 62 registers (address 0xF8)
output reg [11:0]  m85_core1_cfg_dclscorectl,

// Group 63 registers (address 0xFC)
output reg [11:0]  m85_core2_cfg_dclscorectl,

// Group 64 registers (address 0x100)
output reg [11:0]  m85_core3_cfg_dclscorectl,

// Group 65 registers (address 0x104)
input [31:0]  aud_spare_in,

// Group 66 registers (address 0x108)
output reg [1:0]  gmac0_speed_mode,
output reg        gmac0_rmii_refclk_phase_sel,
output reg        gmac0_rx_refclk_phase_sel,
output reg [3:0]  gmac0_phy_intf_sel_i,
output reg        gmac0_rgmii_txc_src_sel,
output reg        gmac0_1588_clk_en,
output reg        gmac0_refclk_sel,
output reg [1:0]  gmac0_clk_1588_sel,

// Group 67 registers (address 0x10C)
output reg         gmac0_rgmii_rxc_dline_pu,
output reg [7:0]   gmac0_rgmii_rxc_dline_range,
output reg [19:0]  gmac0_rgmii_rxc_dline_adj,

// Group 68 registers (address 0x110)
output reg         gmac0_rgmii_txc_dline_pu,
output reg [7:0]   gmac0_rgmii_txc_dline_range,
output reg [19:0]  gmac0_rgmii_txc_dline_adj,

// Group 69 registers (address 0x114)
output reg [1:0]  gmac1_speed_mode,
output reg        gmac1_rmii_refclk_phase_sel,
output reg        gmac1_rx_refclk_phase_sel,
output reg [3:0]  gmac1_phy_intf_sel_i,
output reg        gmac1_rgmii_txc_src_sel,
output reg        gmac1_1588_clk_en,
output reg        gmac1_refclk_sel,
output reg [1:0]  gmac1_clk_1588_sel,

// Group 70 registers (address 0x118)
output reg         gmac1_rgmii_rxc_dline_pu,
output reg [7:0]   gmac1_rgmii_rxc_dline_range,
output reg [19:0]  gmac1_rgmii_rxc_dline_adj,

// Group 71 registers (address 0x11C)
output reg         gmac1_rgmii_txc_dline_pu,
output reg [7:0]   gmac1_rgmii_txc_dline_range,
output reg [19:0]  gmac1_rgmii_txc_dline_adj,

// Group 72 registers (address 0x120)
output reg        regin_gmac0_sys_rst_n,
output reg        regin_gmac0_pwr_isolate_i,
output reg        regin_gmac0_pwr_clamp_ctrl_i,
output reg        regin_gmac0_pwr_down_ctrl_i,
output reg        regin_gmac0_csysreq_i,
output reg        regin_gmac0_sbd_pmac_hold_i,
output reg [1:0]  regin_gmac0_mcg_pst_trig_i,
output reg [1:0]  regin_gmac0_mcgr_dma_ack_i,
output reg [3:0]  regin_gmac0_sbd_pc_tim_wdw_i,

// Group 73 registers (address 0x124)
output reg [1:0]   regin_gmac0_clk_gate,
output reg [12:0]  regin_gmac0_intr_mask,
output reg         regin_gmac0_cfg_clamp_en,

// Group 74 registers (address 0x128)
input        regout_gmac0_rst_clk_tx_n_o,
input        regout_gmac0_rst_clk_rx_n_o,
input        regout_gmac0_rst_clk_app_n_o,
input [1:0]  regout_gmac0_mac_speed_o,
input        regout_gmac0_sbd_tx_clk_gating_ctrl_o,
input [2:0]  regout_gmac0_sbd_ar_dma_ch_no_o,
input [2:0]  regout_gmac0_sbd_aw_dma_ch_no_o,
input [2:0]  regout_gmac0_sbd_w_dma_ch_no_o,
input        regout_gmac0_csysack_o,
input        regout_gmac0_cactive_o,
input        regout_gmac0_ati_datatxon_o,
input        regout_gmac0_ati_pmac_txon_o,
input        regout_gmac0_ati_pmac_actv_o,
input [1:0]  regout_gmac0_mcgr_dma_req_o,
input        regout_gmac0_sbd_pwr_down_ack_o,

// Group 75 registers (address 0x12C)
output reg        regin_gmac1_sys_rst_n,
output reg        regin_gmac1_pwr_isolate_i,
output reg        regin_gmac1_pwr_clamp_ctrl_i,
output reg        regin_gmac1_pwr_down_ctrl_i,
output reg        regin_gmac1_csysreq_i,
output reg        regin_gmac1_sbd_pmac_hold_i,
output reg [1:0]  regin_gmac1_mcg_pst_trig_i,
output reg [1:0]  regin_gmac1_mcgr_dma_ack_i,
output reg [3:0]  regin_gmac1_sbd_pc_tim_wdw_i,

// Group 76 registers (address 0x130)
output reg [1:0]   regin_gmac1_clk_gate,
output reg [12:0]  regin_gmac1_intr_mask,
output reg         regin_gmac1_cfg_clamp_en,

// Group 77 registers (address 0x134)
input        regout_gmac1_rst_clk_tx_n_o,
input        regout_gmac1_rst_clk_rx_n_o,
input        regout_gmac1_rst_clk_app_n_o,
input [1:0]  regout_gmac1_mac_speed_o,
input        regout_gmac1_sbd_tx_clk_gating_ctrl_o,
input [2:0]  regout_gmac1_sbd_ar_dma_ch_no_o,
input [2:0]  regout_gmac1_sbd_aw_dma_ch_no_o,
input [2:0]  regout_gmac1_sbd_w_dma_ch_no_o,
input        regout_gmac1_csysack_o,
input        regout_gmac1_cactive_o,
input        regout_gmac1_ati_datatxon_o,
input        regout_gmac1_ati_pmac_txon_o,
input        regout_gmac1_ati_pmac_actv_o,
input [1:0]  regout_gmac1_mcgr_dma_req_o,
input        regout_gmac1_sbd_pwr_down_ack_o,

// Group 78 registers (address 0x138)
output reg [18:0]  pcm_clk_res_ctrl,

// Group 79 registers (address 0x13C)
output reg  pcm0_ch0_en,
output reg  pcm0_ch1_en,
output reg  pcm0_ch2_en,
output reg  pcm0_ch3_en,
output reg  pcm_mch_en,
output reg  pcm_apb_on,

// Group 80 registers (address 0x140)
output reg        mch_adma_mode,
output reg [1:0]  mch_adma_data_num,
output reg [2:0]  adc0_adma0_mode,
output reg [2:0]  adc0_adma1_mode,
output reg [2:0]  adc0_adma2_mode,
output reg [2:0]  adc0_adma3_mode,

// Group 81 registers (address 0x144)
output reg [18:0]  pcm1_clk_res_ctrl,

// Group 82 registers (address 0x148)
output reg  pcm1_ch0_en,
output reg  pcm1_ch1_en,
output reg  pcm1_ch2_en,
output reg  pcm1_ch3_en,
output reg  pcm1_mch_en,
output reg  pcm1_apb_on,

// Group 83 registers (address 0x14C)
output reg        mch1_adma_mode,
output reg [1:0]  mch1_adma_data_num,
output reg [2:0]  adc1_adma0_mode,
output reg [2:0]  adc1_adma1_mode,
output reg [2:0]  adc1_adma2_mode,
output reg [2:0]  adc1_adma3_mode,

// Group 84 registers (address 0x150)
output reg [7:0]  dmic0_adma_clk_res_ctrl,

// Group 85 registers (address 0x154)
output reg [7:0]  dmic1_adma_clk_res_ctrl,

// Group 86 registers (address 0x158)
output reg [4:0]  aud_dmic0_gt_ctrl,
output reg [4:0]  aud_dmic1_gt_ctrl,
output reg [4:0]  aud_dmic2_gt_ctrl,
output reg [4:0]  aud_dmic3_gt_ctrl,

// Group 87 registers (address 0x15C)
output reg [4:0]  aud_dmic4_gt_ctrl,
output reg [4:0]  aud_dmic5_gt_ctrl,
output reg [4:0]  aud_dmic6_gt_ctrl,
output reg [4:0]  aud_dmic7_gt_ctrl,

// Group 88 registers (address 0x160) - mcusys_dbgclk_ctrl
output reg [9:0]  mcusys_dbgclk_ctrl,
input             mcusys_dbgclk_fc_done,

// Group 89 registers (address 0x164)
output reg [31:0]  mcusys_pll2_ctrl0,

// Group 90 registers (address 0x168)
output reg [31:0]  mcusys_pll2_ctrl1,

// Group 91 registers (address 0x16C)
output reg [31:0]  mcusys_pll2_ctrl2,

// Group 92 registers (address 0x170)
output reg [31:0]  mcusys_pll2_ctrl3,

// Group 93 registers (address 0x174)
output reg [3:0]  mcusys_pll2_mon_config,

// Group 94 registers (address 0x178)
output reg [7:0]  mcusys_pll2_div_en,
output reg        mcusys_pll2_pw_sw,

// Group 95 registers (address 0x17C)
output reg [31:0]  mcusys_pll3_ctrl0,

// Group 96 registers (address 0x180)
output reg [31:0]  mcusys_pll3_ctrl1,

// Group 97 registers (address 0x184)
output reg [31:0]  mcusys_pll3_ctrl2,

// Group 98 registers (address 0x188)
output reg [31:0]  mcusys_pll3_ctrl3,

// Group 99 registers (address 0x18C)
output reg [3:0]  mcusys_pll3_mon_config,

// Group 100 registers (address 0x190)
output reg [7:0]  mcusys_pll3_div_en,
output reg        mcusys_pll3_pw_sw,

// Group 101 registers (address 0x194)
output reg [31:0]  mcusys_pll4_ctrl0,

// Group 102 registers (address 0x198)
output reg [31:0]  mcusys_pll4_ctrl1,

// Group 103 registers (address 0x19C)
output reg [31:0]  mcusys_pll4_ctrl2,

// Group 104 registers (address 0x1A0)
output reg [31:0]  mcusys_pll4_ctrl3,

// Group 105 registers (address 0x1A4)
output reg [3:0]  mcusys_pll4_mon_config,

// Group 106 registers (address 0x1A8)
output reg [7:0]  mcusys_pll4_div_en,
output reg        mcusys_pll4_pw_sw,

// Group 107 registers (address 0x1AC)
output reg [3:0]  axi_sram_control,
output reg [1:0]  axi_sram_gating_en,

// Group 108 registers (address 0x1B0)
output reg [31:0]  rv_core4_cfg,

// Group 109 registers (address 0x1B4)
output reg [31:0]  rv_reset_vector,

// Group 110 registers (address 0x1B8)
output reg [9:0]  rv_hart_id,

// Group 111 registers (address 0x1BC)
output reg  rv_stop_on_reset,

// Group 112 registers (address 0x1C0)
output reg [31:0]  rv_ecc_msk0,

// Group 113 registers (address 0x1C4)
output reg [31:0]  rv_ecc_msk1,

// Group 114 registers (address 0x1C8)
input [31:0]  rv_ecc_status0,

// Group 115 registers (address 0x1CC)
input [17:0]  rv_ecc_status1,

// Group 116 registers (address 0x1D0)
input [1:0]  rv_lockstep_mis,
input [1:0]  rv_safety_error,
input [1:0]  rv_safety_input_error_dcls,

// Group 117 registers (address 0x1D4)
input [31:0]  rv_core_status0,

// Group 118 registers (address 0x1D8)
input [31:0]  rv_core_status1,

// Group 119 registers (address 0x1DC)
input [31:0]  rv_core_status2,

// Group 120 registers (address 0x1E0)
input [31:0]  rv_core_status3,

// Group 121 registers (address 0x1E4)
input [31:0]  rv_core_status4,

// Group 122 registers (address 0x1E8)
input [31:0]  rv_core_status5,

// Group 123 registers (address 0x1EC)
input [31:0]  rv_i1_core_status1,

// Group 124 registers (address 0x1F0)
input [31:0]  rv_i1_core_status2,

// Group 125 registers (address 0x1F4)
input [31:0]  rv_i1_core_status3,

// Group 126 registers (address 0x1F8)
input [31:0]  rv_i1_core_status4,

// Group 127 registers (address 0x1FC)
output reg [31:0]  mem_ema_cfg_31_0,

// Group 128 registers (address 0x200)
output reg [31:0]  mem_ema_cfg_63_32,

// Group 129 registers (address 0x204)
output reg [31:0]  mem_ema_cfg_95_64,

// Group 130 registers (address 0x208)
output reg [31:0]  mem_ema_cfg_127_96,

// Group 131 registers (address 0x20C)
output reg [7:0]  ref_clk_io_cfg,

// Group 132 registers (address 0x210)
output reg [15:0]  gpio_pwr_cfg,

// Group 133 registers (address 0x214)
output reg [7:0]  ext_32k_in_io_cfg,

// Group 134 registers (address 0x218)
output reg [7:0]  mcu_trst_n_io_cfg,

// Group 135 registers (address 0x21C)
output reg [7:0]  pmic_en_io_cfg,

// Group 136 registers (address 0x220)
output reg [7:0]  reset_in_n_io_cfg,

// Group 137 registers (address 0x224)
output reg [8:0]  reserved2_m85_c1,

// Group 138 registers (address 0x228)
output reg [8:0]  reserved3_m85_c1,

// Group 139 registers (address 0x22C)
output reg [8:0]  reserved0_m85_c2,

// Group 140 registers (address 0x230)
output reg [8:0]  reserved1_m85_c2,

// Group 141 registers (address 0x234)
output reg [8:0]  reserved2_m85_c2,

// Group 142 registers (address 0x238)
output reg [8:0]  reserved3_m85_c2,

// Group 143 registers (address 0x23C)
output reg [8:0]  reserved0_m85_c3,

// Group 144 registers (address 0x240)
output reg [8:0]  reserved1_m85_c3,

// Group 145 registers (address 0x244)
output reg [8:0]  reserved2_m85_c3,

// Group 146 registers (address 0x248)
output reg [8:0]  reserved3_m85_c3,

// Group 147 registers (address 0x24C)
output reg [8:0]  reserved0_rv_m,

// Group 148 registers (address 0x250)
output reg [8:0]  reserved1_rv_m,

// Group 149 registers (address 0x254)
output reg [8:0]  reserved2_rv_m,

// Group 150 registers (address 0x258)
output reg [8:0]  reserved3_rv_m,

// Group 151 registers (address 0x25C)
output reg [8:0]  reserved0_rv_s,

// Group 152 registers (address 0x260)
output reg [8:0]  reserved1_rv_s,

// Group 153 registers (address 0x264)
output reg [8:0]  reserved2_rv_s,

// Group 154 registers (address 0x268)
output reg [8:0]  reserved3_rv_s,

// Group 155 registers (address 0x26C)
output reg [5:0]  usb_clk_ctrl,

// Group 156 registers (address 0x270) - usb_wk_ctrl
output reg [5:0]  usb_wk_mask,
output reg        usb_wk_int_mask,
output reg [5:0]  usb_wk_clr,
output reg        usb_vbus_drv,
output reg        usb_id_ovrd_en,
output reg        usb_id_ovrd_val,
input [5:0]       usb_wk_status,
input             usb_wk_int_status

);




wire          wr_valid = psel & penable & pwrite;
wire          rd_valid = psel & ~pwrite;
assign        pready = 1'b1;

// Address 0x00: Group 0 - MGCR and force_all_clk_on
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        MGCR <= 16'hFFFF;
        force_all_clk_on <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h00) begin
        MGCR <= pwdata[15:0];
        force_all_clk_on <= pwdata[16];
      end
   end
end

// Address 0x04: Group 1 - mcusys_aclk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_aclk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h01) begin
        mcusys_aclk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_aclk_ctrl4_prstn;
macro_and u_mcusys_aclk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_aclk_fc_done), .o(mcusys_aclk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_aclk_ctrl4_prstn) begin
   if (~mcusys_aclk_ctrl4_prstn) begin
        mcusys_aclk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h01) begin
        mcusys_aclk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x08: Group 2 - mcusys_pclk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pclk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h02) begin
        mcusys_pclk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_pclk_ctrl4_prstn;
macro_and u_mcusys_pclk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_pclk_fc_done), .o(mcusys_pclk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_pclk_ctrl4_prstn) begin
   if (~mcusys_pclk_ctrl4_prstn) begin
        mcusys_pclk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h02) begin
        mcusys_pclk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x0C: Group 3 - mcusys_rv_core_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rv_core_clk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h03) begin
        mcusys_rv_core_clk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_rv_core_clk_ctrl4_prstn;
macro_and u_mcusys_rv_core_clk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_rv_core_clk_fc_done), .o(mcusys_rv_core_clk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_rv_core_clk_ctrl4_prstn) begin
   if (~mcusys_rv_core_clk_ctrl4_prstn) begin
        mcusys_rv_core_clk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h03) begin
        mcusys_rv_core_clk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x10: Group 4 - mcusys_m85_core0_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_m85_core0_clk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h04) begin
        mcusys_m85_core0_clk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_m85_core0_clk_ctrl4_prstn;
macro_and u_mcusys_m85_core0_clk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_m85_core0_clk_fc_done), .o(mcusys_m85_core0_clk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_m85_core0_clk_ctrl4_prstn) begin
   if (~mcusys_m85_core0_clk_ctrl4_prstn) begin
        mcusys_m85_core0_clk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h04) begin
        mcusys_m85_core0_clk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x14: Group 5 - mcusys_m85_core1_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_m85_core1_clk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h05) begin
        mcusys_m85_core1_clk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_m85_core1_clk_ctrl4_prstn;
macro_and u_mcusys_m85_core1_clk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_m85_core1_clk_fc_done), .o(mcusys_m85_core1_clk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_m85_core1_clk_ctrl4_prstn) begin
   if (~mcusys_m85_core1_clk_ctrl4_prstn) begin
        mcusys_m85_core1_clk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h05) begin
        mcusys_m85_core1_clk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x18: Group 6 - mcusys_m85_core2_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_m85_core2_clk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h06) begin
        mcusys_m85_core2_clk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_m85_core2_clk_ctrl4_prstn;
macro_and u_mcusys_m85_core2_clk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_m85_core2_clk_fc_done), .o(mcusys_m85_core2_clk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_m85_core2_clk_ctrl4_prstn) begin
   if (~mcusys_m85_core2_clk_ctrl4_prstn) begin
        mcusys_m85_core2_clk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h06) begin
        mcusys_m85_core2_clk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x1C: Group 7 - mcusys_m85_core3_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_m85_core3_clk_ctrl[3:0] <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h07) begin
        mcusys_m85_core3_clk_ctrl[3:0] <= pwdata[3:0];
      end
   end
end

// Clear fc_req even while the destination PCLK is gated during a frequency change.
wire mcusys_m85_core3_clk_ctrl4_prstn;
macro_and u_mcusys_m85_core3_clk_ctrl4_prstn (
    .a(prstn), .b(~mcusys_m85_core3_clk_fc_done), .o(mcusys_m85_core3_clk_ctrl4_prstn)
);

always @(posedge pclk or negedge mcusys_m85_core3_clk_ctrl4_prstn) begin
   if (~mcusys_m85_core3_clk_ctrl4_prstn) begin
        mcusys_m85_core3_clk_ctrl[4] <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h07) begin
        mcusys_m85_core3_clk_ctrl[4] <= pwdata[4];
      end
   end
end

// Address 0x20: Group 8 - rv_core_sw_rstn
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_core_sw_rstn <= 1'b1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h08) begin
        rv_core_sw_rstn <= pwdata[0];
      end
   end
end

// Address 0x24: Group 9 - m85_core0_sw_rstn
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_sw_rstn <= 1'b1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h09) begin
        m85_core0_sw_rstn <= pwdata[0];
      end
   end
end

// Address 0x28: Group 10 - m85_core1_sw_rstn
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_sw_rstn <= 1'b1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0A) begin
        m85_core1_sw_rstn <= pwdata[0];
      end
   end
end

// Address 0x2C: Group 11 - m85_core2_sw_rstn
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_sw_rstn <= 1'b1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0B) begin
        m85_core2_sw_rstn <= pwdata[0];
      end
   end
end

// Address 0x30: Group 12 - m85_core3_sw_rstn
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_sw_rstn <= 1'b1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0C) begin
        m85_core3_sw_rstn <= pwdata[0];
      end
   end
end

// Address 0x34: Group 13 - m85_core0_cfg0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg0 <= 32'h000f30a0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0D) begin
        m85_core0_cfg0 <= pwdata[31:0];
      end
   end
end

// Address 0x38: Group 14 - m85_core0_cfg1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg1 <= 32'hff154;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0E) begin
        m85_core0_cfg1 <= pwdata[31:0];
      end
   end
end

// Address 0x3C: Group 15 - m85_core0_cfg2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg2 <= 32'h140;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h0F) begin
        m85_core0_cfg2 <= pwdata[31:0];
      end
   end
end

// Address 0x40: Group 16 - m85_core0_cfg_ns_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_ns_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h10) begin
        m85_core0_cfg_ns_systick <= pwdata[25:0];
      end
   end
end

// Address 0x44: Group 17 - m85_core0_cfg_s_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_s_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h11) begin
        m85_core0_cfg_s_systick <= pwdata[25:0];
      end
   end
end

// Address 0x48: Group 18 - m85_core0_cfg_s_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_s_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h12) begin
        m85_core0_cfg_s_vector <= pwdata[31:0];
      end
   end
end

// Address 0x4C: Group 19 - m85_core0_cfg_ns_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_ns_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h13) begin
        m85_core0_cfg_ns_vector <= pwdata[31:0];
      end
   end
end

// Address 0x50: Group 20 - m85_core0_cfg_dptarget_id
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_dptarget_id <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h14) begin
        m85_core0_cfg_dptarget_id <= pwdata[31:0];
      end
   end
end

// Address 0x54: Group 21 - m85_core1_cfg0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg0 <= 32'h000f30a0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h15) begin
        m85_core1_cfg0 <= pwdata[31:0];
      end
   end
end

// Address 0x58: Group 22 - m85_core1_cfg1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg1 <= 32'hff154;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h16) begin
        m85_core1_cfg1 <= pwdata[31:0];
      end
   end
end

// Address 0x5C: Group 23 - m85_core1_cfg2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg2 <= 32'h140;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h17) begin
        m85_core1_cfg2 <= pwdata[31:0];
      end
   end
end

// Address 0x60: Group 24 - m85_core1_cfg_ns_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_ns_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h18) begin
        m85_core1_cfg_ns_systick <= pwdata[25:0];
      end
   end
end

// Address 0x64: Group 25 - m85_core1_cfg_s_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_s_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h19) begin
        m85_core1_cfg_s_systick <= pwdata[25:0];
      end
   end
end

// Address 0x68: Group 26 - m85_core1_cfg_s_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_s_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1A) begin
        m85_core1_cfg_s_vector <= pwdata[31:0];
      end
   end
end

// Address 0x6C: Group 27 - m85_core1_cfg_ns_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_ns_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1B) begin
        m85_core1_cfg_ns_vector <= pwdata[31:0];
      end
   end
end

// Address 0x70: Group 28 - m85_core1_cfg_dptarget_id
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_dptarget_id <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1C) begin
        m85_core1_cfg_dptarget_id <= pwdata[31:0];
      end
   end
end

// Address 0x74: Group 29 - m85_core2_cfg0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg0 <= 32'h000f30a0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1D) begin
        m85_core2_cfg0 <= pwdata[31:0];
      end
   end
end

// Address 0x78: Group 30 - m85_core2_cfg1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg1 <= 32'hff154;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1E) begin
        m85_core2_cfg1 <= pwdata[31:0];
      end
   end
end

// Address 0x7C: Group 31 - m85_core2_cfg2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg2 <= 32'h140;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h1F) begin
        m85_core2_cfg2 <= pwdata[31:0];
      end
   end
end

// Address 0x80: Group 32 - m85_core2_cfg_ns_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_ns_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h20) begin
        m85_core2_cfg_ns_systick <= pwdata[25:0];
      end
   end
end

// Address 0x84: Group 33 - m85_core2_cfg_s_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_s_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h21) begin
        m85_core2_cfg_s_systick <= pwdata[25:0];
      end
   end
end

// Address 0x88: Group 34 - m85_core2_cfg_s_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_s_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h22) begin
        m85_core2_cfg_s_vector <= pwdata[31:0];
      end
   end
end

// Address 0x8C: Group 35 - m85_core2_cfg_ns_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_ns_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h23) begin
        m85_core2_cfg_ns_vector <= pwdata[31:0];
      end
   end
end

// Address 0x90: Group 36 - m85_core2_cfg_dptarget_id
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_dptarget_id <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h24) begin
        m85_core2_cfg_dptarget_id <= pwdata[31:0];
      end
   end
end

// Address 0x94: Group 37 - m85_core3_cfg0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg0 <= 32'h000f30a0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h25) begin
        m85_core3_cfg0 <= pwdata[31:0];
      end
   end
end

// Address 0x98: Group 38 - m85_core3_cfg1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg1 <= 32'hff154;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h26) begin
        m85_core3_cfg1 <= pwdata[31:0];
      end
   end
end

// Address 0x9C: Group 39 - m85_core3_cfg2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg2 <= 32'h140;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h27) begin
        m85_core3_cfg2 <= pwdata[31:0];
      end
   end
end

// Address 0xA0: Group 40 - m85_core3_cfg_ns_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_ns_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h28) begin
        m85_core3_cfg_ns_systick <= pwdata[25:0];
      end
   end
end

// Address 0xA4: Group 41 - m85_core3_cfg_s_systick
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_s_systick <= 26'h270f;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h29) begin
        m85_core3_cfg_s_systick <= pwdata[25:0];
      end
   end
end

// Address 0xA8: Group 42 - m85_core3_cfg_s_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_s_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2A) begin
        m85_core3_cfg_s_vector <= pwdata[31:0];
      end
   end
end

// Address 0xAC: Group 43 - m85_core3_cfg_ns_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_ns_vector <= 32'h30000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2B) begin
        m85_core3_cfg_ns_vector <= pwdata[31:0];
      end
   end
end

// Address 0xB0: Group 44 - m85_core3_cfg_dptarget_id
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_dptarget_id <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2C) begin
        m85_core3_cfg_dptarget_id <= pwdata[31:0];
      end
   end
end

// Address 0xB4: Group 45 - mcusys_pll1_ctrl0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_ctrl0 <= 32'h00F81053;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2D) begin
        mcusys_pll1_ctrl0 <= pwdata[31:0];
      end
   end
end

// Address 0xB8: Group 46 - mcusys_pll1_ctrl1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_ctrl1 <= 32'h00555555;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2E) begin
        mcusys_pll1_ctrl1 <= pwdata[31:0];
      end
   end
end

// Address 0xBC: Group 47 - mcusys_pll1_ctrl2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_ctrl2 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h2F) begin
        mcusys_pll1_ctrl2 <= pwdata[31:0];
      end
   end
end

// Address 0xC0: Group 48 - mcusys_pll1_ctrl3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_ctrl3 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h30) begin
        mcusys_pll1_ctrl3 <= pwdata[31:0];
      end
   end
end

// Address 0xC4: Group 49 - mcusys_pll1_mon_config
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_mon_config <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h31) begin
        mcusys_pll1_mon_config <= pwdata[3:0];
      end
   end
end

// Address 0xC8: Group 50 - mcusys_pll1_div_en and mcusys_pll1_pw_sw
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll1_div_en <= 8'hFF;
        mcusys_pll1_pw_sw <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h32) begin
        mcusys_pll1_div_en <= pwdata[7:0];
        mcusys_pll1_pw_sw <= pwdata[8];
      end
   end
end

// Address 0xCC: Group 51 - mcusys_rsvd0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd0 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h33) begin
        mcusys_rsvd0 <= pwdata[31:0];
      end
   end
end

// Address 0xD0: Group 52 - mcusys_rsvd1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd1 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h34) begin
        mcusys_rsvd1 <= pwdata[31:0];
      end
   end
end

// Address 0xD4: Group 53 - mcusys_rsvd2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd2 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h35) begin
        mcusys_rsvd2 <= pwdata[31:0];
      end
   end
end

// Address 0xD8: Group 54 - mcusys_rsvd3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd3 <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h36) begin
        mcusys_rsvd3 <= pwdata[3:0];
      end
   end
end

// Address 0xDC: Group 55 - mcusys_rsvd4
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd4 <= 8'hFF;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h37) begin
        mcusys_rsvd4 <= pwdata[7:0];
      end
   end
end

// Address 0xE0: Group 56 - mcusys_rsvd5
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_rsvd5 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h38) begin
        mcusys_rsvd5 <= pwdata[31:0];
      end
   end
end

// Address 0xE4: Group 57 - arqos_mcu_sys_fab
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        arqos_mcu_sys_fab <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h39) begin
        arqos_mcu_sys_fab <= pwdata[31:0];
      end
   end
end

// Address 0xE8: Group 58 - awqos_mcu_sys_fab
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        awqos_mcu_sys_fab <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3A) begin
        awqos_mcu_sys_fab <= pwdata[31:0];
      end
   end
end

// Address 0xEC: Group 59 - arqos_mcucore_sys_fab
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        arqos_mcucore_sys_fab <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3B) begin
        arqos_mcucore_sys_fab <= pwdata[31:0];
      end
   end
end

// Address 0xF0: Group 60 - awqos_mcucore_sys_fab
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        awqos_mcucore_sys_fab <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3C) begin
        awqos_mcucore_sys_fab <= pwdata[31:0];
      end
   end
end

// Address 0xF4: Group 61 - m85_core0_cfg_dclscorectl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core0_cfg_dclscorectl <= 12'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3D) begin
        m85_core0_cfg_dclscorectl <= pwdata[11:0];
      end
   end
end

// Address 0xF8: Group 62 - m85_core1_cfg_dclscorectl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core1_cfg_dclscorectl <= 12'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3E) begin
        m85_core1_cfg_dclscorectl <= pwdata[11:0];
      end
   end
end

// Address 0xFC: Group 63 - m85_core2_cfg_dclscorectl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core2_cfg_dclscorectl <= 12'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h3F) begin
        m85_core2_cfg_dclscorectl <= pwdata[11:0];
      end
   end
end

// Address 0x100: Group 64 - m85_core3_cfg_dclscorectl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        m85_core3_cfg_dclscorectl <= 12'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h40) begin
        m85_core3_cfg_dclscorectl <= pwdata[11:0];
      end
   end
end

// Address 0x108: Group 66 - gmac0_speed_mode and gmac0_rmii_refclk_phase_sel and gmac0_rx_refclk_phase_sel and gmac0_phy_intf_sel_i and gmac0_rgmii_txc_src_sel and gmac0_1588_clk_en and gmac0_refclk_sel and gmac0_clk_1588_sel
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac0_speed_mode <= 2'h0;
        gmac0_rmii_refclk_phase_sel <= 1'b0;
        gmac0_rx_refclk_phase_sel <= 1'b0;
        gmac0_phy_intf_sel_i <= 4'h0;
        gmac0_rgmii_txc_src_sel <= 1'b0;
        gmac0_1588_clk_en <= 1'b0;
        gmac0_refclk_sel <= 1'b0;
        gmac0_clk_1588_sel <= 2'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h42) begin
        gmac0_speed_mode <= pwdata[1:0];
        gmac0_rmii_refclk_phase_sel <= pwdata[2];
        gmac0_rx_refclk_phase_sel <= pwdata[3];
        gmac0_phy_intf_sel_i <= pwdata[7:4];
        gmac0_rgmii_txc_src_sel <= pwdata[8];
        gmac0_1588_clk_en <= pwdata[9];
        gmac0_refclk_sel <= pwdata[10];
        gmac0_clk_1588_sel <= pwdata[12:11];
      end
   end
end

// Address 0x10C: Group 67 - gmac0_rgmii_rxc_dline_pu and gmac0_rgmii_rxc_dline_range and gmac0_rgmii_rxc_dline_adj
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac0_rgmii_rxc_dline_pu <= 1'b0;
        gmac0_rgmii_rxc_dline_range <= 8'h0;
        gmac0_rgmii_rxc_dline_adj <= 20'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h43) begin
        gmac0_rgmii_rxc_dline_pu <= pwdata[0];
        gmac0_rgmii_rxc_dline_range <= pwdata[8:1];
        gmac0_rgmii_rxc_dline_adj <= pwdata[28:9];
      end
   end
end

// Address 0x110: Group 68 - gmac0_rgmii_txc_dline_pu and gmac0_rgmii_txc_dline_range and gmac0_rgmii_txc_dline_adj
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac0_rgmii_txc_dline_pu <= 1'b0;
        gmac0_rgmii_txc_dline_range <= 8'h0;
        gmac0_rgmii_txc_dline_adj <= 20'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h44) begin
        gmac0_rgmii_txc_dline_pu <= pwdata[0];
        gmac0_rgmii_txc_dline_range <= pwdata[8:1];
        gmac0_rgmii_txc_dline_adj <= pwdata[28:9];
      end
   end
end

// Address 0x114: Group 69 - gmac1_speed_mode and gmac1_rmii_refclk_phase_sel and gmac1_rx_refclk_phase_sel and gmac1_phy_intf_sel_i and gmac1_rgmii_txc_src_sel and gmac1_1588_clk_en and gmac1_refclk_sel and gmac1_clk_1588_sel
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac1_speed_mode <= 2'h0;
        gmac1_rmii_refclk_phase_sel <= 1'b0;
        gmac1_rx_refclk_phase_sel <= 1'b0;
        gmac1_phy_intf_sel_i <= 4'h0;
        gmac1_rgmii_txc_src_sel <= 1'b0;
        gmac1_1588_clk_en <= 1'b0;
        gmac1_refclk_sel <= 1'b0;
        gmac1_clk_1588_sel <= 2'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h45) begin
        gmac1_speed_mode <= pwdata[1:0];
        gmac1_rmii_refclk_phase_sel <= pwdata[2];
        gmac1_rx_refclk_phase_sel <= pwdata[3];
        gmac1_phy_intf_sel_i <= pwdata[7:4];
        gmac1_rgmii_txc_src_sel <= pwdata[8];
        gmac1_1588_clk_en <= pwdata[9];
        gmac1_refclk_sel <= pwdata[10];
        gmac1_clk_1588_sel <= pwdata[12:11];
      end
   end
end

// Address 0x118: Group 70 - gmac1_rgmii_rxc_dline_pu and gmac1_rgmii_rxc_dline_range and gmac1_rgmii_rxc_dline_adj
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac1_rgmii_rxc_dline_pu <= 1'b0;
        gmac1_rgmii_rxc_dline_range <= 8'h0;
        gmac1_rgmii_rxc_dline_adj <= 20'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h46) begin
        gmac1_rgmii_rxc_dline_pu <= pwdata[0];
        gmac1_rgmii_rxc_dline_range <= pwdata[8:1];
        gmac1_rgmii_rxc_dline_adj <= pwdata[28:9];
      end
   end
end

// Address 0x11C: Group 71 - gmac1_rgmii_txc_dline_pu and gmac1_rgmii_txc_dline_range and gmac1_rgmii_txc_dline_adj
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gmac1_rgmii_txc_dline_pu <= 1'b0;
        gmac1_rgmii_txc_dline_range <= 8'h0;
        gmac1_rgmii_txc_dline_adj <= 20'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h47) begin
        gmac1_rgmii_txc_dline_pu <= pwdata[0];
        gmac1_rgmii_txc_dline_range <= pwdata[8:1];
        gmac1_rgmii_txc_dline_adj <= pwdata[28:9];
      end
   end
end

// Address 0x120: Group 72 - regin_gmac0_sys_rst_n and regin_gmac0_pwr_isolate_i and regin_gmac0_pwr_clamp_ctrl_i and regin_gmac0_pwr_down_ctrl_i and regin_gmac0_csysreq_i and regin_gmac0_sbd_pmac_hold_i and regin_gmac0_mcg_pst_trig_i and regin_gmac0_mcgr_dma_ack_i and regin_gmac0_sbd_pc_tim_wdw_i
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        regin_gmac0_sys_rst_n <= 1'b0;
        regin_gmac0_pwr_isolate_i <= 1'b0;
        regin_gmac0_pwr_clamp_ctrl_i <= 1'b0;
        regin_gmac0_pwr_down_ctrl_i <= 1'b0;
        regin_gmac0_csysreq_i <= 1'b1;
        regin_gmac0_sbd_pmac_hold_i <= 1'b0;
        regin_gmac0_mcg_pst_trig_i <= 2'h0;
        regin_gmac0_mcgr_dma_ack_i <= 2'h0;
        regin_gmac0_sbd_pc_tim_wdw_i <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h48) begin
        regin_gmac0_sys_rst_n <= pwdata[0];
        regin_gmac0_pwr_isolate_i <= pwdata[1];
        regin_gmac0_pwr_clamp_ctrl_i <= pwdata[2];
        regin_gmac0_pwr_down_ctrl_i <= pwdata[3];
        regin_gmac0_csysreq_i <= pwdata[4];
        regin_gmac0_sbd_pmac_hold_i <= pwdata[5];
        regin_gmac0_mcg_pst_trig_i <= pwdata[7:6];
        regin_gmac0_mcgr_dma_ack_i <= pwdata[9:8];
        regin_gmac0_sbd_pc_tim_wdw_i <= pwdata[13:10];
      end
   end
end

// Address 0x124: Group 73 - regin_gmac0_clk_gate and regin_gmac0_intr_mask and regin_gmac0_cfg_clamp_en
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        regin_gmac0_clk_gate <= 2'h0;
        regin_gmac0_intr_mask <= 13'h0;
        regin_gmac0_cfg_clamp_en <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h49) begin
        regin_gmac0_clk_gate <= pwdata[1:0];
        regin_gmac0_intr_mask <= pwdata[14:2];
        regin_gmac0_cfg_clamp_en <= pwdata[15];
      end
   end
end

// Address 0x12C: Group 75 - regin_gmac1_sys_rst_n and regin_gmac1_pwr_isolate_i and regin_gmac1_pwr_clamp_ctrl_i and regin_gmac1_pwr_down_ctrl_i and regin_gmac1_csysreq_i and regin_gmac1_sbd_pmac_hold_i and regin_gmac1_mcg_pst_trig_i and regin_gmac1_mcgr_dma_ack_i and regin_gmac1_sbd_pc_tim_wdw_i
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        regin_gmac1_sys_rst_n <= 1'b0;
        regin_gmac1_pwr_isolate_i <= 1'b0;
        regin_gmac1_pwr_clamp_ctrl_i <= 1'b0;
        regin_gmac1_pwr_down_ctrl_i <= 1'b0;
        regin_gmac1_csysreq_i <= 1'b1;
        regin_gmac1_sbd_pmac_hold_i <= 1'b0;
        regin_gmac1_mcg_pst_trig_i <= 2'h0;
        regin_gmac1_mcgr_dma_ack_i <= 2'h0;
        regin_gmac1_sbd_pc_tim_wdw_i <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h4B) begin
        regin_gmac1_sys_rst_n <= pwdata[0];
        regin_gmac1_pwr_isolate_i <= pwdata[1];
        regin_gmac1_pwr_clamp_ctrl_i <= pwdata[2];
        regin_gmac1_pwr_down_ctrl_i <= pwdata[3];
        regin_gmac1_csysreq_i <= pwdata[4];
        regin_gmac1_sbd_pmac_hold_i <= pwdata[5];
        regin_gmac1_mcg_pst_trig_i <= pwdata[7:6];
        regin_gmac1_mcgr_dma_ack_i <= pwdata[9:8];
        regin_gmac1_sbd_pc_tim_wdw_i <= pwdata[13:10];
      end
   end
end

// Address 0x130: Group 76 - regin_gmac1_clk_gate and regin_gmac1_intr_mask and regin_gmac1_cfg_clamp_en
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        regin_gmac1_clk_gate <= 2'h0;
        regin_gmac1_intr_mask <= 13'h0;
        regin_gmac1_cfg_clamp_en <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h4C) begin
        regin_gmac1_clk_gate <= pwdata[1:0];
        regin_gmac1_intr_mask <= pwdata[14:2];
        regin_gmac1_cfg_clamp_en <= pwdata[15];
      end
   end
end

// Address 0x138: Group 78 - pcm_clk_res_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        pcm_clk_res_ctrl <= 19'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h4E) begin
        pcm_clk_res_ctrl <= pwdata[18:0];
      end
   end
end

// Address 0x13C: Group 79 - pcm0_ch0_en and pcm0_ch1_en and pcm0_ch2_en and pcm0_ch3_en and pcm_mch_en and pcm_apb_on
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        pcm0_ch0_en <= 1'h0;
        pcm0_ch1_en <= 1'h0;
        pcm0_ch2_en <= 1'h0;
        pcm0_ch3_en <= 1'h0;
        pcm_mch_en <= 1'h0;
        pcm_apb_on <= 1'h1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h4F) begin
        pcm0_ch0_en <= pwdata[0];
        pcm0_ch1_en <= pwdata[1];
        pcm0_ch2_en <= pwdata[2];
        pcm0_ch3_en <= pwdata[3];
        pcm_mch_en <= pwdata[4];
        pcm_apb_on <= pwdata[5];
      end
   end
end

// Address 0x140: Group 80 - mch_adma_mode and mch_adma_data_num and adc0_adma0_mode and adc0_adma1_mode and adc0_adma2_mode and adc0_adma3_mode
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mch_adma_mode <= 1'h0;
        mch_adma_data_num <= 2'h0;
        adc0_adma0_mode <= 3'h6;
        adc0_adma1_mode <= 3'h6;
        adc0_adma2_mode <= 3'h6;
        adc0_adma3_mode <= 3'h6;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h50) begin
        mch_adma_mode <= pwdata[0];
        mch_adma_data_num <= pwdata[2:1];
        adc0_adma0_mode <= pwdata[5:3];
        adc0_adma1_mode <= pwdata[8:6];
        adc0_adma2_mode <= pwdata[11:9];
        adc0_adma3_mode <= pwdata[14:12];
      end
   end
end

// Address 0x144: Group 81 - pcm1_clk_res_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        pcm1_clk_res_ctrl <= 19'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h51) begin
        pcm1_clk_res_ctrl <= pwdata[18:0];
      end
   end
end

// Address 0x148: Group 82 - pcm1_ch0_en and pcm1_ch1_en and pcm1_ch2_en and pcm1_ch3_en and pcm1_mch_en and pcm1_apb_on
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        pcm1_ch0_en <= 1'h0;
        pcm1_ch1_en <= 1'h0;
        pcm1_ch2_en <= 1'h0;
        pcm1_ch3_en <= 1'h0;
        pcm1_mch_en <= 1'h0;
        pcm1_apb_on <= 1'h1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h52) begin
        pcm1_ch0_en <= pwdata[0];
        pcm1_ch1_en <= pwdata[1];
        pcm1_ch2_en <= pwdata[2];
        pcm1_ch3_en <= pwdata[3];
        pcm1_mch_en <= pwdata[4];
        pcm1_apb_on <= pwdata[5];
      end
   end
end

// Address 0x14C: Group 83 - mch1_adma_mode and mch1_adma_data_num and adc1_adma0_mode and adc1_adma1_mode and adc1_adma2_mode and adc1_adma3_mode
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mch1_adma_mode <= 1'h0;
        mch1_adma_data_num <= 2'h0;
        adc1_adma0_mode <= 3'h6;
        adc1_adma1_mode <= 3'h6;
        adc1_adma2_mode <= 3'h6;
        adc1_adma3_mode <= 3'h6;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h53) begin
        mch1_adma_mode <= pwdata[0];
        mch1_adma_data_num <= pwdata[2:1];
        adc1_adma0_mode <= pwdata[5:3];
        adc1_adma1_mode <= pwdata[8:6];
        adc1_adma2_mode <= pwdata[11:9];
        adc1_adma3_mode <= pwdata[14:12];
      end
   end
end

// Address 0x150: Group 84 - dmic0_adma_clk_res_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        dmic0_adma_clk_res_ctrl <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h54) begin
        dmic0_adma_clk_res_ctrl <= pwdata[7:0];
      end
   end
end

// Address 0x154: Group 85 - dmic1_adma_clk_res_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        dmic1_adma_clk_res_ctrl <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h55) begin
        dmic1_adma_clk_res_ctrl <= pwdata[7:0];
      end
   end
end

// Address 0x158: Group 86 - aud_dmic0_gt_ctrl and aud_dmic1_gt_ctrl and aud_dmic2_gt_ctrl and aud_dmic3_gt_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        aud_dmic0_gt_ctrl <= 5'h10;
        aud_dmic1_gt_ctrl <= 5'h10;
        aud_dmic2_gt_ctrl <= 5'h10;
        aud_dmic3_gt_ctrl <= 5'h10;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h56) begin
        aud_dmic0_gt_ctrl <= pwdata[4:0];
        aud_dmic1_gt_ctrl <= pwdata[9:5];
        aud_dmic2_gt_ctrl <= pwdata[14:10];
        aud_dmic3_gt_ctrl <= pwdata[19:15];
      end
   end
end

// Address 0x15C: Group 87 - aud_dmic4_gt_ctrl and aud_dmic5_gt_ctrl and aud_dmic6_gt_ctrl and aud_dmic7_gt_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        aud_dmic4_gt_ctrl <= 5'h10;
        aud_dmic5_gt_ctrl <= 5'h10;
        aud_dmic6_gt_ctrl <= 5'h10;
        aud_dmic7_gt_ctrl <= 5'h10;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h57) begin
        aud_dmic4_gt_ctrl <= pwdata[4:0];
        aud_dmic5_gt_ctrl <= pwdata[9:5];
        aud_dmic6_gt_ctrl <= pwdata[14:10];
        aud_dmic7_gt_ctrl <= pwdata[19:15];
      end
   end
end

// Address 0x160: Group 88 - mcusys_dbgclk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_dbgclk_ctrl <= 10'h148;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h58) begin
        mcusys_dbgclk_ctrl <= pwdata[9:0];
      end
   end
end

// Address 0x164: Group 89 - mcusys_pll2_ctrl0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_ctrl0 <= 32'h01F81051;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h59) begin
        mcusys_pll2_ctrl0 <= pwdata[31:0];
      end
   end
end

// Address 0x168: Group 90 - mcusys_pll2_ctrl1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_ctrl1 <= 32'h00EB851F;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5A) begin
        mcusys_pll2_ctrl1 <= pwdata[31:0];
      end
   end
end

// Address 0x16C: Group 91 - mcusys_pll2_ctrl2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_ctrl2 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5B) begin
        mcusys_pll2_ctrl2 <= pwdata[31:0];
      end
   end
end

// Address 0x170: Group 92 - mcusys_pll2_ctrl3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_ctrl3 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5C) begin
        mcusys_pll2_ctrl3 <= pwdata[31:0];
      end
   end
end

// Address 0x174: Group 93 - mcusys_pll2_mon_config
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_mon_config <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5D) begin
        mcusys_pll2_mon_config <= pwdata[3:0];
      end
   end
end

// Address 0x178: Group 94 - mcusys_pll2_div_en and mcusys_pll2_pw_sw
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll2_div_en <= 8'hFF;
        mcusys_pll2_pw_sw <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5E) begin
        mcusys_pll2_div_en <= pwdata[7:0];
        mcusys_pll2_pw_sw <= pwdata[8];
      end
   end
end

// Address 0x17C: Group 95 - mcusys_pll3_ctrl0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_ctrl0 <= 32'h01F8105E;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h5F) begin
        mcusys_pll3_ctrl0 <= pwdata[31:0];
      end
   end
end

// Address 0x180: Group 96 - mcusys_pll3_ctrl1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_ctrl1 <= 32'h0147AE1;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h60) begin
        mcusys_pll3_ctrl1 <= pwdata[31:0];
      end
   end
end

// Address 0x184: Group 97 - mcusys_pll3_ctrl2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_ctrl2 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h61) begin
        mcusys_pll3_ctrl2 <= pwdata[31:0];
      end
   end
end

// Address 0x188: Group 98 - mcusys_pll3_ctrl3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_ctrl3 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h62) begin
        mcusys_pll3_ctrl3 <= pwdata[31:0];
      end
   end
end

// Address 0x18C: Group 99 - mcusys_pll3_mon_config
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_mon_config <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h63) begin
        mcusys_pll3_mon_config <= pwdata[3:0];
      end
   end
end

// Address 0x190: Group 100 - mcusys_pll3_div_en and mcusys_pll3_pw_sw
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll3_div_en <= 8'hFF;
        mcusys_pll3_pw_sw <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h64) begin
        mcusys_pll3_div_en <= pwdata[7:0];
        mcusys_pll3_pw_sw <= pwdata[8];
      end
   end
end

// Address 0x194: Group 101 - mcusys_pll4_ctrl0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_ctrl0 <= 32'h01783190;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h65) begin
        mcusys_pll4_ctrl0 <= pwdata[31:0];
      end
   end
end

// Address 0x198: Group 102 - mcusys_pll4_ctrl1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_ctrl1 <= 32'h00000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h66) begin
        mcusys_pll4_ctrl1 <= pwdata[31:0];
      end
   end
end

// Address 0x19C: Group 103 - mcusys_pll4_ctrl2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_ctrl2 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h67) begin
        mcusys_pll4_ctrl2 <= pwdata[31:0];
      end
   end
end

// Address 0x1A0: Group 104 - mcusys_pll4_ctrl3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_ctrl3 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h68) begin
        mcusys_pll4_ctrl3 <= pwdata[31:0];
      end
   end
end

// Address 0x1A4: Group 105 - mcusys_pll4_mon_config
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_mon_config <= 4'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h69) begin
        mcusys_pll4_mon_config <= pwdata[3:0];
      end
   end
end

// Address 0x1A8: Group 106 - mcusys_pll4_div_en and mcusys_pll4_pw_sw
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcusys_pll4_div_en <= 8'hFF;
        mcusys_pll4_pw_sw <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6A) begin
        mcusys_pll4_div_en <= pwdata[7:0];
        mcusys_pll4_pw_sw <= pwdata[8];
      end
   end
end

// Address 0x1AC: Group 107 - axi_sram_control and axi_sram_gating_en
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        axi_sram_control <= 4'h0;
        axi_sram_gating_en <= 2'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6B) begin
        axi_sram_control <= pwdata[3:0];
        axi_sram_gating_en <= pwdata[5:4];
      end
   end
end

// Address 0x1B0: Group 108 - rv_core4_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_core4_cfg <= 32'h000b0068;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6C) begin
        rv_core4_cfg <= pwdata[31:0];
      end
   end
end

// Address 0x1B4: Group 109 - rv_reset_vector
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_reset_vector <= 32'h10000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6D) begin
        rv_reset_vector <= pwdata[31:0];
      end
   end
end

// Address 0x1B8: Group 110 - rv_hart_id
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_hart_id <= 10'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6E) begin
        rv_hart_id <= pwdata[9:0];
      end
   end
end

// Address 0x1BC: Group 111 - rv_stop_on_reset
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_stop_on_reset <= 1'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h6F) begin
        rv_stop_on_reset <= pwdata[0];
      end
   end
end

// Address 0x1C0: Group 112 - rv_ecc_msk0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_ecc_msk0 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h70) begin
        rv_ecc_msk0 <= pwdata[31:0];
      end
   end
end

// Address 0x1C4: Group 113 - rv_ecc_msk1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        rv_ecc_msk1 <= 32'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h71) begin
        rv_ecc_msk1 <= pwdata[31:0];
      end
   end
end

// Address 0x1FC: Group 127 - mem_ema_cfg_31_0
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mem_ema_cfg_31_0 <= 32'h45054415;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h7F) begin
        mem_ema_cfg_31_0 <= pwdata[31:0];
      end
   end
end

// Address 0x200: Group 128 - mem_ema_cfg_63_32
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mem_ema_cfg_63_32 <= 32'hE4205434;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h80) begin
        mem_ema_cfg_63_32 <= pwdata[31:0];
      end
   end
end

// Address 0x204: Group 129 - mem_ema_cfg_95_64
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mem_ema_cfg_95_64 <= 32'h000008B94;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h81) begin
        mem_ema_cfg_95_64 <= pwdata[31:0];
      end
   end
end

// Address 0x208: Group 130 - mem_ema_cfg_127_96
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mem_ema_cfg_127_96 <= 32'h00000000;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h82) begin
        mem_ema_cfg_127_96 <= pwdata[31:0];
      end
   end
end

// Address 0x20C: Group 131 - ref_clk_io_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        ref_clk_io_cfg <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h83) begin
        ref_clk_io_cfg <= pwdata[7:0];
      end
   end
end

// Address 0x210: Group 132 - gpio_pwr_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        gpio_pwr_cfg <= 16'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h84) begin
        gpio_pwr_cfg <= pwdata[15:0];
      end
   end
end

// Address 0x214: Group 133 - ext_32k_in_io_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        ext_32k_in_io_cfg <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h85) begin
        ext_32k_in_io_cfg <= pwdata[7:0];
      end
   end
end

// Address 0x218: Group 134 - mcu_trst_n_io_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        mcu_trst_n_io_cfg <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h86) begin
        mcu_trst_n_io_cfg <= pwdata[7:0];
      end
   end
end

// Address 0x21C: Group 135 - pmic_en_io_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        pmic_en_io_cfg <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h87) begin
        pmic_en_io_cfg <= pwdata[7:0];
      end
   end
end

// Address 0x220: Group 136 - reset_in_n_io_cfg
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reset_in_n_io_cfg <= 8'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h88) begin
        reset_in_n_io_cfg <= pwdata[7:0];
      end
   end
end

// Address 0x224: Group 137 - reserved2_m85_c1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved2_m85_c1 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h89) begin
        reserved2_m85_c1 <= pwdata[8:0];
      end
   end
end

// Address 0x228: Group 138 - reserved3_m85_c1
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved3_m85_c1 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8A) begin
        reserved3_m85_c1 <= pwdata[8:0];
      end
   end
end

// Address 0x22C: Group 139 - reserved0_m85_c2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved0_m85_c2 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8B) begin
        reserved0_m85_c2 <= pwdata[8:0];
      end
   end
end

// Address 0x230: Group 140 - reserved1_m85_c2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved1_m85_c2 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8C) begin
        reserved1_m85_c2 <= pwdata[8:0];
      end
   end
end

// Address 0x234: Group 141 - reserved2_m85_c2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved2_m85_c2 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8D) begin
        reserved2_m85_c2 <= pwdata[8:0];
      end
   end
end

// Address 0x238: Group 142 - reserved3_m85_c2
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved3_m85_c2 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8E) begin
        reserved3_m85_c2 <= pwdata[8:0];
      end
   end
end

// Address 0x23C: Group 143 - reserved0_m85_c3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved0_m85_c3 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h8F) begin
        reserved0_m85_c3 <= pwdata[8:0];
      end
   end
end

// Address 0x240: Group 144 - reserved1_m85_c3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved1_m85_c3 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h90) begin
        reserved1_m85_c3 <= pwdata[8:0];
      end
   end
end

// Address 0x244: Group 145 - reserved2_m85_c3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved2_m85_c3 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h91) begin
        reserved2_m85_c3 <= pwdata[8:0];
      end
   end
end

// Address 0x248: Group 146 - reserved3_m85_c3
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved3_m85_c3 <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h92) begin
        reserved3_m85_c3 <= pwdata[8:0];
      end
   end
end

// Address 0x24C: Group 147 - reserved0_rv_m
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved0_rv_m <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h93) begin
        reserved0_rv_m <= pwdata[8:0];
      end
   end
end

// Address 0x250: Group 148 - reserved1_rv_m
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved1_rv_m <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h94) begin
        reserved1_rv_m <= pwdata[8:0];
      end
   end
end

// Address 0x254: Group 149 - reserved2_rv_m
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved2_rv_m <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h95) begin
        reserved2_rv_m <= pwdata[8:0];
      end
   end
end

// Address 0x258: Group 150 - reserved3_rv_m
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved3_rv_m <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h96) begin
        reserved3_rv_m <= pwdata[8:0];
      end
   end
end

// Address 0x25C: Group 151 - reserved0_rv_s
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved0_rv_s <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h97) begin
        reserved0_rv_s <= pwdata[8:0];
      end
   end
end

// Address 0x260: Group 152 - reserved1_rv_s
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved1_rv_s <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h98) begin
        reserved1_rv_s <= pwdata[8:0];
      end
   end
end

// Address 0x264: Group 153 - reserved2_rv_s
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved2_rv_s <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h99) begin
        reserved2_rv_s <= pwdata[8:0];
      end
   end
end

// Address 0x268: Group 154 - reserved3_rv_s
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        reserved3_rv_s <= 9'h0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h9A) begin
        reserved3_rv_s <= pwdata[8:0];
      end
   end
end

// Address 0x26C: Group 155 - usb_clk_ctrl
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        usb_clk_ctrl <= 6'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h9B) begin
        usb_clk_ctrl <= pwdata[5:0];
      end
   end
end

// Address 0x270: Group 156 - usb_wk_mask and usb_wk_int_mask and usb_wk_clr and usb_vbus_drv and usb_id_ovrd_en and usb_id_ovrd_val
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        usb_wk_mask <= 6'b0;
        usb_wk_int_mask <= 1'b0;
        usb_wk_clr <= 6'b0;
        usb_vbus_drv <= 1'b0;
        usb_id_ovrd_en <= 1'b0;
        usb_id_ovrd_val <= 1'b0;
   end else begin
      if (wr_valid && paddr[9:2] == 8'h9C) begin
        usb_wk_mask <= pwdata[5:0];
        usb_wk_int_mask <= pwdata[6];
        usb_wk_clr <= pwdata[12:7];
        usb_vbus_drv <= pwdata[13];
        usb_id_ovrd_en <= pwdata[14];
        usb_id_ovrd_val <= pwdata[15];
      end
   end
end

wire mcusys_aclk_fc_done_sync;
macro_dsync u_mcusys_aclk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_aclk_fc_done),
    .o(mcusys_aclk_fc_done_sync)
);

wire mcusys_pclk_fc_done_sync;
macro_dsync u_mcusys_pclk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_pclk_fc_done),
    .o(mcusys_pclk_fc_done_sync)
);

wire mcusys_rv_core_clk_fc_done_sync;
macro_dsync u_mcusys_rv_core_clk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_rv_core_clk_fc_done),
    .o(mcusys_rv_core_clk_fc_done_sync)
);

wire mcusys_m85_core0_clk_fc_done_sync;
macro_dsync u_mcusys_m85_core0_clk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_m85_core0_clk_fc_done),
    .o(mcusys_m85_core0_clk_fc_done_sync)
);

wire mcusys_m85_core1_clk_fc_done_sync;
macro_dsync u_mcusys_m85_core1_clk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_m85_core1_clk_fc_done),
    .o(mcusys_m85_core1_clk_fc_done_sync)
);

wire mcusys_m85_core2_clk_fc_done_sync;
macro_dsync u_mcusys_m85_core2_clk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_m85_core2_clk_fc_done),
    .o(mcusys_m85_core2_clk_fc_done_sync)
);

wire mcusys_m85_core3_clk_fc_done_sync;
macro_dsync u_mcusys_m85_core3_clk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_m85_core3_clk_fc_done),
    .o(mcusys_m85_core3_clk_fc_done_sync)
);

wire [31:0] aud_spare_in_sync;
genvar aud_spare_in_sync_i;
generate
for (aud_spare_in_sync_i = 0; aud_spare_in_sync_i <= 31; aud_spare_in_sync_i = aud_spare_in_sync_i + 1) begin : u_aud_spare_in_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(aud_spare_in[aud_spare_in_sync_i]),
        .o(aud_spare_in_sync[aud_spare_in_sync_i])
    );
end
endgenerate

wire regout_gmac0_rst_clk_tx_n_o_sync;
macro_dsync u_regout_gmac0_rst_clk_tx_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_rst_clk_tx_n_o),
    .o(regout_gmac0_rst_clk_tx_n_o_sync)
);

wire regout_gmac0_rst_clk_rx_n_o_sync;
macro_dsync u_regout_gmac0_rst_clk_rx_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_rst_clk_rx_n_o),
    .o(regout_gmac0_rst_clk_rx_n_o_sync)
);

wire regout_gmac0_rst_clk_app_n_o_sync;
macro_dsync u_regout_gmac0_rst_clk_app_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_rst_clk_app_n_o),
    .o(regout_gmac0_rst_clk_app_n_o_sync)
);

wire [1:0] regout_gmac0_mac_speed_o_sync;
genvar regout_gmac0_mac_speed_o_sync_i;
generate
for (regout_gmac0_mac_speed_o_sync_i = 0; regout_gmac0_mac_speed_o_sync_i <= 1; regout_gmac0_mac_speed_o_sync_i = regout_gmac0_mac_speed_o_sync_i + 1) begin : u_regout_gmac0_mac_speed_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac0_mac_speed_o[regout_gmac0_mac_speed_o_sync_i]),
        .o(regout_gmac0_mac_speed_o_sync[regout_gmac0_mac_speed_o_sync_i])
    );
end
endgenerate

wire regout_gmac0_sbd_tx_clk_gating_ctrl_o_sync;
macro_dsync u_regout_gmac0_sbd_tx_clk_gating_ctrl_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_sbd_tx_clk_gating_ctrl_o),
    .o(regout_gmac0_sbd_tx_clk_gating_ctrl_o_sync)
);

wire [2:0] regout_gmac0_sbd_ar_dma_ch_no_o_sync;
genvar regout_gmac0_sbd_ar_dma_ch_no_o_sync_i;
generate
for (regout_gmac0_sbd_ar_dma_ch_no_o_sync_i = 0; regout_gmac0_sbd_ar_dma_ch_no_o_sync_i <= 2; regout_gmac0_sbd_ar_dma_ch_no_o_sync_i = regout_gmac0_sbd_ar_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac0_sbd_ar_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac0_sbd_ar_dma_ch_no_o[regout_gmac0_sbd_ar_dma_ch_no_o_sync_i]),
        .o(regout_gmac0_sbd_ar_dma_ch_no_o_sync[regout_gmac0_sbd_ar_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire [2:0] regout_gmac0_sbd_aw_dma_ch_no_o_sync;
genvar regout_gmac0_sbd_aw_dma_ch_no_o_sync_i;
generate
for (regout_gmac0_sbd_aw_dma_ch_no_o_sync_i = 0; regout_gmac0_sbd_aw_dma_ch_no_o_sync_i <= 2; regout_gmac0_sbd_aw_dma_ch_no_o_sync_i = regout_gmac0_sbd_aw_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac0_sbd_aw_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac0_sbd_aw_dma_ch_no_o[regout_gmac0_sbd_aw_dma_ch_no_o_sync_i]),
        .o(regout_gmac0_sbd_aw_dma_ch_no_o_sync[regout_gmac0_sbd_aw_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire [2:0] regout_gmac0_sbd_w_dma_ch_no_o_sync;
genvar regout_gmac0_sbd_w_dma_ch_no_o_sync_i;
generate
for (regout_gmac0_sbd_w_dma_ch_no_o_sync_i = 0; regout_gmac0_sbd_w_dma_ch_no_o_sync_i <= 2; regout_gmac0_sbd_w_dma_ch_no_o_sync_i = regout_gmac0_sbd_w_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac0_sbd_w_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac0_sbd_w_dma_ch_no_o[regout_gmac0_sbd_w_dma_ch_no_o_sync_i]),
        .o(regout_gmac0_sbd_w_dma_ch_no_o_sync[regout_gmac0_sbd_w_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire regout_gmac0_csysack_o_sync;
macro_dsync u_regout_gmac0_csysack_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_csysack_o),
    .o(regout_gmac0_csysack_o_sync)
);

wire regout_gmac0_cactive_o_sync;
macro_dsync u_regout_gmac0_cactive_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_cactive_o),
    .o(regout_gmac0_cactive_o_sync)
);

wire regout_gmac0_ati_datatxon_o_sync;
macro_dsync u_regout_gmac0_ati_datatxon_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_ati_datatxon_o),
    .o(regout_gmac0_ati_datatxon_o_sync)
);

wire regout_gmac0_ati_pmac_txon_o_sync;
macro_dsync u_regout_gmac0_ati_pmac_txon_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_ati_pmac_txon_o),
    .o(regout_gmac0_ati_pmac_txon_o_sync)
);

wire regout_gmac0_ati_pmac_actv_o_sync;
macro_dsync u_regout_gmac0_ati_pmac_actv_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_ati_pmac_actv_o),
    .o(regout_gmac0_ati_pmac_actv_o_sync)
);

wire [1:0] regout_gmac0_mcgr_dma_req_o_sync;
genvar regout_gmac0_mcgr_dma_req_o_sync_i;
generate
for (regout_gmac0_mcgr_dma_req_o_sync_i = 0; regout_gmac0_mcgr_dma_req_o_sync_i <= 1; regout_gmac0_mcgr_dma_req_o_sync_i = regout_gmac0_mcgr_dma_req_o_sync_i + 1) begin : u_regout_gmac0_mcgr_dma_req_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac0_mcgr_dma_req_o[regout_gmac0_mcgr_dma_req_o_sync_i]),
        .o(regout_gmac0_mcgr_dma_req_o_sync[regout_gmac0_mcgr_dma_req_o_sync_i])
    );
end
endgenerate

wire regout_gmac0_sbd_pwr_down_ack_o_sync;
macro_dsync u_regout_gmac0_sbd_pwr_down_ack_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac0_sbd_pwr_down_ack_o),
    .o(regout_gmac0_sbd_pwr_down_ack_o_sync)
);

wire regout_gmac1_rst_clk_tx_n_o_sync;
macro_dsync u_regout_gmac1_rst_clk_tx_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_rst_clk_tx_n_o),
    .o(regout_gmac1_rst_clk_tx_n_o_sync)
);

wire regout_gmac1_rst_clk_rx_n_o_sync;
macro_dsync u_regout_gmac1_rst_clk_rx_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_rst_clk_rx_n_o),
    .o(regout_gmac1_rst_clk_rx_n_o_sync)
);

wire regout_gmac1_rst_clk_app_n_o_sync;
macro_dsync u_regout_gmac1_rst_clk_app_n_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_rst_clk_app_n_o),
    .o(regout_gmac1_rst_clk_app_n_o_sync)
);

wire [1:0] regout_gmac1_mac_speed_o_sync;
genvar regout_gmac1_mac_speed_o_sync_i;
generate
for (regout_gmac1_mac_speed_o_sync_i = 0; regout_gmac1_mac_speed_o_sync_i <= 1; regout_gmac1_mac_speed_o_sync_i = regout_gmac1_mac_speed_o_sync_i + 1) begin : u_regout_gmac1_mac_speed_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac1_mac_speed_o[regout_gmac1_mac_speed_o_sync_i]),
        .o(regout_gmac1_mac_speed_o_sync[regout_gmac1_mac_speed_o_sync_i])
    );
end
endgenerate

wire regout_gmac1_sbd_tx_clk_gating_ctrl_o_sync;
macro_dsync u_regout_gmac1_sbd_tx_clk_gating_ctrl_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_sbd_tx_clk_gating_ctrl_o),
    .o(regout_gmac1_sbd_tx_clk_gating_ctrl_o_sync)
);

wire [2:0] regout_gmac1_sbd_ar_dma_ch_no_o_sync;
genvar regout_gmac1_sbd_ar_dma_ch_no_o_sync_i;
generate
for (regout_gmac1_sbd_ar_dma_ch_no_o_sync_i = 0; regout_gmac1_sbd_ar_dma_ch_no_o_sync_i <= 2; regout_gmac1_sbd_ar_dma_ch_no_o_sync_i = regout_gmac1_sbd_ar_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac1_sbd_ar_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac1_sbd_ar_dma_ch_no_o[regout_gmac1_sbd_ar_dma_ch_no_o_sync_i]),
        .o(regout_gmac1_sbd_ar_dma_ch_no_o_sync[regout_gmac1_sbd_ar_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire [2:0] regout_gmac1_sbd_aw_dma_ch_no_o_sync;
genvar regout_gmac1_sbd_aw_dma_ch_no_o_sync_i;
generate
for (regout_gmac1_sbd_aw_dma_ch_no_o_sync_i = 0; regout_gmac1_sbd_aw_dma_ch_no_o_sync_i <= 2; regout_gmac1_sbd_aw_dma_ch_no_o_sync_i = regout_gmac1_sbd_aw_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac1_sbd_aw_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac1_sbd_aw_dma_ch_no_o[regout_gmac1_sbd_aw_dma_ch_no_o_sync_i]),
        .o(regout_gmac1_sbd_aw_dma_ch_no_o_sync[regout_gmac1_sbd_aw_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire [2:0] regout_gmac1_sbd_w_dma_ch_no_o_sync;
genvar regout_gmac1_sbd_w_dma_ch_no_o_sync_i;
generate
for (regout_gmac1_sbd_w_dma_ch_no_o_sync_i = 0; regout_gmac1_sbd_w_dma_ch_no_o_sync_i <= 2; regout_gmac1_sbd_w_dma_ch_no_o_sync_i = regout_gmac1_sbd_w_dma_ch_no_o_sync_i + 1) begin : u_regout_gmac1_sbd_w_dma_ch_no_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac1_sbd_w_dma_ch_no_o[regout_gmac1_sbd_w_dma_ch_no_o_sync_i]),
        .o(regout_gmac1_sbd_w_dma_ch_no_o_sync[regout_gmac1_sbd_w_dma_ch_no_o_sync_i])
    );
end
endgenerate

wire regout_gmac1_csysack_o_sync;
macro_dsync u_regout_gmac1_csysack_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_csysack_o),
    .o(regout_gmac1_csysack_o_sync)
);

wire regout_gmac1_cactive_o_sync;
macro_dsync u_regout_gmac1_cactive_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_cactive_o),
    .o(regout_gmac1_cactive_o_sync)
);

wire regout_gmac1_ati_datatxon_o_sync;
macro_dsync u_regout_gmac1_ati_datatxon_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_ati_datatxon_o),
    .o(regout_gmac1_ati_datatxon_o_sync)
);

wire regout_gmac1_ati_pmac_txon_o_sync;
macro_dsync u_regout_gmac1_ati_pmac_txon_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_ati_pmac_txon_o),
    .o(regout_gmac1_ati_pmac_txon_o_sync)
);

wire regout_gmac1_ati_pmac_actv_o_sync;
macro_dsync u_regout_gmac1_ati_pmac_actv_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_ati_pmac_actv_o),
    .o(regout_gmac1_ati_pmac_actv_o_sync)
);

wire [1:0] regout_gmac1_mcgr_dma_req_o_sync;
genvar regout_gmac1_mcgr_dma_req_o_sync_i;
generate
for (regout_gmac1_mcgr_dma_req_o_sync_i = 0; regout_gmac1_mcgr_dma_req_o_sync_i <= 1; regout_gmac1_mcgr_dma_req_o_sync_i = regout_gmac1_mcgr_dma_req_o_sync_i + 1) begin : u_regout_gmac1_mcgr_dma_req_o_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(regout_gmac1_mcgr_dma_req_o[regout_gmac1_mcgr_dma_req_o_sync_i]),
        .o(regout_gmac1_mcgr_dma_req_o_sync[regout_gmac1_mcgr_dma_req_o_sync_i])
    );
end
endgenerate

wire regout_gmac1_sbd_pwr_down_ack_o_sync;
macro_dsync u_regout_gmac1_sbd_pwr_down_ack_o_sync (
    .ck(pclk),
    .clb(prstn),
    .d(regout_gmac1_sbd_pwr_down_ack_o),
    .o(regout_gmac1_sbd_pwr_down_ack_o_sync)
);

wire mcusys_dbgclk_fc_done_sync;
macro_dsync u_mcusys_dbgclk_fc_done_sync (
    .ck(pclk),
    .clb(prstn),
    .d(mcusys_dbgclk_fc_done),
    .o(mcusys_dbgclk_fc_done_sync)
);

wire [31:0] rv_ecc_status0_sync;
genvar rv_ecc_status0_sync_i;
generate
for (rv_ecc_status0_sync_i = 0; rv_ecc_status0_sync_i <= 31; rv_ecc_status0_sync_i = rv_ecc_status0_sync_i + 1) begin : u_rv_ecc_status0_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_ecc_status0[rv_ecc_status0_sync_i]),
        .o(rv_ecc_status0_sync[rv_ecc_status0_sync_i])
    );
end
endgenerate

wire [17:0] rv_ecc_status1_sync;
genvar rv_ecc_status1_sync_i;
generate
for (rv_ecc_status1_sync_i = 0; rv_ecc_status1_sync_i <= 17; rv_ecc_status1_sync_i = rv_ecc_status1_sync_i + 1) begin : u_rv_ecc_status1_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_ecc_status1[rv_ecc_status1_sync_i]),
        .o(rv_ecc_status1_sync[rv_ecc_status1_sync_i])
    );
end
endgenerate

wire [1:0] rv_lockstep_mis_sync;
genvar rv_lockstep_mis_sync_i;
generate
for (rv_lockstep_mis_sync_i = 0; rv_lockstep_mis_sync_i <= 1; rv_lockstep_mis_sync_i = rv_lockstep_mis_sync_i + 1) begin : u_rv_lockstep_mis_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_lockstep_mis[rv_lockstep_mis_sync_i]),
        .o(rv_lockstep_mis_sync[rv_lockstep_mis_sync_i])
    );
end
endgenerate

wire [1:0] rv_safety_error_sync;
genvar rv_safety_error_sync_i;
generate
for (rv_safety_error_sync_i = 0; rv_safety_error_sync_i <= 1; rv_safety_error_sync_i = rv_safety_error_sync_i + 1) begin : u_rv_safety_error_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_safety_error[rv_safety_error_sync_i]),
        .o(rv_safety_error_sync[rv_safety_error_sync_i])
    );
end
endgenerate

wire [1:0] rv_safety_input_error_dcls_sync;
genvar rv_safety_input_error_dcls_sync_i;
generate
for (rv_safety_input_error_dcls_sync_i = 0; rv_safety_input_error_dcls_sync_i <= 1; rv_safety_input_error_dcls_sync_i = rv_safety_input_error_dcls_sync_i + 1) begin : u_rv_safety_input_error_dcls_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_safety_input_error_dcls[rv_safety_input_error_dcls_sync_i]),
        .o(rv_safety_input_error_dcls_sync[rv_safety_input_error_dcls_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status0_sync;
genvar rv_core_status0_sync_i;
generate
for (rv_core_status0_sync_i = 0; rv_core_status0_sync_i <= 31; rv_core_status0_sync_i = rv_core_status0_sync_i + 1) begin : u_rv_core_status0_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status0[rv_core_status0_sync_i]),
        .o(rv_core_status0_sync[rv_core_status0_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status1_sync;
genvar rv_core_status1_sync_i;
generate
for (rv_core_status1_sync_i = 0; rv_core_status1_sync_i <= 31; rv_core_status1_sync_i = rv_core_status1_sync_i + 1) begin : u_rv_core_status1_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status1[rv_core_status1_sync_i]),
        .o(rv_core_status1_sync[rv_core_status1_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status2_sync;
genvar rv_core_status2_sync_i;
generate
for (rv_core_status2_sync_i = 0; rv_core_status2_sync_i <= 31; rv_core_status2_sync_i = rv_core_status2_sync_i + 1) begin : u_rv_core_status2_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status2[rv_core_status2_sync_i]),
        .o(rv_core_status2_sync[rv_core_status2_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status3_sync;
genvar rv_core_status3_sync_i;
generate
for (rv_core_status3_sync_i = 0; rv_core_status3_sync_i <= 31; rv_core_status3_sync_i = rv_core_status3_sync_i + 1) begin : u_rv_core_status3_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status3[rv_core_status3_sync_i]),
        .o(rv_core_status3_sync[rv_core_status3_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status4_sync;
genvar rv_core_status4_sync_i;
generate
for (rv_core_status4_sync_i = 0; rv_core_status4_sync_i <= 31; rv_core_status4_sync_i = rv_core_status4_sync_i + 1) begin : u_rv_core_status4_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status4[rv_core_status4_sync_i]),
        .o(rv_core_status4_sync[rv_core_status4_sync_i])
    );
end
endgenerate

wire [31:0] rv_core_status5_sync;
genvar rv_core_status5_sync_i;
generate
for (rv_core_status5_sync_i = 0; rv_core_status5_sync_i <= 31; rv_core_status5_sync_i = rv_core_status5_sync_i + 1) begin : u_rv_core_status5_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_core_status5[rv_core_status5_sync_i]),
        .o(rv_core_status5_sync[rv_core_status5_sync_i])
    );
end
endgenerate

wire [31:0] rv_i1_core_status1_sync;
genvar rv_i1_core_status1_sync_i;
generate
for (rv_i1_core_status1_sync_i = 0; rv_i1_core_status1_sync_i <= 31; rv_i1_core_status1_sync_i = rv_i1_core_status1_sync_i + 1) begin : u_rv_i1_core_status1_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_i1_core_status1[rv_i1_core_status1_sync_i]),
        .o(rv_i1_core_status1_sync[rv_i1_core_status1_sync_i])
    );
end
endgenerate

wire [31:0] rv_i1_core_status2_sync;
genvar rv_i1_core_status2_sync_i;
generate
for (rv_i1_core_status2_sync_i = 0; rv_i1_core_status2_sync_i <= 31; rv_i1_core_status2_sync_i = rv_i1_core_status2_sync_i + 1) begin : u_rv_i1_core_status2_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_i1_core_status2[rv_i1_core_status2_sync_i]),
        .o(rv_i1_core_status2_sync[rv_i1_core_status2_sync_i])
    );
end
endgenerate

wire [31:0] rv_i1_core_status3_sync;
genvar rv_i1_core_status3_sync_i;
generate
for (rv_i1_core_status3_sync_i = 0; rv_i1_core_status3_sync_i <= 31; rv_i1_core_status3_sync_i = rv_i1_core_status3_sync_i + 1) begin : u_rv_i1_core_status3_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_i1_core_status3[rv_i1_core_status3_sync_i]),
        .o(rv_i1_core_status3_sync[rv_i1_core_status3_sync_i])
    );
end
endgenerate

wire [31:0] rv_i1_core_status4_sync;
genvar rv_i1_core_status4_sync_i;
generate
for (rv_i1_core_status4_sync_i = 0; rv_i1_core_status4_sync_i <= 31; rv_i1_core_status4_sync_i = rv_i1_core_status4_sync_i + 1) begin : u_rv_i1_core_status4_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(rv_i1_core_status4[rv_i1_core_status4_sync_i]),
        .o(rv_i1_core_status4_sync[rv_i1_core_status4_sync_i])
    );
end
endgenerate

wire [5:0] usb_wk_status_sync;
genvar usb_wk_status_sync_i;
generate
for (usb_wk_status_sync_i = 0; usb_wk_status_sync_i <= 5; usb_wk_status_sync_i = usb_wk_status_sync_i + 1) begin : u_usb_wk_status_sync
    macro_dsync u_dsync (
        .ck(pclk),
        .clb(prstn),
        .d(usb_wk_status[usb_wk_status_sync_i]),
        .o(usb_wk_status_sync[usb_wk_status_sync_i])
    );
end
endgenerate

wire usb_wk_int_status_sync;
macro_dsync u_usb_wk_int_status_sync (
    .ck(pclk),
    .clb(prstn),
    .d(usb_wk_int_status),
    .o(usb_wk_int_status_sync)
);


// latch prdata
reg [31:0] prdata_d;
always @(posedge pclk or negedge prstn) begin
   if (~prstn) begin
        prdata_d <= 32'h0;
   end else begin
       if(psel) begin
            prdata_d <= prdata;
       end
   end
end

// APB read data mux
always @( * ) begin
    case(paddr[9:2])
      8'h00: prdata = {15'b0, force_all_clk_on, MGCR};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x000 - Group 0
      8'h01: prdata = {26'b0, mcusys_aclk_fc_done_sync, mcusys_aclk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x004 - Group 1
      8'h02: prdata = {26'b0, mcusys_pclk_fc_done_sync, mcusys_pclk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x008 - Group 2
      8'h03: prdata = {26'b0, mcusys_rv_core_clk_fc_done_sync, mcusys_rv_core_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x00C - Group 3
      8'h04: prdata = {26'b0, mcusys_m85_core0_clk_fc_done_sync, mcusys_m85_core0_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x010 - Group 4
      8'h05: prdata = {26'b0, mcusys_m85_core1_clk_fc_done_sync, mcusys_m85_core1_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x014 - Group 5
      8'h06: prdata = {26'b0, mcusys_m85_core2_clk_fc_done_sync, mcusys_m85_core2_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x018 - Group 6
      8'h07: prdata = {26'b0, mcusys_m85_core3_clk_fc_done_sync, mcusys_m85_core3_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x01C - Group 7
      8'h08: prdata = {31'b0, rv_core_sw_rstn};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             // 0x020 - Group 8
      8'h09: prdata = {31'b0, m85_core0_sw_rstn};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x024 - Group 9
      8'h0A: prdata = {31'b0, m85_core1_sw_rstn};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x028 - Group 10
      8'h0B: prdata = {31'b0, m85_core2_sw_rstn};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x02C - Group 11
      8'h0C: prdata = {31'b0, m85_core3_sw_rstn};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x030 - Group 12
      8'h0D: prdata = m85_core0_cfg0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x034 - Group 13
      8'h0E: prdata = m85_core0_cfg1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x038 - Group 14
      8'h0F: prdata = m85_core0_cfg2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x03C - Group 15
      8'h10: prdata = {6'b0, m85_core0_cfg_ns_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x040 - Group 16
      8'h11: prdata = {6'b0, m85_core0_cfg_s_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x044 - Group 17
      8'h12: prdata = m85_core0_cfg_s_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               // 0x048 - Group 18
      8'h13: prdata = m85_core0_cfg_ns_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x04C - Group 19
      8'h14: prdata = m85_core0_cfg_dptarget_id;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x050 - Group 20
      8'h15: prdata = m85_core1_cfg0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x054 - Group 21
      8'h16: prdata = m85_core1_cfg1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x058 - Group 22
      8'h17: prdata = m85_core1_cfg2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x05C - Group 23
      8'h18: prdata = {6'b0, m85_core1_cfg_ns_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x060 - Group 24
      8'h19: prdata = {6'b0, m85_core1_cfg_s_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x064 - Group 25
      8'h1A: prdata = m85_core1_cfg_s_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               // 0x068 - Group 26
      8'h1B: prdata = m85_core1_cfg_ns_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x06C - Group 27
      8'h1C: prdata = m85_core1_cfg_dptarget_id;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x070 - Group 28
      8'h1D: prdata = m85_core2_cfg0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x074 - Group 29
      8'h1E: prdata = m85_core2_cfg1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x078 - Group 30
      8'h1F: prdata = m85_core2_cfg2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x07C - Group 31
      8'h20: prdata = {6'b0, m85_core2_cfg_ns_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x080 - Group 32
      8'h21: prdata = {6'b0, m85_core2_cfg_s_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x084 - Group 33
      8'h22: prdata = m85_core2_cfg_s_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               // 0x088 - Group 34
      8'h23: prdata = m85_core2_cfg_ns_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x08C - Group 35
      8'h24: prdata = m85_core2_cfg_dptarget_id;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x090 - Group 36
      8'h25: prdata = m85_core3_cfg0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x094 - Group 37
      8'h26: prdata = m85_core3_cfg1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x098 - Group 38
      8'h27: prdata = m85_core3_cfg2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x09C - Group 39
      8'h28: prdata = {6'b0, m85_core3_cfg_ns_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x0A0 - Group 40
      8'h29: prdata = {6'b0, m85_core3_cfg_s_systick};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x0A4 - Group 41
      8'h2A: prdata = m85_core3_cfg_s_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               // 0x0A8 - Group 42
      8'h2B: prdata = m85_core3_cfg_ns_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x0AC - Group 43
      8'h2C: prdata = m85_core3_cfg_dptarget_id;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x0B0 - Group 44
      8'h2D: prdata = mcusys_pll1_ctrl0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0B4 - Group 45
      8'h2E: prdata = mcusys_pll1_ctrl1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0B8 - Group 46
      8'h2F: prdata = mcusys_pll1_ctrl2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0BC - Group 47
      8'h30: prdata = mcusys_pll1_ctrl3;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0C0 - Group 48
      8'h31: prdata = {28'b0, mcusys_pll1_mon_config};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x0C4 - Group 49
      8'h32: prdata = {23'b0, mcusys_pll1_pw_sw, mcusys_pll1_div_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x0C8 - Group 50
      8'h33: prdata = mcusys_rsvd0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x0CC - Group 51
      8'h34: prdata = mcusys_rsvd1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x0D0 - Group 52
      8'h35: prdata = mcusys_rsvd2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x0D4 - Group 53
      8'h36: prdata = {28'b0, mcusys_rsvd3};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x0D8 - Group 54
      8'h37: prdata = {24'b0, mcusys_rsvd4};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x0DC - Group 55
      8'h38: prdata = mcusys_rsvd5;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x0E0 - Group 56
      8'h39: prdata = arqos_mcu_sys_fab;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0E4 - Group 57
      8'h3A: prdata = awqos_mcu_sys_fab;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x0E8 - Group 58
      8'h3B: prdata = arqos_mcucore_sys_fab;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x0EC - Group 59
      8'h3C: prdata = awqos_mcucore_sys_fab;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x0F0 - Group 60
      8'h3D: prdata = {20'b0, m85_core0_cfg_dclscorectl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   // 0x0F4 - Group 61
      8'h3E: prdata = {20'b0, m85_core1_cfg_dclscorectl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   // 0x0F8 - Group 62
      8'h3F: prdata = {20'b0, m85_core2_cfg_dclscorectl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   // 0x0FC - Group 63
      8'h40: prdata = {20'b0, m85_core3_cfg_dclscorectl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   // 0x100 - Group 64
      8'h41: prdata = aud_spare_in_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x104 - Group 65
      8'h42: prdata = {19'b0, gmac0_clk_1588_sel, gmac0_refclk_sel, gmac0_1588_clk_en, gmac0_rgmii_txc_src_sel, gmac0_phy_intf_sel_i, gmac0_rx_refclk_phase_sel, gmac0_rmii_refclk_phase_sel, gmac0_speed_mode};                                                                                                                                                                                                                                                                                                                                                            // 0x108 - Group 66
      8'h43: prdata = {3'b0, gmac0_rgmii_rxc_dline_adj, gmac0_rgmii_rxc_dline_range, gmac0_rgmii_rxc_dline_pu};                                                                                                                                                                                                                                                                                                                                                                                                                                                             // 0x10C - Group 67
      8'h44: prdata = {3'b0, gmac0_rgmii_txc_dline_adj, gmac0_rgmii_txc_dline_range, gmac0_rgmii_txc_dline_pu};                                                                                                                                                                                                                                                                                                                                                                                                                                                             // 0x110 - Group 68
      8'h45: prdata = {19'b0, gmac1_clk_1588_sel, gmac1_refclk_sel, gmac1_1588_clk_en, gmac1_rgmii_txc_src_sel, gmac1_phy_intf_sel_i, gmac1_rx_refclk_phase_sel, gmac1_rmii_refclk_phase_sel, gmac1_speed_mode};                                                                                                                                                                                                                                                                                                                                                            // 0x114 - Group 69
      8'h46: prdata = {3'b0, gmac1_rgmii_rxc_dline_adj, gmac1_rgmii_rxc_dline_range, gmac1_rgmii_rxc_dline_pu};                                                                                                                                                                                                                                                                                                                                                                                                                                                             // 0x118 - Group 70
      8'h47: prdata = {3'b0, gmac1_rgmii_txc_dline_adj, gmac1_rgmii_txc_dline_range, gmac1_rgmii_txc_dline_pu};                                                                                                                                                                                                                                                                                                                                                                                                                                                             // 0x11C - Group 71
      8'h48: prdata = {18'b0, regin_gmac0_sbd_pc_tim_wdw_i, regin_gmac0_mcgr_dma_ack_i, regin_gmac0_mcg_pst_trig_i, regin_gmac0_sbd_pmac_hold_i, regin_gmac0_csysreq_i, regin_gmac0_pwr_down_ctrl_i, regin_gmac0_pwr_clamp_ctrl_i, regin_gmac0_pwr_isolate_i, regin_gmac0_sys_rst_n};                                                                                                                                                                                                                                                                                       // 0x120 - Group 72
      8'h49: prdata = {16'b0, regin_gmac0_cfg_clamp_en, regin_gmac0_intr_mask, regin_gmac0_clk_gate};                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x124 - Group 73
      8'h4A: prdata = {9'b0, regout_gmac0_sbd_pwr_down_ack_o_sync, regout_gmac0_mcgr_dma_req_o_sync, regout_gmac0_ati_pmac_actv_o_sync, regout_gmac0_ati_pmac_txon_o_sync, regout_gmac0_ati_datatxon_o_sync, regout_gmac0_cactive_o_sync, regout_gmac0_csysack_o_sync, regout_gmac0_sbd_w_dma_ch_no_o_sync, regout_gmac0_sbd_aw_dma_ch_no_o_sync, regout_gmac0_sbd_ar_dma_ch_no_o_sync, regout_gmac0_sbd_tx_clk_gating_ctrl_o_sync, regout_gmac0_mac_speed_o_sync, regout_gmac0_rst_clk_app_n_o_sync, regout_gmac0_rst_clk_rx_n_o_sync, regout_gmac0_rst_clk_tx_n_o_sync};  // 0x128 - Group 74
      8'h4B: prdata = {18'b0, regin_gmac1_sbd_pc_tim_wdw_i, regin_gmac1_mcgr_dma_ack_i, regin_gmac1_mcg_pst_trig_i, regin_gmac1_sbd_pmac_hold_i, regin_gmac1_csysreq_i, regin_gmac1_pwr_down_ctrl_i, regin_gmac1_pwr_clamp_ctrl_i, regin_gmac1_pwr_isolate_i, regin_gmac1_sys_rst_n};                                                                                                                                                                                                                                                                                       // 0x12C - Group 75
      8'h4C: prdata = {16'b0, regin_gmac1_cfg_clamp_en, regin_gmac1_intr_mask, regin_gmac1_clk_gate};                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x130 - Group 76
      8'h4D: prdata = {9'b0, regout_gmac1_sbd_pwr_down_ack_o_sync, regout_gmac1_mcgr_dma_req_o_sync, regout_gmac1_ati_pmac_actv_o_sync, regout_gmac1_ati_pmac_txon_o_sync, regout_gmac1_ati_datatxon_o_sync, regout_gmac1_cactive_o_sync, regout_gmac1_csysack_o_sync, regout_gmac1_sbd_w_dma_ch_no_o_sync, regout_gmac1_sbd_aw_dma_ch_no_o_sync, regout_gmac1_sbd_ar_dma_ch_no_o_sync, regout_gmac1_sbd_tx_clk_gating_ctrl_o_sync, regout_gmac1_mac_speed_o_sync, regout_gmac1_rst_clk_app_n_o_sync, regout_gmac1_rst_clk_rx_n_o_sync, regout_gmac1_rst_clk_tx_n_o_sync};  // 0x134 - Group 77
      8'h4E: prdata = {13'b0, pcm_clk_res_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x138 - Group 78
      8'h4F: prdata = {26'b0, pcm_apb_on, pcm_mch_en, pcm0_ch3_en, pcm0_ch2_en, pcm0_ch1_en, pcm0_ch0_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x13C - Group 79
      8'h50: prdata = {17'b0, adc0_adma3_mode, adc0_adma2_mode, adc0_adma1_mode, adc0_adma0_mode, mch_adma_data_num, mch_adma_mode};                                                                                                                                                                                                                                                                                                                                                                                                                                        // 0x140 - Group 80
      8'h51: prdata = {13'b0, pcm1_clk_res_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x144 - Group 81
      8'h52: prdata = {26'b0, pcm1_apb_on, pcm1_mch_en, pcm1_ch3_en, pcm1_ch2_en, pcm1_ch1_en, pcm1_ch0_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x148 - Group 82
      8'h53: prdata = {17'b0, adc1_adma3_mode, adc1_adma2_mode, adc1_adma1_mode, adc1_adma0_mode, mch1_adma_data_num, mch1_adma_mode};                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x14C - Group 83
      8'h54: prdata = {24'b0, dmic0_adma_clk_res_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x150 - Group 84
      8'h55: prdata = {24'b0, dmic1_adma_clk_res_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x154 - Group 85
      8'h56: prdata = {12'b0, aud_dmic3_gt_ctrl, aud_dmic2_gt_ctrl, aud_dmic1_gt_ctrl, aud_dmic0_gt_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x158 - Group 86
      8'h57: prdata = {12'b0, aud_dmic7_gt_ctrl, aud_dmic6_gt_ctrl, aud_dmic5_gt_ctrl, aud_dmic4_gt_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x15C - Group 87
      8'h58: prdata = {21'b0, mcusys_dbgclk_fc_done_sync, mcusys_dbgclk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x160 - Group 88
      8'h59: prdata = mcusys_pll2_ctrl0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x164 - Group 89
      8'h5A: prdata = mcusys_pll2_ctrl1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x168 - Group 90
      8'h5B: prdata = mcusys_pll2_ctrl2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x16C - Group 91
      8'h5C: prdata = mcusys_pll2_ctrl3;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x170 - Group 92
      8'h5D: prdata = {28'b0, mcusys_pll2_mon_config};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x174 - Group 93
      8'h5E: prdata = {23'b0, mcusys_pll2_pw_sw, mcusys_pll2_div_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x178 - Group 94
      8'h5F: prdata = mcusys_pll3_ctrl0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x17C - Group 95
      8'h60: prdata = mcusys_pll3_ctrl1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x180 - Group 96
      8'h61: prdata = mcusys_pll3_ctrl2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x184 - Group 97
      8'h62: prdata = mcusys_pll3_ctrl3;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x188 - Group 98
      8'h63: prdata = {28'b0, mcusys_pll3_mon_config};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x18C - Group 99
      8'h64: prdata = {23'b0, mcusys_pll3_pw_sw, mcusys_pll3_div_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x190 - Group 100
      8'h65: prdata = mcusys_pll4_ctrl0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x194 - Group 101
      8'h66: prdata = mcusys_pll4_ctrl1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x198 - Group 102
      8'h67: prdata = mcusys_pll4_ctrl2;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x19C - Group 103
      8'h68: prdata = mcusys_pll4_ctrl3;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x1A0 - Group 104
      8'h69: prdata = {28'b0, mcusys_pll4_mon_config};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x1A4 - Group 105
      8'h6A: prdata = {23'b0, mcusys_pll4_pw_sw, mcusys_pll4_div_en};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       // 0x1A8 - Group 106
      8'h6B: prdata = {26'b0, axi_sram_gating_en, axi_sram_control};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        // 0x1AC - Group 107
      8'h6C: prdata = rv_core4_cfg;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x1B0 - Group 108
      8'h6D: prdata = rv_reset_vector;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      // 0x1B4 - Group 109
      8'h6E: prdata = {22'b0, rv_hart_id};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x1B8 - Group 110
      8'h6F: prdata = {31'b0, rv_stop_on_reset};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x1BC - Group 111
      8'h70: prdata = rv_ecc_msk0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          // 0x1C0 - Group 112
      8'h71: prdata = rv_ecc_msk1;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          // 0x1C4 - Group 113
      8'h72: prdata = rv_ecc_status0_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  // 0x1C8 - Group 114
      8'h73: prdata = {14'b0, rv_ecc_status1_sync};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         // 0x1CC - Group 115
      8'h74: prdata = {26'b0, rv_safety_input_error_dcls_sync, rv_safety_error_sync, rv_lockstep_mis_sync};                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1D0 - Group 116
      8'h75: prdata = rv_core_status0_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1D4 - Group 117
      8'h76: prdata = rv_core_status1_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1D8 - Group 118
      8'h77: prdata = rv_core_status2_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1DC - Group 119
      8'h78: prdata = rv_core_status3_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1E0 - Group 120
      8'h79: prdata = rv_core_status4_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1E4 - Group 121
      8'h7A: prdata = rv_core_status5_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 // 0x1E8 - Group 122
      8'h7B: prdata = rv_i1_core_status1_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x1EC - Group 123
      8'h7C: prdata = rv_i1_core_status2_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x1F0 - Group 124
      8'h7D: prdata = rv_i1_core_status3_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x1F4 - Group 125
      8'h7E: prdata = rv_i1_core_status4_sync;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x1F8 - Group 126
      8'h7F: prdata = mem_ema_cfg_31_0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     // 0x1FC - Group 127
      8'h80: prdata = mem_ema_cfg_63_32;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x200 - Group 128
      8'h81: prdata = mem_ema_cfg_95_64;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    // 0x204 - Group 129
      8'h82: prdata = mem_ema_cfg_127_96;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   // 0x208 - Group 130
      8'h83: prdata = {24'b0, ref_clk_io_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x20C - Group 131
      8'h84: prdata = {16'b0, gpio_pwr_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x210 - Group 132
      8'h85: prdata = {24'b0, ext_32k_in_io_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x214 - Group 133
      8'h86: prdata = {24'b0, mcu_trst_n_io_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x218 - Group 134
      8'h87: prdata = {24'b0, pmic_en_io_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x21C - Group 135
      8'h88: prdata = {24'b0, reset_in_n_io_cfg};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           // 0x220 - Group 136
      8'h89: prdata = {23'b0, reserved2_m85_c1};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x224 - Group 137
      8'h8A: prdata = {23'b0, reserved3_m85_c1};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x228 - Group 138
      8'h8B: prdata = {23'b0, reserved0_m85_c2};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x22C - Group 139
      8'h8C: prdata = {23'b0, reserved1_m85_c2};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x230 - Group 140
      8'h8D: prdata = {23'b0, reserved2_m85_c2};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x234 - Group 141
      8'h8E: prdata = {23'b0, reserved3_m85_c2};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x238 - Group 142
      8'h8F: prdata = {23'b0, reserved0_m85_c3};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x23C - Group 143
      8'h90: prdata = {23'b0, reserved1_m85_c3};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x240 - Group 144
      8'h91: prdata = {23'b0, reserved2_m85_c3};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x244 - Group 145
      8'h92: prdata = {23'b0, reserved3_m85_c3};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            // 0x248 - Group 146
      8'h93: prdata = {23'b0, reserved0_rv_m};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x24C - Group 147
      8'h94: prdata = {23'b0, reserved1_rv_m};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x250 - Group 148
      8'h95: prdata = {23'b0, reserved2_rv_m};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x254 - Group 149
      8'h96: prdata = {23'b0, reserved3_rv_m};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x258 - Group 150
      8'h97: prdata = {23'b0, reserved0_rv_s};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x25C - Group 151
      8'h98: prdata = {23'b0, reserved1_rv_s};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x260 - Group 152
      8'h99: prdata = {23'b0, reserved2_rv_s};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x264 - Group 153
      8'h9A: prdata = {23'b0, reserved3_rv_s};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              // 0x268 - Group 154
      8'h9B: prdata = {26'b0, usb_clk_ctrl};                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                // 0x26C - Group 155
      8'h9C: prdata = {9'b0, usb_wk_int_status_sync, usb_wk_status_sync, usb_id_ovrd_val, usb_id_ovrd_en, usb_vbus_drv, usb_wk_clr, usb_wk_int_mask, usb_wk_mask};                                                                                                                                                                                                                                                                                                                                                                                                          // 0x270 - Group 156
      default: prdata = prdata_d;
    endcase
end

endmodule
                                                                                              