#!/usr/bin/env python3
# show_rows.py <report_dir> <instance-substr> [signal-substr]
# 列出 urg -format both 报告里指定实例的 Toggle 行 (0to1/1to0 方向列).
import glob
import re
import sys

repdir, sub = sys.argv[1], sys.argv[2]
sigsub = sys.argv[3] if len(sys.argv) > 3 else ""
SEC = re.compile(r'<a name="(?:inst_tag_\d+_)?Toggle"></a>')
TITLE = re.compile(
    r"Toggle Coverage for (Instance|Module(?: Instance)?) :\s*"
    r"<a[^>]*>([^<]+)")
ROW = re.compile(
    r'<td>([\w.\[\]:]+)</td>\s*'
    r'<td class="(?:s\d+ cl|wht cl)">(Yes|No|Excluded)</td>\s*'
    r'<td class="(?:s\d+ cl|wht cl)">(Yes|No|Excluded)</td>', re.S)

for f in sorted(glob.glob(repdir + "/mod*.html")):
    html = open(f, encoding="utf-8", errors="replace").read()
    heads = list(SEC.finditer(html))
    for hi, h in enumerate(heads):
        end = heads[hi + 1].start() if hi + 1 < len(heads) else len(html)
        seg = html[h.end():end]
        t = TITLE.search(seg[:500])
        if not t or sub not in t.group(2):
            continue
        print("== [%s] %s" % (t.group(1), t.group(2)))
        for r in ROW.finditer(seg):
            if sigsub in r.group(1) and (r.group(2) != "Yes"
                                         or r.group(3) != "Yes"):
                print("   %-14s 0to1=%-8s 1to0=%s"
                      % (r.group(1), r.group(2), r.group(3)))
