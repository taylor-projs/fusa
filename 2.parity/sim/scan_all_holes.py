#!/usr/bin/env python3
# urg 报告 modinfo.txt 未覆盖对象扫描 (line/cond/branch/toggle)
# 用法: python3 scan_holes.py <report_dir> [--mod]
#   默认扫全部段; --mod 只看 Module 段 (模块定义域)
import os, re, sys

rep = sys.argv[1]
only_mod = "--mod" in sys.argv
path = os.path.join(rep, "modinfo.txt")

line_re = re.compile(r"^\s*(\d+)\s+0/\d+\s")
ln_hdr_re = re.compile(r"^\s*LINE\s+(\d+)\s*$")
expr_re = re.compile(r"^\s*EXPRESSION\s+(.*)$")
tbl_re = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
src_re = re.compile(r"^\s*(\d+)\s+\S")
tgl_re = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                    r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
ob_re = re.compile(r"^\s*Other bits of (\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                   r"\s*$")

hdr, metric, dom = None, None, None
cur_line, cur_expr = None, None
out = []
for raw in open(path, encoding="utf-8", errors="replace"):
    ln = raw.rstrip("\n")
    m = re.match(r"^(Line|Cond|Branch|Toggle) Coverage for "
                 r"(Instance|Module) : (.*)$", ln)
    if m:
        metric, dom = m.group(1), m.group(2)
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(3).strip())
        cur_line, cur_expr = None, None
        continue
    if hdr is None or metric is None:
        continue
    if only_mod and dom != "Module":
        continue
    if metric == "Line":
        m2 = line_re.match(ln)
        if m2:
            out.append("[%s %s] line %s" % (dom, hdr, m2.group(1)))
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
                out.append("[%s %s] cond L%s '%s' %s"
                           % (dom, hdr, cur_line, (cur_expr or "?")[:50],
                              "".join(m2.group(1).split())))
    elif metric == "Branch":
        m2 = src_re.match(ln)
        if m2 and not tbl_re.match(ln):
            cur_line = m2.group(1)     # 记最近源行 (分支组锚)
            continue
        m2 = tbl_re.match(ln)
        if m2 and m2.group(2) == "Not Covered" and cur_line:
            out.append("[%s %s] branch@L%s %s"
                       % (dom, hdr, cur_line, ",".join(m2.group(1).split())))
    elif metric == "Toggle":
        m2 = tgl_re.match(ln) or ob_re.match(ln)
        if m2 and "No" in (m2.group(2), m2.group(3), m2.group(4)):
            out.append("[%s %s] tgl %s %s%s%s"
                       % (dom, hdr, m2.group(1), m2.group(2)[0],
                          m2.group(3)[0], m2.group(4)[0]))
for o in out:
    print(o)
print("total holes:", len(out))
