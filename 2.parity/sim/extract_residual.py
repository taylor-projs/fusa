#!/usr/bin/env python3
# 从 urg modinfo.txt 提取 toggle 未全覆盖残量 (实例级):
# 解析 "Toggle Coverage for Instance : <path>" 段的 Port/Signal Details,
# 任一方向为 No 的行 = 一行残量. Excluded 行自动跳过.
# 用法: python3 extract_residual.py urg_report_excl/modinfo.txt > residual.txt
import sys, re

inst = None
sec = None
n = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    m = re.match(r"Toggle Coverage for Instance : (\S+?)(\(x\))?\s*$", line)
    if m:
        inst = m.group(1)
        sec = None
        continue
    if line.startswith("Toggle Coverage for Module"):
        inst = None
        sec = None
        continue
    if inst is None:
        continue
    if line.startswith("Port Details"):
        sec = "port"
        continue
    if line.startswith("Signal Details"):
        sec = "sig"
        continue
    if line.startswith("====") or line.startswith("----"):
        sec = None
        continue
    if sec in ("port", "sig"):
        f = line.split()
        if f and f[-1] in ("INPUT", "OUTPUT", "INOUT"):
            triple, name = f[-4:-1], f[:-4]
        else:
            triple, name = f[-3:], f[:-3]
        if len(triple) == 3 and all(t in ("Yes", "No") for t in triple) and name:
            if "No" in triple:
                dirs = "".join("0" if t == "No" else "1" for t in triple)
                print(f"{inst} :: {sec} :: {' '.join(name).strip()} :: {dirs}")
                n += 1
print(f"# total residual rows: {n}", file=sys.stderr)
