#!/usr/bin/env python3
"""Build parity structural exclusions from a RAW merged urg report.

Only raw holes which can be proved unreachable are emitted.  Any unclassified
hole is fatal.  Condition exclusions additionally require a value contradiction
against a toggle-proven constant operand; hard-to-cover XOR rows are not enough.

Run from sim/ after run_vcs.sh and fresh full_exclusions dumps:
  python3 gen_parity_excl.py
"""
import collections
import os
import re
import sys

SIM = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(SIM, "obj_vcs", "urg_report", "modinfo.txt")
DUMP_DIRS = [os.path.join(SIM, "obj_vcs"), os.path.join(SIM, "obj_vcs_side")]
TGL_OUT = os.path.join(SIM, "tgl_struct_excl.el")
MISC_OUT = os.path.join(SIM, "misc_struct_excl.el")


def norm_expr(s):
    return re.sub(r"\s+", "", s or "")


def sig_parts(sig):
    m = re.match(r"^([\w.]+)(?:\[(\d+)(?::(\d+))?\])?$", sig)
    if not m:
        raise ValueError("unsupported toggle row: " + sig)
    base = m.group(1)
    if m.group(2) is None:
        return base, None
    hi = int(m.group(2))
    lo = int(m.group(3)) if m.group(3) is not None else hi
    return base, set(range(lo, hi + 1))


def params_of(scope):
    text = scope.get("module", "") + " " + scope["hdr"]
    return {k: int(v) for k, v in re.findall(r"\b([A-Z_][A-Z0-9_]*)=(\d+)", text)}


def base_module(scope):
    text = scope.get("module", "") or scope["hdr"]
    m = re.search(r"\b([A-Za-z_]\w*)", text)
    return m.group(1) if m else "?"


# ---------------------------------------------------------------------------
# Fresh full_exclusions dump parsing
# ---------------------------------------------------------------------------
def parse_dump(path, metric, kind):
    scopes = []
    cur = None
    pending_checksum = None
    pending_module = ""
    cur_line = None
    prefixes = {"tgl": "Toggle ", "cond": "Condition ",
                "line": "Block ", "branch": "Branch "}
    prefix = prefixes[metric]
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            if not raw.startswith("//"):
                continue
            ln = raw[3:] if raw.startswith("// ") else raw[2:]
            ln = ln.rstrip("\n")
            m = re.match(r"CHECKSUM:\s+(\"[^\"]+\")", ln)
            if m:
                pending_checksum = m.group(1)
                continue
            m = re.match(r"ANNOTATION:\s+\"ModuleName:\s*(.*)\"", ln)
            if m:
                pending_module = m.group(1)
                continue
            m = re.match(r"(INSTANCE|MODULE):\s*(.*)$", ln)
            if m and m.group(1) == kind:
                cur = {"kind": kind, "name": m.group(2).rstrip(),
                       "hdr": ln.rstrip(), "key": ln.rstrip(),
                       "checksum": pending_checksum,
                       "module": pending_module, "rows": [], "decls": {}}
                scopes.append(cur)
                cur_line = None
                continue
            if cur is None:
                continue
            m = re.match(r"ANNOTATION:.*LineNumber:\s*(\d+)\"", ln)
            if m:
                cur_line = int(m.group(1))
                continue
            if ln.startswith(prefix):
                cur["rows"].append({"line": cur_line, "text": ln})
                if metric == "tgl":
                    dm = re.search(r'"([^"]*)"$', ln)
                    body = ln[len(prefix):].split('"')[0].strip()
                    body = re.sub(r"^(?:0to1|1to0)\s+", "", body)
                    sig = body.split()[0]
                    base = sig.split("[")[0]
                    if dm:
                        cur["decls"][base] = dm.group(1)
    return scopes


def load_dumps():
    # metric -> instance scopes / module-definition scopes
    dumps = {}
    for metric, ext in (("tgl", "tgl"), ("cond", "cond"),
                        ("line", "line"), ("branch", "branch")):
        inst, mod = {}, {}
        seen_mod = set()
        for dd in DUMP_DIRS:
            for kind, fn in (("INSTANCE", "fullexclude." + ext),
                             ("MODULE", "fullexclude_module." + ext)):
                path = os.path.join(dd, fn)
                if not os.path.exists(path):
                    raise SystemExit("missing fresh dump: " + path)
                for sc in parse_dump(path, metric, kind):
                    if kind == "INSTANCE":
                        if sc["key"] in inst:
                            raise SystemExit("duplicate instance dump scope: " + sc["key"])
                        inst[sc["key"]] = sc
                    else:
                        k = (sc["key"], sc["checksum"])
                        if k not in seen_mod:
                            seen_mod.add(k)
                            mod.setdefault(base_module(sc), []).append(sc)
        dumps[metric] = {"I": inst, "M": mod}
    return dumps


# ---------------------------------------------------------------------------
# Raw modinfo parsing.  Module self-instances is intentionally never a scope.
# ---------------------------------------------------------------------------
def parse_raw(path):
    holes = []
    metric = dom = hdr = None
    cur_line = None
    cur_expr = None
    cur_terms = []
    in_terms = False
    branch_lines = set()
    line_re = re.compile(r"^\s*(\d+)\s+0/\d+\s")
    ln_hdr_re = re.compile(r"^\s*LINE\s+(\d+)\s*$")
    expr_re = re.compile(r"^\s*EXPRESSION\s+(.*)$")
    tbl_re = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
    tgl_re = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                        r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
    ob_re = re.compile(r"^\s*Other bits of\s+")
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            ln = raw.rstrip("\n")
            m = re.match(r"^(Line|Cond|Branch|Toggle) Coverage for "
                         r"(Instance|Module) : (.*)$", ln)
            if m:
                metric = m.group(1)
                dom = "I" if m.group(2) == "Instance" else "M"
                hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(3).strip())
                cur_line = cur_expr = None
                cur_terms = []
                in_terms = False
                branch_lines = set()
                continue
            if hdr is None:
                continue
            if metric == "Line":
                m = line_re.match(ln)
                if m:
                    holes.append({"metric": "line", "dom": dom, "scope": hdr,
                                  "line": int(m.group(1))})
            elif metric == "Toggle":
                if ob_re.match(ln):
                    raise SystemExit("Other-bits toggle row needs explicit expansion: " + ln)
                m = tgl_re.match(ln)
                if m and "No" in (m.group(2), m.group(3), m.group(4)):
                    holes.append({"metric": "tgl", "dom": dom, "scope": hdr,
                                  "sig": m.group(1),
                                  "dirs": m.group(2)[0] + m.group(3)[0] + m.group(4)[0]})
            elif metric == "Cond":
                m = ln_hdr_re.match(ln)
                if m:
                    cur_line = int(m.group(1))
                    cur_expr = None
                    cur_terms = []
                    in_terms = False
                    continue
                m = expr_re.match(ln)
                if m:
                    cur_expr = re.sub(r"\s+", " ", m.group(1)).strip()
                    cur_terms = []
                    in_terms = False
                    continue
                if re.match(r"^\s*Number\s+Term\s*$", ln):
                    in_terms = True
                    continue
                if "Status" in ln and re.match(r"^\s*-1-", ln):
                    in_terms = False
                m = tbl_re.match(ln)
                if m and m.group(2) == "Not Covered" and cur_line is not None:
                    holes.append({"metric": "cond", "dom": dom, "scope": hdr,
                                  "line": cur_line, "expr": cur_expr or "",
                                  "terms": list(cur_terms),
                                  "vec": "".join(m.group(1).split())})
                    continue
                if in_terms:
                    m = re.match(r"^\s*(\d+)\s+(.+?)\s*$", ln)
                    if m and not tbl_re.match(ln):
                        cur_terms.append(m.group(2))
            elif metric == "Branch":
                # Summary rows name the source line of each decision group.
                m = re.match(r"^\s*\S+\s+(\d+)\s+\d+\s+\d+\s+\d+(?:\.\d+)?\s*$", ln)
                if m and not tbl_re.match(ln):
                    branch_lines.add(int(m.group(1)))
                    continue
                m = re.match(r"^\s*(\d+)\s+\S", ln)
                if m and not tbl_re.match(ln) and int(m.group(1)) in branch_lines:
                    cur_line = int(m.group(1))
                    continue
                m = tbl_re.match(ln)
                if m and m.group(2) == "Not Covered" and cur_line is not None:
                    holes.append({"metric": "branch", "dom": dom, "scope": hdr,
                                  "line": cur_line,
                                  "vec": ",".join(m.group(1).split())})
    return holes


# ---------------------------------------------------------------------------
# Toggle structural whitelist.  Returns (family, constant value) or None.
# ---------------------------------------------------------------------------
FOLLOWERS = {"u_err_st", "u_fault_st", "u_err2", "u_fault2",
             "u_cfg_en", "u_cfg_force", "u_cfg_irqen"}
ERR_FOLLOWERS = {"u_err_st", "u_fault_st", "u_err2", "u_fault2"}
STATE_WRAPS = {"u_w_sta_err", "u_w_sta_fault", "u_w_sta_parc", "u_w_sta_rail"}
RF_HALFSIGS = {"site_err", "err_st", "fault_st", "err_nxt", "fault_nxt",
               "err_s1", "fault_s1", "err_s2", "fault_s2"}
DATA_SIGS = {"wdata", "rdata", "r.data_q", "rin.data_q"}
PARITY_MIN = [0, 0, 1, 4, 11, 26, 57]


def is_gen_site(path):
    return path and (".g_req_gen." in path or ".g_rsp_gen." in path)


def side_half(path, bits):
    if bits is None:
        return False
    if path.startswith("tb_edc_side.u_ms."):
        return bits and max(bits) <= 12
    if path.startswith("tb_edc_side.u_sl."):
        return bits and min(bits) >= 13 and max(bits) <= 17
    return False


def tgl_family(scope, sig, dom):
    path = scope["name"] if dom == "I" else None
    mod = base_module(scope)
    p = params_of(scope)
    dw, edcw = p.get("DW"), p.get("EDCW")
    base, bits = sig_parts(sig)

    def const_if(ok, family, value=0):
        return (family, value) if ok else None

    if mod in ("edc_core", "edc_regfile", "edc_top") and base == "addr":
        return const_if(bits is not None and
                        (max(bits) <= 1 or min(bits) >= 10), "ADDR_DECODE")
    if mod == "nuclei300_edc_gen":
        if base == "t_dat" and dw is not None:
            return const_if(bits is not None and min(bits) >= min(dw, 64)
                            and max(bits) <= 63, "ZERO_EXT")
        if base == "t_edc" and dw is not None:
            return const_if(bits is not None and
                            all(dw <= PARITY_MIN[b] for b in bits), "ZERO_EXT_XOR")
    if mod == "nuclei300_edc_chk":
        if is_gen_site(path) and dw == 64 and base in ("edc", "t_edc"):
            return const_if(bits is None or max(bits) < edcw, "DW64_EDC_SLOT")
        if base == "t_dat" and dw is not None:
            return const_if(bits is not None and min(bits) >= min(dw, 64)
                            and max(bits) <= 63, "ZERO_EXT")
        if base == "t_edc" and edcw is not None:
            return const_if(bits is not None and min(bits) >= edcw
                            and max(bits) <= 6, "ZERO_EXT")
        if base == "syndrome" and dw is not None and edcw is not None:
            return const_if(bits is not None and
                            all(b >= edcw and dw <= PARITY_MIN[b] for b in bits),
                            "ZERO_EXT_XOR")
    if mod == "nuclei300_edc_chk_fault_ej":
        pw = p.get("PW", edcw)
        force_bit = 128 - dw - pw if dw is not None and pw is not None else None
        if base == "einj_pos":
            return const_if(bits is not None and min(bits) >= 64
                            and max(bits) <= 127, "INJ_ZERO_EXT")
        if base == "einj_force_err":
            return const_if(bits is not None and force_bit not in bits
                            and min(bits) >= 0 and max(bits) <= 127,
                            "INJ_ONEHOT")
        if base == "edc" and is_gen_site(path):
            return const_if(bits is None or max(bits) < edcw, "GEN_INPUT_TIEOFF")
        if base == "edc_ej" and is_gen_site(path) and dw == 64:
            return const_if(bits is None or max(bits) < edcw, "DW64_EDC_SLOT")
    if mod == "edc_site":
        pw = edcw
        force_bit = 128 - dw - pw if dw is not None and pw is not None else None
        if base in ("inj_pos_e", "inj_pos_g"):
            return const_if(bits is not None and min(bits) >= 64
                            and max(bits) <= 127, "INJ_ZERO_EXT")
        if base == "inj_force_v":
            return const_if(bits is not None and force_bit not in bits
                            and min(bits) >= 0 and max(bits) <= 127,
                            "INJ_ONEHOT")
        if base == "gen_msk" and dw == 64:
            return const_if(bits is not None and max(bits) <= 6,
                            "DW64_EDC_SLOT")
        if base == "i_edc" and is_gen_site(path):
            return const_if(bits is None or max(bits) < edcw, "GEN_INPUT_TIEOFF")
        if base == "o_err" and is_gen_site(path):
            return const_if(bits is None or bits == {0}, "GEN_LOCAL_ERR_TIEOFF")
    if mod == "edc_regfile":
        if base in ("r.wsel_q", "rin.wsel_q"):
            return const_if(bits == {4}, "WSEL_DEAD_DECODE")
        if base == "perr":
            return const_if(bits in ({4}, {10}), "RETIRED_PERR_GROUP")
        if base in RF_HALFSIGS and dom == "I":
            return const_if(side_half(path, bits), "SIDE_GEN_HALF")
    if mod == "sync_dff" and base in ("d", "q") and dom == "I":
        return const_if(side_half(path, bits), "SIDE_GEN_HALF")
    if mod == "edc_core":
        if path in ("tb_edc_top.dut0", "tb_edc_top.dut1"):
            if base in ("awuser_o", "wuser_o", "aruser_o", "buser_o", "ruser_o"):
                return const_if(True, "OBSERVER_USER_TIEOFF")
        if path == "tb_edc_side.u_ms":
            if base in ("awuser", "wuser", "aruser", "buser_o", "ruser_o", "req_site_err"):
                return const_if(True, "SIDE_DIRECTION_TIEOFF")
            if base == "site_err_g":
                return const_if(bits is not None and max(bits) <= 12, "SIDE_GEN_HALF")
        if path == "tb_edc_side.u_sl":
            if base in ("buser", "ruser", "awuser_o", "wuser_o", "aruser_o", "rsp_site_err"):
                return const_if(True, "SIDE_DIRECTION_TIEOFF")
            if base == "site_err_g":
                return const_if(bits is not None and min(bits) >= 13
                                and max(bits) <= 17, "SIDE_GEN_HALF")
    if mod == "edc_top":
        if base in ("sta_err_r", "sta_fault_r", "sta_parc_r", "sta_rail_r"):
            return const_if(bits is not None and min(bits) >= 2
                            and max(bits) <= 31, "NUM_CORE_ZERO_EXT")
        if base == "sta_par_rb":
            return const_if(bits is not None and min(bits) >= 8
                            and max(bits) <= 31, "NUM_CORE_ZERO_EXT")
        if base == "rdata":
            return const_if(bits is not None and
                            all(b >= 8 and ((0xEDC02002 >> b) & 1) == 0 for b in bits),
                            "READ_MUX_CONSTANT")
    if mod == "reg_wrap":
        leaf = path.split(".")[-1] if path else ""
        if base == "wr" and leaf in FOLLOWERS:
            return const_if(bits is None, "FOLLOWER_WR_TIE1", 1)
        if base in DATA_SIGS and leaf in STATE_WRAPS:
            return const_if(bits is not None and min(bits) >= 2
                            and max(bits) <= 31, "NUM_CORE_ZERO_EXT")
        if base in DATA_SIGS and leaf in ERR_FOLLOWERS and dom == "I":
            return const_if(side_half(path, bits), "SIDE_GEN_HALF")
    if mod == "rst_sync" and base == "scan_mode":
        return const_if(bits is None, "SCAN_MODE_TIE0")
    return None


# ---------------------------------------------------------------------------
# EL block/constant-map helpers
# ---------------------------------------------------------------------------
def block_key(scope):
    return scope["key"], scope["checksum"], scope["hdr"]


def add_row(blocks, scope, row):
    key = block_key(scope)
    blocks[key]["rows"].add(row)


def put_const(consts, scope, sig, value):
    base, bits = sig_parts(sig)
    ent = consts[scope["key"]].setdefault(base, {"whole": None, "bits": {}})
    if bits is None:
        if ent["whole"] is not None and ent["whole"] != value:
            raise SystemExit("conflicting constant: %s %s" % (scope["key"], base))
        ent["whole"] = value
    else:
        for b in bits:
            if b in ent["bits"] and ent["bits"][b] != value:
                raise SystemExit("conflicting constant bit: %s %s[%d]" %
                                 (scope["key"], base, b))
            ent["bits"][b] = value


def const_operand(consts, scope_key, operand):
    operand = strip_parens(operand.strip())
    operand = re.sub(r"(?:\|\||&&|\^|\||&)\s*$", "", operand).strip()
    operand = operand.rstrip(")").lstrip("(").strip()
    m = re.match(r"^([~!]*)\s*([\w.]+?)(?:\[(\d+)\])?$", operand)
    if not m:
        # Common constant literals in ternaries/conditions.
        lit = re.match(r"^(?:1'b([01])|'0)$", operand)
        if lit:
            return 0 if operand == "'0" else int(lit.group(1))
        return None
    inv = len(m.group(1)) % 2
    base = m.group(2)
    bit = int(m.group(3)) if m.group(3) is not None else None
    ent = consts.get(scope_key, {}).get(base)
    if not ent:
        return None
    val = ent["whole"] if bit is None else ent["bits"].get(bit, ent["whole"])
    if bit is None and val is None and set(ent["bits"]) == {0}:
        val = ent["bits"][0]
    if val is None:
        return None
    return val ^ inv


def strip_parens(s):
    s = s.strip()
    while s.startswith("(") and s.endswith(")"):
        depth = 0
        wraps = True
        for i, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and i != len(s) - 1:
                    wraps = False
                    break
        if not wraps:
            break
        s = s[1:-1].strip()
    return s


def split_operands(expr, n):
    s = strip_parens(expr)
    parts, start, depth = [], 0, 0
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif depth == 0:
            op = None
            if s.startswith("||", i) or s.startswith("&&", i):
                op = 2
            elif ch in "^|&" and i > start:
                op = 1
            if op:
                parts.append(s[start:i].strip())
                i += op
                start = i
                continue
        i += 1
    parts.append(s[start:].strip())
    return parts if len(parts) == n else []


# ---------------------------------------------------------------------------
# Build toggle exclusions and the per-instance constant proof map.
# ---------------------------------------------------------------------------
def build_toggle(raw_holes, dumps):
    blocks = collections.defaultdict(lambda: {"rows": set()})
    consts = collections.defaultdict(dict)
    unclassified = []
    family_counts = collections.Counter()
    for h in raw_holes:
        if h["dom"] == "I":
            candidates = [dumps["tgl"]["I"].get("INSTANCE: " + h["scope"])]
        else:
            candidates = dumps["tgl"]["M"].get(h["scope"], [])
        emitted = 0
        for sc in candidates:
            if sc is None:
                continue
            proof = tgl_family(sc, h["sig"], h["dom"])
            if proof is None or h["dirs"] != "NNN":
                continue
            base, _ = sig_parts(h["sig"])
            decl = sc["decls"].get(base)
            if decl is None:
                continue
            sig_text = h["sig"]
            m = re.match(r"^([\w.]+)(\[[^\]]+\])$", sig_text)
            if m:
                sig_text = m.group(1) + " " + m.group(2)
            add_row(blocks, sc, 'Toggle %s "%s"' % (sig_text, decl))
            if h["dom"] == "I":
                put_const(consts, sc, h["sig"], proof[1])
            family_counts[proof[0]] += 1
            emitted += 1
        if not emitted:
            unclassified.append("tgl [%s %s] %s %s" %
                                (h["dom"], h["scope"], h["sig"], h["dirs"]))
    return blocks, consts, unclassified, family_counts


# ---------------------------------------------------------------------------
# Condition exclusions: exact vector + contradictory constant operand.
# ---------------------------------------------------------------------------
def cond_row_parts(text):
    m = re.match(r'Condition\s+\d+\s+"[^"]*"\s+"(.*)"(?:\s+\((\d+)\s+"([^"]*)"\))?$', text)
    if not m:
        return None
    sig, vec = m.group(1), m.group(3)
    expr = re.sub(r"\s+\d+\s+-1$", "", sig)
    return expr, vec


def condition_proof(h, scope, consts):
    # Ternary scan bypass: scan_mode is tied to zero at every parity instance.
    if base_module(scope) == "rst_sync" and h["line"] == 109 and h["vec"] == "1":
        return "SCAN_MODE_TIE0"
    vec = h["vec"]
    operands = list(h.get("terms", [])) or split_operands(h["expr"], len(vec))
    if len(vec) == 1 and not operands:
        operands = [strip_parens(h["expr"])]
    if len(operands) != len(vec):
        return None
    for wanted, operand in zip(vec, operands):
        if wanted not in "01":
            continue
        val = const_operand(consts, scope["key"], operand)
        if val is not None and int(wanted) != val:
            return "CONST_OPERAND_CONTRADICTION"
    return None


def build_cond(raw_holes, dumps, consts):
    blocks = collections.defaultdict(lambda: {"rows": set()})
    unclassified = []
    family_counts = collections.Counter()
    for h in raw_holes:
        if h["dom"] == "I":
            candidates = [dumps["cond"]["I"].get("INSTANCE: " + h["scope"])]
        else:
            candidates = dumps["cond"]["M"].get(h["scope"], [])
        emitted = 0
        for sc in candidates:
            if sc is None:
                continue
            proof = condition_proof(h, sc, consts)
            if proof is None:
                continue
            matches = []
            for row in sc["rows"]:
                if row["line"] != h["line"]:
                    continue
                parts = cond_row_parts(row["text"])
                if not parts or parts[1] != h["vec"]:
                    continue
                if not h["expr"] or norm_expr(parts[0]) == norm_expr(h["expr"]):
                    matches.append(row)
            if len(matches) != 1:
                continue
            add_row(blocks, sc, matches[0]["text"])
            family_counts[proof] += 1
            emitted += 1
        if not emitted:
            unclassified.append("cond [%s %s] L%d %s %s" %
                                (h["dom"], h["scope"], h["line"], h["expr"], h["vec"]))
    return blocks, unclassified, family_counts


# ---------------------------------------------------------------------------
# Line and branch exclusions (same structural wrap/reset families).
# ---------------------------------------------------------------------------
DISJOINT_SELFTEST = {"u_inj_en", "u_inj_force", "u_irqen", "u_cfg_pos",
                     "u_w_cmd", "u_w_esmtst"}


def wrap_leaf(scope):
    return scope["name"].split(".")[-1] if scope["kind"] == "INSTANCE" else ""


def line_proof(h, scope):
    if base_module(scope) != "reg_wrap":
        return None
    leaf = wrap_leaf(scope)
    if h["line"] in (108, 110) and leaf in FOLLOWERS:
        return "FOLLOWER_WR_TIE1"
    if h["line"] == 104 and leaf in DISJOINT_SELFTEST:
        return "WR_SELFTEST_ADDR_MUTEX"
    return None


def branch_proof(h, scope):
    mod = base_module(scope)
    if mod == "rst_sync" and h["line"] == 109 and h["vec"] == "1":
        return "SCAN_MODE_TIE0"
    if mod != "reg_wrap" or h["line"] != 100:
        return None
    leaf = wrap_leaf(scope)
    if leaf in FOLLOWERS and h["vec"] in ("0,-,1", "0,-,0"):
        return "FOLLOWER_WR_TIE1"
    if leaf in DISJOINT_SELFTEST and h["vec"] == "1,1,-":
        return "WR_SELFTEST_ADDR_MUTEX"
    return None


def build_line_branch(raw_holes, dumps, metric):
    blocks = collections.defaultdict(lambda: {"rows": set()})
    unclassified = []
    family_counts = collections.Counter()
    proof_fn = line_proof if metric == "line" else branch_proof
    for h in raw_holes:
        if h["dom"] == "I":
            candidates = [dumps[metric]["I"].get("INSTANCE: " + h["scope"])]
        else:
            candidates = dumps[metric]["M"].get(h["scope"], [])
        emitted = 0
        for sc in candidates:
            if sc is None:
                continue
            proof = proof_fn(h, sc)
            if proof is None:
                continue
            rows = [r for r in sc["rows"] if r["line"] == h["line"]]
            if metric == "branch":
                matches = []
                for row in rows:
                    vm = re.search(r'\(\d+\)\s+"([^"]*)"\s*$', row["text"])
                    if vm and vm.group(1).rsplit(" ", 1)[-1] == h["vec"]:
                        matches.append(row)
                rows = matches
            if len(rows) != 1:
                continue
            add_row(blocks, sc, rows[0]["text"])
            family_counts[proof] += 1
            emitted += 1
        if not emitted:
            extra = " " + h["vec"] if metric == "branch" else ""
            unclassified.append("%s [%s %s] L%d%s" %
                                (metric, h["dom"], h["scope"], h["line"], extra))
    return blocks, unclassified, family_counts


def merge_blocks(dst, src):
    for key, val in src.items():
        dst[key]["rows"].update(val["rows"])


def write_el(path, title, blocks, metric):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("// ============================================================================\n")
        f.write("// " + title + "\n")
        f.write("// Generated by gen_parity_excl.py from RAW modinfo + fresh urg dumps.\n")
        f.write("// No legacy whole-vector exclusions are inherited.  Any unproved raw\n")
        f.write("// hole aborts generation.  Families (all structural, not stimulus gaps):\n")
        f.write("// ZERO_EXT/ZERO_EXT_XOR: DW<64 data/EDC zero-extension and dead XOR terms.\n")
        f.write("// INJ_ZERO_EXT/INJ_ONEHOT: 128b injection zero-extension/one-hot force.\n")
        f.write("// GEN_*_TIEOFF: GEN sites have i_edc/local o_err structurally tied off.\n")
        f.write("// SIDE_GEN_HALF/SIDE_DIRECTION_TIEOFF/OBSERVER_USER_TIEOFF: deployment generate direction.\n")
        f.write("// ADDR_DECODE/WSEL_DEAD_DECODE/RETIRED_PERR_GROUP: unused map/group bits.\n")
        f.write("// NUM_CORE_ZERO_EXT/READ_MUX_CONSTANT: NUM_CORE=2 and fixed read-mux zero legs.\n")
        f.write("// FOLLOWER_WR_TIE1: follower reg_wrap wr=1'b1 (no-write branch is dead).\n")
        f.write("// WR_SELFTEST_ADDR_MUTEX: wr and REG_SELFTEST register decodes are mutually exclusive.\n")
        f.write("// SCAN_MODE_TIE0: every rst_sync scan_mode input is tied to 1'b0.\n")
        f.write("// DW64_EDC_SLOT: DW=64 EDC injection slots lie in the zero-extended region.\n")
        if metric == "cond":
            f.write("// CONST_OPERAND_CONTRADICTION: each excluded condition vector contains\n")
            f.write("// a 0/1 requirement incompatible with a toggle-proven constant operand.\n")
        f.write("// ============================================================================\n\n")
        for (key, checksum, hdr), val in sorted(blocks.items(), key=lambda x: x[0][0]):
            if not val["rows"]:
                continue
            f.write("CHECKSUM: %s\n%s\n" % (checksum, hdr))
            for row in sorted(val["rows"]):
                f.write(row + "\n")
            f.write("\n")
        f.write("// Total exclusion rows: %d\n" %
                sum(len(v["rows"]) for v in blocks.values()))


def main():
    if not os.path.exists(RAW):
        raise SystemExit("missing raw report: " + RAW)
    dumps = load_dumps()
    raw = parse_raw(RAW)
    by_metric = collections.defaultdict(list)
    for h in raw:
        by_metric[h["metric"]].append(h)
    print("raw holes: " + ", ".join("%s=%d" % (m, len(by_metric[m]))
                                    for m in ("line", "cond", "branch", "tgl")))

    tgl_blocks, consts, un_tgl, fam_tgl = build_toggle(by_metric["tgl"], dumps)
    cond_blocks, un_cond, fam_cond = build_cond(by_metric["cond"], dumps, consts)
    line_blocks, un_line, fam_line = build_line_branch(by_metric["line"], dumps, "line")
    branch_blocks, un_branch, fam_branch = build_line_branch(by_metric["branch"], dumps, "branch")
    unclassified = un_tgl + un_cond + un_line + un_branch
    if unclassified:
        print("UNCLASSIFIED raw holes (%d):" % len(unclassified))
        for item in unclassified[:250]:
            print("  " + item)
        if len(unclassified) > 250:
            print("  ... %d more" % (len(unclassified) - 250))
        raise SystemExit("refusing to hide unproved coverage gaps")

    misc = collections.defaultdict(lambda: {"rows": set()})
    merge_blocks(misc, line_blocks)
    merge_blocks(misc, cond_blocks)
    merge_blocks(misc, branch_blocks)
    write_el(TGL_OUT, "parity structural TOGGLE exclusions", tgl_blocks, "tgl")
    write_el(MISC_OUT, "parity structural LINE/COND/BRANCH exclusions", misc, "cond")
    for name, fam in (("toggle", fam_tgl), ("condition", fam_cond),
                      ("line", fam_line), ("branch", fam_branch)):
        print(name + " families: " + ", ".join("%s=%d" % kv for kv in sorted(fam.items())))
    print("wrote %d toggle rows -> %s" %
          (sum(len(v["rows"]) for v in tgl_blocks.values()), TGL_OUT))
    print("wrote %d line/cond/branch rows -> %s" %
          (sum(len(v["rows"]) for v in misc.values()), MISC_OUT))


if __name__ == "__main__":
    main()
