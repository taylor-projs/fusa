#!/usr/bin/env python3
# 退役修剪: 基线 (无排除 urg_report) 中已覆盖、却被排除文件排除的对象
# —— "旧项被覆盖后必须退役" (urg-exclusion-flow 规矩)。
# 排除一个已覆盖 bin 不掉分但违反最小排除纪律, 且 -excl_strict 报
# UCAPI-ILOAD 警告; 本脚本读基线 modinfo.txt 逐行核对六个排除文件:
#   - 完全覆盖的行 -> 删除
#   - 部分覆盖的 Toggle 区间行 -> 拆成未覆盖子区间行
#   - 空块丢弃
#
# 对应关系 (dump 与 modinfo 源码文本规范化不同, 一律经 dump 行号间接映射):
#   Line   el Block 行 -> fresh_line[_mod].dump 同 scope 同行文行号 -> 基线该行 covered?
#   Cond   el Condition 行 -> fresh_cond[_mod].dump 行号 -> 基线 Cond 段该行 EXPRESSION bin
#   Branch el Branch 行 -> fresh_branch[_mod].dump 行号 -> 基线 Branch 段含该行组的 outcome
#   Toggle el Toggle 行 (方向+信号[位/区间]) -> 基线 Toggle Details Yes 区间求交/拆分
#
# 用法: 排除链 (rebuild_* -> append_*) 全部跑完后执行, 再跑最终 urg。
import os, re

SIM = os.path.dirname(os.path.abspath(__file__))
METRICS = ("Line", "Cond", "Branch", "Toggle")

# ---------------------------------------------------------------- 基线解析
def parse_baseline():
    """secs[metric][scope] = {"line":{ln:1}, "cond":{(ln,expr):{combos}},
       "branch":{ln:{combos}}, "tgl":{base:[(rng,dirs)]}}"""
    secs = {m: {} for m in METRICS}
    cur, cur_expr, cur_line = None, None, None
    grp_conds, grp_tbl = [], None        # Branch: 组内条件行号 / 当前表头序
    line_re   = re.compile(r"^\s*(\d+)\s+(\d+)/(\d+)\s")
    ln_hdr_re = re.compile(r"^\s*LINE\s+(\d+)\s*$")
    expr_re   = re.compile(r"^\s*EXPRESSION\s+(.*)$")
    src_re    = re.compile(r"^\s*(\d+)\s+\S")
    mark_re   = re.compile(r"^\s+-(\d+)-\s*$")
    tblrow_re = re.compile(r"^([\s01]+?)\s(Covered|Not Covered|Excluded)\s*$")
    tblrowb_re = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
    tgl_re    = re.compile(r"^(\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                           r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
    for raw in open(os.path.join(SIM, "urg_report/modinfo.txt"),
                    encoding="utf-8", errors="replace"):
        ln = raw.rstrip("\n")
        m = re.match(r"^(Line|Cond|Branch|Toggle|FSM) Coverage for "
                     r"(Instance|Module) : (.*)$", ln)
        if m:
            met = m.group(1)
            if met in METRICS:
                key = ("I:" if m.group(2) == "Instance" else "M:") + m.group(3).strip()
                cur = (met, key)
                if key not in secs[met]:
                    secs[met][key] = {"line": {}, "cond": {}, "branch": {},
                                      "tgl": {}}
            else:
                cur = None
            cur_expr, cur_line, grp_conds, grp_tbl = None, None, [], None
            continue
        if cur is None:
            continue
        d = secs[cur[0]][cur[1]]
        if cur[0] == "Line":
            m = line_re.match(ln)
            if m and int(m.group(2)) > 0:
                d["line"][int(m.group(1))] = 1
        elif cur[0] == "Cond":
            m = ln_hdr_re.match(ln)
            if m:
                cur_line = int(m.group(1))
                continue
            m = expr_re.match(ln)
            if m:
                cur_expr = re.sub(r"\s+", " ", m.group(1)).strip()
            else:
                m = tblrow_re.match(ln)
                if m and cur_expr and m.group(2) == "Covered":
                    combo = "".join(m.group(1).split())
                    d["cond"].setdefault((cur_line, cur_expr), set()).add(combo)
        elif cur[0] == "Branch":
            m = src_re.match(ln)
            if m and not tblrowb_re.match(ln):
                grp_conds.append(int(m.group(1)))
                grp_tbl = None
                continue
            m = mark_re.match(ln)
            if m:
                grp_tbl = []          # 新组开始 (表头列 = 标记出现序)
                continue
            m = tblrowb_re.match(ln)
            if m and grp_conds:
                combo = ",".join(m.group(1).split())
                if m.group(2) == "Covered":
                    for cl in grp_conds:
                        d["branch"].setdefault(cl, set()).add(combo)
        elif cur[0] == "Toggle":
            m = tgl_re.match(ln)
            if m:
                name = m.group(1)
                rm = re.match(r"^([\w.]+)\[(\d+):(\d+)\]$", name)
                base, rng = ((rm.group(1), (int(rm.group(2)), int(rm.group(3))))
                             if rm else (name.split("[")[0], None))
                dirs = set()
                if m.group(2) == "Yes": dirs.add("T")
                if m.group(3) == "Yes": dirs.add("1to0")
                if m.group(4) == "Yes": dirs.add("0to1")
                if dirs:
                    d["tgl"].setdefault(base, []).append((rng, dirs))
    return secs

# ---------------------------------------------------------------- dump 行号映射
def parse_dump(path):
    """{scope_key: {row_text: lineno}} — 行号取自每行前的 ANNOTATION"""
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

# ---------------------------------------------------------------- 作用域匹配
def scope_key(hdr):
    m = re.match(r"^(INSTANCE|MODULE): (.*)$", hdr or "")
    if not m:
        return None
    return ("I:" if m.group(1) == "INSTANCE" else "M:") + m.group(2).strip()

def wset(name):
    return set(re.findall(r"W=\d+", name))

def base_mod(name):
    return name.split("(")[0].strip()

def match_secs(sec_dict, key):
    if key in sec_dict:
        return [key]
    kw, kb = wset(key), base_mod(key)
    return [k for k in sec_dict
            if base_mod(k) == kb and ((not wset(k) and not kw) or
                                      (wset(k) and wset(k) <= kw))]

# ---------------------------------------------------------------- el 文件解析
def parse_blocks(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    blocks, cur = [], None
    for ln in txt.splitlines():
        if ln.startswith("CHECKSUM:"):
            if cur: blocks.append(cur)
            cur = [ln, [], []]
            continue
        if cur is None:
            continue
        if re.match(r"^(INSTANCE|MODULE): ", ln):
            cur[1].append(ln)
        elif ln.startswith("//") or not ln.strip():
            continue
        else:
            cur[2].append(ln)
    if cur: blocks.append(cur)
    return blocks

# ---------------------------------------------------------------- 判定 (True=退役)
def covered_line(secs, dmaps, key, row):
    ln = dmaps["line"].get(key, {}).get(row)
    if ln is None:
        return False
    return any(ln in secs["Line"][k]["line"] for k in match_secs(secs["Line"], key))

def strip_vec(row):
    row = re.sub(r"\s*\(\d+\)\s+\"[^\"]*\"\s*$", "", row)     # Branch
    return re.sub(r"\s*\(\d+\s+\"[^\"]*\"\)\s*$", "", row)    # Condition

def dump_lineno(scope_map, row):
    """el 行 -> dump 行号: 全字匹配优先, 退化按去 vec 后缀匹配"""
    if row in scope_map:
        return scope_map[row]
    sv = strip_vec(row)
    for k, ln in scope_map.items():
        if strip_vec(k) == sv:
            return ln
    return None

def covered_cond(secs, dmaps, key, row):
    ln = dmaps["cond"].get(key, {}).get(strip_vec(row))
    if ln is None:
        return False
    for k in match_secs(secs["Cond"], key):
        for (bln, be), combos in secs["Cond"][k]["cond"].items():
            if bln == ln and combos:
                return True          # 该行任一已覆盖 bin? 逐 combo 见下
    return False

def cond_combos(secs, dmaps, key, row, combo):
    ln = dump_lineno(dmaps["cond"].get(key, {}), row)
    if ln is None or combo is None:
        return False
    for k in match_secs(secs["Cond"], key):
        for (bln, be), combos in secs["Cond"][k]["cond"].items():
            if bln == ln and combo in combos:
                return True
    return False

def combo_of(row):
    m = re.search(r'\(\d+\s+"([^"]*)"\)\s*$', row)        # Condition (3 "1101")
    if m:
        return m.group(1)
    m = re.search(r'\(\d+\)\s+"([^"]*)"\s*$', row)        # Branch (0) "wr 1,1,-"
    if m:
        parts = m.group(1).split()
        return parts[-1] if parts else None
    return None

def covered_branch(secs, dmaps, key, row):
    ln = dump_lineno(dmaps["branch"].get(key, {}), row)
    if ln is None:
        return False
    c = combo_of(row)
    if c is None:
        return False
    return any(c in secs["Branch"][k]["branch"].get(ln, {})
               for k in match_secs(secs["Branch"], key))

# ---- Toggle: 返回 ("keep"|"drop"|"split", 新行列表) ----
def uncovered_subranges(hi, lo, yes):
    if any(r is None for r in yes):
        return []
    ivs = sorted((max(lo, a), min(hi, b)) for (a, b) in yes
                 if a <= hi and lo <= b and max(lo, a) <= min(hi, b))
    out, cur = [], lo
    for a, b in ivs:
        if a > cur:
            out.append((a - 1, cur))
        cur = max(cur, b + 1)
    if cur <= hi:
        out.append((hi, cur))
    return out

def tgl_action(secs, key, row):
    m = re.match(r'^Toggle\s+([01]to[01])\s+([\w.]+)(?:\s+\[(\d+)(?::(\d+))?\])?\s+"([^"]*)"\s*$',
                 row)
    if not m:
        return ("keep", None)          # 无方向/其他形态: 不动
    d, sig, b1, b2, decl = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
    b1 = int(b1) if b1 else None
    target = None
    if b1 is not None:
        target = (b1, int(b2) if b2 is not None else b1)   # [hi] 或 [hi:lo]
    else:
        dm = re.search(r"\[(\d+):(\d+)\]", decl)
        target = ((int(dm.group(1)), int(dm.group(2))) if dm else (0, 0))  # 标量按 [0:0]
    hi, lo = target
    yes = []
    for k in match_secs(secs["Toggle"], key):
        for (rng, dirs) in secs["Toggle"][k]["tgl"].get(sig, []):
            if d in dirs:
                yes.append(rng)
    sub = uncovered_subranges(hi, lo, yes)
    if not sub:
        return ("drop", None)          # 全覆盖
    if len(sub) == 1 and sub[0] == (hi, lo):
        return ("keep", None)          # 无覆盖交集
    return ("split",
            ['Toggle %s %s [%d:%d] "%s"' % (d, sig, h2, l2, decl)
             for (h2, l2) in sub])

FILES = [
    ("excl_new_line.el",   "line"),   ("excl_new_cond.el",   "cond"),
    ("excl_new_branch.el", "branch"), ("excl_new_fsm.el",    None),
    ("excl_new_inst.tgl",  "tgl"),    ("excl_new_mod.tgl",   "tgl"),
]

if __name__ == "__main__":
    secs = parse_baseline()
    dmaps = {
        "line":   {**parse_dump("fresh_line.dump"), **parse_dump("fresh_line_mod.dump")},
        "cond":   {**parse_dump("fresh_cond.dump"), **parse_dump("fresh_cond_mod.dump")},
        "branch": {**parse_dump("fresh_branch.dump"), **parse_dump("fresh_branch_mod.dump")},
    }
    for fname, metric in FILES:
        path = os.path.join(SIM, fname)
        if not os.path.exists(path):
            print("skip (缺): %s" % fname)
            continue
        blocks = parse_blocks(path)
        kept, dropped, split = [], [], 0
        for chk, hdrs, rows in blocks:
            key = scope_key(hdrs[0]) if hdrs else None
            if key is None:
                kept.append((chk, hdrs, rows))
                continue
            newrows = []
            for r in rows:
                if metric == "line":
                    bad = covered_line(secs, dmaps, key, r)
                    if bad:
                        dropped.append("  [%s] %s" % (key[:56], r[:88]))
                    else:
                        newrows.append(r)
                elif metric == "cond":
                    c = combo_of(r)
                    bad = cond_combos(secs, dmaps, key, r, c)
                    if bad:
                        dropped.append("  [%s] %s" % (key[:56], r[:88]))
                    else:
                        newrows.append(r)
                elif metric == "branch":
                    bad = covered_branch(secs, dmaps, key, r)
                    if bad:
                        dropped.append("  [%s] %s" % (key[:56], r[:88]))
                    else:
                        newrows.append(r)
                elif metric == "tgl":
                    act, new = tgl_action(secs, key, r)
                    if act == "drop":
                        dropped.append("  [%s] %s" % (key[:56], r[:88]))
                    elif act == "split":
                        dropped.append("  拆 %s" % r[:88])
                        newrows.extend(new)
                        split += 1
                    else:
                        newrows.append(r)
                else:
                    newrows.append(r)
            if newrows:
                kept.append((chk, hdrs, newrows))
        with open(path, "w") as f:
            for chk, hdrs, rows in kept:
                f.write(chk + "\n")
                for h in hdrs: f.write(h + "\n")
                for r in rows:  f.write(r + "\n")
                f.write("\n")
        print("%s: 保留 %d 块, 退役 %d 行, 拆分 %d 行"
              % (fname, len(kept), len(dropped) - split, split))
        for d in dropped:
            print(d)
