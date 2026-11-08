#!/usr/bin/env python3
# scan_tgl_holes.py -- 解析 urg -format both 报告的 mod*.html, 只在
# <a name="..._Toggle"> 段内提取行 (toggle 位段), 列出全部洞 (No):
# 模块定义视图 + 每个实例视图.
#
# 与 scan_cov_holes.py 的区别: 旧版 ROW 正则不区分 metric, 同页 Line/
# Branch/FSM 表也被匹配 (计数虚高且归属错乱); 本版按段锚点切分, 实例名
# 取自段头 "Toggle Coverage for Instance : <a>路径</a>".
#
# 用法: python3 scan_tgl_holes.py <urg_report_dir> [模块名过滤]
import glob
import os
import re
import sys

repdir = sys.argv[1]
filt = sys.argv[2] if len(sys.argv) > 2 else None

SEC = re.compile(r'<a name="(?:inst_tag_\d+_)?Toggle"></a>')
TITLE = re.compile(
    r"Toggle Coverage for (Instance|Module(?: Instance)?) :\s*"
    r"<a[^>]*>([^<]+)")
ROW = re.compile(
    r'<td>([\w.\[\]:]+)</td>\s*'
    r'<td class="(?:s\d+ cl|wht cl)">(Yes|No|Excluded)</td>\s*'
    r'<td class="(?:s\d+ cl|wht cl)">(Yes|No|Excluded)</td>', re.S)

total_mod = total_inst = 0
for f in sorted(glob.glob(os.path.join(repdir, "mod*.html"))):
    html = open(f, encoding="utf-8", errors="replace").read()
    m = re.search(r"<title>(.*?)</title>", html, re.S)
    mod = m.group(1).replace("Unified Coverage Report :: ", "") \
        if m else os.path.basename(f)
    if filt and filt not in mod:
        continue
    heads = list(SEC.finditer(html))
    for hi, h in enumerate(heads):
        end = heads[hi + 1].start() if hi + 1 < len(heads) else len(html)
        seg = html[h.end():end]
        t = TITLE.search(seg[:500])
        kind, name = (t.group(1), t.group(2)) if t else ("?", "?")
        holes = [r.group(1) for r in ROW.finditer(seg)
                 if r.group(2) == "No" or r.group(3) == "No"]
        if not holes:
            continue
        tag = "%s [%s] / %s" % (mod, kind, name)
        print("== %s: %d hole(s)" % (tag, len(holes)))
        print("   " + "  ".join(holes))
        if kind == "Instance":
            total_inst += 1
        else:
            total_mod += 1

print("\nscan_tgl_holes: %d module-view, %d instance-view tables with holes"
      % (total_mod, total_inst))
