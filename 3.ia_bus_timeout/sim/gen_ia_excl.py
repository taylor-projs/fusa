#!/usr/bin/env python3
"""Rebuild ia structural exclusions from one fresh raw urg report.

Run on the VM from sim/obj_vcs after run_vcs.sh and:
  urg -dir simv.vdb -dump full_exclusions line+cond+fsm+tgl+branch -report /tmp/ia_dump
  python3 ../gen_ia_excl.py

Outputs tgl_struct_excl_new.el and misc_struct_excl_new.el in the CWD.
Every raw hole must match a justified structural family; otherwise generation
aborts. Review the files, then install them as ../tgl_struct_excl.el and
../misc_struct_excl.el. No covered item is intentionally copied: -excl_strict
is the final gate.
"""
import re
from collections import OrderedDict
from pathlib import Path

REPORT = Path("urg_report/modinfo.txt")

# ---------------------------------------------------------------------------
# Raw modinfo hole scanner (line/cond/branch/toggle, instance + module domain).
# ---------------------------------------------------------------------------
line_re = re.compile(r"^\s*(\d+)\s+0/\d+\s")
ln_hdr_re = re.compile(r"^\s*LINE\s+(\d+)\s*$")
expr_re = re.compile(r"^\s*EXPRESSION\s+(.*)$")
tbl_re = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
src_re = re.compile(r"^\s*(\d+)\s+\S")
tgl_re = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                    r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
ob_re = re.compile(r"^\s*Other bits of (\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)\s*$")

holes = []
hdr = metric = dom = None
cur_line = cur_expr = None
for raw in REPORT.open(encoding="utf-8", errors="replace"):
    ln = raw.rstrip("\n")
    m = re.match(r"^(Line|Cond|Branch|Toggle) Coverage for (Instance|Module) : (.*)$", ln)
    if m:
        metric, dom = m.group(1), m.group(2)
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(3).strip()).rstrip()
        cur_line = cur_expr = None
        continue
    if hdr is None or metric is None:
        continue
    if metric == "Line":
        m2 = line_re.match(ln)
        if m2:
            holes.append((dom, hdr, "line", m2.group(1), ""))
    elif metric == "Cond":
        m2 = ln_hdr_re.match(ln)
        if m2:
            cur_line = m2.group(1)
            continue
        m2 = expr_re.match(ln)
        if m2:
            cur_expr = re.sub(r"\s+", " ", m2.group(1)).strip()
        else:
            m2 = tbl_re.match(ln)
            if m2 and m2.group(2) == "Not Covered" and cur_line:
                holes.append((dom, hdr, "cond", cur_line,
                              "".join(m2.group(1).split())))
    elif metric == "Branch":
        m2 = src_re.match(ln)
        if m2 and not tbl_re.match(ln):
            cur_line = m2.group(1)
            continue
        m2 = tbl_re.match(ln)
        if m2 and m2.group(2) == "Not Covered" and cur_line:
            holes.append((dom, hdr, "branch", cur_line,
                          ",".join(m2.group(1).split())))
    elif metric == "Toggle":
        m2 = tgl_re.match(ln) or ob_re.match(ln)
        if m2 and "No" in (m2.group(2), m2.group(3), m2.group(4)):
            sig = m2.group(1)
            if ln.lstrip().startswith("Other bits of "):
                mm = re.match(r"^Other bits of ([\w.]+)((?:\[[^\]]+\])+)$", ln.strip())
                if mm:
                    sig = mm.group(1) + mm.group(2)
            holes.append((dom, hdr, "tgl", sig, ""))

# The aggregator has a Module modinfo section but no top-level Instance
# section. Mirror its structural toggle rules to the real hierarchy instance.
mirror = []
for dom, scope, met, val, extra in holes:
    if met == "tgl" and dom == "Module" and scope == "ia_bus_timeo_top":
        mirror.append(("Instance", "tb_ia_timeo_gen_wrap.u_agg", met, val, extra))
holes.extend(mirror)

# ---------------------------------------------------------------------------
# Structural-only classification. Anything not listed here is a TB gap.
# ---------------------------------------------------------------------------
def classify(dom, scope, met, val, extra):
    is_wrap = ("reg_wrap" in scope or
               re.search(r"\.u_[rcw]_[A-Za-z0-9_]+$", scope) is not None)
    base = val.split("[")[0]
    if met == "tgl":
        if base == "cfg_key":
            return "cfg_key is hard-wired to 4'b1010"
        if base == "par_l_dup_f" and val == "par_l_dup_f[1]":
            return "vector LHS consumes scalar != result; only bit0 exists"
        if is_wrap and base == "wr":
            return "mbus image wrapper has wr tied high (follow semantics)"
        if is_wrap and base in ("wdata", "rdata", "r.data_q", "rin.data_q"):
            return "NUM_CORE=2 zero-extends W=32 sticky payload to [1:0]"
        if base == "rdata":
            return "read mux reserved/zero-fill bits and fixed zero ID bits"
        if base in ("sta_err_r", "sta_fault_r", "sta_parc_r", "sta_rail_r"):
            return "NUM_CORE=2 zero-extends sticky state above bit1"
        if base == "sta_par_rb":
            return "STA_PAR concatenation hard-wires [31:8] to zero"
    elif met == "line" and is_wrap:
        if val in ("108", "110"):
            return "wr=1 image cannot take selftest-without-write branch"
        if val == "104":
            return "this wrapper injects selftest only while wr=0"
    elif met == "branch" and is_wrap and val == "111":
        if extra in ("0,-,1", "0,-,0"):
            return "wr=1 image makes both wr=0 branch arms unreachable"
        if extra == "1,1,-":
            return "selftest and wr never coincide on this wrapper"
    elif met == "cond" and scope.endswith("u_ia_bus_timeo_mon"):
        if val == "327" and extra == "10":
            return "cfg_key is hard-wired to 4'b1010; false key arm is dead"
    elif met == "cond" and scope == "ia_bus_timeo_mon":
        if val == "327" and extra == "10":
            return "cfg_key is hard-wired to 4'b1010; false key arm is dead"
    return None

unclassified = []
for h in holes:
    if classify(*h) is None:
        unclassified.append(h)
if unclassified:
    for h in unclassified:
        print("UNCLASSIFIED:", h)
    raise SystemExit("raw report contains non-structural or unknown holes; fix TB first")

# ---------------------------------------------------------------------------
# Dump parser: exact CHECKSUM, declaration, source-line anchor and hash rows.
# ---------------------------------------------------------------------------
def parse_dump(path):
    scopes = {}
    cur = chk = None
    src_line = None
    for raw in Path(path).open(encoding="utf-8", errors="replace"):
        ln = raw.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            raw_hdr = "%s: %s" % (m.group(1), m.group(2))
            cur = raw_hdr.rstrip()
            scopes[cur] = {"checksum": chk, "hdr": raw_hdr,
                           "decl": {}, "rows": []}
            src_line = None
            continue
        if cur is None:
            continue
        m = re.search(r"LineNumber: (\d+)", ln)
        if m:
            src_line = m.group(1)
            continue
        m = re.match(r"^// (Toggle|Block|Condition|Branch) (.*)$", ln)
        if m:
            kind, rest = m.group(1), m.group(2)
            row = "%s %s" % (kind, rest)
            scopes[cur]["rows"].append((kind, src_line, row))
            if kind == "Toggle":
                mm = re.match(r"^(\S+) \"(.*)\"$", rest)
                if mm:
                    scopes[cur]["decl"][mm.group(1)] = mm.group(2)
    return scopes

DUMPS = {}
for met in ("tgl", "line", "cond", "branch"):
    ext = "tgl" if met == "tgl" else met
    DUMPS[("Instance", met)] = parse_dump("fullexclude." + ext)
    DUMPS[("Module", met)] = parse_dump("fullexclude_module." + ext)


def split_sig(sig):
    m = re.match(r"^([\w.]+)((?:\[[^\]]+\])+)$", sig)
    if m:
        return m.group(1), m.group(2)
    return sig, ""


def exclusion_row(dom, scope, met, val, extra):
    key = ("INSTANCE: " if dom == "Instance" else "MODULE: ") + scope
    key = key.rstrip()
    info = DUMPS[(dom, met)].get(key)
    if info is None:
        raise SystemExit("dump scope missing: %s / %s" % (met, key))
    if met == "tgl":
        base, rng = split_sig(val)
        decl = info["decl"].get(base)
        if decl is None:
            for k, v in info["decl"].items():
                if k.split("[")[0] == base:
                    decl = v
                    break
        if decl is None:
            raise SystemExit("toggle declaration missing: %s %s" % (key, val))
        return 'Toggle %s %s "%s"' % (base, rng, decl)
    for kind, src_line, row in info["rows"]:
        if met == "line" and kind == "Block" and src_line == val:
            return row
        if met == "cond" and kind == "Condition" and src_line == val:
            if re.search(r'\(\d+ "%s"\)$' % re.escape(extra), row):
                return row
        if met == "branch" and kind == "Branch":
            if row.endswith('"wr %s"' % extra):
                return row
    raise SystemExit("dump row missing: %s %s %s %s" % (key, met, val, extra))

# Preserve report order but deduplicate by (domain, metric, scope, row).
groups = OrderedDict()
for h in holes:
    dom, scope, met, val, extra = h
    row = exclusion_row(*h)
    key = (dom, met, scope)
    groups.setdefault(key, [])
    if row not in groups[key]:
        groups[key].append(row)

TGL_HEADER = """// ==================================================================
// ia_bus_timeout structural TOGGLE exclusions; generated from raw urg.
// Families (all dual-domain where urg has both bins):
//   * cfg_key is hard-wired 4'b1010 in every leaf/aggregator wrapper.
//   * rdata reserved/zero-fill and fixed-zero ID bits can never toggle.
//   * NUM_CORE=2 zero-extends aggregator sticky payloads/state above bit1.
//   * mbus image reg_wrap wr is tied high by follow semantics.
//   * par_l_dup_f[1] is dead: a 1-bit != result is assigned to a vector.
// The 'Module self-instances' pseudo-section is not a coverage target.
// ==================================================================
"""
MISC_HEADER = """// ==================================================================
// ia_bus_timeout structural LINE/COND/BRANCH exclusions.
// LINE/BRANCH: reg_wrap image wrappers have wr=1, so selftest-without-write
//   is unreachable; the other wrappers inject only with wr=0, so the
//   selftest-with-write arm is unreachable. Module branch is already 100
//   raw and is deliberately not excluded (strict-mode hygiene).
// COND: cfg_key=4'b1010 makes the cfg_wr=1/key-mismatch vector impossible.
// No FSM bins exist in this design (dashboard FSM='--').
// ==================================================================
"""

def write_groups(path, selected, header):
    with Path(path).open("w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n")
        for (dom, met, scope), rows in groups.items():
            if met not in selected:
                continue
            key = ("INSTANCE: " if dom == "Instance" else "MODULE: ") + scope
            info = DUMPS[(dom, met)][key.rstrip()]
            f.write("CHECKSUM: %s\n%s\n" % (info["checksum"], info["hdr"]))
            for row in rows:
                f.write(row + "\n")
            f.write("\n")

write_groups("tgl_struct_excl_new.el", {"tgl"}, TGL_HEADER)
write_groups("misc_struct_excl_new.el", {"line", "cond", "branch"}, MISC_HEADER)
print("raw structural holes: %d" % len(holes))
for met in ("tgl", "line", "cond", "branch"):
    print("%s scopes: %d" % (met, sum(1 for k in groups if k[1] == met)))
print("wrote tgl_struct_excl_new.el and misc_struct_excl_new.el")
