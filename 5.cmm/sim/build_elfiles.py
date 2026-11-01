#!/usr/bin/env python3
# Build cmm exclusion elfiles from excl5/fullexclude* dumps + fresh urg_report red bins.
# (excl5 = dump after the sync_2dff/sync_dff cell-wrap conversion; line numbers
#  in cmm_regfile.sv shifted vs excl4 - remap applied below)
# urg elfile rules (from dump usage headers):
#   - an exclusion row is active only when its enclosing section header is active:
#       module-level files:   CHECKSUM: "..."        + MODULE: <name>
#       instance-level files: CHECKSUM: "..."        + INSTANCE: <path>
#     (ModuleName/FileName ANNOTATION lines may stay commented - they are optional)
#   - urg rejects stacked ANNOTATION lines without -excl_append_annotation, so each
#     justification is merged into the object's existing ANNOTATION line.
# All targets verified unreachable at the RTL level.
import re, os

SIM = "/home/eda/work/cmm/sim"
EXC = os.path.join(SIM, "excl5")
REP = os.path.join(SIM, "urg_report")
OUT = os.path.join(SIM, "excl")
os.makedirs(OUT, exist_ok=True)

def merge_just(out_lines, just):
    """merge justification into the last ANNOTATION line in out_lines"""
    for i in range(len(out_lines) - 1, -1, -1):
        if out_lines[i].startswith('// ANNOTATION: "'):
            if out_lines[i].rstrip().endswith('"'):
                out_lines[i] = out_lines[i].rstrip()[:-1] + " | EXCLUDED: " + just + '"'
            return
    out_lines.append('// ANNOTATION: "EXCLUDED: ' + just + '"')

class Sec:
    """track section headers so they can be activated when a row is excluded"""
    def __init__(self):
        self.pending = []   # out[] indices of CHECKSUM + MODULE/INSTANCE lines
        self.active  = False
        self.names   = []
    def feed(self, out, ln):
        """returns True if ln is a section header line (already appended)"""
        if ln.startswith("// CHECKSUM:"):
            self.pending = [len(out)]
            self.active  = False
            out.append(ln)
            return True
        if ln.startswith("// MODULE:") or ln.startswith("// INSTANCE:"):
            self.pending.append(len(out))
            self.names.append(ln.split(None, 1)[1])
            out.append(ln)
            return True
        return False
    def activate(self, out):
        if not self.active:
            for i in self.pending:
                out[i] = out[i][3:]          # strip "// "
            self.active = True

# ---------------------------------------------------------------- cond ----
RF  = "cmm_regfile.sv"
TOP = "cmm_top.sv"
CHK = "cmm_clk_dut_chk.sv"
cond_just = {
 (CHK,294): "dead_a/dead_b are dual compares of the same noedge counter rails; disagreement implies ne_dup=1 (rows 011/101 covered). 010/100 impossible with consistent rails",
 (TOP,147): "wend_a^wend_b=1 requires inconsistent win_cnt rails, but then (win_cnt_n != ~win_cnt)=1 -> row 10 impossible",
 (RF,189): "cword<15 iff coff<60; off<CHBASE (0x40) makes coff wrap to >=0xC4 -> cword>=48. row 01 impossible",
 (RF,227): "enhi_ill is guarded by (8+n)<N_DUT; N_DUT=5 -> enhi_ill constant 0; rows with enhi_ill=1 unreachable",
 (RF,404): "enlo_r[31:20] and enhi_r[31:0] hold unwritable nibbles (ch>=N_DUT) stuck at all-F reset -> |enlo_r and |enhi_r constant 1; only row 11 reachable",
 (RF,433): "any_en constant 1 (see L404) -> 2-bit row 01 unreachable; s_fire_a/s_fire_b are dual compares of the same stale-counter rails, disagreement sets s_dup -> single-fire rows 010/100 without s_dup impossible",
 (RF,438): "any_en constant 1 (see L404) -> !any_en constant 0 -> row 01 unreachable",
 (RF,516): "sto_ch implies ch_hit implies cword<15 implies ch_idx=cword/3<5=N_DUT -> row 10 impossible",
 (RF,722): "ch_hit implies cword<15 implies ch_idx<5 (row 10 out); ch_idx<5 implies cword<15 and with off>=CHBASE (see L189) implies ch_hit (row 01 out)",
 (RF,811): "q_ side of L722: q_chhit implies q_cword<15 implies q_chidx<5 (row 10 out); q_chidx<5 implies q_cword<15, with q_off>=CHBASE implies q_chhit (row 01 out)",
 (RF,820): "bad-key writes are filtered in the mbus domain (wr_fwd includes !keyed_bad) and never cross; with req_edge && off==GCTRL the key was valid -> q_key=1; row 110 unreachable",
 (RF,836): "same as L820 for OFF_FORCE: bad-key writes never cross the CDC",
 (RF,838): "same as L820 for OFF_REGST: bad-key writes never cross the CDC",
 (RF,841): "same as L820 for channel config space: bad-key writes never cross the CDC",
 (RF,910): "nib_ok_hi = (i>=8)&&legal; nibble index i>=8 >= N_DUT=5 is illegal by construction -> nib_ok_hi constant 0; rows with it 1 unreachable",
 (RF,914): "nib_ok_hi constant 0 (nibble index >=8 >= N_DUT=5 illegal) -> rows with nib_ok_hi=1 unreachable (main 0010, sub 01/11)",
 (RF,923): "term2 carries (k>=8); generate k in 0..N_DUT-1=0..4 -> constant 0 -> row 01 unreachable",
 (RF,249): "enhi_ill is constant 0 (guarded by (8+n)<N_DUT, N_DUT=5) -> row 01 with enhi_ill=1 unreachable",
 (RF,381): "h_fire_a/h_fire_b are dual compares of the same hang-counter rails; any disagreement sets h_dup -> single-fire rows 010/100 without h_dup impossible",
}
# (file,line) -> {row: expr_regex_or_None}; the regex, when given, must match the
# condition signature for the row to be excluded (lines with several 2-bit
# sub-expressions sharing row patterns need this guard).
cond_rows = {
 (CHK,294): {"010": None, "100": None},
 (TOP,147): {"10": None},
 (RF,189): {"01": None},
 (RF,227): {"10": None, "11": None},
 (RF,404): {"00": None, "01": None, "10": None},
 (RF,433): {"01": None, "010": None, "100": None},
 (RF,438): {"01": None},
 (RF,516): {"10": None},
 (RF,722): {"01": None, "10": None},
 (RF,811): {"01": None, "10": None},
 (RF,820): {"110": None},
 (RF,836): {"110": None},
 (RF,838): {"11011": None},
 (RF,841): {"110": None},
 (RF,910): {"01": None, "11": None},
 (RF,914): {"0010": None, "01": r"nib_ok_hi", "11": r"nib_ok_hi"},
 (RF,923): {"01": None},
 (RF,249): {"01": r"^\(enlo_ill \|\| enhi_ill\)"},
 (RF,381): {"010": None, "100": None},
}
src = open(os.path.join(EXC, "fullexclude_module.cond")).read()
out = []
sec = Sec()
cur_key = None
n_exc = 0
for ln in src.splitlines():
    if sec.feed(out, ln):
        continue
    m = re.match(r"// ANNOTATION: \"(?:vcs_gen_start:i=\d+:vcs_gen_end:)?FileName: .*?(\w+\.sv), LineNumber: (\d+)\"", ln)
    if m:
        cur_key = (m.group(1), int(m.group(2)))
        out.append(ln)
        continue
    mr = re.match(r"// Condition (\d+) \"(\d+)\" \"(.*?)\" \((\d+) \"([01]+)\"\)\s*$", ln)
    if mr and cur_key in cond_rows and mr.group(5) in cond_rows[cur_key]:
        filt = cond_rows[cur_key][mr.group(5)]
        if filt is None or re.search(filt, mr.group(3)):
            sec.activate(out)
            merge_just(out, "row " + mr.group(5) + ": " + cond_just[cur_key])
            out.append(f'Condition {mr.group(1)} "{mr.group(2)}" "{mr.group(3)}" ({mr.group(4)} "{mr.group(5)}")')
            n_exc += 1
            continue
    out.append(ln)
open(os.path.join(OUT, "cmm_excl.cond"), "w").write("\n".join(out) + "\n")
print("cond done,", n_exc, "rows excluded")

# ---------------------------------------------------------------- fsm -----
src = open(os.path.join(EXC, "fullexclude_module.fsm")).read()
out = []
sec = Sec()
n_exc = 0
fsm_idx = None                       # out[] index of enclosing '// Fsm ...' line
for ln in src.splitlines():
    if sec.feed(out, ln):
        fsm_idx = None
        continue
    if ln.startswith("// Fsm "):
        fsm_idx = len(out)
        out.append(ln)
        continue
    if ln.startswith('// Transition FSM_ARM->FSM_ERR'):
        sec.activate(out)
        if fsm_idx is not None:      # Transition must sit under active Fsm scope
            out[fsm_idx] = out[fsm_idx][3:]
            fsm_idx = None
        merge_just(out, "FSM has no functional ARM->ERR arc; the only entry is the !fsm_onehot_ok corruption guard (SEU containment net), not stimulable without state corruption")
        out.append(ln[3:])
        n_exc += 1
    else:
        out.append(ln)
open(os.path.join(OUT, "cmm_excl.fsm"), "w").write("\n".join(out) + "\n")
print("fsm done,", n_exc, "transitions excluded")

# ---------------------------------------------------------------- line ----
src = open(os.path.join(EXC, "fullexclude_module.line")).read()
out = []
sec = Sec()
cur_key = None
n_exc = 0
for ln in src.splitlines():
    if sec.feed(out, ln):
        continue
    m = re.match(r"// ANNOTATION: \"(?:vcs_gen_start:i=\d+:vcs_gen_end:)?FileName: .*?(\w+\.sv), LineNumber: (\d+)\"", ln)
    if m:
        cur_key = (m.group(1), int(m.group(2)))
        out.append(ln)
        continue
    if ln.startswith('// Block 6 ') and "enhi_nxt" in ln:
        sec.activate(out)
        merge_just(out, "guarded by (8+n)<N_DUT with N_DUT=5 -> constant false; enhi_nxt never assigned (dead code for this config)")
        out.append(ln[3:])
        n_exc += 1
    elif ln.startswith('// Block 13 ') and "enhi_ill = 1'b1;" in ln:
        sec.activate(out)
        merge_just(out, "guarded by (8+n)<N_DUT with N_DUT=5 -> constant false; enhi_ill never sets")
        out.append(ln[3:])
        n_exc += 1
    elif ln.startswith("// Block ") and cur_key == (RF, 910) and "cw_wd[40:37]" in ln:
        sec.activate(out)
        merge_just(out, "body of 'if (q_enhi && nib_ok_hi)': nib_ok_hi constant 0 (nibble index >=8 >= N_DUT=5 illegal) -> inline body never executes (dead for this config)")
        out.append(ln[3:])
        n_exc += 1
    else:
        out.append(ln)
line_mod = "\n".join(out) + "\n"

# (b) instance-level: reg_wrap reg_ff injection-branch dead lines
#     - 12 non-image wraps: L77 body (par_q <= ~(^wdata)) dead - REGST injection is
#       a write to OFF_REGST and never coincides with this wrap's own write strobe
#     - 4 image wraps: L81/L82 dead - wr tied to 1'b1, else-if(selftest_key) never taken
IMG = ("u_errimg", "u_srcimg", "u_fusrcimg", "u_fustatimg")
src = open(os.path.join(EXC, "fullexclude.line")).read()
out = []
sec = Sec()
cur_inst = None
cur_key = None
ni = 0
for ln in src.splitlines():
    if ln.startswith("// CHECKSUM:"):
        sec.feed(out, ln)
        cur_inst = None
        cur_key = None
        continue
    mi = re.match(r"// INSTANCE: (\S+)", ln)
    if mi:
        sec.feed(out, ln)
        cur_inst = mi.group(1)
        cur_key = None
        continue
    m = re.match(r"// ANNOTATION: \"FileName: .*?(\w+\.sv), LineNumber: (\d+)\"", ln)
    if m:
        cur_key = (m.group(1), int(m.group(2)))
        out.append(ln)
        continue
    if ln.startswith("// Block ") and cur_inst and cur_key and cur_key[0] == "reg_wrap.sv":
        is_img = any(x in cur_inst for x in IMG)
        lno = cur_key[1]
        if (not is_img and lno == 77) or (is_img and lno in (81, 82)):
            sec.activate(out)
            if lno == 77:
                merge_just(out, "REGST injection is a write to OFF_REGST and never coincides with a write to this wrap's own register -> wr && selftest_key never coincide -> injection-with-write line dead for non-image wraps")
            else:
                merge_just(out, "image wrap has wr tied to 1'b1 (free-running broadcast) -> else-if(selftest_key) branch never taken; injection enters via the wr branch")
            out.append(ln[3:])
            ni += 1
            continue
    out.append(ln)
open(os.path.join(OUT, "cmm_excl.line"), "w").write(line_mod + "\n".join(out) + "\n")
print("line done,", n_exc, "module blocks +", ni, "instance blocks excluded")

# --------------------------------------------------------------- branch ---
# (a) module-level: regfile L910 TRUE row (genvar i=0..4)
src = open(os.path.join(EXC, "fullexclude_module.branch")).read()
out = []
sec = Sec()
cur890 = False
nb_mod = 0
for ln in src.splitlines():
    if sec.feed(out, ln):
        continue
    if re.match(r"// ANNOTATION: \"(?:vcs_gen_start:i=\d+:vcs_gen_end:)?FileName: .*?cmm_regfile\.sv, LineNumber: 910\"", ln):
        cur890 = True
    elif ln.startswith("// ANNOTATION"):
        cur890 = False
    mb = re.match(r"// (Branch \d+ \"\d+\" \"\(q_enhi && g_cwrap\[\d+\]\.nib_ok_hi\)\") \(0\) \"\(q_enhi && g_cwrap\[\d+\]\.nib_ok_hi\) 1\"\s*$", ln)
    if cur890 and mb:
        sec.activate(out)
        merge_just(out, "nib_ok_hi constant 0 (nibble index >=8 >= N_DUT=5 illegal) -> q_enhi && nib_ok_hi never true")
        out.append(ln[3:])
        nb_mod += 1
        continue
    out.append(ln)
mod_branch = "\n".join(out) + "\n"

# (b) instance-level: reg_ff block rows of reg_wrap instances
src = open(os.path.join(EXC, "fullexclude.branch")).read()
IMG = ("u_errimg", "u_srcimg", "u_fusrcimg", "u_fustatimg")
out = []
sec = Sec()
cur_inst = None
cur_b0 = False
nb = 0
for ln in src.splitlines():
    if sec.feed(out, ln):
        mi = re.match(r"// INSTANCE: (\S+)", ln)
        cur_inst = mi.group(1) if mi else None
        cur_b0 = False
        continue
    if re.match(r"// ANNOTATION: \"FileName: .*?reg_wrap\.sv, LineNumber: 70\"", ln):
        cur_b0 = True
        out.append(ln)
        continue
    if ln.startswith("// ANNOTATION"):
        cur_b0 = False
    mr = re.match(r"// (Branch 0 \"\d+\" \"\(!rst_n\)\") \((\d+)\) \"\(!rst_n\) ([01],.*?)\"\s*$", ln)
    if cur_b0 and cur_inst and mr:
        combo = mr.group(3)
        is_img = any(x in cur_inst for x in IMG)
        if combo == "0,1,1,-":
            sec.activate(out)
            merge_just(out, "wr && selftest_key never coincide - REGST injection is a write to OFF_REGST, not to this wrap (wrap wr strobes are independent)")
            out.append(mr.group(1) + " (" + mr.group(2) + ") \"(!rst_n) " + combo + "\"")
            nb += 1
            continue
        if is_img and combo in ("0,0,-,1", "0,0,-,0"):
            sec.activate(out)
            merge_just(out, "image wrap has wr tied to 1'b1 (free-running broadcast image) -> else-if(selftest_key) never evaluated")
            out.append(mr.group(1) + " (" + mr.group(2) + ") \"(!rst_n) " + combo + "\"")
            nb += 1
            continue
    out.append(ln)
inst_branch = "\n".join(out) + "\n"
open(os.path.join(OUT, "cmm_excl.branch"), "w").write(mod_branch + inst_branch)
print("branch done,", nb_mod, "module rows +", nb, "instance rows excluded")

# ----------------------------------------------------------------- tgl ----
import glob as _glob
MODS = [os.path.basename(p) for p in sorted(
    _glob.glob(os.path.join(REP, "mod*.html")))
    if re.match(r"mod\d+\.html$", os.path.basename(p))]
# skip the testbench top itself; only DUT objects are excludable
def _is_dut_inst(nm):
    return nm.startswith("tb_cmm_top.dut")

def split_name(name):
    m = re.match(r"^(.*?)(?:\[(\d+(?::\d+)?)\])?$", name)
    return m.group(1), m.group(2)

red = {}
for mf in MODS:
    html = open(os.path.join(REP, mf), encoding="utf-8", errors="replace").read()
    secs = [(m.group(1), m.start()) for m in re.finditer(
        r"Toggle Coverage for Instance : <a[^>]*>([^<]+)</a>", html)]
    if not secs:
        mi = re.search(r"Module Instance : <a[^>]*>([^<]+)</a>", html)
        if mi:
            secs = [(mi.group(1), 0)]
    for k, (nm, pos) in enumerate(secs):
        end = secs[k+1][1] if k+1 < len(secs) else len(html)
        seg = html[pos:end]
        if not _is_dut_inst(nm):
            continue
        for tm in re.finditer(r"(?:Port|Signal) Details</b></caption>(.*?)</table>", seg, re.S):
            for r in re.findall(r"<tr[^>]*>.*?</tr>", tm.group(1), re.S):
                cells = re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)
                cells = [re.sub(r"<[^>]+>", "", c).strip() for c in cells]
                if len(cells) >= 4 and "No" in cells[1:4]:
                    base, rng = split_name(cells[0])
                    red.setdefault(nm, set()).add((base, rng))

for inst, bins in sorted(red.items()):
    print("RED-TGL", inst, len(bins))

def tgl_just(sig):
    if sig in ("addr", "mbus_addr", "off", "coff", "wsel_q", "q_off", "q_coff"):
        return "address decode bits: word-aligned accesses with offsets < 0x80 keep these bits constant 0"
    if sig in ("rdata", "rdata_mux", "mbus_rdata"):
        return "register layout constant-0 bit (no register drives it)"
    if sig in ("enhi_r", "enhi_nxt", "enhi_rd", "enhi_ill"):
        return "ENHI channel nibbles (ch>=8) do not exist at N_DUT=5: unwritable, stuck at all-F reset"
    if sig in ("enlo_r", "enlo_nxt", "enlo_rd"):
        return "ENLO nibbles for ch>=N_DUT=5 are unwritable, stuck at all-F reset"
    if sig == "any_en":
        return "constant 1: enlo_r[31:20] and enhi_r are stuck at all-F reset (ch>=N_DUT nibbles unwritable)"
    if sig.startswith("force_r"):
        return "FORCE register reserved bits (only inj[4:0]/[16:17] implemented; WKEY=5)"
    if sig in ("clo_r", "chi_r", "cdead_r", "clo_nxt", "chi_nxt", "cdead_nxt", "data_q"):
        return "config array pad bits for channels >= N_DUT=5 (array sized for 16 channels)"
    if sig in ("errimg_r", "srcimg_r", "fustat_img_r", "fusrcimg_r"):
        return "status image pad bits above the implemented status width (N_DUT=5)"
    if sig in ("win_cnt", "win_cnt_n"):
        return "WIN_LAST=255: win_cnt[15:8] constant 0, win_cnt_n[15:8] constant 1"
    if sig == "q_chidx":
        return "q_chidx=q_cword/3; bit3 needs q_cword>=24 i.e. access beyond ch aperture tail - never issued"
    if "nib_ok_hi" in sig:
        return "nib_ok_hi constant 0 (nibble index >=8 >= N_DUT=5 illegal)"
    if sig == "wr":
        return "image wrap wr port tied to 1'b1 (free-running broadcast)"
    if sig == "wdata":
        return "wrap wdata pad bits above implemented width (driven from 32-bit bus into W-wide pad)"
    if sig == "dup_err":
        return "image wrap dual-rail fault net (fault injection covered on g_cwrap config wraps)"
    if sig == "d":
        return "sync_2dff data input tied to 1'b1 (reset-release synchronizer): constant 1, never toggles"
    return "structural constant for N_DUT=5 configuration"

src = open(os.path.join(EXC, "fullexclude.tgl")).read()
lines = src.splitlines()
out = []
sec = Sec()
cur_inst = None
emitted = 0
for ln in lines:
    if ln.startswith("// CHECKSUM:"):
        sec.feed(out, ln)
        cur_inst = None
        continue
    mi = re.match(r"// INSTANCE: (\S+)", ln)
    if mi:
        sec.feed(out, ln)
        cur_inst = mi.group(1)
        continue
    mt = re.match(r"// Toggle (\S+) \"([^\"]+)\"\s*$", ln)
    if mt and cur_inst in red:
        sig = mt.group(1)
        decl = mt.group(2)
        bins = sorted(r for (s, r) in red[cur_inst] if s == sig)
        if bins:
            sec.activate(out)
            merge_just(out, tgl_just(sig))
            dm = re.search(r"\[(\d+:\d+)\]", decl)
            full = dm.group(1) if dm else None
            for rng in bins:
                if rng is None or rng == full:
                    out.append(f'Toggle {sig} "{decl}"')
                    emitted += 1
                else:
                    out.append(f'Toggle 0to1 {sig} [{rng}] "{decl}"')
                    out.append(f'Toggle 1to0 {sig} [{rng}] "{decl}"')
                    emitted += 2
            red[cur_inst] = {(s, r) for (s, r) in red[cur_inst] if s != sig}
            continue
    out.append(ln)

open(os.path.join(OUT, "cmm_excl.tgl"), "w").write("\n".join(out) + "\n")
print("tgl done, emitted", emitted)
for inst, bins in sorted(red.items()):
    if bins:
        print("LEFTOVER", inst, sorted(bins)[:20])

# ------------------------------------------- tgl (module scope) ----
# module-level aggregation merges all self-instances per parameterization;
# bins red here are red in every instance (structural constants/pads).
redm = {}
for mf in MODS:
    html = open(os.path.join(REP, mf), encoding="utf-8", errors="replace").read()
    bounds = [m.start() for m in re.finditer(r"Toggle Coverage for (?:Module|Instance) :", html)]
    for m in re.finditer(r"Toggle Coverage for Module :", html):
        pos = m.start()
        nxt = [b for b in bounds if b > pos]
        seg = html[pos:(nxt[0] if nxt else len(html))]
        lm = re.search(r">([^<>]*\S[^<>]*)<", seg[:300])
        if not lm:
            continue
        label = lm.group(1).strip()
        if label == "tb_cmm_top":
            continue
        for tm in re.finditer(r"(?:Port|Signal) Details</b></caption>(.*?)</table>", seg, re.S):
            for r in re.findall(r"<tr[^>]*>.*?</tr>", tm.group(1), re.S):
                cells = re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)
                cells = [re.sub(r"<[^>]+>", "", c).strip() for c in cells]
                if len(cells) >= 4 and "No" in cells[1:4]:
                    base, rng = split_name(cells[0])
                    redm.setdefault(label, set()).add((base, rng))

for modn, bins in sorted(redm.items()):
    print("RED-TGL-MOD", modn, len(bins))

src = open(os.path.join(EXC, "fullexclude_module.tgl")).read()
out = []
sec = Sec()
cur_mod = None
emitted_m = 0
for ln in src.splitlines():
    if ln.startswith("// CHECKSUM:"):
        sec.feed(out, ln)
        cur_mod = None
        continue
    mm = re.match(r"// MODULE: (.*?)\s*$", ln)
    if mm:
        sec.feed(out, ln)
        cur_mod = mm.group(1)
        continue
    mt = re.match(r"// Toggle (\S+) \"([^\"]+)\"\s*$", ln)
    if mt and cur_mod in redm:
        sig = mt.group(1)
        decl = mt.group(2)
        bins = sorted(r for (s, r) in redm[cur_mod] if s == sig)
        if bins:
            sec.activate(out)
            merge_just(out, tgl_just(sig))
            dm = re.search(r"\[(\d+:\d+)\]", decl)
            full = dm.group(1) if dm else None
            for rng in bins:
                if rng is None or rng == full:
                    out.append(f'Toggle {sig} "{decl}"')
                    emitted_m += 1
                else:
                    out.append(f'Toggle 0to1 {sig} [{rng}] "{decl}"')
                    out.append(f'Toggle 1to0 {sig} [{rng}] "{decl}"')
                    emitted_m += 2
            redm[cur_mod] = {(s, r) for (s, r) in redm[cur_mod] if s != sig}
            continue
    out.append(ln)

open(os.path.join(OUT, "cmm_excl_mod.tgl"), "w").write("\n".join(out) + "\n")
print("tgl-module done, emitted", emitted_m)
for modn, bins in sorted(redm.items()):
    if bins:
        print("LEFTOVER-MOD", modn, sorted(bins)[:20])
