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
#   GEN 模式站点实例:    o_err 恒 0 (MODE=0 屏蔽), i_edc 输入恒 0
#                       (GEN 忽略随路 EDC, TB 侧 user 位驱 0)
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
                t = re.match(r'^// Toggle (?:0to1 |1to0 )?(\w+) "([^"]+)"', b)
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

out = ["// ==================================================================",
       "// tgl_struct_excl.el -- 2.parity 结构常量 toggle 排除 (urg -elfile)",
       "// 由 gen_tgl_excl.py 依据 urg full-exclusion 模板生成; 排除项全部为",
       "// 结构上恒 0 的位 (零扩展填充 / 未用注入向量位 / GEN 模式屏蔽输出),",
       "// 与激励无关, 任何测试都翻不动. RTL 改动后需重新生成 (见脚本头注释).",
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

for sec in parse(instfile, "INSTANCE"):
    inst = sec["name"][len("INSTANCE: "):].strip()
    if inst in GEN_INSTS:
        out += sec["hdr"]
        for sig in ("o_err", "i_edc"):
            decl = sec["sigs"].get(sig)
            if decl is None:
                sys.stderr.write("WARN: %s: signal %s not in template, skipped\n"
                                 % (inst, sig))
                continue
            out.append('Toggle %s "%s"' % (sig, decl))
            n_line += 1
        out.append("")
        n_inst += 1

open(outfile, "w", encoding="utf-8").write("\n".join(out) + "\n")
sys.stderr.write("gen_tgl_excl: %d module variants, %d instances, %d exclusion lines -> %s\n"
                 % (n_mod, n_inst, n_line, outfile))
