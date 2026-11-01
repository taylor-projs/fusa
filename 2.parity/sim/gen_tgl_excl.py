#!/usr/bin/env python3
# gen_tgl_excl.py -- 从 urg -dump full_exclusions tgl 的模板生成结构常量 toggle 排除文件.
#
# 排除对象 (全部是结构上恒 0、任何激励都翻不动的位):
#   nuclei300_edc_gen:  t_dat[63:DW]      -- 64 位零扩展填充 (DW<64)
#                       t_edc 中 XOR 源全在填充区内的恒定位
#   nuclei300_edc_chk:  t_dat[63:DW], t_edc[6:EDCW] (EDC 位宽零填充),
#                       syndrome 中数据/校验源全恒 0 的恒定位
#   nuclei300_edc_chk_fault_ej:
#                       einj_pos[127:64]  (edc_site.inj_pos_g 高 64 位恒 0),
#                       einj_force_err 除独热强制位 (128-DW-EDCW) 外恒 0
#   edc_site:           inj_pos_g[127:64], inj_force_v 除强制位外恒 0
#   GEN 模式站点实例:    o_err 恒 0 (MODE=0 屏蔽).
#                       注: i_edc 不再排除 -- T18 起 TB 驱动 user 边带
#                       逐位走 1 + 全零拍, i_edc 两个方向均已被激励覆盖.
#   实例级结构常量段:    GEN 半侧 err/fault 向量与父级检查输出恒 0
#                       (mport 请求站 0..12 / sport 响应站 13..17 恒 GEN),
#                       跟随型 wrap 的 GEN 半侧数据位与 wr=1'b1 常量绑定,
#                       mbus addr[15:9] (inst_bad 门控, NP=2 实例号仅 bit8)
#
# 用法: python3 gen_tgl_excl.py fullexclude_module.tgl fullexclude.tgl out.el
# 模板来自: cd obj_vcs && urg -dir simv.vdb -dump full_exclusions tgl -report /tmp/x
# CHECKSUM/模块头/信号签名均从模板原文拷贝, 保证 urg 能精确对位.
import re
import sys

modfile, instfile, outfile = sys.argv[1], sys.argv[2], sys.argv[3]


def parse(path, key):
    """解析 dump 模板, 返回 [{'hdr': [...], 'name': str, 'sigs': {sig: decl}}]"""
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    secs = []
    for idx, ln in enumerate(lines):
        if ln.startswith("// %s:" % key):
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
            secs.append({"hdr": hdr, "name": ln[3:], "sigs": sigs})
    return secs


def tgl(sig, hi, lo, decl):
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
    return [("inj_pos_g", 127, 64),
            ("inj_force_v", 127, f + 1), ("inj_force_v", f - 1, 0)]


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

# ---------------- 实例级: GEN 模式站点的 o_err / i_edc ----------------
REQ_SITES = ["u_aw_addr_hi", "u_aw_addr_lo", "u_aw_attri0", "u_aw_attri1",
             "u_aw_id", "u_w_data", "u_w_mask", "u_w_last",
             "u_ar_addr_hi", "u_ar_addr_lo", "u_ar_attri0", "u_ar_attri1",
             "u_ar_id"]
RESP_SITES = ["u_b_attri", "u_b_id", "u_r_data", "u_r_attri", "u_r_id"]
GEN_INSTS = (["tb_edc_top.dut.g_mport[0].u_ip.u_gen." + s for s in REQ_SITES]
             + ["tb_edc_top.dut.g_sport[0].u_ip.u_chk." + s for s in RESP_SITES])

# ---------------- 实例级: 结构常量段/位 (恒 0, 任何激励翻不动) ----------------
# 规则 = (实例路径, [(信号, hi, lo), ...]); hi=None 表示整个信号.
# 依据:
#  (a) GEN 半侧恒 0: edc_ip 内 u_gen 恒为 GEN 模式 (mport: 请求站 0..12),
#     GEN 站点不产生错误 -> 父级检查输出 (o_site_err/字段 err) 与 err/fault
#     向量的 GEN 半侧恒 0. sport 镜像: u_chk 恒为响应 GEN (站 13..17),
#     恒 0 半侧为 [17:13] / o_site_err[4:0].
#  (b) 跟随型 wrap (u_err2/u_fault2/u_err_st/u_fault_st): 数据 = err/fault
#     向量 -> GEN 半侧数据位恒 0; wr 端口 RTL 常量绑 1'b1.
#  (c) addr[15:9]: apb2mbus 对 inst >= NP 的地址不发 mbus 传输 (inst_bad),
#     mbus 上 inst 域 [15:9] 恒 0 (NP=2, 实例号仅 bit8); 且 req_fire 带
#     !inst_bad 门控 -> paddr_q 只锁存合法实例地址 -> 桥内保持寄存器
#     r_apb.paddr_q[15:9] 同样恒 0. (桥 hang 看门狗信号不在此排除:
#     停止 mbus_clk 即可激励, 属 6.apb2mbus 项目的激励覆盖范畴.)
def _whole(s):
    return (s, None, None)


def _half(s, hi, lo):
    return (s, hi, lo)


MPORT = r"tb_edc_top.dut.g_mport[0].u_ip"
SPORT = r"tb_edc_top.dut.g_sport[0].u_ip"
MPORT_GEN_ERRS = ["aw_hi_err", "aw_lo_err", "aw_a0_err", "aw_a1_err",
                  "aw_id_err", "w_data_err", "w_mask_err", "w_last_err",
                  "ar_hi_err", "ar_lo_err", "ar_a0_err", "ar_a1_err",
                  "ar_id_err"]
SPORT_GEN_ERRS = ["b_at_err", "b_id_err", "r_rd_err", "r_at_err", "r_id_err"]
IP_HALFSIGS = ["err_axi", "fault_axi", "err_st", "fault_st",
               "err_nxt", "fault_nxt"]
RF_HALFSIGS = ["err_axi", "fault_axi", "r.err_s1", "r.fault_s1",
               "rin.err_s1", "rin.fault_s1", "err_s2", "fault_s2"]
FOLLOWER_DATASIGS = ["wdata", "rdata", "r.data_q", "rin.data_q"]

INST_STRUCT_RULES = (
    [(MPORT + ".u_gen",
      [_whole(s) for s in MPORT_GEN_ERRS] + [_half("o_site_err", 12, 0)]),
     (SPORT + ".u_chk",
      [_whole(s) for s in SPORT_GEN_ERRS] + [_half("o_site_err", 4, 0)]),
     (MPORT,
      [_half("addr", 15, 9), _half("gen_site_err", 12, 0),
       _half("site_err_g", 12, 0)]
      + [_half(s, 12, 0) for s in IP_HALFSIGS]),
     (SPORT,
      [_half("addr", 15, 9), _half("chk_site_err", 4, 0),
       _half("site_err_g", 17, 13)]
      + [_half(s, 17, 13) for s in IP_HALFSIGS]),
     (MPORT + ".u_regfile",
      [_half("addr", 15, 9)] + [_half(s, 12, 0) for s in RF_HALFSIGS]),
     (SPORT + ".u_regfile",
      [_half("addr", 15, 9)] + [_half(s, 17, 13) for s in RF_HALFSIGS]),
     ("tb_edc_top.dut.u_apb2mbus",
      [_half("addr", 15, 9), _half("r_apb.paddr_q", 15, 9),
       _half("rin_apb.paddr_q", 15, 9)])]
    + [(MPORT + "." + w,
        [_half(s, 12, 0) for s in FOLLOWER_DATASIGS] + [_whole("wr")])
       for w in ("u_regfile.u_err2", "u_regfile.u_fault2",
                 "u_err_st", "u_fault_st")]
    + [(SPORT + "." + w,
        [_half(s, 17, 13) for s in FOLLOWER_DATASIGS] + [_whole("wr")])
       for w in ("u_regfile.u_err2", "u_regfile.u_fault2",
                 "u_err_st", "u_fault_st")]
)

out = ["// ==================================================================",
       "// tgl_struct_excl.el -- 2.parity 结构常量 toggle 排除 (urg -elfile)",
       "// 由 gen_tgl_excl.py 依据 urg full-exclusion 模板生成; 排除项全部为",
       "// 结构上恒 0/恒 1 的位 (零扩展填充 / 未用注入向量位 / GEN 模式屏蔽",
       "// 输出与其下游 err/fault 半侧向量 / 跟随 wrap 常量半侧与 wr 绑定 /",
       "// mbus addr[15:9] inst_bad 门控), 与激励无关, 任何测试都翻不动.",
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

# 实例路径 -> 排除项表: GEN 模式站点 (仅 o_err; i_edc 已被 T18 激励覆盖)
# + 结构常量段规则
INST_MAP = {i: [("o_err", None, None)] for i in GEN_INSTS}
for path, items in INST_STRUCT_RULES:
    INST_MAP.setdefault(path, []).extend(items)

# ---------------- 模块级: module-definition 视图的结构常量段 ----------------
# 实例级排除不反映到 urg 的 module-definition 视图 (单实例模块的 module
# 段仍报 addr[15:9] 未覆盖). 下列模块级条目与实例级规则同一结构依据
# (apb2mbus inst_bad 门控: paddr[15:8] >= NP=2 不发起 mbus 传输, 且
# req_fire 带 !inst_bad -> paddr_q 只锁存合法实例地址 -> 桥内 paddr_q
# 与 mbus 上 addr/mb_addr 的实例域 [15:9] 恒 0), 与实例级条目是 urg 的
# 不同对象, 互不冲突.
MOD_STRUCT_RULES = [
    (r"^MODULE: apb2mbus\s*$",
     [("addr", 15, 9), ("r_apb.paddr_q", 15, 9), ("rin_apb.paddr_q", 15, 9)]),
    (r"^MODULE: edc_top\s*$",
     [("mb_addr", 15, 9)]),
    (r"^MODULE: edc_regfile\s*$",
     [("addr", 15, 9)]),
    (r"^MODULE: edc_core\s*$",
     [("addr", 15, 9)]),
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
            if hi is None:
                out.append('Toggle %s "%s"' % (sig, decl))
            else:
                out.append(tgl(sig, hi, lo, decl))
            n_line += 1
        out.append("")
        n_inst += 1

open(outfile, "w", encoding="utf-8").write("\n".join(out) + "\n")
sys.stderr.write("gen_tgl_excl: %d module variants, %d instances, %d exclusion lines -> %s\n"
                 % (n_mod, n_inst, n_line, outfile))
