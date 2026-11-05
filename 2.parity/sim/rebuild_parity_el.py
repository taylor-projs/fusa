#!/usr/bin/env python3
# Rebuild 2.parity tgl_struct_excl.el after the edc_reg_wrap -> common
# reg_wrap switch (2026-11-05). Same algorithm as the cmm rebuild:
#   - every kept row re-emitted with the FRESH per-scope CHECKSUM and the
#     FRESH signal signature
#   - rows whose signal is no longer uncovered are RETIRED
#   - scopes that no longer exist are DROPPED
# Parity keeps ONE elfile holding both MODULE- and INSTANCE-domain blocks;
# the fresh instance dump and module dump are merged for lookup.
import re, os

OBJ = "/home/eda/work/parity/sim/obj_vcs"
OLD = "/home/eda/work/parity/sim/tgl_struct_excl.el"

ROW_RE      = re.compile(r'^Toggle\s+(?:(0to1|1to0)\s+)?(\S+?)((?:\s+\[[^\]]+\])*)\s+"([^"]*)"')
DUMP_ROW_RE = re.compile(r'^// Toggle\s+(?:(0to1|1to0)\s+)?(\S+?)((?:\s+\[[^\]]+\])*)\s+"([^"]*)"')

def norm_sel(sig, sel):
    sel = (sel or "").strip().replace(" ", "")
    return sig + (sel if sel else "")

def parse_el(path):
    blocks, cur = [], None
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln.startswith("CHECKSUM:"):
            cur = {"kind": None, "name": None, "rows": []}
            blocks.append(cur)
        elif ln.startswith("MODULE:") or ln.startswith("INSTANCE:"):
            kind, name = ln.split(":", 1)
            if cur is not None:
                cur["kind"], cur["name"] = kind.strip(), name.strip()
        else:
            m = ROW_RE.match(ln)
            if m and cur is not None:
                tr, sig, sel, sigline = m.groups()
                cur["rows"].append((tr, sig, (sel or "").strip(), sigline))
    return [b for b in blocks if b["kind"]]

def parse_dump(path):
    scopes, cur = {}, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r'^// CHECKSUM: "(\d+ \d+)"', ln)
        if m:
            cur = {"checksum": m.group(1), "sigs": {}, "hdr": None}
            continue
        m = re.match(r'^// (MODULE|INSTANCE): (.*)$', ln)
        if m:
            cur["hdr"] = ln[3:]
            scopes[m.group(1)[0] + ":" + m.group(2).rstrip()] = cur
            continue
        m = DUMP_ROW_RE.match(ln)
        if m and cur is not None:
            tr, sig, sel, sigline = m.groups()
            cur["sigs"][norm_sel(sig, sel)] = ln[3:]
    return scopes

def parse_uncovered(path):
    unc, hdr = {}, None
    for ln in open(path):
        m = re.match(r"Toggle Coverage for (Instance|Module) : (.*)", ln)
        if m:
            hdr = m.group(1)[0] + ":" + m.group(2).strip()
            unc.setdefault(hdr, set())
            continue
        m = re.match(r"Module Instance : (.*)", ln)
        if m:
            hdr = "I:" + m.group(1).strip()
            unc.setdefault(hdr, set())
            continue
        if hdr is None:
            continue
        m = re.match(r"^(\S+(?:\[[^\]]*\])*)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)\b", ln)
        if m:
            sig = m.group(1).replace(" ", "")
            full, d10, d01 = m.group(2), m.group(3), m.group(4)
            if full == "No" and d10 == "No" and d01 == "No":
                unc[hdr].add(sig)
            else:
                if d10 == "No":
                    unc[hdr].add(sig + ":1to0")
                if d01 == "No":
                    unc[hdr].add(sig + ":0to1")
    return unc

def main():
    unc = parse_uncovered(os.path.join(OBJ, "urg_report", "modinfo.txt"))
    scopes = parse_dump(os.path.join(OBJ, "fullexclude.tgl"))
    scopes.update(parse_dump(os.path.join(OBJ, "fullexclude_module.tgl")))
    out, stats = [], {"kept": 0, "retired": 0, "noscope": 0, "nosig": 0}
    for b in parse_el(OLD):
        key = b["kind"][0] + ":" + b["name"]
        sc = scopes.get(key)
        if sc is None:
            stats["noscope"] += len(b["rows"])
            print("DROP scope (not in fresh dump):", key)
            continue
        blk = ['CHECKSUM: "%s"' % sc["checksum"], sc["hdr"]]
        for tr, sig, sel, sigline in b["rows"]:
            ns = norm_sel(sig, sel)
            u = unc.get(key, set())
            still = ns in u or (tr and (ns + ":" + tr) in u)
            if not still and not sel:
                still = any(x.startswith(sig + "[") for x in u)
            if not still:
                stats["retired"] += 1
                print("RETIRE (now covered/absent): %s %s" % (key, ns))
                continue
            fresh = sc["sigs"].get(ns) or sc["sigs"].get(sig)
            if fresh is None:
                stats["nosig"] += 1
                print("WARN sig not in fresh dump scope: %s %s" % (key, ns))
                continue
            msig = re.search(r'"([^"]*)"$', fresh)
            blk.append("Toggle " + ((tr + " ") if tr else "") + sig +
                       ((" " + sel) if sel else "") + ' "%s"' % msig.group(1))
            stats["kept"] += 1
        if len(blk) > 2:
            out.append("\n".join(blk) + "\n")
    open(os.path.join(OBJ, "excl_new.el"), "w").write("\n".join(out))
    print(stats)

if __name__ == "__main__":
    main()
