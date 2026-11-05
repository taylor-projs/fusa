#!/usr/bin/env python3
# Rebuild cmm toggle exclusion elfiles after the multi-channel cmm_core rewrite.
# Inputs (all on the VM):
#   OLD instance .el : excl/cmm_excl.tgl      (old final campaign set)
#   OLD module   .el : excl/cmm_excl_mod.tgl
#   FRESH instance dump: fullexclude.tgl      (urg -dump full_exclusions tgl)
#   FRESH module   dump: fullexclude_module.tgl
#   FRESH uncovered rows : urg_report/modinfo.txt  (no-excl urg run)
# Rules:
#   - scope path remap: u_regfile -> u_cmm_regfile (2026-11 例化命名清查)
#   - every kept row is re-emitted with the FRESH CHECKSUM (per scope) and
#     the FRESH signal signature (taken from the fresh dump line of that
#     signal in that scope)
#   - rows whose signal is no longer uncovered in the fresh report are
#     RETIRED (dropped) -- "旧项被覆盖后必须退役"
#   - rows whose scope no longer exists in the fresh dump are DROPPED with a
#     warning (stale hierarchy)
import re, sys, os

SIM = "/home/eda/work/cmm/sim"

# ---------------------------------------------------------------- parsing --
ROW_RE     = re.compile(r'^Toggle\s+(?:(0to1|1to0)\s+)?(\S+?)((?:\s+\[[^\]]+\])*)\s+"([^"]*)"')
DUMP_ROW_RE = re.compile(r'^// Toggle\s+(?:(0to1|1to0)\s+)?(\S+?)((?:\s+\[[^\]]+\])*)\s+"([^"]*)"')

def norm_sel(sig, sel):
    sel = (sel or "").strip().replace(" ", "")
    return sig + (sel if sel else "")   # sel already carries its brackets

def parse_el(path):
    """old .el -> list of blocks {kind,name,rows:[(tr,sig,sel,sigline)]}"""
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
    """fresh dump -> {kind_name: {"checksum":str, "sigs": {...}, "hdr": str}}"""
    scopes, cur = {}, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r'^// CHECKSUM: "(\d+ \d+)"', ln)
        if m:
            cur = {"checksum": m.group(1), "sigs": {}, "hdr": None}
            continue
        m = re.match(r'^// (MODULE|INSTANCE): (.*)$', ln)
        if m:
            # keep the RAW header text (trailing spaces are part of urg's
            # param-scoped module key - dropping them breaks matching)
            key = m.group(1)[0] + ":" + m.group(2).rstrip()
            cur["hdr"] = ln[3:].rstrip("\n")
            scopes[key] = cur
            continue
        m = DUMP_ROW_RE.match(ln)
        if m and cur is not None:
            tr, sig, sel, sigline = m.groups()
            cur["sigs"][norm_sel(sig, sel)] = ln[3:]
    return scopes

def parse_uncovered(path):
    """modinfo.txt -> {scope: set()} for Toggle sections; entries are
    '<sig>' when BOTH directions are missing, plus '<sig>:1to0' / '<sig>:0to1'
    when only one direction is missing (half-toggle rows)."""
    unc, hdr = {}, None
    for ln in open(path):
        m = re.match(r"Toggle Coverage for (Instance|Module) : (.*)", ln)
        if m:
            hdr = (m.group(1)[0] + ":" + m.group(2).strip())
            unc.setdefault(hdr, set())
            continue
        m = re.match(r"Module Instance : (.*)", ln)
        if m:
            # self-instance scope (dut / regfile self bins)
            hdr = "I:" + m.group(1).strip()
            unc.setdefault(hdr, set())
            continue
        if hdr is None:
            continue
        # columns: <sig> <Toggle> <Toggle 1->0> <Toggle 0->1> [Direction]
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

def map_path(name):
    return name.replace("u_regfile", "u_cmm_regfile")

# ---------------------------------------------------------------- rebuild --
def rebuild(old_path, dump_path, unc, kind_letter, extra=None):
    old = parse_el(old_path)
    scopes = parse_dump(dump_path)
    extra = extra or {}
    out, stats = [], {"kept": 0, "retired": 0, "noscope": 0, "nosig": 0}
    for b in old:
        name = map_path(b["name"])
        key = kind_letter + ":" + name
        sc = scopes.get(key)
        if sc is None:
            stats["noscope"] += len(b["rows"])
            print("DROP scope (not in fresh dump):", key)
            continue
        blk = ['CHECKSUM: "%s"' % sc["checksum"], sc["hdr"]]
        # ---- supplemental rows: uncovered structural bits that only exist
        # in the NEW hierarchy (no old counterpart), hand-classified ----
        for csig, csel in extra.get(key, []):
            u = unc.get(key, set())
            ns = norm_sel(csig, csel)
            if not (ns in u or any(x.startswith(ns) for x in u)):
                continue
            fresh = sc["sigs"].get(ns) or sc["sigs"].get(csig)
            if fresh is None:
                print("WARN extra sig not in dump: %s %s" % (key, ns))
                continue
            msig = re.search(r'"([^"]*)"$', fresh)
            blk.append("Toggle " + csig + ((" " + csel) if csel else "") +
                       ' "%s"' % msig.group(1))
            stats["kept"] += 1
        for tr, sig, sel, sigline in b["rows"]:
            # old local reg_wrap exposed flat data_q; the common reg_wrap
            # keeps it in a GRLIB struct -> r.data_q / rin.data_q
            cands = [sig]
            if sig == "data_q":
                cands = ["r.data_q", "rin.data_q"]
            elif sig == "wsel_q":
                cands = ["r_mb.wsel_q", "rin_mb.wsel_q"]
            emitted = False
            for csig in cands:
                ns = norm_sel(csig, sel)
                u = unc.get(key, set())
                still = ns in u or (tr and (ns + ":" + tr) in u)
                if not still and not sel:
                    # full-signal row: keep if ANY bit/part of the signal
                    # is still uncovered (old sets excluded whole vectors)
                    still = any(x.startswith(csig + "[") for x in u)
                if not still:
                    continue
                fresh = sc["sigs"].get(ns) or sc["sigs"].get(csig)
                if fresh is None:
                    stats["nosig"] += 1
                    print("WARN sig not in fresh dump scope: %s %s" % (key, ns))
                    continue
                msig = re.search(r'"([^"]*)"$', fresh)
                row = "Toggle " + ((tr + " ") if tr else "") + csig + \
                      ((" " + sel) if sel else "") + ' "%s"' % msig.group(1)
                blk.append(row)
                stats["kept"] += 1
                emitted = True
            if not emitted:
                stats["retired"] += 1
                print("RETIRE (now covered/absent): %s %s" % (key, norm_sel(sig, sel)))
        if len(blk) > 2:
            out.append("\n".join(blk) + "\n")
    return out, stats

WIN_CNT = [("r.win_cnt", "[15:8]"), ("rin.win_cnt", "[15:8]"),
           ("r.win_cnt_n", "[15:8]"), ("rin.win_cnt_n", "[15:8]")]
# win window length < 256 ref cycles in every TB config -> [15:8] never set;
# the counter moved from the per-channel mon (old excl target) into cmm_top
# in the multi-channel rewrite, so these rows have no old counterpart.

def main():
    unc = parse_uncovered(os.path.join(SIM, "urg_report", "modinfo.txt"))
    inst, s1 = rebuild(os.path.join(SIM, "excl", "cmm_excl.tgl"),
                       os.path.join(SIM, "fullexclude.tgl"), unc, "I",
                       extra={"I:tb_cmm_top.dut": WIN_CNT})
    mod,  s2 = rebuild(os.path.join(SIM, "excl", "cmm_excl_mod.tgl"),
                       os.path.join(SIM, "fullexclude_module.tgl"), unc, "M",
                       extra={"M:cmm_top": WIN_CNT})
    open(os.path.join(SIM, "excl_new_inst.tgl"), "w").write("\n".join(inst))
    open(os.path.join(SIM, "excl_new_mod.tgl"), "w").write("\n".join(mod))
    print("instance:", s1)
    print("module  :", s2)

if __name__ == "__main__":
    main()
