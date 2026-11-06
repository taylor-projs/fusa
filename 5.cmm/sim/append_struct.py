#!/usr/bin/env python3
# Append the structurally-unreachable rows left after the 2026-11-06
# house-map retrofit (reg_wrap 五件套升级 + cmm_regfile REGST/REGSEL 改造)
# and the TB regroup-0..12 sweep + ERRSTAT pattern write.
#
# Families (all structural, campaign precedents):
#   A. reg_wrap COND (r.flt_q_n != (~r.flt_q)) bin "1"   双轨失步检测臂:
#      flt_q/flt_q_n 同拍装载 (W1C 清 或 par_err|dup_err 置位), 总线可达
#      路径无法使两轨失步 (SEU-only) —— 双轨一致性族判例
#   B. reg_wrap COND (par_err | dup_err) bin "01"        dup_err 单独置位
#      (dup_err 永不置起, 同 A)
#   C. reg_wrap BRANCH wr&selftest_key 臂 "1,1,-"        S1 族: 单口 mbus 的
#      REGST 注错脉冲与目标寄存器写永不同拍; u_w_cmd 的 wr=par_bad||W1C 同理
#   D. cmm_regfile COND wr_fwd(...) bin "1101"           逻辑矛盾:
#      regst_key_bad=1 ⇒ off==REGST ⇒ 第4项 (off集合|regst_wr|ch_hit) 恒 0
#   E. reg_wrap LINE "v.par_q = (~(^wdata));" 注错即写臂 (S1 族, 同 C;
#      仅 u_w_cmd 与模块域缺行 —— 其余 16 实例由 append_supplement 覆盖)
#   F. reg_wrap TOGGLE dup_err (永 0 不翻转, 同 A; 仅 u_w_cmd/模块域缺行)
#   G. cmm_regfile LINE 1080 cw_wd[40:37] ENHI 支路 (家族2 通道对称:
#      nib_ok_hi 需 i>=8 恒 0, TB 全配置 N_DUT<=5; 行号过滤与 1077 ENLO 区分)
#   H. cmm_regfile TOGGLE perr_w[11] (组11=latch 通道, assign 恒 1'b0 结构常量)
#   I. reg_wrap LINE 108/110 无写注错臂 @ 模块域 W=64 参数组 (S1 族镜像判例:
#      该参数组仅含镜像 wrap 实例 u_fusrcimg 等, wr 恒 1 → else-if 臂结构性
#      不可达; 4 镜像实例域排除已由 append_supplement 覆盖, 仅模块域缺行)
import os, re

SIM = os.path.dirname(os.path.abspath(__file__))

# (dump, srcfile filter, kind, anchor, combo-or-None, scope regex-or-None, lineno)
TARGETS = [
    ("fresh_cond.dump",   "reg_wrap.sv",    "Condition", "(r.flt_q_n != (~r.flt_q))", "1",     None, None),
    ("fresh_cond.dump",   "reg_wrap.sv",    "Condition", "(par_err | dup_err)",      "01",    None, None),
    ("fresh_cond.dump",   "cmm_regfile.sv", "Condition", "wr_ok && ((!keyed_bad))",  "1101",  None, None),
    ("fresh_branch.dump", "reg_wrap.sv",    "Branch",    '"wr"',                     "1,1,-", None, None),
    ("fresh_line.dump",   "reg_wrap.sv",    "Block",     "v.par_q = (~(^wdata));",   None,
     r"u_w_cmd|^MODULE: reg_wrap", None),
    ("fullexclude.tgl",   "reg_wrap.sv",    "Toggle",    "dup_err",                  None,
     r"u_w_cmd|^MODULE: reg_wrap", None),
    ("fresh_line.dump",   "cmm_regfile.sv", "Block",     "cw_wd[40:37] = r_mb.wdata_q", None,
     None, 1080),
    # I: 无写注错臂 108/110 行 —— 仅 W=64 模块参数组 (dump 文本为 urg 规范化:
    # "if (selftest_key)" / "v.par_q = (~r.par_q);", 以行号锚定)
    ("fresh_line_mod.dump", "reg_wrap.sv",  "Block",     "if (selftest_key)",      None,
     r"MODULE: reg_wrap \( parameter W=64", 108),
    ("fresh_line_mod.dump", "reg_wrap.sv",  "Block",     "v.par_q = (~r.par_q);",  None,
     r"MODULE: reg_wrap \( parameter W=64", 110),
]

# 手写位选行 (dump 只有整向量行, 位选行按既有 .el 风格手写, 双域各一份):
# (dump 主域文件, 作用域名 regex, [行文本])
MANUAL = [
    ("fullexclude.tgl", r"u_cmm_regfile$|^MODULE: cmm_regfile", [
        'Toggle 0to1 perr_w [11] "logic perr_w[12:0]"',
        'Toggle 1to0 perr_w [11] "logic perr_w[12:0]"',
    ]),
]

def parse_scopes(path):
    scopes, cur, srcfile, lineno = [], None, "", None
    for ln in open(os.path.join(SIM, path)):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            if cur: cur["srcs"].add(srcfile); scopes.append(cur)
            cur = {"checksum": m.group(1), "hdr": None, "rows": [], "srcs": set()}
            srcfile, lineno = "", None
            continue
        if cur is None: continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m: cur["hdr"] = "%s: %s" % (m.group(1), m.group(2)); continue
        m = re.match(r"^// ANNOTATION: .*FileName: ", ln)
        if m:
            srcfile = re.search(r"FileName: ([^,]+),", ln).group(1)
            lm = re.search(r"LineNumber: (\d+)", ln)
            lineno = int(lm.group(1)) if lm else None
            continue
        if re.match(r"^// (Condition|Branch|Block|Toggle) ", ln):
            cur["rows"].append((ln[3:], lineno))
    if cur: cur["srcs"].add(srcfile); scopes.append(cur)
    return scopes

def strip_vec(row):
    row = re.sub(r"\s*\(\d+\) \"[^\"]*\"\s*$", "", row)   # Branch ' (0) "wr 1,1,-"'
    return re.sub(r"\s*\(\d+ \"[^\"]*\"\)\s*$", "", row)  # Condition ' (3 "1101")'

def match_rows(sc, kind, anchor, combo, lineno):
    """rows in scope matching the target; each returned row is .el-ready"""
    if kind == "Toggle":
        # 'Toggle [1to0|0to1] <signal> "<signature>"' - no hash, per-direction rows
        pat = re.compile(r'^Toggle( [01]to[01])? %s\b' % re.escape(anchor))
        return [r for r, ln in sc["rows"] if pat.match(r)]
    base_re = re.compile(r'^%s [\w.]+ "\d+" .*%s' % (kind, re.escape(anchor)))
    if lineno is not None:
        return [r for r, ln in sc["rows"] if ln == lineno and base_re.match(r)]
    if combo is None:
        return [r for r, ln in sc["rows"] if base_re.match(r)]
    if kind == "Branch":
        vec_re = re.compile(r'^%s [\w.]+ "\d+" .*\(\d+\) "[^"]*%s"\s*$'
                            % (kind, re.escape(combo)))
        return [r for r, ln in sc["rows"] if vec_re.match(r) and base_re.match(strip_vec(r))]
    vec_re = re.compile(r'^%s [\w.]+ "\d+" .*\(\d+ "%s"\)\s*$' % (kind, re.escape(combo)))
    return [r for r, ln in sc["rows"] if vec_re.match(r) and base_re.match(strip_vec(r))]

added = {"cond": [], "branch": [], "line": [], "tgl": []}
for dumpf, srcfilter, kind, anchor, combo, scopere, lineno in TARGETS:
    doms = [dumpf]
    if dumpf.endswith(".dump"):
        doms.append(dumpf.replace(".dump", "_mod.dump"))
    elif dumpf.endswith(".tgl"):
        doms.append(dumpf.replace(".tgl", "_module.tgl"))
    hit = 0
    for dom in doms:
        if not os.path.exists(os.path.join(SIM, dom)): continue
        for sc in parse_scopes(dom):
            if not any(srcfilter in s for s in sc["srcs"]): continue
            if scopere and not re.search(scopere, sc["hdr"] or ""): continue
            rows = match_rows(sc, kind, anchor, combo, lineno)
            if not rows: continue
            key = {"Condition": "cond", "Branch": "branch",
                   "Block": "line", "Toggle": "tgl"}[kind]
            text = "\n".join(["CHECKSUM: %s" % sc["checksum"], sc["hdr"]] + rows) + "\n"
            if text not in added[key]: added[key].append(text); hit += 1
    print("%-20s %-13s %-9s bin %-6s -> %d scopes"
          % (os.path.basename(dumpf), srcfilter, kind, combo or "-", hit))

# 手写位选行
for dumpf, scopere, rowtexts in MANUAL:
    doms = [dumpf, dumpf.replace(".tgl", "_module.tgl")]
    hit = 0
    for dom in doms:
        for sc in parse_scopes(dom):
            if not re.search(scopere, sc["hdr"] or ""): continue
            text = "\n".join(["CHECKSUM: %s" % sc["checksum"], sc["hdr"]] + rowtexts) + "\n"
            if text not in added["tgl"]: added["tgl"].append(text); hit += 1
    print("%-20s %-13s MANUAL    perr_w[11] -> %d scopes" % (os.path.basename(dumpf), "cmm_regfile", hit))

for key, fname in (("cond", "excl_new_cond.el"), ("branch", "excl_new_branch.el"),
                   ("line", "excl_new_line.el")):
    if not added[key]: continue
    with open(os.path.join(SIM, fname), "a") as f:
        for blk in added[key]: f.write("\n" + blk)
    print("appended %d blocks -> %s" % (len(added[key]), fname))
# tgl: 按块头域分发 (实例域排除不进模块定义域 bin, 双域各一份)
for blk in added["tgl"]:
    fname = "excl_new_mod.tgl" if blk.splitlines()[1].startswith("MODULE") \
            else "excl_new_inst.tgl"
    with open(os.path.join(SIM, fname), "a") as f:
        f.write("\n" + blk)
    print("appended 1 block -> %s" % fname)
