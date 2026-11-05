#!/usr/bin/env python3
# Rebuild cmm line/cond/branch/fsm exclusion elfiles after the multi-channel
# rewrite. Rows in these metrics are content-keyed (source expression text +
# urg content hash), so old rows are matched against the fresh dump by the
# row TAIL after the leading "<Keyword> <lineno>" - line shifts between old
# and new RTL therefore do not matter. Stale scopes (cmm_clk_dut_mon/_chk -
# deleted modules) and stale rows drop out automatically.
# FSM: the rewritten cmm_top keeps fsm_state as a struct field reset by the
# full REF_REG_RST struct load; urg models the reset constant as a pseudo
# state (the 95'b blob) -> its 6 transitions are structural artifacts and
# are excluded together with the by-design unreachable ARM->ERR.
import re, os

SIM = "/home/eda/work/cmm/sim"
KW  = r"(?:Block|Condition|Branch|Fsm|Transition)"

def parse_blocks(path, active_only=True):
    """-> [ {kind,name,rows:[(head, tail)]} ] head='Keyword <n>', tail=rest"""
    blocks, cur, rows = [], None, []
    def flush():
        nonlocal cur, rows
        if cur and rows:
            blocks.append({"kind": cur[0], "name": cur[1], "rows": rows})
        rows = []
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln.startswith("CHECKSUM:"):
            flush(); cur = None
        elif ln.startswith("MODULE:") or ln.startswith("INSTANCE:"):
            k, n = ln.split(":", 1)
            cur = (k.strip(), n.strip())
        else:
            cm = (not active_only) or not ln.startswith("//")
            m = re.match(r"^(?:// )?(%s) (\d+) (.*)$" % KW, ln) if "Block" in ln or True else None
            m2 = re.match(r"^(?:// )?(Fsm|Transition) (.*)$", ln)
            if cm and m2 and not m:
                rows.append((m2.group(1), m2.group(2)))
            elif cm and m:
                rows.append((m.group(1) + " " + m.group(2), m.group(3)))
    flush()
    return blocks

def parse_fresh(path):
    scopes, cur = {}, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r'^// CHECKSUM: "(\d+ \d+)"', ln)
        if m:
            cur = {"checksum": m.group(1), "hdr": None, "rows": []}
            continue
        m = re.match(r"^// (MODULE|INSTANCE): (.*)$", ln)
        if m:
            cur["hdr"] = ln[3:]
            scopes[m.group(1)[0] + ":" + m.group(2).rstrip()] = cur
            continue
        m = re.match(r"^// (%s) (\d+) (.*)$" % KW, ln)
        if m and cur is not None:
            cur["rows"].append((m.group(1) + " " + m.group(2), m.group(3), ln[3:]))
            continue
        m = re.match(r"^// (Fsm|Transition) (.*)$", ln)
        if m and cur is not None:
            cur["rows"].append((m.group(1), m.group(2), ln[3:]))
    return scopes

def nohash(tail):
    """drop the urg content-hash right after Keyword <n> - it changes between
    compiles even for identical expressions"""
    return re.sub(r'^"\d+" ', "", tail)

def rebuild(metric, old_file, fresh_file, fsm_all=False):
    old = parse_blocks(os.path.join(SIM, "excl", old_file))
    # a dump run writes BOTH domains: fullexclude.<m> (instance) and
    # fullexclude_module.<m> (module definition) - merge them
    fresh = parse_fresh(os.path.join(SIM, fresh_file))
    fresh.update(parse_fresh(os.path.join(SIM, fresh_file.replace(".dump", "_mod.dump"))))
    out, kept, dropped = [], 0, 0
    if fsm_all:
        # emit one block per scope (instance AND module domains) that carries
        # the FSM: artifact transitions of the struct-reset pseudo state (the
        # 95'b blob = REF_REG_RST constant) + by-design unreachable ARM->ERR;
        # the four lifecycle arcs stay measured
        for key, sc in fresh.items():
            if not any(h == "Fsm" for h, t, raw in sc["rows"]):
                continue
            blk = ['CHECKSUM: "%s"' % sc["checksum"], sc["hdr"],
                   "Fsm r.fsm_state \"1592279044\""]
            for h, t, raw in sc["rows"]:
                if not raw.startswith("Transition"):
                    continue
                if re.match(r"Transition (FSM_ARM->FSM_RUN|FSM_ERR->FSM_ARM"
                            r"|FSM_RUN->FSM_ARM|FSM_RUN->FSM_ERR) ", raw):
                    continue
                blk.append(raw); kept += 1
            out.append("\n".join(blk) + "\n")
    else:
        for b in old:
            name = b["name"].replace("u_regfile", "u_cmm_regfile")
            key = ("M" if b["kind"] == "MODULE" else "I") + ":" + name
            sc = fresh.get(key)
            if sc is None:
                dropped += len(b["rows"])
                print("DROP scope:", key)
                continue
            blk = ['CHECKSUM: "%s"' % sc["checksum"], sc["hdr"]]
            tails = {}
            for h, t, raw in sc["rows"]:
                tails.setdefault(nohash(t), raw)
            for head, tail in b["rows"]:
                raw = tails.get(nohash(tail))
                if raw is None:
                    dropped += 1
                    print("  stale %s row in %s: %s %s" % (metric, key, head, tail[:60]))
                    continue
                blk.append(raw); kept += 1
            if len(blk) > 2:
                out.append("\n".join(blk) + "\n")
    open(os.path.join(SIM, "excl_new_%s.el" % metric), "w").write("\n".join(out))
    print("%s: kept %d rows, dropped %d" % (metric, kept, dropped))

rebuild("line",   "cmm_excl.line",   "fresh_line.dump")
rebuild("cond",   "cmm_excl.cond",   "fresh_cond.dump")
rebuild("branch", "cmm_excl.branch", "fresh_branch.dump")
rebuild("fsm",    "cmm_excl.fsm",    "fresh_fsm.dump", fsm_all=True)
