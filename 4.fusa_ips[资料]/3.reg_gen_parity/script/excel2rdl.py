#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
excel2rdl.py -- convert the FuSa register Excel table to SystemRDL.

Usage (run where openpyxl is available, e.g. VM rocky-eda):
    python3 excel2rdl.py taylor_v3.xlsx [-o taylor_v3.rdl]

Input schema (worksheet #1, mirrors reg_gen_parity.pl Proc_info):
    row1  BASE_ADDR  0x0
    row2  ADDR_WIDTH 13
    row3  APB3                       (bus type)
    row4  REG_NUM    1
    row5  ECC_OFFSET 0x4
    row6  header: Offset|Register Name|SubBits|Field Name|Attribute|
                 DefaultValue|Description (Shadow/ShadowAddr/CDC/SetClear
                 optional but NOT supported by rdl2reg yet)
    row7+ register rows, fields msb->lsb, grouped under a Register Name

Output: SystemRDL 2.0 text.  Standard properties (sw/hw/onwrite/onread/
reset/desc) are emitted for tool interop; the original Excel attribute
token rides in the custom `attr` string property and is the authoritative
input for rdl2reg.py code generation.

Repeated reserved rows are renamed reserved, reserved_1, reserved_2 ...
(RDL forbids duplicate instance names); rdl2reg.py normalizes any
reserved[_n] name back to the perl `reserved` semantics.
"""

import os
import re
import sys

import regmodel
from regmodel import Field, Reg, Module, RdlError

try:
    import openpyxl
except ImportError:
    sys.stderr.write("[ERROR] openpyxl is required (pip3 install openpyxl)\n")
    sys.exit(1)


SUBBITS_RE = re.compile(r"^\[\s*(\d+)\s*(?::\s*(\d+)\s*)?\]$")
OFFSET_RE = re.compile(r"^[0-9a-fA-F]+\s*[hH]$")
HEXVAL_RE = re.compile(r"^0[xX][0-9a-fA-F]+$")

# Excel attribute aliases accepted at load (normalized before the Field is
# built; the RDL/RTL/C outputs only ever carry the canonical token).
ATTR_ALIAS = {"W1C/R": "W1C"}  # write-1-to-clear, readable (W1C already is)

# ---- v2 FuSa block n/m placeholder auto-sizing (fusa_std_block.md §6) ----
# The hand-sketched FuSa block sizes its status/select fields from the bank:
#   m = number of parity-bank registers, n = m + 4
#   [31:n] reserved, [n-1:4] reg<m-1>..reg0 status/select field, <m>'b0 reset
PH_SUB_HI = re.compile(r"^\[\s*31\s*:\s*n\s*\]$")           # [31:n]
PH_SUB_LO = re.compile(r"^\[\s*n\s*-\s*1\s*:\s*4\s*\]$")    # [n-1:4]
PH_VAL = re.compile(r"^<m>\s*'{1,2}b0$")                    # <m>'b0 / <m>''b0
PH_NAME = re.compile(r"^reg<m\s*-\s*1>~reg0_par_err_sta$")


def cell_str(v):
    if v is None:
        return ""
    s = str(v)
    return s.strip()


def parse_header_info(ws):
    """Extract BASE_ADDR/ADDR_WIDTH/bus/REG_NUM/ECC_OFFSET + header row."""
    info = {"BASE_ADDR": "0x0", "ADDR_WIDTH": "13", "BUS": "APB3",
            "REG_NUM": "0", "ECC_OFFSET": None}
    header_row = None
    for row in ws.iter_rows(min_row=1, max_row=min(20, ws.max_row)):
        vals = [cell_str(c.value) for c in row]
        if not any(vals):
            continue
        first = vals[0]
        if first.lower() == "offset":
            header_row = row[0].row
            break
        # "KEY: value" in one cell, or KEY in col A + value in col B
        kv = None
        for s in vals[:3]:
            m = re.match(r"^([A-Za-z_ ]+)\s*[:=]\s*(.+)$", s)
            if m and m.group(1).strip().upper().replace(" ", "_") in (
                    "BASE_ADDR", "ADDR_WIDTH", "REG_NUM", "ECC_OFFSET"):
                kv = (m.group(1).strip().upper().replace(" ", "_"),
                      m.group(2).strip())
                break
        if kv:
            info[kv[0]] = kv[1]
            continue
        if re.match(r"^APB\d$", first):
            info["BUS"] = first.upper()
            continue
        key = first.upper().replace(" ", "_")
        if key in ("BASE_ADDR", "ADDR_WIDTH", "REG_NUM", "ECC_OFFSET"):
            nxt = vals[1] if len(vals) > 1 else ""
            if nxt:
                info[key] = nxt
    if header_row is None:
        raise RdlError("header row (first cell 'Offset') not found")
    if info["ECC_OFFSET"] is None:
        raise RdlError("ECC_OFFSET entry not found in the header area")
    return info, header_row


def parse_columns(ws, header_row):
    """Map lc'd column names -> index."""
    cols = {}
    for c in ws[header_row]:
        name = cell_str(c.value).lower().replace(" ", "")
        if name:
            cols[name] = c.column - 1
    need = ("offset", "registername", "subbits", "fieldname",
            "attribute", "defaultvalue")
    for n in need:
        if n not in cols:
            raise RdlError("column %r missing from header row %d"
                           % (n, header_row))
    return cols


def read_extint_sheet(wb):
    """Parse the optional 'ExtInt' worksheet -> [(name, width)] or None.

    Layout: header row `Field Name | Bits | Description`, then one row per
    ext fault, msb-descending (FIRST row = HIGHEST bit, bit1 upward from
    the bottom; bit0 is always parity_err).  Bits column = decimal width
    (default 1).
    """
    for ws in wb.worksheets[1:]:
        if ws.title.strip().lower() != "extint":
            continue
        rows = []
        seen_header = False
        for row in ws.iter_rows():
            vals = [cell_str(c.value) for c in row]
            if not any(vals):
                continue
            if not seen_header:
                if vals[0].strip().lower() != "field name":
                    raise RdlError("ExtInt sheet: first non-empty row must "
                                   "be the header 'Field Name | Bits | "
                                   "Description'")
                seen_header = True
                continue
            name = vals[0]
            if not name:
                continue
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
                raise RdlError("ExtInt sheet: bad fault name %r" % name)
            if name == "parity_err":
                raise RdlError("ExtInt sheet: 'parity_err' is reserved "
                               "(bit0 of the standard block)")
            w = vals[1] if len(vals) > 1 and vals[1] else "1"
            if not re.match(r"^[1-9]\d*$", w):
                raise RdlError("ExtInt sheet %s: Bits must be a decimal "
                               "width >= 1 (got %r)" % (name, w))
            rows.append((name, int(w)))
        if not seen_header:
            raise RdlError("ExtInt sheet is empty (no header row)")
        return rows
    return None


def resolve_placeholders(mod, raw):
    """Resolve the v2 FuSa block's n/m placeholders in place (see §6 of
    fusa_std_block.md).

        m = parity-bank size (non-RO/RES regs that are not PASSWORD/Set*/
            Status*), n = m + 4
        [31:n] reserved -> [31:n], [n-1:4] field -> [n-1:4],
        reg<m-1>~reg0_par_err_sta -> reg_par_err_sta, <m>'b0 -> m'b0

    Bank membership never depends on field widths, so m is derived from the
    concrete (placeholder-free) rows of every register; a register made only
    of placeholder fields cannot be attributed and is an error.
    """
    def is_ph(fr):
        return (PH_SUB_HI.match(fr["sub"]) or PH_SUB_LO.match(fr["sub"])
                or PH_VAL.match(fr["value"]) or PH_NAME.match(fr["name"]))
    if not any(is_ph(fr) for _, fs in raw for fr in fs):
        return
    m = 0
    for reg, fs in raw:
        flags = set()
        n_concrete = 0
        for fr in fs:
            if is_ph(fr):
                continue
            n_concrete += 1
            if regmodel.norm_reserved_name(fr["name"]) == "reserved":
                flags.add("res")
                continue
            tok = fr["attr"]
            if tok not in regmodel.ATTR_TOKENS:
                raise RdlError("REG %s field %s: unknown attribute %r"
                               % (reg.gname, fr["name"], tok))
            flags.add(regmodel.ATTR_FLAG[tok])
        if n_concrete == 0:
            raise RdlError("REG %s: cannot size the bank from n/m "
                           "placeholders (register has no concrete field)"
                           % reg.gname)
        live = flags - {"res"}          # non-reserved attr flags
        if live and live != {"ro"} and not reg.skipped_from_bank():
            m += 1
    n = m + 4
    if n > 31:
        raise RdlError("n/m placeholders: bank size m=%d pushes n=%d past "
                       "bit 31 (max m=27)" % (m, n))
    for reg, fs in raw:
        for fr in fs:
            if PH_SUB_HI.match(fr["sub"]):
                fr["sub"] = "[31:%d]" % n
            elif PH_SUB_LO.match(fr["sub"]):
                fr["sub"] = "[%d:4]" % (n - 1)
            if PH_VAL.match(fr["value"]):
                fr["value"] = "%d'b0" % m
            if PH_NAME.match(fr["name"]):
                fr["name"] = "reg_par_err_sta"
    print("[INFO]: n/m placeholders resolved: m=%d bank regs, n=%d" % (m, n))


def load_xlsx(path, no_std_block=False):
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.worksheets[0]
    info, header_row = parse_header_info(ws)
    cols = parse_columns(ws, header_row)

    mod = Module(os.path.splitext(os.path.basename(path))[0])
    mod.base_addr = info["BASE_ADDR"]
    mod.addr_width = int(info["ADDR_WIDTH"])
    mod.bus = info["BUS"]
    mod.reg_num_hdr = int(info["REG_NUM"]) if str(info["REG_NUM"]).isdigit() else 0
    if HEXVAL_RE.match(info["ECC_OFFSET"]):
        mod.ecc_offset = int(info["ECC_OFFSET"], 16)
    else:
        mod.ecc_offset = int(info["ECC_OFFSET"])

    cur = None
    frows = None
    res_count = {}
    raw = []  # [(Reg, [field-row dict])] in file order
    for row in ws.iter_rows(min_row=header_row + 1):
        vals = [cell_str(c.value) for c in row]
        def col(name):
            i = cols.get(name)
            return vals[i] if i is not None and i < len(vals) else ""
        off = col("offset")
        gname = col("registername")
        subbits = col("subbits")
        fname = col("fieldname")
        attr = col("attribute")
        value = col("defaultvalue")
        desc = col("description")
        if not (off or gname or fname):
            continue
        if off and not OFFSET_RE.match(off):
            # section separators like "registers group"
            continue
        if gname:
            offset = off.lower().replace(" ", "")
            cur = Reg(gname, offset)
            mod.regs.append(cur)
            frows = []
            raw.append((cur, frows))
            res_count[cur.gname] = 0
        if cur is None:
            raise RdlError("field row before any Register Name: %r" % vals)
        if not fname:
            continue
        name = fname
        if regmodel.norm_reserved_name(name) == "reserved":
            n = res_count[cur.gname]
            name = "reserved" if n == 0 else "reserved_%d" % n
            res_count[cur.gname] = n + 1
        frows.append({
            "sub": subbits or "", "name": name,
            "attr": ATTR_ALIAS.get(attr.upper() if attr else "RO",
                                   attr.upper() if attr else "RO"),
            "value": value if value else "0", "desc": desc,
            "cdc": col("cdc"), "shad": col("shadow"),
            "shadaddr": int(col("shadowaddr"), 16)
            if HEXVAL_RE.match(col("shadowaddr") or "") else 0,
        })
    if not mod.regs:
        raise RdlError("no register rows found")

    resolve_placeholders(mod, raw)

    for reg, fs in raw:
        for fr in fs:
            m = SUBBITS_RE.match(fr["sub"])
            if not m:
                raise RdlError("REG %s field %s: bad SubBits %r"
                               % (reg.gname, fr["name"], fr["sub"]))
            msb = int(m.group(1))
            lsb = int(m.group(2)) if m.group(2) else msb
            reg.fields.append(Field(
                fr["name"], msb, lsb, fr["attr"], fr["value"],
                desc=fr["desc"], cdc=fr["cdc"], shad=fr["shad"],
                shadaddr=fr["shadaddr"],
            ))

    # ---- standard FuSa block (auto-append, fusa_std_block.md v1.0) -------
    ext_rows = read_extint_sheet(wb)
    hand_written = (any(r.is_password() for r in mod.regs)
                    or any(r.offset_int >= mod.ecc_offset for r in mod.regs))
    if hand_written:
        # full map: the ECC region already carries registers (a PASSWORD, a
        # v1 standard block, or a hand-written v2 FuSa block) -- never append
        if ext_rows is not None:
            raise RdlError("ExtInt sheet is only used when the standard "
                           "FuSa block is auto-appended; this map already "
                           "carries registers at/above ECC_OFFSET (or a "
                           "PASSWORD) -- remove one of the two")
    elif not no_std_block:
        mod.regs.extend(regmodel.std_block_regs(
            mod.ecc_offset, ext_rows if ext_rows is not None else []))
        mod.std_appended = True

    mod.derive()
    mod.validate()
    return mod


# ---------------------------------------------------------------------------
# SystemRDL emission
# ---------------------------------------------------------------------------

def esc(s):
    return (s or "").replace("\\", "\\\\").replace('"', '\\"').replace(
        "\r", " ").replace("\n", "\\n")


def fmt_addr(v):
    return "0x%x" % v


def emit_field(f):
    sw, onwrite, onread = regmodel.RDL_SW[f.attr]
    hw = "rw" if f.attr in ("HW", "W1C") else "r"
    props = ["sw = %s" % sw]
    if onwrite:
        props.append("onwrite = %s" % onwrite)
    if onread:
        props.append("onread = %s" % onread)
    props.append("hw = %s" % hw)
    # emit the stored token verbatim (round-trip stable: xlsx empty cell -> 0,
    # hand-written RDL 'h0 -> 'h0; rdl2reg re-normalizes bare 0 on reserved)
    props.append("reset = %s" % f.value)
    props.append('attr = "%s"' % f.attr)
    if f.desc:
        props.append('desc = "%s"' % esc(f.desc))
    # SystemRDL: every property assignment is ';'-terminated, including
    # the last one before '}' (the parser enforces this too)
    body = " ".join(p + ";" for p in props)
    rng = "[%d]" % f.msb if f.width == 1 else "[%d:%d]" % (f.msb, f.lsb)
    return "        field { %s } %s%s;" % (body, f.name, rng)


def emit_rdl(mod):
    out = []
    out.append("// Generated by excel2rdl.py from %s.xlsx -- this file is"
               % mod.name)
    out.append("// the source of truth; feed it to rdl2reg.py.")
    out.append("// Excel header: BUS=%s ADDR_WIDTH=%d BASE_ADDR=%s "
               "ECC_OFFSET=0x%x REG_NUM=%d"
               % (mod.bus, mod.addr_width, mod.base_addr, mod.ecc_offset,
                  mod.reg_num_hdr))
    if mod.std_appended:
        out.append("// Standard FuSa block (PASSWORD/FUSA_CTRL/"
                   "MIssionIntStatusSet0/MIssionIntStatus0/MIssionIntMask0)"
                   " auto-appended at ECC_OFFSET=0x%x per fusa_std_block.md"
                   " v1.0; ext faults from the ExtInt sheet: %s"
                   % (mod.ecc_offset,
                      ", ".join("%s[%d]" % nv for nv in mod.ext_int)
                      or "none"))
    out.append("")
    out.append("property apb_addr_width { type = longint; "
               "component = addrmap; };")
    out.append("property bus_type       { type = string;  "
               "component = addrmap; };")
    out.append("property base_addr      { type = longint; "
               "component = addrmap; };")
    out.append("property ecc_offset     { type = longint; "
               "component = addrmap; };")
    out.append("property attr           { type = string;  "
               "component = field; };")
    out.append("")
    out.append("addrmap %s {" % mod.name)
    out.append("    apb_addr_width = %d;" % mod.addr_width)
    out.append('    bus_type       = "%s";' % mod.bus)
    out.append("    base_addr      = %s;" % fmt_addr(
        int(mod.base_addr, 16) if HEXVAL_RE.match(mod.base_addr or "")
        else int(mod.base_addr or 0)))
    out.append("    ecc_offset     = %s;" % fmt_addr(mod.ecc_offset))
    out.append("")
    out.append("    default regwidth = 32;")
    for reg in mod.regs:
        out.append("")
        ecc = " (ECC)" if reg.ecc else ""
        out.append("    // ---- %s: %s%s ----"
                   % (fmt_addr(reg.offset_int), reg.gname, ecc))
        out.append("    reg {")
        for f in reg.fields:
            out.append(emit_field(f))
        out.append("    } %s @ %s;" % (reg.gname, fmt_addr(reg.offset_int)))
    out.append("};")
    return "\n".join(out) + "\n"


def main():
    args = sys.argv[1:]
    infile = None
    outfile = None
    no_std = False
    usage = "usage: excel2rdl.py <regs.xlsx> [-o out.rdl] [--no-std-block]\n"
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-o":
            if i + 1 >= len(args):
                sys.stderr.write(usage)
                sys.exit(1)
            outfile = args[i + 1]
            i += 2
        elif a == "--no-std-block":
            no_std = True
            i += 1
        else:
            if infile is not None:
                sys.stderr.write(usage)
                sys.exit(1)
            infile = a
            i += 1
    if infile is None:
        sys.stderr.write(usage)
        sys.exit(1)
    path = infile
    if outfile is None:
        outfile = os.path.splitext(path)[0] + ".rdl"
    try:
        mod = load_xlsx(path, no_std_block=no_std)
        text = emit_rdl(mod)
    except RdlError as e:
        sys.stderr.write("[ERROR] %s\n" % e)
        sys.exit(1)
    with open(outfile, "w") as fh:
        fh.write(text)
    print("[INFO]: %d registers, ecc_offset=0x%x, bank=%d%s"
          % (len(mod.regs), mod.ecc_offset, mod.func_num_w,
             ", std-block auto-appended (%d ext faults)"
             % len(mod.ext_int) if mod.std_appended else ""))
    print("[INFO]: wrote %s" % outfile)


if __name__ == "__main__":
    main()
