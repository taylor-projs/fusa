// ==================================================================
// tgl_struct_excl.el -- 8.reset_checker 结构常量 toggle 排除 (urg -elfile)
// 依据 urg -dump full_exclusions tgl 模板生成; CHECKSUM/模块头/信号签名
// 均从模板原文拷贝, 保证 urg 能精确对位. RTL 改动后需重新生成.
// 2026-11-05 重生成: 单体 reset_checker 拆分 reset_checker_core/_top,
//   regfile 例化名 u_regfile -> u_reset_checker_regfile, 内部信号
//   off -> offset; CHECKSUM 全部按新 vdb 重新拷贝.
//   注: reg_wrap 参数化模块头行尾的空格是 urg 对位的一部分, 勿删.
//
// 排除对象 (全部是结构上恒 0/恒 1、任何激励都翻不动的位):
//   addr[1:0]        上游 apb2mbus 桥保证字对齐 (协议常量 00)
//   addr[7:5]        寄存器图仅 0x00-0x14, >=0x18 全落同一未知偏移桶,
//                    译码不区分 (映射孔洞; parity/apb2mbus 同款排除)
//   offset[1:0]/[7:5] 同上 (offset = addr[7:0])
//   rdata/rdata_mux  保留位读恒 0: [15:10] [21:19] [24:23] [27:26] [29] [31]
//                    (ID 常量 0 位 + STAT/EV/REGPAR 保留字段)
//   ctrl_r[3]/rdata[3]/data_q[3]  CTRL.MODE 是 4bit one-hot 合法码
//                    0001/0010/0100 (NORMAL/INJECT/OFF), sto_ctrl 写门含
//                    mode_ok -> 非法码 (含一切 MODE[3]=1 码) 永不落盘,
//                    bit3 结构恒 0 (regfile 回读线 + u_ctrl wrap 内部位)
//   reg_wrap wr      镜像 wrap (u_evimg/u_statimg) wr 恒接 1'b1 (跟随
//                    模式, 每拍跟随), 无 0 电平 (ia 项目同款排除)
// 双域排除: 实例域排除不进模块定义域 bin, 模块域 + 实例域各一份.
// ==================================================================

CHECKSUM: "697297812 546028165"
MODULE: reset_checker_regfile
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle offset [1:0] "logic offset[7:0]"
Toggle offset [7:5] "logic offset[7:0]"
Toggle rdata [15:10] "logic rdata[31:0]"
Toggle rdata [21:19] "logic rdata[31:0]"
Toggle rdata [24:23] "logic rdata[31:0]"
Toggle rdata [27:26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle rdata_mux [15:10] "logic rdata_mux[31:0]"
Toggle rdata_mux [21:19] "logic rdata_mux[31:0]"
Toggle rdata_mux [24:23] "logic rdata_mux[31:0]"
Toggle rdata_mux [27:26] "logic rdata_mux[31:0]"
Toggle rdata_mux [29] "logic rdata_mux[31:0]"
Toggle rdata_mux [31] "logic rdata_mux[31:0]"
Toggle ctrl_r [3] "logic ctrl_r[3:0]"

CHECKSUM: "153086616 1831917773"
MODULE: reset_checker_top
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle rdata [15:10] "logic rdata[31:0]"
Toggle rdata [21:19] "logic rdata[31:0]"
Toggle rdata [24:23] "logic rdata[31:0]"
Toggle rdata [27:26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1754090427 2954376894"
MODULE: reg_wrap ( parameter W=3,RESET=0 ) 
Toggle wr "logic wr"

CHECKSUM: "1754090427 3389037570"
MODULE: reg_wrap ( parameter W=11,RESET=0 ) 
Toggle wr "logic wr"

CHECKSUM: "1754090427 1027321138"
MODULE: reg_wrap ( parameter W=4,RESET=1 ) 
Toggle rdata [3] "logic rdata[3:0]"
Toggle r.data_q [3] "logic r.data_q[3:0]"
Toggle rin.data_q [3] "logic rin.data_q[3:0]"

// ---------------- 实例域 (双域第二份) ----------------

CHECKSUM: "697297812 546028165"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle offset [1:0] "logic offset[7:0]"
Toggle offset [7:5] "logic offset[7:0]"
Toggle rdata [15:10] "logic rdata[31:0]"
Toggle rdata [21:19] "logic rdata[31:0]"
Toggle rdata [24:23] "logic rdata[31:0]"
Toggle rdata [27:26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"
Toggle rdata_mux [15:10] "logic rdata_mux[31:0]"
Toggle rdata_mux [21:19] "logic rdata_mux[31:0]"
Toggle rdata_mux [24:23] "logic rdata_mux[31:0]"
Toggle rdata_mux [27:26] "logic rdata_mux[31:0]"
Toggle rdata_mux [29] "logic rdata_mux[31:0]"
Toggle rdata_mux [31] "logic rdata_mux[31:0]"
Toggle ctrl_r [3] "logic ctrl_r[3:0]"

CHECKSUM: "153086616 1831917773"
INSTANCE: tb_reset_checker.dut
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle rdata [15:10] "logic rdata[31:0]"
Toggle rdata [21:19] "logic rdata[31:0]"
Toggle rdata [24:23] "logic rdata[31:0]"
Toggle rdata [27:26] "logic rdata[31:0]"
Toggle rdata [29] "logic rdata[31:0]"
Toggle rdata [31] "logic rdata[31:0]"

CHECKSUM: "1754090427 2954376894"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_evimg
Toggle wr "logic wr"

CHECKSUM: "1754090427 3389037570"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_statimg
Toggle wr "logic wr"

CHECKSUM: "1754090427 1027321138"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_ctrl
Toggle rdata [3] "logic rdata[3:0]"
Toggle r.data_q [3] "logic r.data_q[3:0]"
Toggle rin.data_q [3] "logic rin.data_q[3:0]"

// ---- 2026-11-07 增补 (TB 109-check vdb 复验残 4 对象) ----
// rdata[18]/rdata_mux[18]: 全图恒 0 (ID 0x5243_0001 bit18=0, 其余
//   字段窄于 bit18) —— 读恒 0 保留位族, 同 [15:10]/[21:19] 判例
// dup_err: reg_wrap 双轨副本失配线, 总线路径不可达 (cmm F 族判例)
CHECKSUM: "1754090427 2929597457"
INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_w_cmd
Toggle dup_err "logic dup_err"

CHECKSUM: "153086616 1831917773"
MODULE: reset_checker_top
Toggle rdata [18] "logic rdata[31:0]"

CHECKSUM: "2049934112 3639887880"
MODULE: reset_checker_regfile
Toggle rdata [18] "logic rdata[31:0]"
Toggle rdata_mux [18] "logic rdata_mux[31:0]"

CHECKSUM: "1754090427 2929597457"
MODULE: reg_wrap ( parameter W=1,RESET=0 ) 
Toggle dup_err "logic dup_err"

