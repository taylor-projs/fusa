#!/usr/bin/env python3
# gen_tgl_excl.py -- 从 urg -dump full_exclusions tgl 的模板生成结构常量 toggle 排除文件.
#
# 排除对象 (全部是结构上恒 0/恒 1、任何激励都翻不动的位):
#   nuclei300_edc_gen:  t_dat[63:DW]      -- 64 位零扩展填充 (DW<64)
#                       t_edc 中 XOR 源全在填充区内的恒定位
#   nuclei300_edc_chk:  t_dat[63:DW], t_edc[6:EDCW] (EDC 位宽零填充),
#                       syndrome 中数据/校验源全恒 0 的恒定位
#   nuclei300_edc_chk_fault_ej:
#                       einj_pos[127:64]  (edc_site.inj_pos_g 高 64 位恒 0),
#                       einj_force_err 除独热强制位 (128-DW-EDCW) 外恒 0
#   edc_site:           inj_pos_g/inj_pos_e [127:64] ({64'b0,i_inj_pos} 零扩),
#                       inj_force_v 除强制位外恒 0; DW=64 变体 gen_msk 切片
#                       [DW+:EDCW] 全落零扩区 -> 整段恒 0
#   GEN 模式站点实例 (tb_edc_side): o_err 悬空 (GEN 本地不置位, 对端 CHK 报)
#                       + i_edc 绑 '0 (GEN 只重算 EDC, 不消费随路 EDC);
#                       DW=64 站 (w_data/r_data) 内部 chk 的 t_edc 网亦恒 0
#                       (einj EDC 槽 [70:64] 落 inj_pos 零扩区, pos 不可达)
#   TB 端点注错恒 0:   tb_edc_top 的端点 edc_gen (u_gen0/u_gen1: i_inj_en/
#                       i_inj_pos/i_inj_force 绑 0) 及其内部 13 站 edc_site
#                       + TB 自建端点 edc_site (u_b0_*/u_r0_*/u_b1_*/u_r1_*:
#                       注错三口与 i_edc 全绑常 0) -> 注错链信号整段恒 0
#   SIDE 部署结构常量:  edc_core GEN 方向 req/rsp 半侧 err 恒 0 + 非生成方向
#                       user_o 恒 0 + GEN 方向 user 输入绑 0; edc_regfile 内
#                       err 链 GEN 半侧 (含 err_st/fault_st 输出) + 跟随型
#                       wrap (wr 绑 1'b1) 数据 GEN 半侧; rst_sync scan_mode
#                       绑 0; mbus addr[15:9] (实例号 <=2, bit8 已是最高位)
#                       + addr[1:0] (字对齐, edc_core/edc_regfile/edc_top)
#   寄存器地图常量:    edc_regfile perr[4]/perr[10] (CLR_MASK/pos 影子组随
#                       锁存+req_edge 改版退役, 恒 0); edc_top NUM_CORE=2 ->
#                       sta_*_r 32 位 wrap [31:2] 恒 0 + sta_par_rb[31:7]
#                       恒 0 (25'h0 拼接)
#
# 当前拓扑 (2026-11-08 双域 regfile 改版后):
#   tb_edc_side: u_ms=edc_core#(IDX0,SIDE0) + u_sl=edc_core#(IDX1,SIDE1)
#                + u_agg=edc_top#(IDX2) 聚合器
#     SIDE=0: req 站 0..12 GEN (g_req_gen) -> req_site_err 恒 0, b/r user_o 恒 0
#     SIDE=1: rsp 站 13..17 GEN (g_rsp_gen) -> rsp_site_err 恒 0, aw/w/ar user_o 恒 0
#   tb_edc_top:  dut0/dut1=edc_core#(SIDE2) 观测 (全站 CHK, user_o 全恒 0)
#                + u_agg=edc_top 聚合器 (不内嵌 core, 双轨为输入)
#   edc_regfile: 锁存+req_edge 改版后拓扑 (2026-11-08):
#                - err 链 GEN 半侧 (site_err/s1/s2/nxt) + 跟随 wrap 常量
#                  (u_err_st/u_fault_st/u_err2/u_fault2/u_cfg_en/u_cfg_force/
#                   u_cfg_irqen 的 wr 绑 1'b1; 数据 GEN 半侧仅 err 链四个)
#                - u_err_sync/u_fault_sync (sync_dff 首级) q 的 GEN 半侧
#                - wsel_q[4]: 地址地图性质 (合法 wsel 0..3/0x28..0x2D 无 bit4)
#
# 用法: python3 gen_tgl_excl.py fullexclude_module.tgl fullexclude.tgl out.el
# 模板来自 (两个 vdb 各 dump 一次, 模块/实例模板都拼接; 模块段同名去重 --
# 共有模块保留 side 版, edc_gen/DW=2 站点等 top 独有模块照常通过):
#   cd obj_vcs      && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/fx_top
#   cd obj_vcs_side && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/fx_side
#   cat /tmp/fx_side/fullexclude_module.tgl /tmp/fx_top/fullexclude_module.tgl > /tmp/fx_mod.tgl
#   cat /tmp/fx_side/fullexclude.tgl /tmp/fx_top/fullexclude.tgl > /tmp/fx_inst.tgl
# CHECKSUM/模块头/信号签名均从模板原文拷贝, 保证 urg 能精确对位.
import re
import sys

modfile, instfile, outfile = sys.argv[1], sys.argv[2], sys.argv[3]


def parse(path, key):
    """解析 dump 模板, 返回 [{'hdr': [...], 'name': str, 'sigs': {sig: decl}}]
    同名段 (side+top 模板拼接) 保留首见 (side), top 独有段照常通过."""
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    secs = []
    seen_names = set()
    for idx, ln in enumerate(lines):
        if ln.startswith("// %s:" % key):
            name = ln[3:]
            if name in seen_names:
                continue
            seen_names.add(name)
            hdr = []
            for back in range(max(0, idx - 4), idx):
                if lines[back].startswith("// CHECKSUM:"):
                    hdr.append(lines[back][3:])
                    break
            hdr.append(ln[3:])
            sigs = {}
            k = idx + 1
            while k < len(lines):
                b = lines[k]
                if (b.startswith("// CHECKSUM:") or b.startswith("// MODULE:")
                        or b.startswith("// INSTANCE:")):
                    break
                # 信号名可为 packed 结构成员 (r.err_s1), 需放行 '.'
                t = re.match(r'^// Toggle (?:0to1 |1to0 )?([\w.]+) "([^"]+)"', b)
                if t and t.group(1) not in sigs:
                    sigs[t.group(1)] = t.group(2)
                k += 1
            secs.append({"hdr": hdr, "name": name, "sigs": sigs})
    return secs


def tgl(sig, hi, lo, decl):
    if hi is None:
        return 'Toggle %s "%s"' % (sig, decl)
    if hi == lo:
        return 'Toggle %s [%d] "%s"' % (sig, hi, decl)
    return 'Toggle %s [%d:%d] "%s"' % (sig, hi, lo, decl)


# ---------------- 模块级: 每参数变体的恒定范围 ----------------
# gen: t_dat 高位填充 + t_edc 恒定位 (XOR 源最低位: edc[2]=1,[3]=4,[4]=11,[5]=26,[6]=57)
GEN_T = {1: [("t_dat", 63, 1), ("t_edc", 6, 2)],
         2: [("t_dat", 63, 2), ("t_edc", 6, 3)],
         3: [("t_dat", 63, 3), ("t_edc", 6, 3)],
         4: [("t_dat", 63, 4), ("t_edc", 6, 3)],
         8: [("t_dat", 63, 8), ("t_edc", 6, 4)],
         10: [("t_dat", 63, 10), ("t_edc", 6, 4)],
         11: [("t_dat", 63, 11), ("t_edc", 6, 4)],
         20: [("t_dat", 63, 20), ("t_edc", 6, 5)]}
# chk: 再加 t_edc[6:EDCW] 填充 + syndrome 恒定位
CHK_T = {1: [("t_dat", 63, 1), ("t_edc", 6, 1), ("syndrome", 6, 2)],
         2: [("t_dat", 63, 2), ("t_edc", 6, 3), ("syndrome", 6, 3)],
         3: [("t_dat", 63, 3), ("t_edc", 6, 3), ("syndrome", 6, 3)],
         4: [("t_dat", 63, 4), ("t_edc", 6, 3), ("syndrome", 6, 3)],
         8: [("t_dat", 63, 8), ("t_edc", 6, 4), ("syndrome", 6, 4)],
         10: [("t_dat", 63, 10), ("t_edc", 6, 4), ("syndrome", 6, 4)],
         11: [("t_dat", 63, 11), ("t_edc", 6, 4), ("syndrome", 6, 4)],
         20: [("t_dat", 63, 20), ("t_edc", 6, 5), ("syndrome", 6, 5)]}


def force_ranges(dw, edcw):
    f = 128 - dw - edcw          # 独热强制位位置
    return [("einj_pos", 127, 64),
            ("einj_force_err", 127, f + 1), ("einj_force_err", f - 1, 0)]


def site_ranges(dw, edcw):
    f = 128 - dw - edcw
    r = [("inj_pos_g", 127, 64), ("inj_pos_e", 127, 64),
         ("inj_force_v", 127, f + 1), ("inj_force_v", f - 1, 0)]
    if dw == 64:
        # DW=64: gen_msk = inj_pos_e[64+:EDCW] 全落 {64'b0,...} 零扩区
        r.append(("gen_msk", 6, 0))
    return r


MOD_RULES = [  # (模块名正则, 范围表函数)
    (r"^MODULE: nuclei300_edc_gen \( parameter DW=(\d+),EDCW=(\d+) \)\s*$",
     lambda dw, edcw: GEN_T.get(dw, [])),
    (r"^MODULE: nuclei300_edc_chk \( parameter DW=(\d+),EDCW=(\d+) \)\s*$",
     lambda dw, edcw: CHK_T.get(dw, [])),
    (r"^MODULE: nuclei300_edc_chk_fault_ej \( parameter DW=(\d+),EDCW=(\d+),PW=(\d+) \)\s*$",
     lambda dw, edcw, pw: force_ranges(dw, edcw)),
    (r"^MODULE: edc_site \( parameter DW=(\d+),MODE,EDCW=(\d+) \)\s*$",
     site_ranges),
]

# ---------------- 实例级: GEN 模式站点 (SIDE 部署, 仅 tb_edc_side) -------------
# u_ms (SIDE=0) req 半侧 13 站 / u_sl (SIDE=1) rsp 半侧 5 站为 GEN:
#   o_err 悬空 (GEN 注错只翻 EDC 位, 本地不置位 -- 对端 CHK 检出上报)
#   i_edc 绑 '0 (GEN 不消费随路 EDC; chk 方向站点经 TB user 激励覆盖)
REQ_SITES = ["u_gen_aw_hi", "u_gen_aw_lo", "u_gen_aw_a0", "u_gen_aw_a1",
             "u_gen_aw_id", "u_gen_w_data", "u_gen_w_mask", "u_gen_w_last",
             "u_gen_ar_hi", "u_gen_ar_lo", "u_gen_ar_a0", "u_gen_ar_a1",
             "u_gen_ar_id"]
RSP_SITES = ["u_gen_b_at", "u_gen_b_id", "u_gen_r_data", "u_gen_r_at",
             "u_gen_r_id"]
GEN_INSTS = (["tb_edc_side.u_ms.g_req_gen." + s for s in REQ_SITES]
             + ["tb_edc_side.u_sl.g_rsp_gen." + s for s in RSP_SITES])

# ---------------- 实例级: 结构常量段/位 (恒 0, 任何激励翻不动) ----------------
# 规则 = (实例路径, [(信号, hi, lo), ...]); hi=None 表示整个信号.
# 依据:
#  (a) SIDE 部署半侧 (tb_edc_side): GEN 方向站点不置位 ->
#     edc_core req_site_err (SIDE=0, [12:0] 整段) / rsp_site_err (SIDE=1,
#     [4:0] 整段) 与 site_err_g 的 GEN 半侧恒 0; 非生成方向 user_o 绑常 0
#     (g_req_chk/g_rsp_chk else 分支); 观测 core (dut0/dut1, SIDE=2) 全部
#     user_o 恒 0 (纯挂线监控, 集成可不接).
#  (b) edc_regfile err 链 GEN 半侧: site_err 输入 / 同步级 r.err_s1,fault_s1
#     (含 rin) / 镜像 err_s2,fault_s2 / 组合 err_nxt,fault_nxt / 跟随 wrap
#     (u_err_st,u_fault_st,u_err2,u_fault2: wr 端口 RTL 常量绑 1'b1, 数据
#     = err_nxt/err_s1 的 GEN 半侧) 恒 0.
#  (c) rst_sync (regfile 内 u_rst_sync): scan_mode 例化绑 1'b0 (DFT 信号,
#     仿真激励不可达).
#  (d) addr[15:9]: 实例号 [15:8] 只有 0/1/2 (两个 core + 聚合器, bit8 已是
#     最高有效位), mbus 上 addr[15:9] 恒 0; 两个 TB 同构 (tb_edc_top 经
#     apb2mbus, inst_bad 门控同结论; tb_edc_side TB 直接驱动, 实例号恒 <=2).
def _whole(s):
    return (s, None, None)


def _half(s, hi, lo):
    return (s, hi, lo)


MS = "tb_edc_side.u_ms"       # SIDE=0: GEN 半侧 = req 站 0..12
SL = "tb_edc_side.u_sl"       # SIDE=1: GEN 半侧 = rsp 站 13..17
OBS = ["tb_edc_top.dut0", "tb_edc_top.dut1"]   # SIDE=2 观测
CORES = [MS, SL] + OBS
USERO_ALL = ["awuser_o", "wuser_o", "aruser_o", "buser_o", "ruser_o"]

# regfile 内 err 链 (GEN 半侧恒 0): 输入/同步级/镜像/组合下一拍/输出
RF_HALFSIGS = ["site_err", "err_s1", "fault_s1",
               "err_s2", "fault_s2", "err_nxt", "fault_nxt",
               "err_st", "fault_st"]
# 跟随型 wrap (wr 绑 1'b1): err 链四个数据 GEN 半侧, cfg 图像三个数据全活
FOLLOWER_DATASIGS = ["wdata", "rdata", "r.data_q", "rin.data_q"]
ERRFOLLOWER_WRAPS = ["u_err_st", "u_fault_st",   # mod 域 sticky
                     "u_err2", "u_fault2"]       # mbus 域镜像
CFGFOLLOWER_WRAPS = ["u_cfg_en", "u_cfg_force", "u_cfg_irqen"]  # mbus 图像


# 地图级常量 (4 个 core 实例同): addr[1:0] 字对齐不译码; perr[4]/perr[10]
# 退役组恒 0 (CLR_MASK 累加器与 pos 影子随锁存+req_edge 改版撤销)
RF_MAPCONST = [_half("addr", 1, 0), _half("perr", 4, 4), _half("perr", 10, 10)]


def rf_rules(hi, lo):
    return ([_half("addr", 15, 9), _half("r.wsel_q", 4, 4),
             _half("rin.wsel_q", 4, 4)] + RF_MAPCONST
            + [_half(s, hi, lo) for s in RF_HALFSIGS])


INST_STRUCT_RULES = (
    # 观测 core: user_o 全恒 0 + addr[15:9]/addr[1:0]
    [(o, [_half("addr", 15, 9), _half("addr", 1, 0)]
      + [_whole(s) for s in USERO_ALL])
     for o in OBS]
    # SIDE=0 / SIDE=1 core: GEN 半侧 err + 非生成方向 user_o + GEN 方向
    # user 输入 (tb_edc_side 绑 0, GEN 不消费输入 user) + addr 常量域
    + [(MS, [_half("addr", 15, 9), _half("addr", 1, 0),
             _whole("req_site_err"), _half("site_err_g", 12, 0)]
        + [_whole(s) for s in ("buser_o", "ruser_o",
                               "awuser", "wuser", "aruser")]),
       (SL, [_half("addr", 15, 9), _half("addr", 1, 0),
             _whole("rsp_site_err"), _half("site_err_g", 17, 13)]
        + [_whole(s) for s in ("awuser_o", "wuser_o", "aruser_o",
                               "buser", "ruser")]),
       # regfile: err 链 GEN 半侧 (观测 core 无半侧, 只排地图常量)
       (MS + ".u_edc_regfile", rf_rules(12, 0)),
       (SL + ".u_edc_regfile", rf_rules(17, 13))]
    + [(o + ".u_edc_regfile", [_half("addr", 15, 9), _half("r.wsel_q", 4, 4),
                               _half("rin.wsel_q", 4, 4)] + RF_MAPCONST)
       for o in OBS]
    # rst_sync scan_mode 绑 0 (4 个 core 的 regfile 各一)
    + [(c + ".u_edc_regfile.u_rst_sync", [_whole("scan_mode")])
       for c in CORES]
    # edc_top 聚合器 (两 TB 各一): addr[15:9] + addr[1:0] (字对齐) +
    # NUM_CORE=2 -> sta_*_r 32 位 wrap [31:2] 恒 0 + sta_par_rb[31:7] 恒 0;
    # rdata 组合读出总线上无任何寄存器腿驱动的位 (IDX=2 地图: 状态腿
    # [1:0]/[6:2] + ID 0xEDC0_2002 的 1 位并集之外) 恒 0
    + [("tb_edc_top.u_agg",
        [_half("addr", 15, 9), _half("addr", 1, 0),
         _half("sta_err_r", 31, 2), _half("sta_fault_r", 31, 2),
         _half("sta_parc_r", 31, 2), _half("sta_rail_r", 31, 2),
         _half("sta_par_rb", 31, 7),
         _half("rdata", 21, 14), _half("rdata", 12, 7),
         _half("rdata", 25, 25), _half("rdata", 28, 28)]),
       ("tb_edc_side.u_agg",
        [_half("addr", 15, 9), _half("addr", 1, 0),
         _half("sta_err_r", 31, 2), _half("sta_fault_r", 31, 2),
         _half("sta_parc_r", 31, 2), _half("sta_rail_r", 31, 2),
         _half("sta_par_rb", 31, 7),
         _half("rdata", 21, 14), _half("rdata", 12, 7),
         _half("rdata", 25, 25), _half("rdata", 28, 28)])]
    # 聚合器 4 个 32 位状态 wrap: 数据 = {30'b0, 2 位 live} -> [31:2] 恒 0
    + [(tb + ".u_agg." + w,
        [_half(s, 31, 2) for s in FOLLOWER_DATASIGS])
       for tb in ("tb_edc_top", "tb_edc_side")
       for w in ("u_w_sta_err", "u_w_sta_fault", "u_w_sta_parc",
                 "u_w_sta_rail")]
    # 跟随 wrap: err 链四件数据 GEN 半侧 + wr 常量 (仅 SIDE core)
    + [(MS + ".u_edc_regfile." + w,
        [_half(s, 12, 0) for s in FOLLOWER_DATASIGS] + [_whole("wr")])
       for w in ERRFOLLOWER_WRAPS]
    + [(SL + ".u_edc_regfile." + w,
        [_half(s, 17, 13) for s in FOLLOWER_DATASIGS] + [_whole("wr")])
       for w in ERRFOLLOWER_WRAPS]
    # 跟随 wrap wr 常量 (改版后全部 4 个 core 的 err 链/cfg 图像都是跟随)
    + [(c + ".u_edc_regfile." + w, [_whole("wr")])
       for c in CORES for w in ERRFOLLOWER_WRAPS + CFGFOLLOWER_WRAPS]
    # sync_dff 首级 (err/fault) q/d 的 GEN 半侧 (SIDE core; 观测 core 全活;
    # d = 首级输入 = mod 域 err 链 GEN 半侧, 与 q 同源恒 0)
    + [(MS + ".u_edc_regfile.u_err_sync",   [_half("q", 12, 0),
                                             _half("d", 12, 0)]),
       (MS + ".u_edc_regfile.u_fault_sync", [_half("q", 12, 0),
                                             _half("d", 12, 0)]),
       (SL + ".u_edc_regfile.u_err_sync",   [_half("q", 17, 13),
                                             _half("d", 17, 13)]),
       (SL + ".u_edc_regfile.u_fault_sync", [_half("q", 17, 13),
                                             _half("d", 17, 13)])]
    # GEN 站点内部 chk_fault_ej: edc 输入 = 站点 i_edc 绑 '0 -> 恒 0;
    # DW=64 站 (w_data/r_data) 的 einj EDC 槽 [DW+PW-1:DW]=[70:64] 落
    # inj_pos 零扩区 (edc_site.sv 头注释: DW=64 站 pos 不可达, 只支持
    # force) -> edc_ej 与内部 chk 的 edc 口 + 内部 t_edc 网同恒 0
    # (其余 GEN 站 edc_ej/内部 edc/t_edc 由 einj 活位驱动, S14k EN=1
    # 图案扫描覆盖, 不排); DW=64 GEN 站只存在于 tb_edc_side (top 观测
    # core SIDE=2 双向全 CHK, generate-if 不例化 gen 引擎)
    + [(i + ".u_nuclei300_edc_chk_fault_ej", [_whole("edc")])
       for i in GEN_INSTS]
    + [(i + ".u_nuclei300_edc_chk_fault_ej",
        [_whole("edc"), _whole("edc_ej")])
       for i in ("tb_edc_side.u_ms.g_req_gen.u_gen_w_data",
                 "tb_edc_side.u_sl.g_rsp_gen.u_gen_r_data")]
    + [(i + ".u_nuclei300_edc_chk_fault_ej.u_nuclei300_edc_chk",
        [_whole("edc"), _whole("t_edc")])
       for i in ("tb_edc_side.u_ms.g_req_gen.u_gen_w_data",
                 "tb_edc_side.u_sl.g_rsp_gen.u_gen_r_data")]
    # tb_edc_top 端点注错链恒 0:
    #   (e) TB 自建端点 edc_site (B/R 响应 EDC 现算): 注错三口 + i_edc 全绑
    #       常 0, o_err 悬空 (GEN 模式本就恒 0) -> 注错链整段恒 0
    #   (f) u_gen0/u_gen1 (edc_gen MODE=0) 内部 13 站: i_inj_* 经模块口绑 0
    #       -> 站点注错链恒 0 (i_edc 接 TB user 激励, 活; 不排)
    + [(  "tb_edc_top." + s,
          [_whole(x) for x in ("i_inj_pos", "i_inj_en", "i_inj_force",
                               "gen_msk", "inj_pos_e", "inj_pos_g",
                               "inj_force_v", "o_err", "i_edc")])
       for s in ("u_b0_at", "u_b0_id", "u_r0_data", "u_r0_at", "u_r0_id",
                 "u_b1_at", "u_b1_id", "u_r1_data", "u_r1_at", "u_r1_id")]
    + [(  "tb_edc_top.u_gen" + g + "." + s,
          [_whole(x) for x in ("i_inj_pos", "i_inj_en", "i_inj_force",
                               "gen_msk", "inj_pos_e", "inj_pos_g",
                               "inj_force_v", "o_err")])
       for g in ("0", "1")
       for s in ("u_aw_addr_hi", "u_aw_addr_lo", "u_aw_attri0", "u_aw_attri1",
                 "u_aw_id", "u_w_data", "u_w_mask", "u_w_last",
                 "u_ar_addr_hi", "u_ar_addr_lo", "u_ar_attri0", "u_ar_attri1",
                 "u_ar_id")]
)

out = ["// ==================================================================",
       "// tgl_struct_excl.el -- 2.parity 结构常量 toggle 排除 (urg -elfile)",
       "// 由 gen_tgl_excl.py 依据 urg full-exclusion 模板生成; 排除项全部为",
       "// 结构上恒 0/恒 1 的位 (零扩展填充 / 未用注入向量位 / GEN 模式屏蔽",
       "// 输出与 SIDE 部署半侧 err·user_o 向量 / 跟随 wrap 常量半侧与 wr 绑定 /",
       "// rst_sync scan_mode 绑 0 / mbus addr[15:9] 实例号域), 与激励无关,",
       "// 任何测试都翻不动.",
       "// RTL 改动后需重新生成 (见脚本头注释).",
       "// ==================================================================",
       ""]

n_mod = n_inst = n_line = 0
for sec in parse(modfile, "MODULE"):
    for pat, fn in MOD_RULES:
        m = re.match(pat, sec["name"])
        if not m:
            continue
        ranges = fn(*[int(g) for g in m.groups()])
        if not ranges:
            break
        out += sec["hdr"]
        for sig, hi, lo in ranges:
            decl = sec["sigs"].get(sig)
            if decl is None:
                sys.stderr.write("WARN: %s: signal %s not in template, skipped\n"
                                 % (sec["name"], sig))
                continue
            out.append(tgl(sig, hi, lo, decl))
            n_line += 1
        out.append("")
        n_mod += 1
        break

# 实例路径 -> 排除项表: GEN 模式站点 + 结构常量段规则
INST_MAP = {i: [("o_err", None, None), ("i_edc", None, None)]
            for i in GEN_INSTS}
for path, items in INST_STRUCT_RULES:
    INST_MAP.setdefault(path, []).extend(items)

# ---------------- 模块级: module-definition 视图的结构常量段 ----------------
# 实例级排除不反映到 urg 的 module-definition 视图 (单实例模块的 module
# 段仍报未覆盖). 下列模块级条目与实例级规则同一结构依据:
#   addr[15:9]: 实例号只有 0/1/2 -> mbus/寄存器面地址实例域恒 0
#     (tb_edc_top 经 apb2mbus inst_bad 门控: paddr[15:8] >= NP 不发起
#      mbus 传输, 桥内保持寄存器 paddr_q 同样只锁合法地址);
#   addr[1:0]: 寄存器面字对齐, 两位不参与译码;
#   perr[4]/perr[10]: 退役 PERR 组恒 0 (锁存+req_edge 改版);
#   edc_top sta_*_r[31:2]/sta_par_rb[31:7]: NUM_CORE=2 (全部实例) 拼接常 0;
#   edc_core: 无参段 = top 观测形状 (user_o 全恒 0); SIDE=0/1 参数段 =
#     side 单实例形 (GEN 半侧常量, 同 MS/SL 实例规则);
#   reg_wrap W=32 段: 仅聚合器 5 wrap, 数据口 2/1 位网络零扩 -> [31:2] 恒 0;
#   rst_sync scan_mode: 所有例化绑 1'b0 (DFT);
#   edc_gen: 模板无该模块段 -- dut/core 内部 gen 引擎的 i_inj_* 接各自
#     regfile (活), 模块视图真覆盖, 不排除.
MOD_STRUCT_RULES = [
    (r"^MODULE: apb2mbus\s*$",
     [("addr", 15, 9),
      ("r_apb.paddr_q", 15, 9), ("rin_apb.paddr_q", 15, 9)]),
    (r"^MODULE: edc_top\s*$",
     [("addr", 15, 9), ("addr", 1, 0),
      ("sta_err_r", 31, 2), ("sta_fault_r", 31, 2),
      ("sta_parc_r", 31, 2), ("sta_rail_r", 31, 2),
      ("sta_par_rb", 31, 7),
      ("rdata", 21, 14), ("rdata", 12, 7),
      ("rdata", 25, 25), ("rdata", 28, 28)]),
    (r"^MODULE: edc_regfile\s*$",
     [("addr", 15, 9), ("addr", 1, 0),
      ("perr", 4, 4), ("perr", 10, 10),           # 退役组恒 0
      ("r.wsel_q", 4, 4), ("rin.wsel_q", 4, 4)]),   # 合法 wsel 无 bit4
    # edc_core 无参数段 = tb_edc_top 的 SIDE=2 观测形状 (dut0/dut1 两实例
    # 同形合并; side 设计无此段): 观测 core 纯挂线, user_o 全恒 0
    (r"^MODULE: edc_core\s*$",
     [("addr", 15, 9), ("addr", 1, 0)]
     + [(s, None, None) for s in USERO_ALL]),
    # edc_core SIDE=0/1 参数段 (tb_edc_side 单实例形): 与 MS/SL 实例规则
    # 同一结构依据 (GEN 半侧 user 输入绑 0 / 非生成方向 user_o 恒 0 /
    # GEN 半侧 site_err 恒 0)
    (r"^MODULE: edc_core \( parameter IDW=\d+,IDX=\d+,SIDE=0,",
     [("addr", 15, 9), ("addr", 1, 0), ("req_site_err", None, None),
      ("site_err_g", 12, 0)]
     + [(s, None, None) for s in ("awuser", "wuser", "aruser",
                                  "buser_o", "ruser_o")]),
    (r"^MODULE: edc_core \( parameter IDW=\d+,IDX=\d+,SIDE=1,",
     [("addr", 15, 9), ("addr", 1, 0), ("rsp_site_err", None, None),
      ("site_err_g", 17, 13)]
     + [(s, None, None) for s in ("buser", "ruser",
                                  "awuser_o", "wuser_o", "aruser_o")]),
    # reg_wrap W=32 段: 两设计该段实例 = edc_top 聚合器 5 个 wrap
    # (sta_err_w 等为 2 位/1 位网络零扩接入 32 位口, cmd_w 1 位) ->
    # wdata/rdata/r.data_q/rin.data_q [31:2] 结构恒 0
    (r"^MODULE: reg_wrap \( parameter W=32,RESET=0 \)\s*$",
     [(s, 31, 2) for s in ("wdata", "rdata", "r.data_q", "rin.data_q")]),
    (r"^MODULE: rst_sync",
     [("scan_mode", None, None)]),
]

for sec in parse(modfile, "MODULE"):
    for pat, ranges in MOD_STRUCT_RULES:
        if not re.match(pat, sec["name"]):
            continue
        out += sec["hdr"]
        for sig, hi, lo in ranges:
            decl = sec["sigs"].get(sig)
            if decl is None:
                sys.stderr.write("WARN: %s: signal %s not in template, skipped\n"
                                 % (sec["name"], sig))
                continue
            out.append(tgl(sig, hi, lo, decl))
            n_line += 1
        out.append("")
        n_mod += 1
        break


for sec in parse(instfile, "INSTANCE"):
    inst = sec["name"][len("INSTANCE: "):].strip()
    items = INST_MAP.get(inst)
    if items:
        out += sec["hdr"]
        for sig, hi, lo in items:
            decl = sec["sigs"].get(sig)
            if decl is None:
                sys.stderr.write("WARN: %s: signal %s not in template, skipped\n"
                                 % (inst, sig))
                continue
            out.append(tgl(sig, hi, lo, decl))
            n_line += 1
        out.append("")
        n_inst += 1

open(outfile, "w", encoding="utf-8").write("\n".join(out) + "\n")
sys.stderr.write("gen_tgl_excl: %d module variants, %d instances, %d exclusion lines -> %s\n"
                 % (n_mod, n_inst, n_line, outfile))
