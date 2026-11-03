// ==================================================================
// tgl_struct_excl.el -- 8.reset_checker 结构常量 toggle 排除 (urg -elfile)
// 依据 urg -dump full_exclusions tgl 模板生成; CHECKSUM/模块头/信号签名
// 均从模板原文拷贝, 保证 urg 能精确对位. RTL 改动后需重新生成.
//
// 排除对象 (全部是结构上恒 0/恒 1、任何激励都翻不动的位):
//   addr[1:0]        上游 apb2mbus 桥保证字对齐 (协议常量 00)
//   addr[7:5]        寄存器图仅 0x00-0x14, >=0x18 全落同一未知偏移桶,
//                    译码不区分 (映射孔洞; parity/apb2mbus 同款排除)
//   off[1:0]/[7:5]   同上 (off = addr[7:0])
//   rdata/rdata_mux  保留位读恒 0: [15:10] [21:19] [24:23] [27:26] [29] [31]
//                    (ID 常量 0 位 + STAT/EV/REGPAR 保留字段)
//   reg_wrap wr      镜像 wrap (u_evimg/u_statimg) wr 恒接 1'b1 (跟随
//                    模式, 每拍跟随), 无 0 电平 (ia 项目同款排除)
// 双域排除: 实例域排除不进模块定义域 bin, 模块域 + 实例域各一份.
// ==================================================================

CHECKSUM: "3373645044 1676514623"
MODULE: reset_checker_regfile
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle off [1:0] "logic off[7:0]"
Toggle off [7:5] "logic off[7:0]"
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

CHECKSUM: "3125161402 3894550875"
MODULE: reset_checker
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

// ---------------- 实例域 (双域第二份) ----------------

CHECKSUM: "3373645044 1676514623"
INSTANCE: tb_reset_checker.dut.u_regfile
Toggle addr [1:0] "logic addr[15:0]"
Toggle addr [7:5] "logic addr[15:0]"
Toggle off [1:0] "logic off[7:0]"
Toggle off [7:5] "logic off[7:0]"
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

CHECKSUM: "3125161402 3894550875"
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
INSTANCE: tb_reset_checker.dut.u_regfile.u_evimg
Toggle wr "logic wr"

CHECKSUM: "1754090427 3389037570"
INSTANCE: tb_reset_checker.dut.u_regfile.u_statimg
Toggle wr "logic wr"
