#!/usr/bin/env python3
# 通用 tgl .el 刷新: 旧 .el 的行集是人工甄别的结构常量集 (语义不变),
# 每次 compile 变的只有 CHECKSUM —— 用新 dump 的 checksum 重写各块,
# 并报告在新 dump 中找不到的 scope/行 (真正的结构变化)。
# 用法: python3 refresh_el.py <old.el> <new_dump_inst> <new_dump_mod> <out.el>
import re, sys

old, di, dm, out = sys.argv[1:5]

def parse_dump(path):
    scopes = {}
    cur = chk = None
    try:
        f = open(path)
    except OSError:
        return scopes
    for ln in f:
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk, cur = m.group(1), None
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            cur = "%s: %s" % (m.group(1), m.group(2))
            scopes[cur] = {"checksum": chk, "rows": set()}
            continue
        if cur and re.match(r"^// Toggle ", ln):
            scopes[cur]["rows"].add(ln[3:])
    return scopes

D = {}
D.update(parse_dump(di))
D.update(parse_dump(dm))

blocks, cur = [], None
for ln in open(old):
    ln = ln.rstrip("\n")
    if ln.startswith("CHECKSUM: "):
        if cur: blocks.append(cur)
        cur = [ln, None, []]
        continue
    if cur is None: continue
    if re.match(r"^(INSTANCE|MODULE): ", ln):
        cur[1] = ln
    elif ln.strip() and not ln.startswith("//"):
        cur[2].append(ln)
if cur: blocks.append(cur)

miss_scope, miss_row, ok = [], [], 0
with open(out, "w") as f:
    for chk, hdr, rows in blocks:
        if hdr not in D:
            miss_scope.append(hdr)
            continue
        newc = "CHECKSUM: %s" % D[hdr]["checksum"]
        lost = [r for r in rows if r not in D[hdr]["rows"]]
        if lost:
            miss_row.append((hdr, lost))
            continue
        f.write(newc + "\n" + hdr + "\n" + "\n".join(rows) + "\n\n")
        ok += 1
print("块刷新 %d | 丢scope %d | 丢行块 %d" % (ok, len(miss_scope), len(miss_row)))
for h in miss_scope: print("  SCOPE缺失:", h)
for h, l in miss_row:
    print("  行缺失 @", h)
    for r in l[:4]: print("     ", r[:90])
