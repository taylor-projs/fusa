`timescale 1ns/1ps
module miter_mcusys_ciu;
  integer output_checks = 0, output_mismatch = 0;
  integer fc_req_mismatch = 0, other_output_mismatch = 0;
  integer read_checks = 0, read_mismatch = 0;
  integer invalid_read_mismatch = 0, ro_sync_read_mismatch = 0;
  reg [31:0] ro_pattern = 32'h5A5A_A5A5;
  integer stable_ro_read_mismatch = 0;
  reg pclk = 0;
  always #5 pclk = ~pclk;
  reg por_n;
  reg prstn;
  reg [31:0] paddr;
  reg pwrite;
  reg psel;
  reg penable;
  reg [31:0] pwdata;
  reg mcusys_aclk_fc_done;
  reg mcusys_pclk_fc_done;
  reg mcusys_rv_core_clk_fc_done;
  reg mcusys_m85_core0_clk_fc_done;
  reg mcusys_m85_core1_clk_fc_done;
  reg mcusys_m85_core2_clk_fc_done;
  reg mcusys_m85_core3_clk_fc_done;
  reg [31:0] aud_spare_in;
  reg regout_gmac0_rst_clk_tx_n_o;
  reg regout_gmac0_rst_clk_rx_n_o;
  reg regout_gmac0_rst_clk_app_n_o;
  reg [1:0] regout_gmac0_mac_speed_o;
  reg regout_gmac0_sbd_tx_clk_gating_ctrl_o;
  reg [2:0] regout_gmac0_sbd_ar_dma_ch_no_o;
  reg [2:0] regout_gmac0_sbd_aw_dma_ch_no_o;
  reg [2:0] regout_gmac0_sbd_w_dma_ch_no_o;
  reg regout_gmac0_csysack_o;
  reg regout_gmac0_cactive_o;
  reg regout_gmac0_ati_datatxon_o;
  reg regout_gmac0_ati_pmac_txon_o;
  reg regout_gmac0_ati_pmac_actv_o;
  reg [1:0] regout_gmac0_mcgr_dma_req_o;
  reg regout_gmac0_sbd_pwr_down_ack_o;
  reg regout_gmac1_rst_clk_tx_n_o;
  reg regout_gmac1_rst_clk_rx_n_o;
  reg regout_gmac1_rst_clk_app_n_o;
  reg [1:0] regout_gmac1_mac_speed_o;
  reg regout_gmac1_sbd_tx_clk_gating_ctrl_o;
  reg [2:0] regout_gmac1_sbd_ar_dma_ch_no_o;
  reg [2:0] regout_gmac1_sbd_aw_dma_ch_no_o;
  reg [2:0] regout_gmac1_sbd_w_dma_ch_no_o;
  reg regout_gmac1_csysack_o;
  reg regout_gmac1_cactive_o;
  reg regout_gmac1_ati_datatxon_o;
  reg regout_gmac1_ati_pmac_txon_o;
  reg regout_gmac1_ati_pmac_actv_o;
  reg [1:0] regout_gmac1_mcgr_dma_req_o;
  reg regout_gmac1_sbd_pwr_down_ack_o;
  reg mcusys_dbgclk_fc_done;
  reg [31:0] rv_ecc_status0;
  reg [17:0] rv_ecc_status1;
  reg [1:0] rv_lockstep_mis;
  reg [1:0] rv_safety_error;
  reg [1:0] rv_safety_input_error_dcls;
  reg [31:0] rv_core_status0;
  reg [31:0] rv_core_status1;
  reg [31:0] rv_core_status2;
  reg [31:0] rv_core_status3;
  reg [31:0] rv_core_status4;
  reg [31:0] rv_core_status5;
  reg [31:0] rv_i1_core_status1;
  reg [31:0] rv_i1_core_status2;
  reg [31:0] rv_i1_core_status3;
  reg [31:0] rv_i1_core_status4;
  reg [5:0] usb_wk_status;
  reg usb_wk_int_status;

  wire [31:0] orig_prdata;
  wire [31:0] gen_prdata;
  wire orig_pready;
  wire gen_pready;
  wire [15:0] orig_MGCR;
  wire [15:0] gen_MGCR;
  wire orig_force_all_clk_on;
  wire gen_force_all_clk_on;
  wire [4:0] orig_mcusys_aclk_ctrl;
  wire [4:0] gen_mcusys_aclk_ctrl;
  wire [4:0] orig_mcusys_pclk_ctrl;
  wire [4:0] gen_mcusys_pclk_ctrl;
  wire [4:0] orig_mcusys_rv_core_clk_ctrl;
  wire [4:0] gen_mcusys_rv_core_clk_ctrl;
  wire [4:0] orig_mcusys_m85_core0_clk_ctrl;
  wire [4:0] gen_mcusys_m85_core0_clk_ctrl;
  wire [4:0] orig_mcusys_m85_core1_clk_ctrl;
  wire [4:0] gen_mcusys_m85_core1_clk_ctrl;
  wire [4:0] orig_mcusys_m85_core2_clk_ctrl;
  wire [4:0] gen_mcusys_m85_core2_clk_ctrl;
  wire [4:0] orig_mcusys_m85_core3_clk_ctrl;
  wire [4:0] gen_mcusys_m85_core3_clk_ctrl;
  wire orig_rv_core_sw_rstn;
  wire gen_rv_core_sw_rstn;
  wire orig_m85_core0_sw_rstn;
  wire gen_m85_core0_sw_rstn;
  wire orig_m85_core1_sw_rstn;
  wire gen_m85_core1_sw_rstn;
  wire orig_m85_core2_sw_rstn;
  wire gen_m85_core2_sw_rstn;
  wire orig_m85_core3_sw_rstn;
  wire gen_m85_core3_sw_rstn;
  wire [31:0] orig_m85_core0_cfg0;
  wire [31:0] gen_m85_core0_cfg0;
  wire [31:0] orig_m85_core0_cfg1;
  wire [31:0] gen_m85_core0_cfg1;
  wire [31:0] orig_m85_core0_cfg2;
  wire [31:0] gen_m85_core0_cfg2;
  wire [25:0] orig_m85_core0_cfg_ns_systick;
  wire [25:0] gen_m85_core0_cfg_ns_systick;
  wire [25:0] orig_m85_core0_cfg_s_systick;
  wire [25:0] gen_m85_core0_cfg_s_systick;
  wire [31:0] orig_m85_core0_cfg_s_vector;
  wire [31:0] gen_m85_core0_cfg_s_vector;
  wire [31:0] orig_m85_core0_cfg_ns_vector;
  wire [31:0] gen_m85_core0_cfg_ns_vector;
  wire [31:0] orig_m85_core0_cfg_dptarget_id;
  wire [31:0] gen_m85_core0_cfg_dptarget_id;
  wire [31:0] orig_m85_core1_cfg0;
  wire [31:0] gen_m85_core1_cfg0;
  wire [31:0] orig_m85_core1_cfg1;
  wire [31:0] gen_m85_core1_cfg1;
  wire [31:0] orig_m85_core1_cfg2;
  wire [31:0] gen_m85_core1_cfg2;
  wire [25:0] orig_m85_core1_cfg_ns_systick;
  wire [25:0] gen_m85_core1_cfg_ns_systick;
  wire [25:0] orig_m85_core1_cfg_s_systick;
  wire [25:0] gen_m85_core1_cfg_s_systick;
  wire [31:0] orig_m85_core1_cfg_s_vector;
  wire [31:0] gen_m85_core1_cfg_s_vector;
  wire [31:0] orig_m85_core1_cfg_ns_vector;
  wire [31:0] gen_m85_core1_cfg_ns_vector;
  wire [31:0] orig_m85_core1_cfg_dptarget_id;
  wire [31:0] gen_m85_core1_cfg_dptarget_id;
  wire [31:0] orig_m85_core2_cfg0;
  wire [31:0] gen_m85_core2_cfg0;
  wire [31:0] orig_m85_core2_cfg1;
  wire [31:0] gen_m85_core2_cfg1;
  wire [31:0] orig_m85_core2_cfg2;
  wire [31:0] gen_m85_core2_cfg2;
  wire [25:0] orig_m85_core2_cfg_ns_systick;
  wire [25:0] gen_m85_core2_cfg_ns_systick;
  wire [25:0] orig_m85_core2_cfg_s_systick;
  wire [25:0] gen_m85_core2_cfg_s_systick;
  wire [31:0] orig_m85_core2_cfg_s_vector;
  wire [31:0] gen_m85_core2_cfg_s_vector;
  wire [31:0] orig_m85_core2_cfg_ns_vector;
  wire [31:0] gen_m85_core2_cfg_ns_vector;
  wire [31:0] orig_m85_core2_cfg_dptarget_id;
  wire [31:0] gen_m85_core2_cfg_dptarget_id;
  wire [31:0] orig_m85_core3_cfg0;
  wire [31:0] gen_m85_core3_cfg0;
  wire [31:0] orig_m85_core3_cfg1;
  wire [31:0] gen_m85_core3_cfg1;
  wire [31:0] orig_m85_core3_cfg2;
  wire [31:0] gen_m85_core3_cfg2;
  wire [25:0] orig_m85_core3_cfg_ns_systick;
  wire [25:0] gen_m85_core3_cfg_ns_systick;
  wire [25:0] orig_m85_core3_cfg_s_systick;
  wire [25:0] gen_m85_core3_cfg_s_systick;
  wire [31:0] orig_m85_core3_cfg_s_vector;
  wire [31:0] gen_m85_core3_cfg_s_vector;
  wire [31:0] orig_m85_core3_cfg_ns_vector;
  wire [31:0] gen_m85_core3_cfg_ns_vector;
  wire [31:0] orig_m85_core3_cfg_dptarget_id;
  wire [31:0] gen_m85_core3_cfg_dptarget_id;
  wire [31:0] orig_mcusys_pll1_ctrl0;
  wire [31:0] gen_mcusys_pll1_ctrl0;
  wire [31:0] orig_mcusys_pll1_ctrl1;
  wire [31:0] gen_mcusys_pll1_ctrl1;
  wire [31:0] orig_mcusys_pll1_ctrl2;
  wire [31:0] gen_mcusys_pll1_ctrl2;
  wire [31:0] orig_mcusys_pll1_ctrl3;
  wire [31:0] gen_mcusys_pll1_ctrl3;
  wire [3:0] orig_mcusys_pll1_mon_config;
  wire [3:0] gen_mcusys_pll1_mon_config;
  wire [7:0] orig_mcusys_pll1_div_en;
  wire [7:0] gen_mcusys_pll1_div_en;
  wire orig_mcusys_pll1_pw_sw;
  wire gen_mcusys_pll1_pw_sw;
  wire [31:0] orig_mcusys_rsvd0;
  wire [31:0] gen_mcusys_rsvd0;
  wire [31:0] orig_mcusys_rsvd1;
  wire [31:0] gen_mcusys_rsvd1;
  wire [31:0] orig_mcusys_rsvd2;
  wire [31:0] gen_mcusys_rsvd2;
  wire [3:0] orig_mcusys_rsvd3;
  wire [3:0] gen_mcusys_rsvd3;
  wire [7:0] orig_mcusys_rsvd4;
  wire [7:0] gen_mcusys_rsvd4;
  wire [31:0] orig_mcusys_rsvd5;
  wire [31:0] gen_mcusys_rsvd5;
  wire [31:0] orig_arqos_mcu_sys_fab;
  wire [31:0] gen_arqos_mcu_sys_fab;
  wire [31:0] orig_awqos_mcu_sys_fab;
  wire [31:0] gen_awqos_mcu_sys_fab;
  wire [31:0] orig_arqos_mcucore_sys_fab;
  wire [31:0] gen_arqos_mcucore_sys_fab;
  wire [31:0] orig_awqos_mcucore_sys_fab;
  wire [31:0] gen_awqos_mcucore_sys_fab;
  wire [11:0] orig_m85_core0_cfg_dclscorectl;
  wire [11:0] gen_m85_core0_cfg_dclscorectl;
  wire [11:0] orig_m85_core1_cfg_dclscorectl;
  wire [11:0] gen_m85_core1_cfg_dclscorectl;
  wire [11:0] orig_m85_core2_cfg_dclscorectl;
  wire [11:0] gen_m85_core2_cfg_dclscorectl;
  wire [11:0] orig_m85_core3_cfg_dclscorectl;
  wire [11:0] gen_m85_core3_cfg_dclscorectl;
  wire [1:0] orig_gmac0_speed_mode;
  wire [1:0] gen_gmac0_speed_mode;
  wire orig_gmac0_rmii_refclk_phase_sel;
  wire gen_gmac0_rmii_refclk_phase_sel;
  wire orig_gmac0_rx_refclk_phase_sel;
  wire gen_gmac0_rx_refclk_phase_sel;
  wire [3:0] orig_gmac0_phy_intf_sel_i;
  wire [3:0] gen_gmac0_phy_intf_sel_i;
  wire orig_gmac0_rgmii_txc_src_sel;
  wire gen_gmac0_rgmii_txc_src_sel;
  wire orig_gmac0_1588_clk_en;
  wire gen_gmac0_1588_clk_en;
  wire orig_gmac0_refclk_sel;
  wire gen_gmac0_refclk_sel;
  wire [1:0] orig_gmac0_clk_1588_sel;
  wire [1:0] gen_gmac0_clk_1588_sel;
  wire orig_gmac0_rgmii_rxc_dline_pu;
  wire gen_gmac0_rgmii_rxc_dline_pu;
  wire [7:0] orig_gmac0_rgmii_rxc_dline_range;
  wire [7:0] gen_gmac0_rgmii_rxc_dline_range;
  wire [19:0] orig_gmac0_rgmii_rxc_dline_adj;
  wire [19:0] gen_gmac0_rgmii_rxc_dline_adj;
  wire orig_gmac0_rgmii_txc_dline_pu;
  wire gen_gmac0_rgmii_txc_dline_pu;
  wire [7:0] orig_gmac0_rgmii_txc_dline_range;
  wire [7:0] gen_gmac0_rgmii_txc_dline_range;
  wire [19:0] orig_gmac0_rgmii_txc_dline_adj;
  wire [19:0] gen_gmac0_rgmii_txc_dline_adj;
  wire [1:0] orig_gmac1_speed_mode;
  wire [1:0] gen_gmac1_speed_mode;
  wire orig_gmac1_rmii_refclk_phase_sel;
  wire gen_gmac1_rmii_refclk_phase_sel;
  wire orig_gmac1_rx_refclk_phase_sel;
  wire gen_gmac1_rx_refclk_phase_sel;
  wire [3:0] orig_gmac1_phy_intf_sel_i;
  wire [3:0] gen_gmac1_phy_intf_sel_i;
  wire orig_gmac1_rgmii_txc_src_sel;
  wire gen_gmac1_rgmii_txc_src_sel;
  wire orig_gmac1_1588_clk_en;
  wire gen_gmac1_1588_clk_en;
  wire orig_gmac1_refclk_sel;
  wire gen_gmac1_refclk_sel;
  wire [1:0] orig_gmac1_clk_1588_sel;
  wire [1:0] gen_gmac1_clk_1588_sel;
  wire orig_gmac1_rgmii_rxc_dline_pu;
  wire gen_gmac1_rgmii_rxc_dline_pu;
  wire [7:0] orig_gmac1_rgmii_rxc_dline_range;
  wire [7:0] gen_gmac1_rgmii_rxc_dline_range;
  wire [19:0] orig_gmac1_rgmii_rxc_dline_adj;
  wire [19:0] gen_gmac1_rgmii_rxc_dline_adj;
  wire orig_gmac1_rgmii_txc_dline_pu;
  wire gen_gmac1_rgmii_txc_dline_pu;
  wire [7:0] orig_gmac1_rgmii_txc_dline_range;
  wire [7:0] gen_gmac1_rgmii_txc_dline_range;
  wire [19:0] orig_gmac1_rgmii_txc_dline_adj;
  wire [19:0] gen_gmac1_rgmii_txc_dline_adj;
  wire orig_regin_gmac0_sys_rst_n;
  wire gen_regin_gmac0_sys_rst_n;
  wire orig_regin_gmac0_pwr_isolate_i;
  wire gen_regin_gmac0_pwr_isolate_i;
  wire orig_regin_gmac0_pwr_clamp_ctrl_i;
  wire gen_regin_gmac0_pwr_clamp_ctrl_i;
  wire orig_regin_gmac0_pwr_down_ctrl_i;
  wire gen_regin_gmac0_pwr_down_ctrl_i;
  wire orig_regin_gmac0_csysreq_i;
  wire gen_regin_gmac0_csysreq_i;
  wire orig_regin_gmac0_sbd_pmac_hold_i;
  wire gen_regin_gmac0_sbd_pmac_hold_i;
  wire [1:0] orig_regin_gmac0_mcg_pst_trig_i;
  wire [1:0] gen_regin_gmac0_mcg_pst_trig_i;
  wire [1:0] orig_regin_gmac0_mcgr_dma_ack_i;
  wire [1:0] gen_regin_gmac0_mcgr_dma_ack_i;
  wire [3:0] orig_regin_gmac0_sbd_pc_tim_wdw_i;
  wire [3:0] gen_regin_gmac0_sbd_pc_tim_wdw_i;
  wire [1:0] orig_regin_gmac0_clk_gate;
  wire [1:0] gen_regin_gmac0_clk_gate;
  wire [12:0] orig_regin_gmac0_intr_mask;
  wire [12:0] gen_regin_gmac0_intr_mask;
  wire orig_regin_gmac0_cfg_clamp_en;
  wire gen_regin_gmac0_cfg_clamp_en;
  wire orig_regin_gmac1_sys_rst_n;
  wire gen_regin_gmac1_sys_rst_n;
  wire orig_regin_gmac1_pwr_isolate_i;
  wire gen_regin_gmac1_pwr_isolate_i;
  wire orig_regin_gmac1_pwr_clamp_ctrl_i;
  wire gen_regin_gmac1_pwr_clamp_ctrl_i;
  wire orig_regin_gmac1_pwr_down_ctrl_i;
  wire gen_regin_gmac1_pwr_down_ctrl_i;
  wire orig_regin_gmac1_csysreq_i;
  wire gen_regin_gmac1_csysreq_i;
  wire orig_regin_gmac1_sbd_pmac_hold_i;
  wire gen_regin_gmac1_sbd_pmac_hold_i;
  wire [1:0] orig_regin_gmac1_mcg_pst_trig_i;
  wire [1:0] gen_regin_gmac1_mcg_pst_trig_i;
  wire [1:0] orig_regin_gmac1_mcgr_dma_ack_i;
  wire [1:0] gen_regin_gmac1_mcgr_dma_ack_i;
  wire [3:0] orig_regin_gmac1_sbd_pc_tim_wdw_i;
  wire [3:0] gen_regin_gmac1_sbd_pc_tim_wdw_i;
  wire [1:0] orig_regin_gmac1_clk_gate;
  wire [1:0] gen_regin_gmac1_clk_gate;
  wire [12:0] orig_regin_gmac1_intr_mask;
  wire [12:0] gen_regin_gmac1_intr_mask;
  wire orig_regin_gmac1_cfg_clamp_en;
  wire gen_regin_gmac1_cfg_clamp_en;
  wire [18:0] orig_pcm_clk_res_ctrl;
  wire [18:0] gen_pcm_clk_res_ctrl;
  wire orig_pcm0_ch0_en;
  wire gen_pcm0_ch0_en;
  wire orig_pcm0_ch1_en;
  wire gen_pcm0_ch1_en;
  wire orig_pcm0_ch2_en;
  wire gen_pcm0_ch2_en;
  wire orig_pcm0_ch3_en;
  wire gen_pcm0_ch3_en;
  wire orig_pcm_mch_en;
  wire gen_pcm_mch_en;
  wire orig_pcm_apb_on;
  wire gen_pcm_apb_on;
  wire orig_mch_adma_mode;
  wire gen_mch_adma_mode;
  wire [1:0] orig_mch_adma_data_num;
  wire [1:0] gen_mch_adma_data_num;
  wire [2:0] orig_adc0_adma0_mode;
  wire [2:0] gen_adc0_adma0_mode;
  wire [2:0] orig_adc0_adma1_mode;
  wire [2:0] gen_adc0_adma1_mode;
  wire [2:0] orig_adc0_adma2_mode;
  wire [2:0] gen_adc0_adma2_mode;
  wire [2:0] orig_adc0_adma3_mode;
  wire [2:0] gen_adc0_adma3_mode;
  wire [18:0] orig_pcm1_clk_res_ctrl;
  wire [18:0] gen_pcm1_clk_res_ctrl;
  wire orig_pcm1_ch0_en;
  wire gen_pcm1_ch0_en;
  wire orig_pcm1_ch1_en;
  wire gen_pcm1_ch1_en;
  wire orig_pcm1_ch2_en;
  wire gen_pcm1_ch2_en;
  wire orig_pcm1_ch3_en;
  wire gen_pcm1_ch3_en;
  wire orig_pcm1_mch_en;
  wire gen_pcm1_mch_en;
  wire orig_pcm1_apb_on;
  wire gen_pcm1_apb_on;
  wire orig_mch1_adma_mode;
  wire gen_mch1_adma_mode;
  wire [1:0] orig_mch1_adma_data_num;
  wire [1:0] gen_mch1_adma_data_num;
  wire [2:0] orig_adc1_adma0_mode;
  wire [2:0] gen_adc1_adma0_mode;
  wire [2:0] orig_adc1_adma1_mode;
  wire [2:0] gen_adc1_adma1_mode;
  wire [2:0] orig_adc1_adma2_mode;
  wire [2:0] gen_adc1_adma2_mode;
  wire [2:0] orig_adc1_adma3_mode;
  wire [2:0] gen_adc1_adma3_mode;
  wire [7:0] orig_dmic0_adma_clk_res_ctrl;
  wire [7:0] gen_dmic0_adma_clk_res_ctrl;
  wire [7:0] orig_dmic1_adma_clk_res_ctrl;
  wire [7:0] gen_dmic1_adma_clk_res_ctrl;
  wire [4:0] orig_aud_dmic0_gt_ctrl;
  wire [4:0] gen_aud_dmic0_gt_ctrl;
  wire [4:0] orig_aud_dmic1_gt_ctrl;
  wire [4:0] gen_aud_dmic1_gt_ctrl;
  wire [4:0] orig_aud_dmic2_gt_ctrl;
  wire [4:0] gen_aud_dmic2_gt_ctrl;
  wire [4:0] orig_aud_dmic3_gt_ctrl;
  wire [4:0] gen_aud_dmic3_gt_ctrl;
  wire [4:0] orig_aud_dmic4_gt_ctrl;
  wire [4:0] gen_aud_dmic4_gt_ctrl;
  wire [4:0] orig_aud_dmic5_gt_ctrl;
  wire [4:0] gen_aud_dmic5_gt_ctrl;
  wire [4:0] orig_aud_dmic6_gt_ctrl;
  wire [4:0] gen_aud_dmic6_gt_ctrl;
  wire [4:0] orig_aud_dmic7_gt_ctrl;
  wire [4:0] gen_aud_dmic7_gt_ctrl;
  wire [9:0] orig_mcusys_dbgclk_ctrl;
  wire [9:0] gen_mcusys_dbgclk_ctrl;
  wire [31:0] orig_mcusys_pll2_ctrl0;
  wire [31:0] gen_mcusys_pll2_ctrl0;
  wire [31:0] orig_mcusys_pll2_ctrl1;
  wire [31:0] gen_mcusys_pll2_ctrl1;
  wire [31:0] orig_mcusys_pll2_ctrl2;
  wire [31:0] gen_mcusys_pll2_ctrl2;
  wire [31:0] orig_mcusys_pll2_ctrl3;
  wire [31:0] gen_mcusys_pll2_ctrl3;
  wire [3:0] orig_mcusys_pll2_mon_config;
  wire [3:0] gen_mcusys_pll2_mon_config;
  wire [7:0] orig_mcusys_pll2_div_en;
  wire [7:0] gen_mcusys_pll2_div_en;
  wire orig_mcusys_pll2_pw_sw;
  wire gen_mcusys_pll2_pw_sw;
  wire [31:0] orig_mcusys_pll3_ctrl0;
  wire [31:0] gen_mcusys_pll3_ctrl0;
  wire [31:0] orig_mcusys_pll3_ctrl1;
  wire [31:0] gen_mcusys_pll3_ctrl1;
  wire [31:0] orig_mcusys_pll3_ctrl2;
  wire [31:0] gen_mcusys_pll3_ctrl2;
  wire [31:0] orig_mcusys_pll3_ctrl3;
  wire [31:0] gen_mcusys_pll3_ctrl3;
  wire [3:0] orig_mcusys_pll3_mon_config;
  wire [3:0] gen_mcusys_pll3_mon_config;
  wire [7:0] orig_mcusys_pll3_div_en;
  wire [7:0] gen_mcusys_pll3_div_en;
  wire orig_mcusys_pll3_pw_sw;
  wire gen_mcusys_pll3_pw_sw;
  wire [31:0] orig_mcusys_pll4_ctrl0;
  wire [31:0] gen_mcusys_pll4_ctrl0;
  wire [31:0] orig_mcusys_pll4_ctrl1;
  wire [31:0] gen_mcusys_pll4_ctrl1;
  wire [31:0] orig_mcusys_pll4_ctrl2;
  wire [31:0] gen_mcusys_pll4_ctrl2;
  wire [31:0] orig_mcusys_pll4_ctrl3;
  wire [31:0] gen_mcusys_pll4_ctrl3;
  wire [3:0] orig_mcusys_pll4_mon_config;
  wire [3:0] gen_mcusys_pll4_mon_config;
  wire [7:0] orig_mcusys_pll4_div_en;
  wire [7:0] gen_mcusys_pll4_div_en;
  wire orig_mcusys_pll4_pw_sw;
  wire gen_mcusys_pll4_pw_sw;
  wire [3:0] orig_axi_sram_control;
  wire [3:0] gen_axi_sram_control;
  wire [1:0] orig_axi_sram_gating_en;
  wire [1:0] gen_axi_sram_gating_en;
  wire [31:0] orig_rv_core4_cfg;
  wire [31:0] gen_rv_core4_cfg;
  wire [31:0] orig_rv_reset_vector;
  wire [31:0] gen_rv_reset_vector;
  wire [9:0] orig_rv_hart_id;
  wire [9:0] gen_rv_hart_id;
  wire orig_rv_stop_on_reset;
  wire gen_rv_stop_on_reset;
  wire [31:0] orig_rv_ecc_msk0;
  wire [31:0] gen_rv_ecc_msk0;
  wire [31:0] orig_rv_ecc_msk1;
  wire [31:0] gen_rv_ecc_msk1;
  wire [31:0] orig_mem_ema_cfg_31_0;
  wire [31:0] gen_mem_ema_cfg_31_0;
  wire [31:0] orig_mem_ema_cfg_63_32;
  wire [31:0] gen_mem_ema_cfg_63_32;
  wire [31:0] orig_mem_ema_cfg_95_64;
  wire [31:0] gen_mem_ema_cfg_95_64;
  wire [31:0] orig_mem_ema_cfg_127_96;
  wire [31:0] gen_mem_ema_cfg_127_96;
  wire [7:0] orig_ref_clk_io_cfg;
  wire [7:0] gen_ref_clk_io_cfg;
  wire [15:0] orig_gpio_pwr_cfg;
  wire [15:0] gen_gpio_pwr_cfg;
  wire [7:0] orig_ext_32k_in_io_cfg;
  wire [7:0] gen_ext_32k_in_io_cfg;
  wire [7:0] orig_mcu_trst_n_io_cfg;
  wire [7:0] gen_mcu_trst_n_io_cfg;
  wire [7:0] orig_pmic_en_io_cfg;
  wire [7:0] gen_pmic_en_io_cfg;
  wire [7:0] orig_reset_in_n_io_cfg;
  wire [7:0] gen_reset_in_n_io_cfg;
  wire [8:0] orig_reserved2_m85_c1;
  wire [8:0] gen_rsvd2_m85_c1;
  wire [8:0] orig_reserved3_m85_c1;
  wire [8:0] gen_rsvd3_m85_c1;
  wire [8:0] orig_reserved0_m85_c2;
  wire [8:0] gen_rsvd0_m85_c2;
  wire [8:0] orig_reserved1_m85_c2;
  wire [8:0] gen_rsvd1_m85_c2;
  wire [8:0] orig_reserved2_m85_c2;
  wire [8:0] gen_rsvd2_m85_c2;
  wire [8:0] orig_reserved3_m85_c2;
  wire [8:0] gen_rsvd3_m85_c2;
  wire [8:0] orig_reserved0_m85_c3;
  wire [8:0] gen_rsvd0_m85_c3;
  wire [8:0] orig_reserved1_m85_c3;
  wire [8:0] gen_rsvd1_m85_c3;
  wire [8:0] orig_reserved2_m85_c3;
  wire [8:0] gen_rsvd2_m85_c3;
  wire [8:0] orig_reserved3_m85_c3;
  wire [8:0] gen_rsvd3_m85_c3;
  wire [8:0] orig_reserved0_rv_m;
  wire [8:0] gen_rsvd0_rv_m;
  wire [8:0] orig_reserved1_rv_m;
  wire [8:0] gen_rsvd1_rv_m;
  wire [8:0] orig_reserved2_rv_m;
  wire [8:0] gen_rsvd2_rv_m;
  wire [8:0] orig_reserved3_rv_m;
  wire [8:0] gen_rsvd3_rv_m;
  wire [8:0] orig_reserved0_rv_s;
  wire [8:0] gen_rsvd0_rv_s;
  wire [8:0] orig_reserved1_rv_s;
  wire [8:0] gen_rsvd1_rv_s;
  wire [8:0] orig_reserved2_rv_s;
  wire [8:0] gen_rsvd2_rv_s;
  wire [8:0] orig_reserved3_rv_s;
  wire [8:0] gen_rsvd3_rv_s;
  wire [5:0] orig_usb_clk_ctrl;
  wire [5:0] gen_usb_clk_ctrl;
  wire [5:0] orig_usb_wk_mask;
  wire [5:0] gen_usb_wk_mask;
  wire orig_usb_wk_int_mask;
  wire gen_usb_wk_int_mask;
  wire [5:0] orig_usb_wk_clr;
  wire [5:0] gen_usb_wk_clr;
  wire orig_usb_vbus_drv;
  wire gen_usb_vbus_drv;
  wire orig_usb_id_ovrd_en;
  wire gen_usb_id_ovrd_en;
  wire orig_usb_id_ovrd_val;
  wire gen_usb_id_ovrd_val;

  mcusys_ciu_orig u_orig (
    .por_n(por_n),
    .pclk(pclk),
    .prstn(prstn),
    .paddr(paddr),
    .pwrite(pwrite),
    .psel(psel),
    .penable(penable),
    .pwdata(pwdata),
    .prdata(orig_prdata),
    .pready(orig_pready),
    .MGCR(orig_MGCR),
    .force_all_clk_on(orig_force_all_clk_on),
    .mcusys_aclk_ctrl(orig_mcusys_aclk_ctrl),
    .mcusys_aclk_fc_done(mcusys_aclk_fc_done),
    .mcusys_pclk_ctrl(orig_mcusys_pclk_ctrl),
    .mcusys_pclk_fc_done(mcusys_pclk_fc_done),
    .mcusys_rv_core_clk_ctrl(orig_mcusys_rv_core_clk_ctrl),
    .mcusys_rv_core_clk_fc_done(mcusys_rv_core_clk_fc_done),
    .mcusys_m85_core0_clk_ctrl(orig_mcusys_m85_core0_clk_ctrl),
    .mcusys_m85_core0_clk_fc_done(mcusys_m85_core0_clk_fc_done),
    .mcusys_m85_core1_clk_ctrl(orig_mcusys_m85_core1_clk_ctrl),
    .mcusys_m85_core1_clk_fc_done(mcusys_m85_core1_clk_fc_done),
    .mcusys_m85_core2_clk_ctrl(orig_mcusys_m85_core2_clk_ctrl),
    .mcusys_m85_core2_clk_fc_done(mcusys_m85_core2_clk_fc_done),
    .mcusys_m85_core3_clk_ctrl(orig_mcusys_m85_core3_clk_ctrl),
    .mcusys_m85_core3_clk_fc_done(mcusys_m85_core3_clk_fc_done),
    .rv_core_sw_rstn(orig_rv_core_sw_rstn),
    .m85_core0_sw_rstn(orig_m85_core0_sw_rstn),
    .m85_core1_sw_rstn(orig_m85_core1_sw_rstn),
    .m85_core2_sw_rstn(orig_m85_core2_sw_rstn),
    .m85_core3_sw_rstn(orig_m85_core3_sw_rstn),
    .m85_core0_cfg0(orig_m85_core0_cfg0),
    .m85_core0_cfg1(orig_m85_core0_cfg1),
    .m85_core0_cfg2(orig_m85_core0_cfg2),
    .m85_core0_cfg_ns_systick(orig_m85_core0_cfg_ns_systick),
    .m85_core0_cfg_s_systick(orig_m85_core0_cfg_s_systick),
    .m85_core0_cfg_s_vector(orig_m85_core0_cfg_s_vector),
    .m85_core0_cfg_ns_vector(orig_m85_core0_cfg_ns_vector),
    .m85_core0_cfg_dptarget_id(orig_m85_core0_cfg_dptarget_id),
    .m85_core1_cfg0(orig_m85_core1_cfg0),
    .m85_core1_cfg1(orig_m85_core1_cfg1),
    .m85_core1_cfg2(orig_m85_core1_cfg2),
    .m85_core1_cfg_ns_systick(orig_m85_core1_cfg_ns_systick),
    .m85_core1_cfg_s_systick(orig_m85_core1_cfg_s_systick),
    .m85_core1_cfg_s_vector(orig_m85_core1_cfg_s_vector),
    .m85_core1_cfg_ns_vector(orig_m85_core1_cfg_ns_vector),
    .m85_core1_cfg_dptarget_id(orig_m85_core1_cfg_dptarget_id),
    .m85_core2_cfg0(orig_m85_core2_cfg0),
    .m85_core2_cfg1(orig_m85_core2_cfg1),
    .m85_core2_cfg2(orig_m85_core2_cfg2),
    .m85_core2_cfg_ns_systick(orig_m85_core2_cfg_ns_systick),
    .m85_core2_cfg_s_systick(orig_m85_core2_cfg_s_systick),
    .m85_core2_cfg_s_vector(orig_m85_core2_cfg_s_vector),
    .m85_core2_cfg_ns_vector(orig_m85_core2_cfg_ns_vector),
    .m85_core2_cfg_dptarget_id(orig_m85_core2_cfg_dptarget_id),
    .m85_core3_cfg0(orig_m85_core3_cfg0),
    .m85_core3_cfg1(orig_m85_core3_cfg1),
    .m85_core3_cfg2(orig_m85_core3_cfg2),
    .m85_core3_cfg_ns_systick(orig_m85_core3_cfg_ns_systick),
    .m85_core3_cfg_s_systick(orig_m85_core3_cfg_s_systick),
    .m85_core3_cfg_s_vector(orig_m85_core3_cfg_s_vector),
    .m85_core3_cfg_ns_vector(orig_m85_core3_cfg_ns_vector),
    .m85_core3_cfg_dptarget_id(orig_m85_core3_cfg_dptarget_id),
    .mcusys_pll1_ctrl0(orig_mcusys_pll1_ctrl0),
    .mcusys_pll1_ctrl1(orig_mcusys_pll1_ctrl1),
    .mcusys_pll1_ctrl2(orig_mcusys_pll1_ctrl2),
    .mcusys_pll1_ctrl3(orig_mcusys_pll1_ctrl3),
    .mcusys_pll1_mon_config(orig_mcusys_pll1_mon_config),
    .mcusys_pll1_div_en(orig_mcusys_pll1_div_en),
    .mcusys_pll1_pw_sw(orig_mcusys_pll1_pw_sw),
    .mcusys_rsvd0(orig_mcusys_rsvd0),
    .mcusys_rsvd1(orig_mcusys_rsvd1),
    .mcusys_rsvd2(orig_mcusys_rsvd2),
    .mcusys_rsvd3(orig_mcusys_rsvd3),
    .mcusys_rsvd4(orig_mcusys_rsvd4),
    .mcusys_rsvd5(orig_mcusys_rsvd5),
    .arqos_mcu_sys_fab(orig_arqos_mcu_sys_fab),
    .awqos_mcu_sys_fab(orig_awqos_mcu_sys_fab),
    .arqos_mcucore_sys_fab(orig_arqos_mcucore_sys_fab),
    .awqos_mcucore_sys_fab(orig_awqos_mcucore_sys_fab),
    .m85_core0_cfg_dclscorectl(orig_m85_core0_cfg_dclscorectl),
    .m85_core1_cfg_dclscorectl(orig_m85_core1_cfg_dclscorectl),
    .m85_core2_cfg_dclscorectl(orig_m85_core2_cfg_dclscorectl),
    .m85_core3_cfg_dclscorectl(orig_m85_core3_cfg_dclscorectl),
    .aud_spare_in(aud_spare_in),
    .gmac0_speed_mode(orig_gmac0_speed_mode),
    .gmac0_rmii_refclk_phase_sel(orig_gmac0_rmii_refclk_phase_sel),
    .gmac0_rx_refclk_phase_sel(orig_gmac0_rx_refclk_phase_sel),
    .gmac0_phy_intf_sel_i(orig_gmac0_phy_intf_sel_i),
    .gmac0_rgmii_txc_src_sel(orig_gmac0_rgmii_txc_src_sel),
    .gmac0_1588_clk_en(orig_gmac0_1588_clk_en),
    .gmac0_refclk_sel(orig_gmac0_refclk_sel),
    .gmac0_clk_1588_sel(orig_gmac0_clk_1588_sel),
    .gmac0_rgmii_rxc_dline_pu(orig_gmac0_rgmii_rxc_dline_pu),
    .gmac0_rgmii_rxc_dline_range(orig_gmac0_rgmii_rxc_dline_range),
    .gmac0_rgmii_rxc_dline_adj(orig_gmac0_rgmii_rxc_dline_adj),
    .gmac0_rgmii_txc_dline_pu(orig_gmac0_rgmii_txc_dline_pu),
    .gmac0_rgmii_txc_dline_range(orig_gmac0_rgmii_txc_dline_range),
    .gmac0_rgmii_txc_dline_adj(orig_gmac0_rgmii_txc_dline_adj),
    .gmac1_speed_mode(orig_gmac1_speed_mode),
    .gmac1_rmii_refclk_phase_sel(orig_gmac1_rmii_refclk_phase_sel),
    .gmac1_rx_refclk_phase_sel(orig_gmac1_rx_refclk_phase_sel),
    .gmac1_phy_intf_sel_i(orig_gmac1_phy_intf_sel_i),
    .gmac1_rgmii_txc_src_sel(orig_gmac1_rgmii_txc_src_sel),
    .gmac1_1588_clk_en(orig_gmac1_1588_clk_en),
    .gmac1_refclk_sel(orig_gmac1_refclk_sel),
    .gmac1_clk_1588_sel(orig_gmac1_clk_1588_sel),
    .gmac1_rgmii_rxc_dline_pu(orig_gmac1_rgmii_rxc_dline_pu),
    .gmac1_rgmii_rxc_dline_range(orig_gmac1_rgmii_rxc_dline_range),
    .gmac1_rgmii_rxc_dline_adj(orig_gmac1_rgmii_rxc_dline_adj),
    .gmac1_rgmii_txc_dline_pu(orig_gmac1_rgmii_txc_dline_pu),
    .gmac1_rgmii_txc_dline_range(orig_gmac1_rgmii_txc_dline_range),
    .gmac1_rgmii_txc_dline_adj(orig_gmac1_rgmii_txc_dline_adj),
    .regin_gmac0_sys_rst_n(orig_regin_gmac0_sys_rst_n),
    .regin_gmac0_pwr_isolate_i(orig_regin_gmac0_pwr_isolate_i),
    .regin_gmac0_pwr_clamp_ctrl_i(orig_regin_gmac0_pwr_clamp_ctrl_i),
    .regin_gmac0_pwr_down_ctrl_i(orig_regin_gmac0_pwr_down_ctrl_i),
    .regin_gmac0_csysreq_i(orig_regin_gmac0_csysreq_i),
    .regin_gmac0_sbd_pmac_hold_i(orig_regin_gmac0_sbd_pmac_hold_i),
    .regin_gmac0_mcg_pst_trig_i(orig_regin_gmac0_mcg_pst_trig_i),
    .regin_gmac0_mcgr_dma_ack_i(orig_regin_gmac0_mcgr_dma_ack_i),
    .regin_gmac0_sbd_pc_tim_wdw_i(orig_regin_gmac0_sbd_pc_tim_wdw_i),
    .regin_gmac0_clk_gate(orig_regin_gmac0_clk_gate),
    .regin_gmac0_intr_mask(orig_regin_gmac0_intr_mask),
    .regin_gmac0_cfg_clamp_en(orig_regin_gmac0_cfg_clamp_en),
    .regout_gmac0_rst_clk_tx_n_o(regout_gmac0_rst_clk_tx_n_o),
    .regout_gmac0_rst_clk_rx_n_o(regout_gmac0_rst_clk_rx_n_o),
    .regout_gmac0_rst_clk_app_n_o(regout_gmac0_rst_clk_app_n_o),
    .regout_gmac0_mac_speed_o(regout_gmac0_mac_speed_o),
    .regout_gmac0_sbd_tx_clk_gating_ctrl_o(regout_gmac0_sbd_tx_clk_gating_ctrl_o),
    .regout_gmac0_sbd_ar_dma_ch_no_o(regout_gmac0_sbd_ar_dma_ch_no_o),
    .regout_gmac0_sbd_aw_dma_ch_no_o(regout_gmac0_sbd_aw_dma_ch_no_o),
    .regout_gmac0_sbd_w_dma_ch_no_o(regout_gmac0_sbd_w_dma_ch_no_o),
    .regout_gmac0_csysack_o(regout_gmac0_csysack_o),
    .regout_gmac0_cactive_o(regout_gmac0_cactive_o),
    .regout_gmac0_ati_datatxon_o(regout_gmac0_ati_datatxon_o),
    .regout_gmac0_ati_pmac_txon_o(regout_gmac0_ati_pmac_txon_o),
    .regout_gmac0_ati_pmac_actv_o(regout_gmac0_ati_pmac_actv_o),
    .regout_gmac0_mcgr_dma_req_o(regout_gmac0_mcgr_dma_req_o),
    .regout_gmac0_sbd_pwr_down_ack_o(regout_gmac0_sbd_pwr_down_ack_o),
    .regin_gmac1_sys_rst_n(orig_regin_gmac1_sys_rst_n),
    .regin_gmac1_pwr_isolate_i(orig_regin_gmac1_pwr_isolate_i),
    .regin_gmac1_pwr_clamp_ctrl_i(orig_regin_gmac1_pwr_clamp_ctrl_i),
    .regin_gmac1_pwr_down_ctrl_i(orig_regin_gmac1_pwr_down_ctrl_i),
    .regin_gmac1_csysreq_i(orig_regin_gmac1_csysreq_i),
    .regin_gmac1_sbd_pmac_hold_i(orig_regin_gmac1_sbd_pmac_hold_i),
    .regin_gmac1_mcg_pst_trig_i(orig_regin_gmac1_mcg_pst_trig_i),
    .regin_gmac1_mcgr_dma_ack_i(orig_regin_gmac1_mcgr_dma_ack_i),
    .regin_gmac1_sbd_pc_tim_wdw_i(orig_regin_gmac1_sbd_pc_tim_wdw_i),
    .regin_gmac1_clk_gate(orig_regin_gmac1_clk_gate),
    .regin_gmac1_intr_mask(orig_regin_gmac1_intr_mask),
    .regin_gmac1_cfg_clamp_en(orig_regin_gmac1_cfg_clamp_en),
    .regout_gmac1_rst_clk_tx_n_o(regout_gmac1_rst_clk_tx_n_o),
    .regout_gmac1_rst_clk_rx_n_o(regout_gmac1_rst_clk_rx_n_o),
    .regout_gmac1_rst_clk_app_n_o(regout_gmac1_rst_clk_app_n_o),
    .regout_gmac1_mac_speed_o(regout_gmac1_mac_speed_o),
    .regout_gmac1_sbd_tx_clk_gating_ctrl_o(regout_gmac1_sbd_tx_clk_gating_ctrl_o),
    .regout_gmac1_sbd_ar_dma_ch_no_o(regout_gmac1_sbd_ar_dma_ch_no_o),
    .regout_gmac1_sbd_aw_dma_ch_no_o(regout_gmac1_sbd_aw_dma_ch_no_o),
    .regout_gmac1_sbd_w_dma_ch_no_o(regout_gmac1_sbd_w_dma_ch_no_o),
    .regout_gmac1_csysack_o(regout_gmac1_csysack_o),
    .regout_gmac1_cactive_o(regout_gmac1_cactive_o),
    .regout_gmac1_ati_datatxon_o(regout_gmac1_ati_datatxon_o),
    .regout_gmac1_ati_pmac_txon_o(regout_gmac1_ati_pmac_txon_o),
    .regout_gmac1_ati_pmac_actv_o(regout_gmac1_ati_pmac_actv_o),
    .regout_gmac1_mcgr_dma_req_o(regout_gmac1_mcgr_dma_req_o),
    .regout_gmac1_sbd_pwr_down_ack_o(regout_gmac1_sbd_pwr_down_ack_o),
    .pcm_clk_res_ctrl(orig_pcm_clk_res_ctrl),
    .pcm0_ch0_en(orig_pcm0_ch0_en),
    .pcm0_ch1_en(orig_pcm0_ch1_en),
    .pcm0_ch2_en(orig_pcm0_ch2_en),
    .pcm0_ch3_en(orig_pcm0_ch3_en),
    .pcm_mch_en(orig_pcm_mch_en),
    .pcm_apb_on(orig_pcm_apb_on),
    .mch_adma_mode(orig_mch_adma_mode),
    .mch_adma_data_num(orig_mch_adma_data_num),
    .adc0_adma0_mode(orig_adc0_adma0_mode),
    .adc0_adma1_mode(orig_adc0_adma1_mode),
    .adc0_adma2_mode(orig_adc0_adma2_mode),
    .adc0_adma3_mode(orig_adc0_adma3_mode),
    .pcm1_clk_res_ctrl(orig_pcm1_clk_res_ctrl),
    .pcm1_ch0_en(orig_pcm1_ch0_en),
    .pcm1_ch1_en(orig_pcm1_ch1_en),
    .pcm1_ch2_en(orig_pcm1_ch2_en),
    .pcm1_ch3_en(orig_pcm1_ch3_en),
    .pcm1_mch_en(orig_pcm1_mch_en),
    .pcm1_apb_on(orig_pcm1_apb_on),
    .mch1_adma_mode(orig_mch1_adma_mode),
    .mch1_adma_data_num(orig_mch1_adma_data_num),
    .adc1_adma0_mode(orig_adc1_adma0_mode),
    .adc1_adma1_mode(orig_adc1_adma1_mode),
    .adc1_adma2_mode(orig_adc1_adma2_mode),
    .adc1_adma3_mode(orig_adc1_adma3_mode),
    .dmic0_adma_clk_res_ctrl(orig_dmic0_adma_clk_res_ctrl),
    .dmic1_adma_clk_res_ctrl(orig_dmic1_adma_clk_res_ctrl),
    .aud_dmic0_gt_ctrl(orig_aud_dmic0_gt_ctrl),
    .aud_dmic1_gt_ctrl(orig_aud_dmic1_gt_ctrl),
    .aud_dmic2_gt_ctrl(orig_aud_dmic2_gt_ctrl),
    .aud_dmic3_gt_ctrl(orig_aud_dmic3_gt_ctrl),
    .aud_dmic4_gt_ctrl(orig_aud_dmic4_gt_ctrl),
    .aud_dmic5_gt_ctrl(orig_aud_dmic5_gt_ctrl),
    .aud_dmic6_gt_ctrl(orig_aud_dmic6_gt_ctrl),
    .aud_dmic7_gt_ctrl(orig_aud_dmic7_gt_ctrl),
    .mcusys_dbgclk_ctrl(orig_mcusys_dbgclk_ctrl),
    .mcusys_dbgclk_fc_done(mcusys_dbgclk_fc_done),
    .mcusys_pll2_ctrl0(orig_mcusys_pll2_ctrl0),
    .mcusys_pll2_ctrl1(orig_mcusys_pll2_ctrl1),
    .mcusys_pll2_ctrl2(orig_mcusys_pll2_ctrl2),
    .mcusys_pll2_ctrl3(orig_mcusys_pll2_ctrl3),
    .mcusys_pll2_mon_config(orig_mcusys_pll2_mon_config),
    .mcusys_pll2_div_en(orig_mcusys_pll2_div_en),
    .mcusys_pll2_pw_sw(orig_mcusys_pll2_pw_sw),
    .mcusys_pll3_ctrl0(orig_mcusys_pll3_ctrl0),
    .mcusys_pll3_ctrl1(orig_mcusys_pll3_ctrl1),
    .mcusys_pll3_ctrl2(orig_mcusys_pll3_ctrl2),
    .mcusys_pll3_ctrl3(orig_mcusys_pll3_ctrl3),
    .mcusys_pll3_mon_config(orig_mcusys_pll3_mon_config),
    .mcusys_pll3_div_en(orig_mcusys_pll3_div_en),
    .mcusys_pll3_pw_sw(orig_mcusys_pll3_pw_sw),
    .mcusys_pll4_ctrl0(orig_mcusys_pll4_ctrl0),
    .mcusys_pll4_ctrl1(orig_mcusys_pll4_ctrl1),
    .mcusys_pll4_ctrl2(orig_mcusys_pll4_ctrl2),
    .mcusys_pll4_ctrl3(orig_mcusys_pll4_ctrl3),
    .mcusys_pll4_mon_config(orig_mcusys_pll4_mon_config),
    .mcusys_pll4_div_en(orig_mcusys_pll4_div_en),
    .mcusys_pll4_pw_sw(orig_mcusys_pll4_pw_sw),
    .axi_sram_control(orig_axi_sram_control),
    .axi_sram_gating_en(orig_axi_sram_gating_en),
    .rv_core4_cfg(orig_rv_core4_cfg),
    .rv_reset_vector(orig_rv_reset_vector),
    .rv_hart_id(orig_rv_hart_id),
    .rv_stop_on_reset(orig_rv_stop_on_reset),
    .rv_ecc_msk0(orig_rv_ecc_msk0),
    .rv_ecc_msk1(orig_rv_ecc_msk1),
    .rv_ecc_status0(rv_ecc_status0),
    .rv_ecc_status1(rv_ecc_status1),
    .rv_lockstep_mis(rv_lockstep_mis),
    .rv_safety_error(rv_safety_error),
    .rv_safety_input_error_dcls(rv_safety_input_error_dcls),
    .rv_core_status0(rv_core_status0),
    .rv_core_status1(rv_core_status1),
    .rv_core_status2(rv_core_status2),
    .rv_core_status3(rv_core_status3),
    .rv_core_status4(rv_core_status4),
    .rv_core_status5(rv_core_status5),
    .rv_i1_core_status1(rv_i1_core_status1),
    .rv_i1_core_status2(rv_i1_core_status2),
    .rv_i1_core_status3(rv_i1_core_status3),
    .rv_i1_core_status4(rv_i1_core_status4),
    .mem_ema_cfg_31_0(orig_mem_ema_cfg_31_0),
    .mem_ema_cfg_63_32(orig_mem_ema_cfg_63_32),
    .mem_ema_cfg_95_64(orig_mem_ema_cfg_95_64),
    .mem_ema_cfg_127_96(orig_mem_ema_cfg_127_96),
    .ref_clk_io_cfg(orig_ref_clk_io_cfg),
    .gpio_pwr_cfg(orig_gpio_pwr_cfg),
    .ext_32k_in_io_cfg(orig_ext_32k_in_io_cfg),
    .mcu_trst_n_io_cfg(orig_mcu_trst_n_io_cfg),
    .pmic_en_io_cfg(orig_pmic_en_io_cfg),
    .reset_in_n_io_cfg(orig_reset_in_n_io_cfg),
    .reserved2_m85_c1(orig_reserved2_m85_c1),
    .reserved3_m85_c1(orig_reserved3_m85_c1),
    .reserved0_m85_c2(orig_reserved0_m85_c2),
    .reserved1_m85_c2(orig_reserved1_m85_c2),
    .reserved2_m85_c2(orig_reserved2_m85_c2),
    .reserved3_m85_c2(orig_reserved3_m85_c2),
    .reserved0_m85_c3(orig_reserved0_m85_c3),
    .reserved1_m85_c3(orig_reserved1_m85_c3),
    .reserved2_m85_c3(orig_reserved2_m85_c3),
    .reserved3_m85_c3(orig_reserved3_m85_c3),
    .reserved0_rv_m(orig_reserved0_rv_m),
    .reserved1_rv_m(orig_reserved1_rv_m),
    .reserved2_rv_m(orig_reserved2_rv_m),
    .reserved3_rv_m(orig_reserved3_rv_m),
    .reserved0_rv_s(orig_reserved0_rv_s),
    .reserved1_rv_s(orig_reserved1_rv_s),
    .reserved2_rv_s(orig_reserved2_rv_s),
    .reserved3_rv_s(orig_reserved3_rv_s),
    .usb_clk_ctrl(orig_usb_clk_ctrl),
    .usb_wk_mask(orig_usb_wk_mask),
    .usb_wk_int_mask(orig_usb_wk_int_mask),
    .usb_wk_clr(orig_usb_wk_clr),
    .usb_vbus_drv(orig_usb_vbus_drv),
    .usb_id_ovrd_en(orig_usb_id_ovrd_en),
    .usb_id_ovrd_val(orig_usb_id_ovrd_val),
    .usb_wk_status(usb_wk_status),
    .usb_wk_int_status(usb_wk_int_status)
  );

  mcusys_ciu u_parity (
    .pclk(pclk),
    .presetn(prstn),
    .paddr(paddr[9:0]),
    .pwrite(pwrite),
    .psel(psel),
    .penable(penable),
    .pwdata(pwdata),
    .prdata(gen_prdata),
    .pready(gen_pready),
    .MGCR(gen_MGCR),
    .force_all_clk_on(gen_force_all_clk_on),
    .mcusys_aclk_ctrl(gen_mcusys_aclk_ctrl),
    .mcusys_aclk_fc_done(mcusys_aclk_fc_done),
    .mcusys_pclk_ctrl(gen_mcusys_pclk_ctrl),
    .mcusys_pclk_fc_done(mcusys_pclk_fc_done),
    .mcusys_rv_core_clk_ctrl(gen_mcusys_rv_core_clk_ctrl),
    .mcusys_rv_core_clk_fc_done(mcusys_rv_core_clk_fc_done),
    .mcusys_m85_core0_clk_ctrl(gen_mcusys_m85_core0_clk_ctrl),
    .mcusys_m85_core0_clk_fc_done(mcusys_m85_core0_clk_fc_done),
    .mcusys_m85_core1_clk_ctrl(gen_mcusys_m85_core1_clk_ctrl),
    .mcusys_m85_core1_clk_fc_done(mcusys_m85_core1_clk_fc_done),
    .mcusys_m85_core2_clk_ctrl(gen_mcusys_m85_core2_clk_ctrl),
    .mcusys_m85_core2_clk_fc_done(mcusys_m85_core2_clk_fc_done),
    .mcusys_m85_core3_clk_ctrl(gen_mcusys_m85_core3_clk_ctrl),
    .mcusys_m85_core3_clk_fc_done(mcusys_m85_core3_clk_fc_done),
    .rv_core_sw_rstn(gen_rv_core_sw_rstn),
    .m85_core0_sw_rstn(gen_m85_core0_sw_rstn),
    .m85_core1_sw_rstn(gen_m85_core1_sw_rstn),
    .m85_core2_sw_rstn(gen_m85_core2_sw_rstn),
    .m85_core3_sw_rstn(gen_m85_core3_sw_rstn),
    .m85_core0_cfg0(gen_m85_core0_cfg0),
    .m85_core0_cfg1(gen_m85_core0_cfg1),
    .m85_core0_cfg2(gen_m85_core0_cfg2),
    .m85_core0_cfg_ns_systick(gen_m85_core0_cfg_ns_systick),
    .m85_core0_cfg_s_systick(gen_m85_core0_cfg_s_systick),
    .m85_core0_cfg_s_vector(gen_m85_core0_cfg_s_vector),
    .m85_core0_cfg_ns_vector(gen_m85_core0_cfg_ns_vector),
    .m85_core0_cfg_dptarget_id(gen_m85_core0_cfg_dptarget_id),
    .m85_core1_cfg0(gen_m85_core1_cfg0),
    .m85_core1_cfg1(gen_m85_core1_cfg1),
    .m85_core1_cfg2(gen_m85_core1_cfg2),
    .m85_core1_cfg_ns_systick(gen_m85_core1_cfg_ns_systick),
    .m85_core1_cfg_s_systick(gen_m85_core1_cfg_s_systick),
    .m85_core1_cfg_s_vector(gen_m85_core1_cfg_s_vector),
    .m85_core1_cfg_ns_vector(gen_m85_core1_cfg_ns_vector),
    .m85_core1_cfg_dptarget_id(gen_m85_core1_cfg_dptarget_id),
    .m85_core2_cfg0(gen_m85_core2_cfg0),
    .m85_core2_cfg1(gen_m85_core2_cfg1),
    .m85_core2_cfg2(gen_m85_core2_cfg2),
    .m85_core2_cfg_ns_systick(gen_m85_core2_cfg_ns_systick),
    .m85_core2_cfg_s_systick(gen_m85_core2_cfg_s_systick),
    .m85_core2_cfg_s_vector(gen_m85_core2_cfg_s_vector),
    .m85_core2_cfg_ns_vector(gen_m85_core2_cfg_ns_vector),
    .m85_core2_cfg_dptarget_id(gen_m85_core2_cfg_dptarget_id),
    .m85_core3_cfg0(gen_m85_core3_cfg0),
    .m85_core3_cfg1(gen_m85_core3_cfg1),
    .m85_core3_cfg2(gen_m85_core3_cfg2),
    .m85_core3_cfg_ns_systick(gen_m85_core3_cfg_ns_systick),
    .m85_core3_cfg_s_systick(gen_m85_core3_cfg_s_systick),
    .m85_core3_cfg_s_vector(gen_m85_core3_cfg_s_vector),
    .m85_core3_cfg_ns_vector(gen_m85_core3_cfg_ns_vector),
    .m85_core3_cfg_dptarget_id(gen_m85_core3_cfg_dptarget_id),
    .mcusys_pll1_ctrl0(gen_mcusys_pll1_ctrl0),
    .mcusys_pll1_ctrl1(gen_mcusys_pll1_ctrl1),
    .mcusys_pll1_ctrl2(gen_mcusys_pll1_ctrl2),
    .mcusys_pll1_ctrl3(gen_mcusys_pll1_ctrl3),
    .mcusys_pll1_mon_config(gen_mcusys_pll1_mon_config),
    .mcusys_pll1_div_en(gen_mcusys_pll1_div_en),
    .mcusys_pll1_pw_sw(gen_mcusys_pll1_pw_sw),
    .mcusys_rsvd0(gen_mcusys_rsvd0),
    .mcusys_rsvd1(gen_mcusys_rsvd1),
    .mcusys_rsvd2(gen_mcusys_rsvd2),
    .mcusys_rsvd3(gen_mcusys_rsvd3),
    .mcusys_rsvd4(gen_mcusys_rsvd4),
    .mcusys_rsvd5(gen_mcusys_rsvd5),
    .arqos_mcu_sys_fab(gen_arqos_mcu_sys_fab),
    .awqos_mcu_sys_fab(gen_awqos_mcu_sys_fab),
    .arqos_mcucore_sys_fab(gen_arqos_mcucore_sys_fab),
    .awqos_mcucore_sys_fab(gen_awqos_mcucore_sys_fab),
    .m85_core0_cfg_dclscorectl(gen_m85_core0_cfg_dclscorectl),
    .m85_core1_cfg_dclscorectl(gen_m85_core1_cfg_dclscorectl),
    .m85_core2_cfg_dclscorectl(gen_m85_core2_cfg_dclscorectl),
    .m85_core3_cfg_dclscorectl(gen_m85_core3_cfg_dclscorectl),
    .aud_spare_in(aud_spare_in),
    .gmac0_speed_mode(gen_gmac0_speed_mode),
    .gmac0_rmii_refclk_phase_sel(gen_gmac0_rmii_refclk_phase_sel),
    .gmac0_rx_refclk_phase_sel(gen_gmac0_rx_refclk_phase_sel),
    .gmac0_phy_intf_sel_i(gen_gmac0_phy_intf_sel_i),
    .gmac0_rgmii_txc_src_sel(gen_gmac0_rgmii_txc_src_sel),
    .gmac0_1588_clk_en(gen_gmac0_1588_clk_en),
    .gmac0_refclk_sel(gen_gmac0_refclk_sel),
    .gmac0_clk_1588_sel(gen_gmac0_clk_1588_sel),
    .gmac0_rgmii_rxc_dline_pu(gen_gmac0_rgmii_rxc_dline_pu),
    .gmac0_rgmii_rxc_dline_range(gen_gmac0_rgmii_rxc_dline_range),
    .gmac0_rgmii_rxc_dline_adj(gen_gmac0_rgmii_rxc_dline_adj),
    .gmac0_rgmii_txc_dline_pu(gen_gmac0_rgmii_txc_dline_pu),
    .gmac0_rgmii_txc_dline_range(gen_gmac0_rgmii_txc_dline_range),
    .gmac0_rgmii_txc_dline_adj(gen_gmac0_rgmii_txc_dline_adj),
    .gmac1_speed_mode(gen_gmac1_speed_mode),
    .gmac1_rmii_refclk_phase_sel(gen_gmac1_rmii_refclk_phase_sel),
    .gmac1_rx_refclk_phase_sel(gen_gmac1_rx_refclk_phase_sel),
    .gmac1_phy_intf_sel_i(gen_gmac1_phy_intf_sel_i),
    .gmac1_rgmii_txc_src_sel(gen_gmac1_rgmii_txc_src_sel),
    .gmac1_1588_clk_en(gen_gmac1_1588_clk_en),
    .gmac1_refclk_sel(gen_gmac1_refclk_sel),
    .gmac1_clk_1588_sel(gen_gmac1_clk_1588_sel),
    .gmac1_rgmii_rxc_dline_pu(gen_gmac1_rgmii_rxc_dline_pu),
    .gmac1_rgmii_rxc_dline_range(gen_gmac1_rgmii_rxc_dline_range),
    .gmac1_rgmii_rxc_dline_adj(gen_gmac1_rgmii_rxc_dline_adj),
    .gmac1_rgmii_txc_dline_pu(gen_gmac1_rgmii_txc_dline_pu),
    .gmac1_rgmii_txc_dline_range(gen_gmac1_rgmii_txc_dline_range),
    .gmac1_rgmii_txc_dline_adj(gen_gmac1_rgmii_txc_dline_adj),
    .regin_gmac0_sys_rst_n(gen_regin_gmac0_sys_rst_n),
    .regin_gmac0_pwr_isolate_i(gen_regin_gmac0_pwr_isolate_i),
    .regin_gmac0_pwr_clamp_ctrl_i(gen_regin_gmac0_pwr_clamp_ctrl_i),
    .regin_gmac0_pwr_down_ctrl_i(gen_regin_gmac0_pwr_down_ctrl_i),
    .regin_gmac0_csysreq_i(gen_regin_gmac0_csysreq_i),
    .regin_gmac0_sbd_pmac_hold_i(gen_regin_gmac0_sbd_pmac_hold_i),
    .regin_gmac0_mcg_pst_trig_i(gen_regin_gmac0_mcg_pst_trig_i),
    .regin_gmac0_mcgr_dma_ack_i(gen_regin_gmac0_mcgr_dma_ack_i),
    .regin_gmac0_sbd_pc_tim_wdw_i(gen_regin_gmac0_sbd_pc_tim_wdw_i),
    .regin_gmac0_clk_gate(gen_regin_gmac0_clk_gate),
    .regin_gmac0_intr_mask(gen_regin_gmac0_intr_mask),
    .regin_gmac0_cfg_clamp_en(gen_regin_gmac0_cfg_clamp_en),
    .regout_gmac0_rst_clk_tx_n_o(regout_gmac0_rst_clk_tx_n_o),
    .regout_gmac0_rst_clk_rx_n_o(regout_gmac0_rst_clk_rx_n_o),
    .regout_gmac0_rst_clk_app_n_o(regout_gmac0_rst_clk_app_n_o),
    .regout_gmac0_mac_speed_o(regout_gmac0_mac_speed_o),
    .regout_gmac0_sbd_tx_clk_gating_ctrl_o(regout_gmac0_sbd_tx_clk_gating_ctrl_o),
    .regout_gmac0_sbd_ar_dma_ch_no_o(regout_gmac0_sbd_ar_dma_ch_no_o),
    .regout_gmac0_sbd_aw_dma_ch_no_o(regout_gmac0_sbd_aw_dma_ch_no_o),
    .regout_gmac0_sbd_w_dma_ch_no_o(regout_gmac0_sbd_w_dma_ch_no_o),
    .regout_gmac0_csysack_o(regout_gmac0_csysack_o),
    .regout_gmac0_cactive_o(regout_gmac0_cactive_o),
    .regout_gmac0_ati_datatxon_o(regout_gmac0_ati_datatxon_o),
    .regout_gmac0_ati_pmac_txon_o(regout_gmac0_ati_pmac_txon_o),
    .regout_gmac0_ati_pmac_actv_o(regout_gmac0_ati_pmac_actv_o),
    .regout_gmac0_mcgr_dma_req_o(regout_gmac0_mcgr_dma_req_o),
    .regout_gmac0_sbd_pwr_down_ack_o(regout_gmac0_sbd_pwr_down_ack_o),
    .regin_gmac1_sys_rst_n(gen_regin_gmac1_sys_rst_n),
    .regin_gmac1_pwr_isolate_i(gen_regin_gmac1_pwr_isolate_i),
    .regin_gmac1_pwr_clamp_ctrl_i(gen_regin_gmac1_pwr_clamp_ctrl_i),
    .regin_gmac1_pwr_down_ctrl_i(gen_regin_gmac1_pwr_down_ctrl_i),
    .regin_gmac1_csysreq_i(gen_regin_gmac1_csysreq_i),
    .regin_gmac1_sbd_pmac_hold_i(gen_regin_gmac1_sbd_pmac_hold_i),
    .regin_gmac1_mcg_pst_trig_i(gen_regin_gmac1_mcg_pst_trig_i),
    .regin_gmac1_mcgr_dma_ack_i(gen_regin_gmac1_mcgr_dma_ack_i),
    .regin_gmac1_sbd_pc_tim_wdw_i(gen_regin_gmac1_sbd_pc_tim_wdw_i),
    .regin_gmac1_clk_gate(gen_regin_gmac1_clk_gate),
    .regin_gmac1_intr_mask(gen_regin_gmac1_intr_mask),
    .regin_gmac1_cfg_clamp_en(gen_regin_gmac1_cfg_clamp_en),
    .regout_gmac1_rst_clk_tx_n_o(regout_gmac1_rst_clk_tx_n_o),
    .regout_gmac1_rst_clk_rx_n_o(regout_gmac1_rst_clk_rx_n_o),
    .regout_gmac1_rst_clk_app_n_o(regout_gmac1_rst_clk_app_n_o),
    .regout_gmac1_mac_speed_o(regout_gmac1_mac_speed_o),
    .regout_gmac1_sbd_tx_clk_gating_ctrl_o(regout_gmac1_sbd_tx_clk_gating_ctrl_o),
    .regout_gmac1_sbd_ar_dma_ch_no_o(regout_gmac1_sbd_ar_dma_ch_no_o),
    .regout_gmac1_sbd_aw_dma_ch_no_o(regout_gmac1_sbd_aw_dma_ch_no_o),
    .regout_gmac1_sbd_w_dma_ch_no_o(regout_gmac1_sbd_w_dma_ch_no_o),
    .regout_gmac1_csysack_o(regout_gmac1_csysack_o),
    .regout_gmac1_cactive_o(regout_gmac1_cactive_o),
    .regout_gmac1_ati_datatxon_o(regout_gmac1_ati_datatxon_o),
    .regout_gmac1_ati_pmac_txon_o(regout_gmac1_ati_pmac_txon_o),
    .regout_gmac1_ati_pmac_actv_o(regout_gmac1_ati_pmac_actv_o),
    .regout_gmac1_mcgr_dma_req_o(regout_gmac1_mcgr_dma_req_o),
    .regout_gmac1_sbd_pwr_down_ack_o(regout_gmac1_sbd_pwr_down_ack_o),
    .pcm_clk_res_ctrl(gen_pcm_clk_res_ctrl),
    .pcm0_ch0_en(gen_pcm0_ch0_en),
    .pcm0_ch1_en(gen_pcm0_ch1_en),
    .pcm0_ch2_en(gen_pcm0_ch2_en),
    .pcm0_ch3_en(gen_pcm0_ch3_en),
    .pcm_mch_en(gen_pcm_mch_en),
    .pcm_apb_on(gen_pcm_apb_on),
    .mch_adma_mode(gen_mch_adma_mode),
    .mch_adma_data_num(gen_mch_adma_data_num),
    .adc0_adma0_mode(gen_adc0_adma0_mode),
    .adc0_adma1_mode(gen_adc0_adma1_mode),
    .adc0_adma2_mode(gen_adc0_adma2_mode),
    .adc0_adma3_mode(gen_adc0_adma3_mode),
    .pcm1_clk_res_ctrl(gen_pcm1_clk_res_ctrl),
    .pcm1_ch0_en(gen_pcm1_ch0_en),
    .pcm1_ch1_en(gen_pcm1_ch1_en),
    .pcm1_ch2_en(gen_pcm1_ch2_en),
    .pcm1_ch3_en(gen_pcm1_ch3_en),
    .pcm1_mch_en(gen_pcm1_mch_en),
    .pcm1_apb_on(gen_pcm1_apb_on),
    .mch1_adma_mode(gen_mch1_adma_mode),
    .mch1_adma_data_num(gen_mch1_adma_data_num),
    .adc1_adma0_mode(gen_adc1_adma0_mode),
    .adc1_adma1_mode(gen_adc1_adma1_mode),
    .adc1_adma2_mode(gen_adc1_adma2_mode),
    .adc1_adma3_mode(gen_adc1_adma3_mode),
    .dmic0_adma_clk_res_ctrl(gen_dmic0_adma_clk_res_ctrl),
    .dmic1_adma_clk_res_ctrl(gen_dmic1_adma_clk_res_ctrl),
    .aud_dmic0_gt_ctrl(gen_aud_dmic0_gt_ctrl),
    .aud_dmic1_gt_ctrl(gen_aud_dmic1_gt_ctrl),
    .aud_dmic2_gt_ctrl(gen_aud_dmic2_gt_ctrl),
    .aud_dmic3_gt_ctrl(gen_aud_dmic3_gt_ctrl),
    .aud_dmic4_gt_ctrl(gen_aud_dmic4_gt_ctrl),
    .aud_dmic5_gt_ctrl(gen_aud_dmic5_gt_ctrl),
    .aud_dmic6_gt_ctrl(gen_aud_dmic6_gt_ctrl),
    .aud_dmic7_gt_ctrl(gen_aud_dmic7_gt_ctrl),
    .mcusys_dbgclk_ctrl(gen_mcusys_dbgclk_ctrl),
    .mcusys_dbgclk_fc_done(mcusys_dbgclk_fc_done),
    .mcusys_pll2_ctrl0(gen_mcusys_pll2_ctrl0),
    .mcusys_pll2_ctrl1(gen_mcusys_pll2_ctrl1),
    .mcusys_pll2_ctrl2(gen_mcusys_pll2_ctrl2),
    .mcusys_pll2_ctrl3(gen_mcusys_pll2_ctrl3),
    .mcusys_pll2_mon_config(gen_mcusys_pll2_mon_config),
    .mcusys_pll2_div_en(gen_mcusys_pll2_div_en),
    .mcusys_pll2_pw_sw(gen_mcusys_pll2_pw_sw),
    .mcusys_pll3_ctrl0(gen_mcusys_pll3_ctrl0),
    .mcusys_pll3_ctrl1(gen_mcusys_pll3_ctrl1),
    .mcusys_pll3_ctrl2(gen_mcusys_pll3_ctrl2),
    .mcusys_pll3_ctrl3(gen_mcusys_pll3_ctrl3),
    .mcusys_pll3_mon_config(gen_mcusys_pll3_mon_config),
    .mcusys_pll3_div_en(gen_mcusys_pll3_div_en),
    .mcusys_pll3_pw_sw(gen_mcusys_pll3_pw_sw),
    .mcusys_pll4_ctrl0(gen_mcusys_pll4_ctrl0),
    .mcusys_pll4_ctrl1(gen_mcusys_pll4_ctrl1),
    .mcusys_pll4_ctrl2(gen_mcusys_pll4_ctrl2),
    .mcusys_pll4_ctrl3(gen_mcusys_pll4_ctrl3),
    .mcusys_pll4_mon_config(gen_mcusys_pll4_mon_config),
    .mcusys_pll4_div_en(gen_mcusys_pll4_div_en),
    .mcusys_pll4_pw_sw(gen_mcusys_pll4_pw_sw),
    .axi_sram_control(gen_axi_sram_control),
    .axi_sram_gating_en(gen_axi_sram_gating_en),
    .rv_core4_cfg(gen_rv_core4_cfg),
    .rv_reset_vector(gen_rv_reset_vector),
    .rv_hart_id(gen_rv_hart_id),
    .rv_stop_on_reset(gen_rv_stop_on_reset),
    .rv_ecc_msk0(gen_rv_ecc_msk0),
    .rv_ecc_msk1(gen_rv_ecc_msk1),
    .rv_ecc_status0(rv_ecc_status0),
    .rv_ecc_status1(rv_ecc_status1),
    .rv_lockstep_mis(rv_lockstep_mis),
    .rv_safety_error(rv_safety_error),
    .rv_safety_input_error_dcls(rv_safety_input_error_dcls),
    .rv_core_status0(rv_core_status0),
    .rv_core_status1(rv_core_status1),
    .rv_core_status2(rv_core_status2),
    .rv_core_status3(rv_core_status3),
    .rv_core_status4(rv_core_status4),
    .rv_core_status5(rv_core_status5),
    .rv_i1_core_status1(rv_i1_core_status1),
    .rv_i1_core_status2(rv_i1_core_status2),
    .rv_i1_core_status3(rv_i1_core_status3),
    .rv_i1_core_status4(rv_i1_core_status4),
    .mem_ema_cfg_31_0(gen_mem_ema_cfg_31_0),
    .mem_ema_cfg_63_32(gen_mem_ema_cfg_63_32),
    .mem_ema_cfg_95_64(gen_mem_ema_cfg_95_64),
    .mem_ema_cfg_127_96(gen_mem_ema_cfg_127_96),
    .ref_clk_io_cfg(gen_ref_clk_io_cfg),
    .gpio_pwr_cfg(gen_gpio_pwr_cfg),
    .ext_32k_in_io_cfg(gen_ext_32k_in_io_cfg),
    .mcu_trst_n_io_cfg(gen_mcu_trst_n_io_cfg),
    .pmic_en_io_cfg(gen_pmic_en_io_cfg),
    .reset_in_n_io_cfg(gen_reset_in_n_io_cfg),
    .rsvd2_m85_c1(gen_rsvd2_m85_c1),
    .rsvd3_m85_c1(gen_rsvd3_m85_c1),
    .rsvd0_m85_c2(gen_rsvd0_m85_c2),
    .rsvd1_m85_c2(gen_rsvd1_m85_c2),
    .rsvd2_m85_c2(gen_rsvd2_m85_c2),
    .rsvd3_m85_c2(gen_rsvd3_m85_c2),
    .rsvd0_m85_c3(gen_rsvd0_m85_c3),
    .rsvd1_m85_c3(gen_rsvd1_m85_c3),
    .rsvd2_m85_c3(gen_rsvd2_m85_c3),
    .rsvd3_m85_c3(gen_rsvd3_m85_c3),
    .rsvd0_rv_m(gen_rsvd0_rv_m),
    .rsvd1_rv_m(gen_rsvd1_rv_m),
    .rsvd2_rv_m(gen_rsvd2_rv_m),
    .rsvd3_rv_m(gen_rsvd3_rv_m),
    .rsvd0_rv_s(gen_rsvd0_rv_s),
    .rsvd1_rv_s(gen_rsvd1_rv_s),
    .rsvd2_rv_s(gen_rsvd2_rv_s),
    .rsvd3_rv_s(gen_rsvd3_rv_s),
    .usb_clk_ctrl(gen_usb_clk_ctrl),
    .usb_wk_mask(gen_usb_wk_mask),
    .usb_wk_int_mask(gen_usb_wk_int_mask),
    .usb_wk_clr(gen_usb_wk_clr),
    .usb_vbus_drv(gen_usb_vbus_drv),
    .usb_id_ovrd_en(gen_usb_id_ovrd_en),
    .usb_id_ovrd_val(gen_usb_id_ovrd_val),
    .usb_wk_status(usb_wk_status),
    .usb_wk_int_status(usb_wk_int_status)
    ,.pslverr()
    ,.mission_int()
    ,.lockstep_fault_injection()
  );

  task automatic check_one(input string tag, input string name,
                           input [31:0] a, input [31:0] b,
                           input bit is_fc);
    begin
      output_checks = output_checks + 1;
      if (a !== b) begin
        output_mismatch = output_mismatch + 1;
        if (is_fc) fc_req_mismatch = fc_req_mismatch + 1;
        else other_output_mismatch = other_output_mismatch + 1;
        if (output_mismatch <= 60 || !is_fc)
          $display("[%0t] OUT-DIFF %s %s orig=%h parity=%h",
                  $time, tag, name, a, b);
      end
    end
  endtask

  task automatic check_outputs(input string tag);
    begin
      check_one(tag, "MGCR", orig_MGCR, gen_MGCR, 0);
      check_one(tag, "force_all_clk_on", orig_force_all_clk_on, gen_force_all_clk_on, 0);
      check_one(tag, "mcusys_aclk_ctrl", orig_mcusys_aclk_ctrl, gen_mcusys_aclk_ctrl, 1);
      check_one(tag, "mcusys_pclk_ctrl", orig_mcusys_pclk_ctrl, gen_mcusys_pclk_ctrl, 1);
      check_one(tag, "mcusys_rv_core_clk_ctrl", orig_mcusys_rv_core_clk_ctrl, gen_mcusys_rv_core_clk_ctrl, 1);
      check_one(tag, "mcusys_m85_core0_clk_ctrl", orig_mcusys_m85_core0_clk_ctrl, gen_mcusys_m85_core0_clk_ctrl, 1);
      check_one(tag, "mcusys_m85_core1_clk_ctrl", orig_mcusys_m85_core1_clk_ctrl, gen_mcusys_m85_core1_clk_ctrl, 1);
      check_one(tag, "mcusys_m85_core2_clk_ctrl", orig_mcusys_m85_core2_clk_ctrl, gen_mcusys_m85_core2_clk_ctrl, 1);
      check_one(tag, "mcusys_m85_core3_clk_ctrl", orig_mcusys_m85_core3_clk_ctrl, gen_mcusys_m85_core3_clk_ctrl, 1);
      check_one(tag, "rv_core_sw_rstn", orig_rv_core_sw_rstn, gen_rv_core_sw_rstn, 0);
      check_one(tag, "m85_core0_sw_rstn", orig_m85_core0_sw_rstn, gen_m85_core0_sw_rstn, 0);
      check_one(tag, "m85_core1_sw_rstn", orig_m85_core1_sw_rstn, gen_m85_core1_sw_rstn, 0);
      check_one(tag, "m85_core2_sw_rstn", orig_m85_core2_sw_rstn, gen_m85_core2_sw_rstn, 0);
      check_one(tag, "m85_core3_sw_rstn", orig_m85_core3_sw_rstn, gen_m85_core3_sw_rstn, 0);
      check_one(tag, "m85_core0_cfg0", orig_m85_core0_cfg0, gen_m85_core0_cfg0, 0);
      check_one(tag, "m85_core0_cfg1", orig_m85_core0_cfg1, gen_m85_core0_cfg1, 0);
      check_one(tag, "m85_core0_cfg2", orig_m85_core0_cfg2, gen_m85_core0_cfg2, 0);
      check_one(tag, "m85_core0_cfg_ns_systick", orig_m85_core0_cfg_ns_systick, gen_m85_core0_cfg_ns_systick, 0);
      check_one(tag, "m85_core0_cfg_s_systick", orig_m85_core0_cfg_s_systick, gen_m85_core0_cfg_s_systick, 0);
      check_one(tag, "m85_core0_cfg_s_vector", orig_m85_core0_cfg_s_vector, gen_m85_core0_cfg_s_vector, 0);
      check_one(tag, "m85_core0_cfg_ns_vector", orig_m85_core0_cfg_ns_vector, gen_m85_core0_cfg_ns_vector, 0);
      check_one(tag, "m85_core0_cfg_dptarget_id", orig_m85_core0_cfg_dptarget_id, gen_m85_core0_cfg_dptarget_id, 0);
      check_one(tag, "m85_core1_cfg0", orig_m85_core1_cfg0, gen_m85_core1_cfg0, 0);
      check_one(tag, "m85_core1_cfg1", orig_m85_core1_cfg1, gen_m85_core1_cfg1, 0);
      check_one(tag, "m85_core1_cfg2", orig_m85_core1_cfg2, gen_m85_core1_cfg2, 0);
      check_one(tag, "m85_core1_cfg_ns_systick", orig_m85_core1_cfg_ns_systick, gen_m85_core1_cfg_ns_systick, 0);
      check_one(tag, "m85_core1_cfg_s_systick", orig_m85_core1_cfg_s_systick, gen_m85_core1_cfg_s_systick, 0);
      check_one(tag, "m85_core1_cfg_s_vector", orig_m85_core1_cfg_s_vector, gen_m85_core1_cfg_s_vector, 0);
      check_one(tag, "m85_core1_cfg_ns_vector", orig_m85_core1_cfg_ns_vector, gen_m85_core1_cfg_ns_vector, 0);
      check_one(tag, "m85_core1_cfg_dptarget_id", orig_m85_core1_cfg_dptarget_id, gen_m85_core1_cfg_dptarget_id, 0);
      check_one(tag, "m85_core2_cfg0", orig_m85_core2_cfg0, gen_m85_core2_cfg0, 0);
      check_one(tag, "m85_core2_cfg1", orig_m85_core2_cfg1, gen_m85_core2_cfg1, 0);
      check_one(tag, "m85_core2_cfg2", orig_m85_core2_cfg2, gen_m85_core2_cfg2, 0);
      check_one(tag, "m85_core2_cfg_ns_systick", orig_m85_core2_cfg_ns_systick, gen_m85_core2_cfg_ns_systick, 0);
      check_one(tag, "m85_core2_cfg_s_systick", orig_m85_core2_cfg_s_systick, gen_m85_core2_cfg_s_systick, 0);
      check_one(tag, "m85_core2_cfg_s_vector", orig_m85_core2_cfg_s_vector, gen_m85_core2_cfg_s_vector, 0);
      check_one(tag, "m85_core2_cfg_ns_vector", orig_m85_core2_cfg_ns_vector, gen_m85_core2_cfg_ns_vector, 0);
      check_one(tag, "m85_core2_cfg_dptarget_id", orig_m85_core2_cfg_dptarget_id, gen_m85_core2_cfg_dptarget_id, 0);
      check_one(tag, "m85_core3_cfg0", orig_m85_core3_cfg0, gen_m85_core3_cfg0, 0);
      check_one(tag, "m85_core3_cfg1", orig_m85_core3_cfg1, gen_m85_core3_cfg1, 0);
      check_one(tag, "m85_core3_cfg2", orig_m85_core3_cfg2, gen_m85_core3_cfg2, 0);
      check_one(tag, "m85_core3_cfg_ns_systick", orig_m85_core3_cfg_ns_systick, gen_m85_core3_cfg_ns_systick, 0);
      check_one(tag, "m85_core3_cfg_s_systick", orig_m85_core3_cfg_s_systick, gen_m85_core3_cfg_s_systick, 0);
      check_one(tag, "m85_core3_cfg_s_vector", orig_m85_core3_cfg_s_vector, gen_m85_core3_cfg_s_vector, 0);
      check_one(tag, "m85_core3_cfg_ns_vector", orig_m85_core3_cfg_ns_vector, gen_m85_core3_cfg_ns_vector, 0);
      check_one(tag, "m85_core3_cfg_dptarget_id", orig_m85_core3_cfg_dptarget_id, gen_m85_core3_cfg_dptarget_id, 0);
      check_one(tag, "mcusys_pll1_ctrl0", orig_mcusys_pll1_ctrl0, gen_mcusys_pll1_ctrl0, 0);
      check_one(tag, "mcusys_pll1_ctrl1", orig_mcusys_pll1_ctrl1, gen_mcusys_pll1_ctrl1, 0);
      check_one(tag, "mcusys_pll1_ctrl2", orig_mcusys_pll1_ctrl2, gen_mcusys_pll1_ctrl2, 0);
      check_one(tag, "mcusys_pll1_ctrl3", orig_mcusys_pll1_ctrl3, gen_mcusys_pll1_ctrl3, 0);
      check_one(tag, "mcusys_pll1_mon_config", orig_mcusys_pll1_mon_config, gen_mcusys_pll1_mon_config, 0);
      check_one(tag, "mcusys_pll1_div_en", orig_mcusys_pll1_div_en, gen_mcusys_pll1_div_en, 0);
      check_one(tag, "mcusys_pll1_pw_sw", orig_mcusys_pll1_pw_sw, gen_mcusys_pll1_pw_sw, 0);
      check_one(tag, "mcusys_rsvd0", orig_mcusys_rsvd0, gen_mcusys_rsvd0, 0);
      check_one(tag, "mcusys_rsvd1", orig_mcusys_rsvd1, gen_mcusys_rsvd1, 0);
      check_one(tag, "mcusys_rsvd2", orig_mcusys_rsvd2, gen_mcusys_rsvd2, 0);
      check_one(tag, "mcusys_rsvd3", orig_mcusys_rsvd3, gen_mcusys_rsvd3, 0);
      check_one(tag, "mcusys_rsvd4", orig_mcusys_rsvd4, gen_mcusys_rsvd4, 0);
      check_one(tag, "mcusys_rsvd5", orig_mcusys_rsvd5, gen_mcusys_rsvd5, 0);
      check_one(tag, "arqos_mcu_sys_fab", orig_arqos_mcu_sys_fab, gen_arqos_mcu_sys_fab, 0);
      check_one(tag, "awqos_mcu_sys_fab", orig_awqos_mcu_sys_fab, gen_awqos_mcu_sys_fab, 0);
      check_one(tag, "arqos_mcucore_sys_fab", orig_arqos_mcucore_sys_fab, gen_arqos_mcucore_sys_fab, 0);
      check_one(tag, "awqos_mcucore_sys_fab", orig_awqos_mcucore_sys_fab, gen_awqos_mcucore_sys_fab, 0);
      check_one(tag, "m85_core0_cfg_dclscorectl", orig_m85_core0_cfg_dclscorectl, gen_m85_core0_cfg_dclscorectl, 0);
      check_one(tag, "m85_core1_cfg_dclscorectl", orig_m85_core1_cfg_dclscorectl, gen_m85_core1_cfg_dclscorectl, 0);
      check_one(tag, "m85_core2_cfg_dclscorectl", orig_m85_core2_cfg_dclscorectl, gen_m85_core2_cfg_dclscorectl, 0);
      check_one(tag, "m85_core3_cfg_dclscorectl", orig_m85_core3_cfg_dclscorectl, gen_m85_core3_cfg_dclscorectl, 0);
      check_one(tag, "gmac0_speed_mode", orig_gmac0_speed_mode, gen_gmac0_speed_mode, 0);
      check_one(tag, "gmac0_rmii_refclk_phase_sel", orig_gmac0_rmii_refclk_phase_sel, gen_gmac0_rmii_refclk_phase_sel, 0);
      check_one(tag, "gmac0_rx_refclk_phase_sel", orig_gmac0_rx_refclk_phase_sel, gen_gmac0_rx_refclk_phase_sel, 0);
      check_one(tag, "gmac0_phy_intf_sel_i", orig_gmac0_phy_intf_sel_i, gen_gmac0_phy_intf_sel_i, 0);
      check_one(tag, "gmac0_rgmii_txc_src_sel", orig_gmac0_rgmii_txc_src_sel, gen_gmac0_rgmii_txc_src_sel, 0);
      check_one(tag, "gmac0_1588_clk_en", orig_gmac0_1588_clk_en, gen_gmac0_1588_clk_en, 0);
      check_one(tag, "gmac0_refclk_sel", orig_gmac0_refclk_sel, gen_gmac0_refclk_sel, 0);
      check_one(tag, "gmac0_clk_1588_sel", orig_gmac0_clk_1588_sel, gen_gmac0_clk_1588_sel, 0);
      check_one(tag, "gmac0_rgmii_rxc_dline_pu", orig_gmac0_rgmii_rxc_dline_pu, gen_gmac0_rgmii_rxc_dline_pu, 0);
      check_one(tag, "gmac0_rgmii_rxc_dline_range", orig_gmac0_rgmii_rxc_dline_range, gen_gmac0_rgmii_rxc_dline_range, 0);
      check_one(tag, "gmac0_rgmii_rxc_dline_adj", orig_gmac0_rgmii_rxc_dline_adj, gen_gmac0_rgmii_rxc_dline_adj, 0);
      check_one(tag, "gmac0_rgmii_txc_dline_pu", orig_gmac0_rgmii_txc_dline_pu, gen_gmac0_rgmii_txc_dline_pu, 0);
      check_one(tag, "gmac0_rgmii_txc_dline_range", orig_gmac0_rgmii_txc_dline_range, gen_gmac0_rgmii_txc_dline_range, 0);
      check_one(tag, "gmac0_rgmii_txc_dline_adj", orig_gmac0_rgmii_txc_dline_adj, gen_gmac0_rgmii_txc_dline_adj, 0);
      check_one(tag, "gmac1_speed_mode", orig_gmac1_speed_mode, gen_gmac1_speed_mode, 0);
      check_one(tag, "gmac1_rmii_refclk_phase_sel", orig_gmac1_rmii_refclk_phase_sel, gen_gmac1_rmii_refclk_phase_sel, 0);
      check_one(tag, "gmac1_rx_refclk_phase_sel", orig_gmac1_rx_refclk_phase_sel, gen_gmac1_rx_refclk_phase_sel, 0);
      check_one(tag, "gmac1_phy_intf_sel_i", orig_gmac1_phy_intf_sel_i, gen_gmac1_phy_intf_sel_i, 0);
      check_one(tag, "gmac1_rgmii_txc_src_sel", orig_gmac1_rgmii_txc_src_sel, gen_gmac1_rgmii_txc_src_sel, 0);
      check_one(tag, "gmac1_1588_clk_en", orig_gmac1_1588_clk_en, gen_gmac1_1588_clk_en, 0);
      check_one(tag, "gmac1_refclk_sel", orig_gmac1_refclk_sel, gen_gmac1_refclk_sel, 0);
      check_one(tag, "gmac1_clk_1588_sel", orig_gmac1_clk_1588_sel, gen_gmac1_clk_1588_sel, 0);
      check_one(tag, "gmac1_rgmii_rxc_dline_pu", orig_gmac1_rgmii_rxc_dline_pu, gen_gmac1_rgmii_rxc_dline_pu, 0);
      check_one(tag, "gmac1_rgmii_rxc_dline_range", orig_gmac1_rgmii_rxc_dline_range, gen_gmac1_rgmii_rxc_dline_range, 0);
      check_one(tag, "gmac1_rgmii_rxc_dline_adj", orig_gmac1_rgmii_rxc_dline_adj, gen_gmac1_rgmii_rxc_dline_adj, 0);
      check_one(tag, "gmac1_rgmii_txc_dline_pu", orig_gmac1_rgmii_txc_dline_pu, gen_gmac1_rgmii_txc_dline_pu, 0);
      check_one(tag, "gmac1_rgmii_txc_dline_range", orig_gmac1_rgmii_txc_dline_range, gen_gmac1_rgmii_txc_dline_range, 0);
      check_one(tag, "gmac1_rgmii_txc_dline_adj", orig_gmac1_rgmii_txc_dline_adj, gen_gmac1_rgmii_txc_dline_adj, 0);
      check_one(tag, "regin_gmac0_sys_rst_n", orig_regin_gmac0_sys_rst_n, gen_regin_gmac0_sys_rst_n, 0);
      check_one(tag, "regin_gmac0_pwr_isolate_i", orig_regin_gmac0_pwr_isolate_i, gen_regin_gmac0_pwr_isolate_i, 0);
      check_one(tag, "regin_gmac0_pwr_clamp_ctrl_i", orig_regin_gmac0_pwr_clamp_ctrl_i, gen_regin_gmac0_pwr_clamp_ctrl_i, 0);
      check_one(tag, "regin_gmac0_pwr_down_ctrl_i", orig_regin_gmac0_pwr_down_ctrl_i, gen_regin_gmac0_pwr_down_ctrl_i, 0);
      check_one(tag, "regin_gmac0_csysreq_i", orig_regin_gmac0_csysreq_i, gen_regin_gmac0_csysreq_i, 0);
      check_one(tag, "regin_gmac0_sbd_pmac_hold_i", orig_regin_gmac0_sbd_pmac_hold_i, gen_regin_gmac0_sbd_pmac_hold_i, 0);
      check_one(tag, "regin_gmac0_mcg_pst_trig_i", orig_regin_gmac0_mcg_pst_trig_i, gen_regin_gmac0_mcg_pst_trig_i, 0);
      check_one(tag, "regin_gmac0_mcgr_dma_ack_i", orig_regin_gmac0_mcgr_dma_ack_i, gen_regin_gmac0_mcgr_dma_ack_i, 0);
      check_one(tag, "regin_gmac0_sbd_pc_tim_wdw_i", orig_regin_gmac0_sbd_pc_tim_wdw_i, gen_regin_gmac0_sbd_pc_tim_wdw_i, 0);
      check_one(tag, "regin_gmac0_clk_gate", orig_regin_gmac0_clk_gate, gen_regin_gmac0_clk_gate, 0);
      check_one(tag, "regin_gmac0_intr_mask", orig_regin_gmac0_intr_mask, gen_regin_gmac0_intr_mask, 0);
      check_one(tag, "regin_gmac0_cfg_clamp_en", orig_regin_gmac0_cfg_clamp_en, gen_regin_gmac0_cfg_clamp_en, 0);
      check_one(tag, "regin_gmac1_sys_rst_n", orig_regin_gmac1_sys_rst_n, gen_regin_gmac1_sys_rst_n, 0);
      check_one(tag, "regin_gmac1_pwr_isolate_i", orig_regin_gmac1_pwr_isolate_i, gen_regin_gmac1_pwr_isolate_i, 0);
      check_one(tag, "regin_gmac1_pwr_clamp_ctrl_i", orig_regin_gmac1_pwr_clamp_ctrl_i, gen_regin_gmac1_pwr_clamp_ctrl_i, 0);
      check_one(tag, "regin_gmac1_pwr_down_ctrl_i", orig_regin_gmac1_pwr_down_ctrl_i, gen_regin_gmac1_pwr_down_ctrl_i, 0);
      check_one(tag, "regin_gmac1_csysreq_i", orig_regin_gmac1_csysreq_i, gen_regin_gmac1_csysreq_i, 0);
      check_one(tag, "regin_gmac1_sbd_pmac_hold_i", orig_regin_gmac1_sbd_pmac_hold_i, gen_regin_gmac1_sbd_pmac_hold_i, 0);
      check_one(tag, "regin_gmac1_mcg_pst_trig_i", orig_regin_gmac1_mcg_pst_trig_i, gen_regin_gmac1_mcg_pst_trig_i, 0);
      check_one(tag, "regin_gmac1_mcgr_dma_ack_i", orig_regin_gmac1_mcgr_dma_ack_i, gen_regin_gmac1_mcgr_dma_ack_i, 0);
      check_one(tag, "regin_gmac1_sbd_pc_tim_wdw_i", orig_regin_gmac1_sbd_pc_tim_wdw_i, gen_regin_gmac1_sbd_pc_tim_wdw_i, 0);
      check_one(tag, "regin_gmac1_clk_gate", orig_regin_gmac1_clk_gate, gen_regin_gmac1_clk_gate, 0);
      check_one(tag, "regin_gmac1_intr_mask", orig_regin_gmac1_intr_mask, gen_regin_gmac1_intr_mask, 0);
      check_one(tag, "regin_gmac1_cfg_clamp_en", orig_regin_gmac1_cfg_clamp_en, gen_regin_gmac1_cfg_clamp_en, 0);
      check_one(tag, "pcm_clk_res_ctrl", orig_pcm_clk_res_ctrl, gen_pcm_clk_res_ctrl, 0);
      check_one(tag, "pcm0_ch0_en", orig_pcm0_ch0_en, gen_pcm0_ch0_en, 0);
      check_one(tag, "pcm0_ch1_en", orig_pcm0_ch1_en, gen_pcm0_ch1_en, 0);
      check_one(tag, "pcm0_ch2_en", orig_pcm0_ch2_en, gen_pcm0_ch2_en, 0);
      check_one(tag, "pcm0_ch3_en", orig_pcm0_ch3_en, gen_pcm0_ch3_en, 0);
      check_one(tag, "pcm_mch_en", orig_pcm_mch_en, gen_pcm_mch_en, 0);
      check_one(tag, "pcm_apb_on", orig_pcm_apb_on, gen_pcm_apb_on, 0);
      check_one(tag, "mch_adma_mode", orig_mch_adma_mode, gen_mch_adma_mode, 0);
      check_one(tag, "mch_adma_data_num", orig_mch_adma_data_num, gen_mch_adma_data_num, 0);
      check_one(tag, "adc0_adma0_mode", orig_adc0_adma0_mode, gen_adc0_adma0_mode, 0);
      check_one(tag, "adc0_adma1_mode", orig_adc0_adma1_mode, gen_adc0_adma1_mode, 0);
      check_one(tag, "adc0_adma2_mode", orig_adc0_adma2_mode, gen_adc0_adma2_mode, 0);
      check_one(tag, "adc0_adma3_mode", orig_adc0_adma3_mode, gen_adc0_adma3_mode, 0);
      check_one(tag, "pcm1_clk_res_ctrl", orig_pcm1_clk_res_ctrl, gen_pcm1_clk_res_ctrl, 0);
      check_one(tag, "pcm1_ch0_en", orig_pcm1_ch0_en, gen_pcm1_ch0_en, 0);
      check_one(tag, "pcm1_ch1_en", orig_pcm1_ch1_en, gen_pcm1_ch1_en, 0);
      check_one(tag, "pcm1_ch2_en", orig_pcm1_ch2_en, gen_pcm1_ch2_en, 0);
      check_one(tag, "pcm1_ch3_en", orig_pcm1_ch3_en, gen_pcm1_ch3_en, 0);
      check_one(tag, "pcm1_mch_en", orig_pcm1_mch_en, gen_pcm1_mch_en, 0);
      check_one(tag, "pcm1_apb_on", orig_pcm1_apb_on, gen_pcm1_apb_on, 0);
      check_one(tag, "mch1_adma_mode", orig_mch1_adma_mode, gen_mch1_adma_mode, 0);
      check_one(tag, "mch1_adma_data_num", orig_mch1_adma_data_num, gen_mch1_adma_data_num, 0);
      check_one(tag, "adc1_adma0_mode", orig_adc1_adma0_mode, gen_adc1_adma0_mode, 0);
      check_one(tag, "adc1_adma1_mode", orig_adc1_adma1_mode, gen_adc1_adma1_mode, 0);
      check_one(tag, "adc1_adma2_mode", orig_adc1_adma2_mode, gen_adc1_adma2_mode, 0);
      check_one(tag, "adc1_adma3_mode", orig_adc1_adma3_mode, gen_adc1_adma3_mode, 0);
      check_one(tag, "dmic0_adma_clk_res_ctrl", orig_dmic0_adma_clk_res_ctrl, gen_dmic0_adma_clk_res_ctrl, 0);
      check_one(tag, "dmic1_adma_clk_res_ctrl", orig_dmic1_adma_clk_res_ctrl, gen_dmic1_adma_clk_res_ctrl, 0);
      check_one(tag, "aud_dmic0_gt_ctrl", orig_aud_dmic0_gt_ctrl, gen_aud_dmic0_gt_ctrl, 0);
      check_one(tag, "aud_dmic1_gt_ctrl", orig_aud_dmic1_gt_ctrl, gen_aud_dmic1_gt_ctrl, 0);
      check_one(tag, "aud_dmic2_gt_ctrl", orig_aud_dmic2_gt_ctrl, gen_aud_dmic2_gt_ctrl, 0);
      check_one(tag, "aud_dmic3_gt_ctrl", orig_aud_dmic3_gt_ctrl, gen_aud_dmic3_gt_ctrl, 0);
      check_one(tag, "aud_dmic4_gt_ctrl", orig_aud_dmic4_gt_ctrl, gen_aud_dmic4_gt_ctrl, 0);
      check_one(tag, "aud_dmic5_gt_ctrl", orig_aud_dmic5_gt_ctrl, gen_aud_dmic5_gt_ctrl, 0);
      check_one(tag, "aud_dmic6_gt_ctrl", orig_aud_dmic6_gt_ctrl, gen_aud_dmic6_gt_ctrl, 0);
      check_one(tag, "aud_dmic7_gt_ctrl", orig_aud_dmic7_gt_ctrl, gen_aud_dmic7_gt_ctrl, 0);
      check_one(tag, "mcusys_dbgclk_ctrl", orig_mcusys_dbgclk_ctrl, gen_mcusys_dbgclk_ctrl, 0);
      check_one(tag, "mcusys_pll2_ctrl0", orig_mcusys_pll2_ctrl0, gen_mcusys_pll2_ctrl0, 0);
      check_one(tag, "mcusys_pll2_ctrl1", orig_mcusys_pll2_ctrl1, gen_mcusys_pll2_ctrl1, 0);
      check_one(tag, "mcusys_pll2_ctrl2", orig_mcusys_pll2_ctrl2, gen_mcusys_pll2_ctrl2, 0);
      check_one(tag, "mcusys_pll2_ctrl3", orig_mcusys_pll2_ctrl3, gen_mcusys_pll2_ctrl3, 0);
      check_one(tag, "mcusys_pll2_mon_config", orig_mcusys_pll2_mon_config, gen_mcusys_pll2_mon_config, 0);
      check_one(tag, "mcusys_pll2_div_en", orig_mcusys_pll2_div_en, gen_mcusys_pll2_div_en, 0);
      check_one(tag, "mcusys_pll2_pw_sw", orig_mcusys_pll2_pw_sw, gen_mcusys_pll2_pw_sw, 0);
      check_one(tag, "mcusys_pll3_ctrl0", orig_mcusys_pll3_ctrl0, gen_mcusys_pll3_ctrl0, 0);
      check_one(tag, "mcusys_pll3_ctrl1", orig_mcusys_pll3_ctrl1, gen_mcusys_pll3_ctrl1, 0);
      check_one(tag, "mcusys_pll3_ctrl2", orig_mcusys_pll3_ctrl2, gen_mcusys_pll3_ctrl2, 0);
      check_one(tag, "mcusys_pll3_ctrl3", orig_mcusys_pll3_ctrl3, gen_mcusys_pll3_ctrl3, 0);
      check_one(tag, "mcusys_pll3_mon_config", orig_mcusys_pll3_mon_config, gen_mcusys_pll3_mon_config, 0);
      check_one(tag, "mcusys_pll3_div_en", orig_mcusys_pll3_div_en, gen_mcusys_pll3_div_en, 0);
      check_one(tag, "mcusys_pll3_pw_sw", orig_mcusys_pll3_pw_sw, gen_mcusys_pll3_pw_sw, 0);
      check_one(tag, "mcusys_pll4_ctrl0", orig_mcusys_pll4_ctrl0, gen_mcusys_pll4_ctrl0, 0);
      check_one(tag, "mcusys_pll4_ctrl1", orig_mcusys_pll4_ctrl1, gen_mcusys_pll4_ctrl1, 0);
      check_one(tag, "mcusys_pll4_ctrl2", orig_mcusys_pll4_ctrl2, gen_mcusys_pll4_ctrl2, 0);
      check_one(tag, "mcusys_pll4_ctrl3", orig_mcusys_pll4_ctrl3, gen_mcusys_pll4_ctrl3, 0);
      check_one(tag, "mcusys_pll4_mon_config", orig_mcusys_pll4_mon_config, gen_mcusys_pll4_mon_config, 0);
      check_one(tag, "mcusys_pll4_div_en", orig_mcusys_pll4_div_en, gen_mcusys_pll4_div_en, 0);
      check_one(tag, "mcusys_pll4_pw_sw", orig_mcusys_pll4_pw_sw, gen_mcusys_pll4_pw_sw, 0);
      check_one(tag, "axi_sram_control", orig_axi_sram_control, gen_axi_sram_control, 0);
      check_one(tag, "axi_sram_gating_en", orig_axi_sram_gating_en, gen_axi_sram_gating_en, 0);
      check_one(tag, "rv_core4_cfg", orig_rv_core4_cfg, gen_rv_core4_cfg, 0);
      check_one(tag, "rv_reset_vector", orig_rv_reset_vector, gen_rv_reset_vector, 0);
      check_one(tag, "rv_hart_id", orig_rv_hart_id, gen_rv_hart_id, 0);
      check_one(tag, "rv_stop_on_reset", orig_rv_stop_on_reset, gen_rv_stop_on_reset, 0);
      check_one(tag, "rv_ecc_msk0", orig_rv_ecc_msk0, gen_rv_ecc_msk0, 0);
      check_one(tag, "rv_ecc_msk1", orig_rv_ecc_msk1, gen_rv_ecc_msk1, 0);
      check_one(tag, "mem_ema_cfg_31_0", orig_mem_ema_cfg_31_0, gen_mem_ema_cfg_31_0, 0);
      check_one(tag, "mem_ema_cfg_63_32", orig_mem_ema_cfg_63_32, gen_mem_ema_cfg_63_32, 0);
      check_one(tag, "mem_ema_cfg_95_64", orig_mem_ema_cfg_95_64, gen_mem_ema_cfg_95_64, 0);
      check_one(tag, "mem_ema_cfg_127_96", orig_mem_ema_cfg_127_96, gen_mem_ema_cfg_127_96, 0);
      check_one(tag, "ref_clk_io_cfg", orig_ref_clk_io_cfg, gen_ref_clk_io_cfg, 0);
      check_one(tag, "gpio_pwr_cfg", orig_gpio_pwr_cfg, gen_gpio_pwr_cfg, 0);
      check_one(tag, "ext_32k_in_io_cfg", orig_ext_32k_in_io_cfg, gen_ext_32k_in_io_cfg, 0);
      check_one(tag, "mcu_trst_n_io_cfg", orig_mcu_trst_n_io_cfg, gen_mcu_trst_n_io_cfg, 0);
      check_one(tag, "pmic_en_io_cfg", orig_pmic_en_io_cfg, gen_pmic_en_io_cfg, 0);
      check_one(tag, "reset_in_n_io_cfg", orig_reset_in_n_io_cfg, gen_reset_in_n_io_cfg, 0);
      check_one(tag, "reserved2_m85_c1", orig_reserved2_m85_c1, gen_rsvd2_m85_c1, 0);
      check_one(tag, "reserved3_m85_c1", orig_reserved3_m85_c1, gen_rsvd3_m85_c1, 0);
      check_one(tag, "reserved0_m85_c2", orig_reserved0_m85_c2, gen_rsvd0_m85_c2, 0);
      check_one(tag, "reserved1_m85_c2", orig_reserved1_m85_c2, gen_rsvd1_m85_c2, 0);
      check_one(tag, "reserved2_m85_c2", orig_reserved2_m85_c2, gen_rsvd2_m85_c2, 0);
      check_one(tag, "reserved3_m85_c2", orig_reserved3_m85_c2, gen_rsvd3_m85_c2, 0);
      check_one(tag, "reserved0_m85_c3", orig_reserved0_m85_c3, gen_rsvd0_m85_c3, 0);
      check_one(tag, "reserved1_m85_c3", orig_reserved1_m85_c3, gen_rsvd1_m85_c3, 0);
      check_one(tag, "reserved2_m85_c3", orig_reserved2_m85_c3, gen_rsvd2_m85_c3, 0);
      check_one(tag, "reserved3_m85_c3", orig_reserved3_m85_c3, gen_rsvd3_m85_c3, 0);
      check_one(tag, "reserved0_rv_m", orig_reserved0_rv_m, gen_rsvd0_rv_m, 0);
      check_one(tag, "reserved1_rv_m", orig_reserved1_rv_m, gen_rsvd1_rv_m, 0);
      check_one(tag, "reserved2_rv_m", orig_reserved2_rv_m, gen_rsvd2_rv_m, 0);
      check_one(tag, "reserved3_rv_m", orig_reserved3_rv_m, gen_rsvd3_rv_m, 0);
      check_one(tag, "reserved0_rv_s", orig_reserved0_rv_s, gen_rsvd0_rv_s, 0);
      check_one(tag, "reserved1_rv_s", orig_reserved1_rv_s, gen_rsvd1_rv_s, 0);
      check_one(tag, "reserved2_rv_s", orig_reserved2_rv_s, gen_rsvd2_rv_s, 0);
      check_one(tag, "reserved3_rv_s", orig_reserved3_rv_s, gen_rsvd3_rv_s, 0);
      check_one(tag, "usb_clk_ctrl", orig_usb_clk_ctrl, gen_usb_clk_ctrl, 0);
      check_one(tag, "usb_wk_mask", orig_usb_wk_mask, gen_usb_wk_mask, 0);
      check_one(tag, "usb_wk_int_mask", orig_usb_wk_int_mask, gen_usb_wk_int_mask, 0);
      check_one(tag, "usb_wk_clr", orig_usb_wk_clr, gen_usb_wk_clr, 0);
      check_one(tag, "usb_vbus_drv", orig_usb_vbus_drv, gen_usb_vbus_drv, 0);
      check_one(tag, "usb_id_ovrd_en", orig_usb_id_ovrd_en, gen_usb_id_ovrd_en, 0);
      check_one(tag, "usb_id_ovrd_val", orig_usb_id_ovrd_val, gen_usb_id_ovrd_val, 0);
    end
  endtask

  task automatic check_prdata(input string tag, input string kind);
    begin
      read_checks = read_checks + 1;
      if (kind == "ro_sync")
        $display("RO_DBG t=%0t addr=%h orig=%h parity=%h aud_sync=%h aud_raw=%h q1=%b q2=%b", $time, paddr, orig_prdata, gen_prdata, u_orig.aud_spare_in_sync, aud_spare_in, u_orig.u_aud_spare_in_sync[0].u_dsync.q1, u_orig.u_aud_spare_in_sync[0].u_dsync.q2);
      if (orig_prdata !== gen_prdata) begin
        if (kind == "invalid") invalid_read_mismatch = invalid_read_mismatch + 1;
        else if (kind == "ro_sync") ro_sync_read_mismatch = ro_sync_read_mismatch + 1;
        else if (kind == "stable_ro") stable_ro_read_mismatch = stable_ro_read_mismatch + 1;
        else read_mismatch = read_mismatch + 1;
        $display("[%0t] PRDATA-DIFF %s/%s addr=%h orig=%h parity=%h",
                 $time, tag, kind, paddr, orig_prdata, gen_prdata);
      end
    end
  endtask

  task automatic read_reg(input [31:0] a, input string tag, input string kind);
    begin
      @(negedge pclk); paddr = a; psel = 1; penable = 0; pwrite = 0;
      if (kind == "ro_sync") begin
        // Change at the setup edge, not one full cycle earlier.
        set_ro_inputs(ro_pattern); ro_pattern = ~ro_pattern;
        // One setup edge only: q2 of the original 2FF sync is old,
        // while the generated direct-input read data is new.
        @(posedge pclk); #1; check_prdata(tag, kind);
      end else begin
        @(negedge pclk); penable = 1;
        #1; check_prdata(tag, kind);
      end
      @(negedge pclk); psel = 0; penable = 0;
    end
  endtask

  task automatic write_reg(input [31:0] a, input [31:0] d, input string tag);
    begin
      @(negedge pclk); paddr = a; pwdata = d; psel = 1; penable = 0; pwrite = 1;
      @(negedge pclk); penable = 1;
      @(negedge pclk); psel = 0; penable = 0; pwrite = 0;
      #1; check_outputs(tag);
      read_reg(a, tag, "write_read");
    end
  endtask

  task automatic set_ro_inputs(input [31:0] value);
    begin
      aud_spare_in = value;
      regout_gmac0_rst_clk_tx_n_o = value;
      regout_gmac0_rst_clk_rx_n_o = value;
      regout_gmac0_rst_clk_app_n_o = value;
      regout_gmac0_mac_speed_o = value;
      regout_gmac0_sbd_tx_clk_gating_ctrl_o = value;
      regout_gmac0_sbd_ar_dma_ch_no_o = value;
      regout_gmac0_sbd_aw_dma_ch_no_o = value;
      regout_gmac0_sbd_w_dma_ch_no_o = value;
      regout_gmac0_csysack_o = value;
      regout_gmac0_cactive_o = value;
      regout_gmac0_ati_datatxon_o = value;
      regout_gmac0_ati_pmac_txon_o = value;
      regout_gmac0_ati_pmac_actv_o = value;
      regout_gmac0_mcgr_dma_req_o = value;
      regout_gmac0_sbd_pwr_down_ack_o = value;
      regout_gmac1_rst_clk_tx_n_o = value;
      regout_gmac1_rst_clk_rx_n_o = value;
      regout_gmac1_rst_clk_app_n_o = value;
      regout_gmac1_mac_speed_o = value;
      regout_gmac1_sbd_tx_clk_gating_ctrl_o = value;
      regout_gmac1_sbd_ar_dma_ch_no_o = value;
      regout_gmac1_sbd_aw_dma_ch_no_o = value;
      regout_gmac1_sbd_w_dma_ch_no_o = value;
      regout_gmac1_csysack_o = value;
      regout_gmac1_cactive_o = value;
      regout_gmac1_ati_datatxon_o = value;
      regout_gmac1_ati_pmac_txon_o = value;
      regout_gmac1_ati_pmac_actv_o = value;
      regout_gmac1_mcgr_dma_req_o = value;
      regout_gmac1_sbd_pwr_down_ack_o = value;
      rv_ecc_status0 = value;
      rv_ecc_status1 = value;
      rv_lockstep_mis = value;
      rv_safety_error = value;
      rv_safety_input_error_dcls = value;
      rv_core_status0 = value;
      rv_core_status1 = value;
      rv_core_status2 = value;
      rv_core_status3 = value;
      rv_core_status4 = value;
      rv_core_status5 = value;
      rv_i1_core_status1 = value;
      rv_i1_core_status2 = value;
      rv_i1_core_status3 = value;
      rv_i1_core_status4 = value;
      usb_wk_status = value;
      usb_wk_int_status = value;
    end
  endtask

  task automatic set_fc_done(input bit value);
    begin
      mcusys_aclk_fc_done = value;
      mcusys_pclk_fc_done = value;
      mcusys_rv_core_clk_fc_done = value;
      mcusys_m85_core0_clk_fc_done = value;
      mcusys_m85_core1_clk_fc_done = value;
      mcusys_m85_core2_clk_fc_done = value;
      mcusys_m85_core3_clk_fc_done = value;
      mcusys_dbgclk_fc_done = value;
    end
  endtask

  integer i;

  initial begin
    por_n = 1'b1; prstn = 1'b0; paddr = 0; pwrite = 0; psel = 0; penable = 0; pwdata = 0;
    mcusys_aclk_fc_done = '0;
    mcusys_pclk_fc_done = '0;
    mcusys_rv_core_clk_fc_done = '0;
    mcusys_m85_core0_clk_fc_done = '0;
    mcusys_m85_core1_clk_fc_done = '0;
    mcusys_m85_core2_clk_fc_done = '0;
    mcusys_m85_core3_clk_fc_done = '0;
    aud_spare_in = '0;
    regout_gmac0_rst_clk_tx_n_o = '0;
    regout_gmac0_rst_clk_rx_n_o = '0;
    regout_gmac0_rst_clk_app_n_o = '0;
    regout_gmac0_mac_speed_o = '0;
    regout_gmac0_sbd_tx_clk_gating_ctrl_o = '0;
    regout_gmac0_sbd_ar_dma_ch_no_o = '0;
    regout_gmac0_sbd_aw_dma_ch_no_o = '0;
    regout_gmac0_sbd_w_dma_ch_no_o = '0;
    regout_gmac0_csysack_o = '0;
    regout_gmac0_cactive_o = '0;
    regout_gmac0_ati_datatxon_o = '0;
    regout_gmac0_ati_pmac_txon_o = '0;
    regout_gmac0_ati_pmac_actv_o = '0;
    regout_gmac0_mcgr_dma_req_o = '0;
    regout_gmac0_sbd_pwr_down_ack_o = '0;
    regout_gmac1_rst_clk_tx_n_o = '0;
    regout_gmac1_rst_clk_rx_n_o = '0;
    regout_gmac1_rst_clk_app_n_o = '0;
    regout_gmac1_mac_speed_o = '0;
    regout_gmac1_sbd_tx_clk_gating_ctrl_o = '0;
    regout_gmac1_sbd_ar_dma_ch_no_o = '0;
    regout_gmac1_sbd_aw_dma_ch_no_o = '0;
    regout_gmac1_sbd_w_dma_ch_no_o = '0;
    regout_gmac1_csysack_o = '0;
    regout_gmac1_cactive_o = '0;
    regout_gmac1_ati_datatxon_o = '0;
    regout_gmac1_ati_pmac_txon_o = '0;
    regout_gmac1_ati_pmac_actv_o = '0;
    regout_gmac1_mcgr_dma_req_o = '0;
    regout_gmac1_sbd_pwr_down_ack_o = '0;
    mcusys_dbgclk_fc_done = '0;
    rv_ecc_status0 = '0;
    rv_ecc_status1 = '0;
    rv_lockstep_mis = '0;
    rv_safety_error = '0;
    rv_safety_input_error_dcls = '0;
    rv_core_status0 = '0;
    rv_core_status1 = '0;
    rv_core_status2 = '0;
    rv_core_status3 = '0;
    rv_core_status4 = '0;
    rv_core_status5 = '0;
    rv_i1_core_status1 = '0;
    rv_i1_core_status2 = '0;
    rv_i1_core_status3 = '0;
    rv_i1_core_status4 = '0;
    usb_wk_status = '0;
    usb_wk_int_status = '0;
    repeat (4) @(negedge pclk);
    check_outputs("reset_assert");
    prstn = 1'b1;
    repeat (3) @(negedge pclk);
    check_outputs("reset_release");
    for (i = 0; i < 157; i = i + 1) begin
      write_reg(i * 4, 32'hA5A5_5A5A ^ (i * 32'h0101_0101), "all_offsets");
    end
    // Invalid addresses use the original prdata_d hold path, not zero.
    write_reg(32'h34, 32'h1234_5678, "invalid_setup");
    read_reg(32'h34, "valid_before_invalid", "write_read");
    read_reg(32'h3fc, "invalid_address", "invalid");
    // Stable RO inputs should agree after the two-FF sync delay.
    set_ro_inputs(32'hA5A5_5A5A);
    repeat (4) @(negedge pclk);
    read_reg(32'h004, "stable_ro", "stable_ro");
    read_reg(32'h008, "stable_ro", "stable_ro");
    read_reg(32'h00c, "stable_ro", "stable_ro");
    read_reg(32'h010, "stable_ro", "stable_ro");
    read_reg(32'h014, "stable_ro", "stable_ro");
    read_reg(32'h018, "stable_ro", "stable_ro");
    read_reg(32'h01c, "stable_ro", "stable_ro");
    read_reg(32'h104, "stable_ro", "stable_ro");
    read_reg(32'h128, "stable_ro", "stable_ro");
    read_reg(32'h134, "stable_ro", "stable_ro");
    read_reg(32'h160, "stable_ro", "stable_ro");
    read_reg(32'h1c8, "stable_ro", "stable_ro");
    read_reg(32'h1cc, "stable_ro", "stable_ro");
    read_reg(32'h1d0, "stable_ro", "stable_ro");
    read_reg(32'h1d4, "stable_ro", "stable_ro");
    read_reg(32'h1d8, "stable_ro", "stable_ro");
    read_reg(32'h1dc, "stable_ro", "stable_ro");
    read_reg(32'h1e0, "stable_ro", "stable_ro");
    read_reg(32'h1e4, "stable_ro", "stable_ro");
    read_reg(32'h1e8, "stable_ro", "stable_ro");
    read_reg(32'h1ec, "stable_ro", "stable_ro");
    read_reg(32'h1f0, "stable_ro", "stable_ro");
    read_reg(32'h1f4, "stable_ro", "stable_ro");
    read_reg(32'h1f8, "stable_ro", "stable_ro");
    read_reg(32'h270, "stable_ro", "stable_ro");
    // Immediate changes expose missing synchronizers in generated RTL.
    // Each RO read toggles the input at its setup edge below.
    read_reg(32'h004, "ro_sync", "ro_sync");
    read_reg(32'h008, "ro_sync", "ro_sync");
    read_reg(32'h00c, "ro_sync", "ro_sync");
    read_reg(32'h010, "ro_sync", "ro_sync");
    read_reg(32'h014, "ro_sync", "ro_sync");
    read_reg(32'h018, "ro_sync", "ro_sync");
    read_reg(32'h01c, "ro_sync", "ro_sync");
    read_reg(32'h104, "ro_sync", "ro_sync");
    read_reg(32'h128, "ro_sync", "ro_sync");
    read_reg(32'h134, "ro_sync", "ro_sync");
    read_reg(32'h160, "ro_sync", "ro_sync");
    read_reg(32'h1c8, "ro_sync", "ro_sync");
    read_reg(32'h1cc, "ro_sync", "ro_sync");
    read_reg(32'h1d0, "ro_sync", "ro_sync");
    read_reg(32'h1d4, "ro_sync", "ro_sync");
    read_reg(32'h1d8, "ro_sync", "ro_sync");
    read_reg(32'h1dc, "ro_sync", "ro_sync");
    read_reg(32'h1e0, "ro_sync", "ro_sync");
    read_reg(32'h1e4, "ro_sync", "ro_sync");
    read_reg(32'h1e8, "ro_sync", "ro_sync");
    read_reg(32'h1ec, "ro_sync", "ro_sync");
    read_reg(32'h1f0, "ro_sync", "ro_sync");
    read_reg(32'h1f4, "ro_sync", "ro_sync");
    read_reg(32'h1f8, "ro_sync", "ro_sync");
    read_reg(32'h270, "ro_sync", "ro_sync");
    // fc_done=0 asynchronously clears the legacy fc_req bit [4].
    set_fc_done(1'b0);
    write_reg(32'h004, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h008, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h00c, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h010, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h014, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h018, 32'h0000_0010, "fc_req_clear");
    write_reg(32'h01c, 32'h0000_0010, "fc_req_clear");
    set_fc_done(1'b1);
    $display("FC_DBG before_set: done=%b prstn=%b custom_resetn=%b ctrl=%h", mcusys_aclk_fc_done, prstn, u_orig.mcusys_aclk_ctrl4_prstn, orig_mcusys_aclk_ctrl);
    write_reg(32'h004, 32'h0000_0010, "fc_req_set");
    write_reg(32'h008, 32'h0000_0010, "fc_req_set");
    write_reg(32'h00c, 32'h0000_0010, "fc_req_set");
    write_reg(32'h010, 32'h0000_0010, "fc_req_set");
    write_reg(32'h014, 32'h0000_0010, "fc_req_set");
    write_reg(32'h018, 32'h0000_0010, "fc_req_set");
    write_reg(32'h01c, 32'h0000_0010, "fc_req_set");
    set_fc_done(1'b0);
    #1; check_outputs("fc_req_done_fall");
    // A final global reset must restore every common output.
    prstn = 1'b0;
    repeat (3) @(negedge pclk);
    check_outputs("final_reset");
    $display("=== MITER SUMMARY ===");
    $display("output_checks=%0d output_mismatch=%0d fc_req_mismatch=%0d other_output_mismatch=%0d",
             output_checks, output_mismatch, fc_req_mismatch, other_output_mismatch);
    $display("read_checks=%0d write_read_mismatch=%0d invalid_read_mismatch=%0d stable_ro_mismatch=%0d ro_sync_mismatch=%0d",
             read_checks, read_mismatch, invalid_read_mismatch, stable_ro_read_mismatch, ro_sync_read_mismatch);
    if (output_mismatch || read_mismatch || invalid_read_mismatch || stable_ro_read_mismatch || ro_sync_read_mismatch)
      $display("MITER_RESULT: DIFFERENCES_FOUND");
    else
      $display("MITER_RESULT: EQUIVALENT_UNDER_TESTED_PROTOCOL");
    $finish;
  end
endmodule
