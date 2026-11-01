#!/usr/bin/env python3
# vcd_events.py - print rising/falling edge times (ns) of selected signals
# usage: vcd_events.py <file.vcd> <sig1> [sig2 ...]   (names as printed in VCD)
import sys, re

path, names = sys.argv[1], sys.argv[2:]
txt = open(path, 'r', errors='replace').read()

# id -> full hierarchical name
id2name, name2id = {}, {}
scope = []
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('$scope'):
        scope.append(line.split()[2])
    elif line.startswith('$upscope'):
        scope.pop()
    elif line.startswith('$var'):
        p = line.split()
        w, vid, nm = p[2], p[3], p[4]
        full = '.'.join(scope[1:] + [nm]) if len(scope) > 1 else nm
        # drop the TB top scope for readability
        full = nm if not scope[1:] else '.'.join(scope[1:] + [nm])
        id2name[vid] = full
        name2id.setdefault(full, vid)
    elif line.startswith('$enddefinitions'):
        break

ids = []
for n in names:
    if n in name2id:
        ids.append((name2id[n], n))
    else:
        cand = [v for k, v in name2id.items() if k.endswith('.' + n) or k == n]
        if cand:
            ids.append((cand[0], n))
        else:
            print(f'NOT FOUND: {n}', file=sys.stderr)

want = {vid for vid, _ in ids}
vals = {}
t = 0
out = []
for line in txt.splitlines():
    line = line.strip()
    if line.startswith('#'):
        t = int(line[1:]) / 1000.0  # ps -> ns
    elif line and line[0] in '01xz' and line[1:] in want:
        v = line[0]
        if vals.get(line[1:]) != v:
            vals[line[1:]] = v
            out.append((t, line[1:], v))
    elif line.startswith('b') and ' ' in line:
        v, vid = line[1:].split(' ', 1)
        if vid in want and vals.get(vid) != v:
            vals[vid] = v
            out.append((t, vid, v))

idr = {vid: n for vid, n in ids}
for t, vid, v in out:
    print(f'{t:10.1f} ns  {idr[vid]:60s} = {v}')
