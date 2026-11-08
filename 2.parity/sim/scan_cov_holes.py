#!/usr/bin/env python3
# scan_cov_holes.py -- 解析 urg -format both 报告的 mod*.html, 列出全部
# toggle 洞 (No 的位段): 模块定义视图 + 每个实例视图.
#
# 用法: python3 scan_cov_holes.py <urg_report_dir> [模块名过滤]
import glob
import os
import re
import sys

repdir = sys.argv[1]
filt = sys.argv[2] if len(sys.argv) > 2 else None

ROW = re.compile(
    r'<td>([\w.\[\]:]+)</td>\s*<td class="(?:s\d+ cl|wht cl)">(Yes|No|Excluded)'
    r'</td>\s*<td class="(?:s\d+ cl|wht cl)">(?:Yes|No|Excluded)</td>'
    r'\s*<td class="(?:s\d+ cl|wht cl)">(?:Yes|No|Excluded)</td>', re.S)
INST = re.compile(r"showContent\('inst_tag_\d+(_Toggle)?'\)[^>]*>([\w.\$\[\]:]+)")


def tables(html):
    """yield (label, [(sig, status), ...]) -- label=None 为模块级表"""
    anchors = [(m.start(), m.group(2)) for m in INST.finditer(html)]
    out = {}
    order = []
    ai = -1
    label = None
    for m in ROW.finditer(html):
        while ai + 1 < len(anchors) and anchors[ai + 1][0] < m.start():
            ai += 1
            label = anchors[ai][1]
        if label not in out:
            out[label] = []
            order.append(label)
        out[label].append((m.group(1), m.group(2)))
    for lab in order:
        yield lab, out[lab]


total_mod = total_inst = 0
for f in sorted(glob.glob(os.path.join(repdir, "mod*.html"))):
    html = open(f, encoding="utf-8", errors="replace").read()
    m = re.search(r"<title>(.*?)</title>", html, re.S)
    mod = m.group(1) if m else os.path.basename(f)
    if filt and filt not in mod:
        continue
    seen = set()
    for label, rows in tables(html):
        holes = [s for s, st in rows if st == "No"]
        if not holes:
            continue
        key = (label, tuple(holes))
        if key in seen:      # 重复段 (锚点交叉) 去重
            continue
        seen.add(key)
        tag = "%s / %s" % (mod, label) if label else "%s / MODULE" % mod
        print("== %s: %d hole(s)" % (tag, len(holes)))
        print("   " + "  ".join(holes))
        if label:
            total_inst += 1
        else:
            total_mod += 1
print("\nscan_cov_holes: %d module-view, %d instance-view tables with holes"
      % (total_mod, total_inst))
