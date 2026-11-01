#!/usr/bin/env python3
# covx.py - extract UNCOVERED objects from an urg "-format both" report dir
# usage: python3 covx.py <urg_report_dir> [line,cond,branch,fsm,tgl]
import re, sys, os, html as H

rep = sys.argv[1]
metrics = set((sys.argv[2] if len(sys.argv) > 2 else "line,cond,branch,fsm,tgl").split(","))

def strip(t):
    return H.unescape(re.sub(r"<[^>]+>", "", t)).replace("\xa0", " ").strip()

found_any = False
for mf in sorted(os.listdir(rep), key=lambda s: (len(s), s)):
    if not re.match(r"mod\d+\.html$", mf):
        continue
    h = open(os.path.join(rep, mf), encoding="utf-8", errors="replace").read()
    bounds = [(m.group(1).lower(), m.group(2), m.group(3), m.start()) for m in
              re.finditer(r"(Line|Cond|Toggle|Branch|FSM) Coverage for (Module|Instance) : <a[^>]*>([^<]+)</a>", h)]
    for k, (kind, lvl, name, pos) in enumerate(bounds):
        if kind not in metrics:
            continue
        end = bounds[k + 1][3] if k + 1 < len(bounds) else len(h)
        seg = h[pos:end]
        items = []
        if kind == "line":
            for pm in re.finditer(r'<pre class="code">(.*?)</pre>', seg, re.S):
                txt = strip(re.sub(r"<br[^>]*>", "\n", pm.group(1)))
                for ln in txt.splitlines():
                    m = re.match(r"\s*(\d+)\s+0/(\d+)\s+(.*)$", ln)
                    if m:
                        items.append("L%s 0/%s %s" % (m.group(1), m.group(2), m.group(3)[:90]))
        elif kind in ("cond", "branch"):
            for m in re.finditer(r'<pre class="code">(.*?)</pre>', seg, re.S):
                raw = m.group(1)
                txt = strip(re.sub(r"<br[^>]*>", "\n", raw))
                # the rows table follows after <br>/<span> markup
                tm = re.search(r"<table.*?</table>", seg[m.end():m.end() + 900], re.S)
                rows = []
                if tm:
                    for rm in re.finditer(r'<tr class="uRed">(.*?)</tr>', tm.group(0), re.S):
                        cells = [strip(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", rm.group(1), re.S)]
                        rows.append("|".join(cells[:-1] if cells and cells[-1].startswith("Not") else cells))
                lm = re.search(r"LINE\s+(\d+)", txt)
                if lm:  # cond style: LINE nnn + EXPRESSION
                    if not rows:
                        continue
                    expr = ""
                    em = re.search(r"EXPRESSION\s+(.+)", txt)
                    if em:
                        expr = em.group(1).splitlines()[0][:90]
                    items.append("L%s %s  red: %s" % (lm.group(1), expr, " ; ".join(rows[:6])))
                else:  # branch style: source line, red font marks, table rows
                    if 'font color = "red"' not in raw or not rows:
                        continue
                    bm = re.match(r"\s*(\d+)\s+(.*)", txt, re.S)
                    if not bm:
                        continue
                    src = " ".join(bm.group(2).split())[:80]
                    items.append("L%s %s  red: %s" % (bm.group(1), src, " ; ".join(rows[:4])))
        elif kind == "fsm":
            for rm in re.finditer(r'<tr class="uRed">(.*?)</tr>', seg, re.S):
                cells = [strip(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", rm.group(1), re.S)]
                if cells:
                    items.append(" ".join(cells[:2]))
        elif kind == "tgl":
            for tm in re.finditer(r"(?:Port|Signal) Details</b></caption>(.*?)</table>", seg, re.S):
                for r in re.findall(r"<tr[^>]*>.*?</tr>", tm.group(1), re.S):
                    cells = [strip(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)]
                    if len(cells) >= 4 and "No" in cells[1:4]:
                        dirs = "".join(cells[i][0] if cells[i] == "No" else "-" for i in range(1, 4))
                        items.append("%s (%s)" % (cells[0], dirs))
        if items:
            found_any = True
            print("### %s %s %s  (%d uncovered)" % (kind, lvl, name, len(items)))
            for it in items:
                print("    " + it)
if not found_any:
    print("CLEAN - no uncovered objects in requested metrics")
