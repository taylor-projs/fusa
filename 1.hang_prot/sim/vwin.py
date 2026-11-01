#!/usr/bin/env python3
# vwin.py - filter vcd_events output to a time window: vwin.py <lo> <hi>
import sys
lo, hi = float(sys.argv[1]), float(sys.argv[2])
for l in sys.stdin:
    try:
        t = float(l.split()[0])
    except ValueError:
        continue
    if lo <= t <= hi:
        sys.stdout.write(l)
