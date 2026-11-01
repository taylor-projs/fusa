#!/usr/bin/env python3
# Survey uncovered (red) coverage objects from urg modinfo.txt (text report).
# Handles single- and multi-column branch tables. Prints compact red list.
import re, sys

MI = sys.argv[1] if len(sys.argv) > 1 else "modinfo.txt"
src = open(MI).read().splitlines()

cur_scope = None
cur_metric = None
out = []
br_srcline = "?"     # last source line no. seen inside a branch detail block

def emit(scope, metric, msg):
    out.append(f"{scope[0][:4]} {scope[1]} :: {metric} :: {msg}")

for idx, ln in enumerate(src):
    m = re.match(r"(Line|Toggle|FSM|Branch|Cond) Coverage for (Module|Instance) : (.*?)\s*$", ln)
    if m:
        cur_metric = m.group(1).upper()
        cur_scope = (m.group(2), m.group(3))
        continue
    if re.match(r"Toggle Coverage for (Module|Instance) self-instances", ln):
        continue
    if cur_metric == "TOGGLE" and cur_scope:
        m = re.match(r"^(\S+(?:\[[\d:]+\])?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)(?:\s+(INPUT|OUTPUT|INOUT))?\s*$", ln)
        if m and (m.group(2) == "No" or m.group(3) == "No" or m.group(4) == "No"):
            # columns: Toggle | Toggle 1->0 | Toggle 0->1 [| Direction]
            dirs = []
            if m.group(3) == "No": dirs.append("1to0")
            if m.group(4) == "No": dirs.append("0to1")
            emit(cur_scope, "TGL", f"{m.group(1)} miss:{'+'.join(dirs)}")
    if cur_metric == "LINE" and cur_scope:
        m = re.match(r"^(\d+)\s+(0/\d+)\s+==>\s*(.*)$", ln)
        if m:
            emit(cur_scope, "LINE", f"L{m.group(1)} [{m.group(2)}] {m.group(3).strip()[:90]}")
    if cur_metric == "BRANCH" and cur_scope:
        # track the source line number at the head of each detail block
        m = re.match(r"^(\d+)\s{4,}(\S.*)$", ln)
        if m and not ln.strip().startswith(("-1-", "==>")):
            br_srcline = m.group(1)
        # multi/single-column rows: sequences of 0/1/- then Covered/Not Covered
        m = re.match(r"^([01\-](?:\s+[01\-])*)\s+(Not Covered)\s*$", ln)
        if m:
            row = re.sub(r"\s+", "", m.group(1))
            emit(cur_scope, "BR", f"L{br_srcline} row[{row}]")

for l in out:
    print(l)
print(f"-- total red objects: {len(out)}")
