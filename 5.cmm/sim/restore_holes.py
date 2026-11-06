#!/usr/bin/env python3
# 回贴: 解析退役后 urg 报告 (modinfo.txt) 中所有未覆盖对象 (= 误退造成的洞,
# 因为退役前排除集五项全 100), 从退役前快照 (*.pre) 找回对应行写回排除文件。
# 与 retire_covered.py 构成闭环:
#   链(rebuild->append) -> cp *.pre -> retire -> urg -> restore -> urg 复验
# 用法: python3 restore_holes.py <report_dir>   (如 urg_chk14)
import os, re, sys

SIM = os.path.dirname(os.path.abspath(__file__))
REP = sys.argv[1] if len(sys.argv) > 1 else "urg_chk14"

line_re   = re.compile(r"^\s*(\d+)\s+0/\d+\s")
ln_hdr_re = re.compile(r"^\s*LINE\s+(\d+)\s*$")
expr_re   = re.compile(r"^\s*EXPRESSION\s+(.*)$")
src_re    = re.compile(r"^\s*(\d+)\s+\S")
mark_re   = re.compile(r"^\s+-(\d+)-\s*$")
tbl_re    = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
tgl_re    = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                       r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")

# ---------------------------------------------------------------- 报告洞收集
holes = {"line": set(), "cond": set(), "branch": set(), "tgl": set()}
cur, cur_line, cur_expr, grp = None, None, None, []
for raw in open(os.path.join(SIM, REP, "modinfo.txt"),
                encoding="utf-8", errors="replace"):
    ln = raw.rstrip("\n")
    m = re.match(r"^(Line|Cond|Branch|Toggle|FSM) Coverage for "
                 r"(Instance|Module) : (.*)$", ln)
    if m:
        met = m.group(1)
        metl = met.lower()
        key = re.sub(r"\s*\(x\)\s*$", "", m.group(3).strip())
        cur = ((metl, ("I:" if m.group(2) == "Instance" else "M:")
                + key) if (metl in holes or metl == "toggle") else None)
        cur_line, cur_expr, grp = None, None, []
        continue
    if cur is None:
        continue
    met, key = cur
    if met == "line":
        m = line_re.match(ln)
        if m:
            holes["line"].add((key, int(m.group(1))))
    elif met == "cond":
        m = ln_hdr_re.match(ln)
        if m:
            cur_line = int(m.group(1))
            continue
        m = expr_re.match(ln)
        if m:
            cur_expr = re.sub(r"\s+", " ", m.group(1)).strip()
        else:
            m = tbl_re.match(ln)
            if m and cur_line is not None and m.group(2) == "Not Covered":
                holes["cond"].add((key, cur_line,
                                   "".join(m.group(1).split())))
    elif met == "branch":
        m = src_re.match(ln)
        if m and not tbl_re.match(ln):
            grp.append(int(m.group(1)))
            continue
        if mark_re.match(ln):
            continue
        m = tbl_re.match(ln)
        if m and m.group(2) == "Not Covered" and grp:
            combo = ",".join(m.group(1).split())
            for gl in grp:
                holes["branch"].add((key, gl, combo))
    elif met == "toggle":
        m = tgl_re.match(ln)
        if m:
            name = m.group(1)
            rm = re.match(r"^([\w.]+)\[(\d+):(\d+)\]$", name)
            base, rng = ((rm.group(1), (int(rm.group(2)), int(rm.group(3))))
                         if rm else (name.split("[")[0], None))
            if m.group(2) == "No":
                holes["tgl"].add((key, base, rng, "T"))
            if m.group(3) == "No":
                holes["tgl"].add((key, base, rng, "1to0"))
            if m.group(4) == "No":
                holes["tgl"].add((key, base, rng, "0to1"))

print("洞: line=%d cond=%d branch=%d tgl=%d"
      % (len(holes["line"]), len(holes["cond"]),
         len(holes["branch"]), len(holes["tgl"])))

# ---------------------------------------------------------------- dump 行号
def parse_dump(path):
    out, cur, hdr, lineno = {}, None, None, None
    try:
        f = open(os.path.join(SIM, path), encoding="utf-8", errors="replace")
    except OSError:
        return out
    with f:
        for raw in f:
            ln = raw.rstrip("\n")
            if ln.startswith("// CHECKSUM:"):
                cur, hdr = {}, None
                continue
            if cur is None:
                continue
            m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
            if m:
                hdr = ("I:" if m.group(1) == "INSTANCE" else "M:") + m.group(2).strip()
                out.setdefault(hdr, cur)
                continue
            m = re.match(r"^// ANNOTATION: .*FileName: ", ln)
            if m:
                lm = re.search(r"LineNumber: (\d+)", ln)
                lineno = int(lm.group(1)) if lm else None
                continue
            if re.match(r"^// (Condition|Branch|Block|Toggle) ", ln):
                if hdr and lineno is not None:
                    cur.setdefault(ln[3:], lineno)
    return out

dmaps = {
    "line":   {**parse_dump("fresh_line.dump"), **parse_dump("fresh_line_mod.dump")},
    "cond":   {**parse_dump("fresh_cond.dump"), **parse_dump("fresh_cond_mod.dump")},
    "branch": {**parse_dump("fresh_branch.dump"), **parse_dump("fresh_branch_mod.dump")},
}

def strip_vec(row):
    row = re.sub(r"\s*\(\d+\)\s+\"[^\"]*\"\s*$", "", row)
    return re.sub(r"\s*\(\d+\s+\"[^\"]*\"\)\s*$", "", row)

def dump_lineno(sm, row):
    if row in sm:
        return sm[row]
    sv = strip_vec(row)
    for k, ln in sm.items():
        if strip_vec(k) == sv:
            return ln
    return None

def combo_of(row):
    m = re.search(r'\(\d+\s+"([^"]*)"\)\s*$', row)
    if m:
        return m.group(1)
    m = re.search(r'\(\d+\)\s+"([^"]*)"\s*$', row)
    if m:
        parts = m.group(1).split()
        return parts[-1] if parts else None
    return None

def tgl_target(row):
    m = re.match(r'^Toggle\s+([01]to[01])\s+([\w.]+)'
                 r'(?:\s+\[(\d+)(?::(\d+))?\])?\s+"([^"]*)"\s*$', row)
    if not m:
        return None
    d, sig, b1, b2, decl = m.groups()
    if b1 is not None:
        rng = (int(b1), int(b2) if b2 is not None else int(b1))
    else:
        dm = re.search(r"\[(\d+):(\d+)\]", decl)
        rng = ((int(dm.group(1)), int(dm.group(2))) if dm else (0, 0))
    return (d, sig, rng)

def rng_overlap(a, b):
    if a is None or b is None:
        return True
    return a[1] <= b[0] and b[1] <= a[0]

# ---------------------------------------------------------------- el 文件解析
def parse_blocks(path):
    try:
        txt = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    blocks, cur = [], None
    for ln in txt.splitlines():
        if ln.startswith("CHECKSUM:"):
            if cur: blocks.append(cur)
            cur = [ln, None, []]
            continue
        if cur is None:
            continue
        if re.match(r"^(INSTANCE|MODULE): ", ln):
            cur[1] = ln
        elif ln.startswith("//") or not ln.strip():
            continue
        else:
            cur[2].append(ln)
    if cur: blocks.append(cur)
    return blocks

FILES = [("excl_new_line.el", "line"),   ("excl_new_cond.el", "cond"),
         ("excl_new_branch.el", "branch"), ("excl_new_fsm.el", None),
         ("excl_new_inst.tgl", "tgl"),    ("excl_new_mod.tgl", "tgl")]

def row_hits_hole(metric, key, row):
    if metric == "line":
        ln = dump_lineno(dmaps["line"].get(key, {}), row)
        return any(k == key and l == ln for (k, l) in holes["line"]) if ln else False
    if metric == "cond":
        ln = dump_lineno(dmaps["cond"].get(key, {}), row)
        c = combo_of(row)
        return (any(k == key and l == ln and c == cc
                    for (k, l, cc) in holes["cond"]) if ln else False)
    if metric == "branch":
        ln = dump_lineno(dmaps["branch"].get(key, {}), row)
        c = combo_of(row)
        return (any(k == key and l == ln and c == cc
                    for (k, l, cc) in holes["branch"]) if ln else False)
    if metric == "tgl":
        t = tgl_target(row)
        if not t:
            return False
        d, sig, rng = t
        return any(k == key and s == sig and d == dd and rng_overlap(rr, rng)
                   for (k, s, rr, dd) in holes["tgl"])
    return False

def scope_key(hdr):
    m = re.match(r"^(INSTANCE|MODULE): (.*)$", hdr or "")
    if not m:
        return None
    return ("I:" if m.group(1) == "INSTANCE" else "M:") + m.group(2).strip()

if __name__ == "__main__":
    for fname, metric in FILES:
        path = os.path.join(SIM, fname)
        prepath = path + ".pre"
        if not os.path.exists(prepath):
            continue
        post_rows = set()
        for chk, hdr, rows in parse_blocks(path):
            post_rows.update(rows)
        restores = {}
        for chk, hdr, rows in parse_blocks(prepath):
            key = scope_key(hdr)
            if key is None or metric is None:
                continue
            for r in rows:
                if r in post_rows:
                    continue
                if row_hits_hole(metric, key, r):
                    restores.setdefault((chk, hdr), []).append(r)
                    print("  回贴 [%s] %s" % (key[:52], r[:84]))
        for (chk, hdr), rows in restores.items():
            with open(path, "a") as f:
                f.write("\n" + chk + "\n" + hdr + "\n" + "\n".join(rows) + "\n")
    print("done")
