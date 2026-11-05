#!/usr/bin/env python3
# Append the structural supplement rows (identifed from urg_final/modinfo.txt
# after the first rebuilt-set run) to the rebuilt cmm elfiles.
# Families (all structural, campaign precedents):
#  S1 reg_wrap selftest injection paths, instance domain:
#     - 12 plain wrap instances: LINE "v.par_q = (~(^wdata));" (write+key),
#       BRANCH "wr" arm (0) = wr=1 & selftest_key=1
#     - 4 follow-mode mirror instances (wr tied 1): LINE
#       "v.par_q = (~r.par_q);" (injection without write), BRANCH arms (2)(3)
#       = wr=0 combos (ia wr-const-1 family)
#     cmm TB never drives the regfile-side selftest key (injection goes
#     through cmm_core FORCE/REGST, not the wrap selftest port).
#  S2 channel symmetry, module domain (N_DUT=5 < 8 in every TB config):
#     - LINE cw_wd[40:37] ENHI path x5 gens (nib_ok_hi needs i>=8 -> const 0)
#     - COND (q_enhi && nib_ok_hi) bins "01"/"11" x5 (nib_ok_hi = const 0)
#     - COND q_fusrc full-OR bin "01" x5 (q_fusrc1 arm needs i>=8, literal
#       (i >= 8) is false for i=0..4)
#  S3 keyword+map hole: COND q_regst bin "11011" (REGST write with key=0
#     pattern: TB writes key-protected regs only with WKEY)
#  S4 dual-rail agreement, module domain:
#     - cmm_core (dead_a|dead_b|ne_dup) bins "010"/"100" x5: noedge_cnt and
#       its ~ replica are loaded together -> dead_a == dead_b whenever
#       ne_dup=0, single-rail-at-threshold combos unreachable
#     - cmm_top ((wend_a ^ wend_b) | (win_cnt_n != ~win_cnt)) bin "10":
#       wend flags derive from the same win_cnt dual rail -> flags disagree
#       only while the rails disagree, (1,0) combo unreachable
import re, os

SIM = "/home/eda/work/cmm/sim"

ENLO12 = ["u_enlo", "u_enhi", "u_gctrl", "u_force", "u_clo", "u_chi",
          "u_cdead"] + ["g_cwrap[%d].u_cwrap" % i for i in range(5)]
ERRIMG4 = ["u_errimg", "u_srcimg", "u_fusrcimg", "u_fustatimg"]

def parse_dump(path):
    """scopes -> {key: {checksum, hdr, rows:[(lineno_or_None, raw)]}}
    lineno captured from the ANNOTATION preceding Block/Branch rows."""
    scopes, cur, lastannot = {}, None, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r'^// CHECKSUM: "(\d+ \d+)"', ln)
        if m:
            cur = {"checksum": m.group(1), "hdr": None, "rows": []}
            continue
        m = re.match(r"^// (MODULE|INSTANCE): (.*)$", ln)
        if m:
            cur["hdr"] = ln[3:]
            scopes[m.group(1)[0] + ":" + m.group(2).rstrip()] = cur
            continue
        m = re.match(r'^// ANNOTATION: .*LineNumber: (\d+)', ln)
        if m:
            lastannot = m.group(1)
            continue
        m = re.match(r"^// (Block|Condition|Branch|Fsm|Transition) (.*)$", ln)
        if m and cur is not None:
            cur["rows"].append((lastannot, ln[3:]))
            continue
    return scopes

def grab(scopes, key, pred):
    sc = scopes.get(key)
    if sc is None:
        print("MISSING scope:", key)
        return []
    return [raw for a, raw in sc["rows"] if pred(a, raw)]

def block_of(scopes, key, rows):
    sc = scopes[key]
    return ['CHECKSUM: "%s"' % sc["checksum"], sc["hdr"]] + rows

linesup, branchsup, condsup = [], [], []

# ---------------- S1: instance-domain reg_wrap injection paths --------------
inst_dump_line  = parse_dump(os.path.join(SIM, "fresh_line.dump"))
inst_dump_br    = parse_dump(os.path.join(SIM, "fresh_branch.dump"))
for base in ENLO12:
    k = "I:tb_cmm_top.dut.u_cmm_regfile." + base
    r = grab(inst_dump_line, k,
             lambda a, r: r.startswith("Block") and '"v.par_q = (~(^wdata));"' in r)
    if r:
        linesup.append(block_of(inst_dump_line, k, r))
    r = grab(inst_dump_br, k,
             lambda a, r: r.startswith("Branch") and '"wr" (0) ' in r)
    if r:
        branchsup.append(block_of(inst_dump_br, k, r))
for base in ERRIMG4:
    k = "I:tb_cmm_top.dut.u_cmm_regfile." + base
    r = grab(inst_dump_line, k,
             lambda a, r: r.startswith("Block") and '"v.par_q = (~r.par_q);"' in r)
    if r:
        linesup.append(block_of(inst_dump_line, k, r))
    r = grab(inst_dump_br, k,
             lambda a, r: r.startswith("Branch") and ('"wr" (2) ' in r or '"wr" (3) ' in r))
    if r:
        branchsup.append(block_of(inst_dump_br, k, r))

# ---------------- S2/S3: module-domain cmm_regfile --------------------------
mod_line = parse_dump(os.path.join(SIM, "fresh_line_mod.dump"))
mod_cond = parse_dump(os.path.join(SIM, "fresh_cond_mod.dump"))

r = grab(mod_line, "M:cmm_regfile",
         lambda a, raw: a == "995" and "cw_wd[40:37]" in raw)
if r:
    linesup.append(block_of(mod_line, "M:cmm_regfile", r))

rows = []
rows += grab(mod_cond, "M:cmm_regfile",
             lambda a, raw: "(3 \"11011\")" in raw and "OFF_REGST" in raw)
for i in range(5):
    rows += grab(mod_cond, "M:cmm_regfile",
                 lambda a, raw, i=i: ("q_enhi && g_cwrap[%d].nib_ok_hi)" % i) in raw
                 and ('(1 "01")' in raw or '(3 "11")' in raw))
    rows += grab(mod_cond, "M:cmm_regfile",
                 lambda a, raw, i=i: ("q_fusrc0 && (%d < 8)" % i) in raw
                 and '(2 "01")' in raw and "||" in raw)
if rows:
    condsup.append(block_of(mod_cond, "M:cmm_regfile", rows))

# ---------------- S4: dual-rail agreement, module domain --------------------
rows = []
for i in range(5):
    rows += grab(mod_cond, "M:cmm_core",
                 lambda a, raw, i=i: ("dead_a[%d] | dead_b[%d] | ne_dup[%d])" % (i, i, i)) in raw
                 and ('(3 "010")' in raw or '(4 "100")' in raw))
if rows:
    condsup.append(block_of(mod_cond, "M:cmm_core", rows))

rows = grab(mod_cond, "M:cmm_top",
            lambda a, raw: "(wend_a ^ wend_b)" in raw and "win_cnt_n" in raw
            and '(3 "10")' in raw)
if rows:
    condsup.append(block_of(mod_cond, "M:cmm_top", rows))

def append(fname, blocks):
    if not blocks:
        return
    with open(os.path.join(SIM, fname), "a") as f:
        f.write("\n" + "\n".join("\n".join(b) for b in blocks) + "\n")
    print("appended %d blocks -> %s" % (len(blocks), fname))

append("excl_new_line.el", linesup)
append("excl_new_branch.el", branchsup)
append("excl_new_cond.el", condsup)
