#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rdl2reg.py -- SystemRDL -> Verilog parity regfile (python replacement of
reg_gen_parity.pl, .v path).

Usage:
    python3 rdl2reg.py taylor_v3.rdl [-o taylor_v3.v.raw]
                [--date 'Date : 2026-11-06 02:45:23'] [--user eda]

Emits the legacy byte-compatible output (reg_gen_parity.pl v0p3-2023/4/5,
post-processed by post_autos.py: AF/AD/AR vim-macro stand-in).  The output
of this script keeps /*autoarg*/ and the //auto wires/regs markers unfilled;
run post_autos.py <raw> <v> afterwards.

Only stdlib is used (python3.6+).  Unsupported legacy features (shadow /
CDC p2l / setclear / -sync / -noecc / --def headers) are rejected with a
clear error instead of silently mis-generating.
"""

import os
import re
import subprocess
import sys
from datetime import datetime

import regmodel
from regmodel import Field, Reg, Module, RdlError

VERSION = "v0p3-2023/4/5"

# ===========================================================================
# RDL-subset parser
# ===========================================================================

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>//[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<num>0[xX][0-9a-fA-F]+|\d*'[bBoOdDhH][0-9a-fA-F_xXzZ]+|\d+)
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<sym>[{}()\[\];,=@:])
""", re.VERBOSE)

BUSED_RE = re.compile(r"/\*.*?\*/", re.S)


def tokenize(text):
    text = BUSED_RE.sub(" ", text)
    # line comments could hide inside strings -- strip strings first by
    # tokenizing in one pass (TOKEN_RE prefers str over lcomment ordering
    # is irrelevant since regex alternation is ordered: ws, lcomment, str)
    pos, toks = 0, []
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise RdlError("RDL syntax error near %r" % text[pos:pos + 30])
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "lcomment"):
            continue
        toks.append((kind, m.group()))
    return toks


class Parser(object):
    """Recursive descent over the token stream of one .rdl file."""

    def __init__(self, toks):
        self.toks = toks
        self.i = 0

    # -- helpers ----------------------------------------------------------
    def peek(self, k=0):
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else (None, None)

    def next(self):
        t = self.peek()
        if t[0] is None:
            raise RdlError("unexpected end of RDL file")
        self.i += 1
        return t

    def expect_sym(self, s):
        k, v = self.next()
        if k != "sym" or v != s:
            raise RdlError("expected %r, got %r" % (s, v))

    def expect_id(self):
        k, v = self.next()
        if k != "id":
            raise RdlError("expected identifier, got %r" % (v,))
        return v

    def accept_sym(self, s):
        k, v = self.peek()
        if k == "sym" and v == s:
            self.i += 1
            return True
        return False

    # -- value syntax ------------------------------------------------------
    def parse_value(self):
        k, v = self.next()
        if k == "str":
            # single-pass unescape, mirrors excel2rdl.esc(): \\ \" \n
            # (sequential .replace() calls would mis-read "\\n" as newline)
            return re.sub(r'\\(["\\n])',
                          lambda m: {'"': '"', "\\": "\\", "n": "\n"}[m.group(1)],
                          v[1:-1])
        if k == "num":
            return NumValue(v)
        if k == "id":
            return v  # boolean/enum literal (true/false/rw/...)
        raise RdlError("expected value, got %r" % (v,))


class NumValue(object):
    """Numeric literal keeping its verbatim text (needed for reset tokens)."""

    def __init__(self, text):
        self.text = text
        m = re.match(r"^(0[xX][0-9a-fA-F]+)$", text)
        if m:
            self.value = int(text, 16)
        elif re.match(r"^\d+$", text):
            self.value = int(text, 10)
        else:
            mm = re.match(r"^(\d*)'([bBoOdDhH])([0-9a-fA-F_xXzZ]+)$", text)
            if not mm:
                raise RdlError("bad number literal %r" % text)
            w, radix, digits = mm.group(1), mm.group(2).lower(), mm.group(3)
            digits = digits.replace("_", "")
            base = {"b": 2, "o": 8, "d": 10, "h": 16}[radix]
            self.value = int(re.sub(r"[xXzZ]", "0", digits), base)

    def __int__(self):
        return self.value


def parse_rdl(path):
    with open(path) as fh:
        text = fh.read()
    p = Parser(tokenize(text))

    # property declarations (validated, then ignored -- the model keys off
    # its own built-in custom property names)
    known = {"apb_addr_width", "bus_type", "base_addr", "ecc_offset", "attr"}
    while True:
        k, v = p.peek()
        if k == "id" and v == "property":
            p.next()
            name = p.expect_id()
            p.expect_sym("{")
            while not p.accept_sym("}"):
                p.next()
            p.accept_sym(";")
            if name not in known:
                raise RdlError("unknown property declaration %r" % name)
        else:
            break

    # addrmap
    k, v = p.next()
    if k != "id" or v != "addrmap":
        raise RdlError("expected 'addrmap' as root component")
    name = p.expect_id()
    mod = Module(name)
    p.expect_sym("{")

    reg = None
    while not p.accept_sym("}"):
        k, v = p.peek()
        if k == "id" and v == "default":
            p.next()
            p.expect_id()  # regwidth
            p.expect_sym("=")
            p.next()
            p.expect_sym(";")
        elif k == "id" and v == "reg":
            p.next()
            reg = parse_reg(p, mod)
            mod.regs.append(reg)
        elif k == "id" and v in ("signal", "mem", "regfile", "field", "enum",
                                 "struct", "constraint", "abstract"):
            raise RdlError("component %r is not supported by this generator"
                           % v)
        else:
            # addrmap-level property assignment
            pname = p.expect_id()
            p.expect_sym("=")
            val = p.parse_value()
            p.expect_sym(";")
            if pname == "apb_addr_width":
                mod.addr_width = int(val)
            elif pname == "bus_type":
                mod.bus = val
            elif pname == "base_addr":
                mod.base_addr = "0x%x" % int(val)
            elif pname == "ecc_offset":
                mod.ecc_offset = int(val)
            elif pname in ("name", "desc"):
                pass
            else:
                raise RdlError("unknown addrmap property %r" % pname)
    p.accept_sym(";")
    if p.peek()[0] is not None:
        raise RdlError("trailing content after addrmap")

    if not mod.regs:
        raise RdlError("addrmap %s contains no registers" % name)
    mod.derive()
    validate_rdl(mod)
    return mod


def parse_reg(p, mod):
    p.expect_sym("{")
    reg = None
    fields = []
    while not p.accept_sym("}"):
        k, v = p.peek()
        if k == "id" and v == "field":
            p.next()
            fields.append(parse_field(p))
        elif k == "id" and v in ("default", "regwidth"):
            p.next()
            while not p.accept_sym(";"):
                p.next()
        else:
            pname = p.expect_id()
            p.expect_sym("=")
            p.parse_value()
            p.expect_sym(";")
            if pname not in ("name", "desc"):
                raise RdlError("unknown reg property %r" % pname)
    rname = p.expect_id()
    p.expect_sym("@")
    k, v = p.next()
    if k != "num":
        raise RdlError("expected address after '@' for reg %s" % rname)
    addr = int(NumValue(v))
    p.expect_sym(";")
    reg = Reg(rname, "%02xh" % addr)
    seen = set()
    for f in fields:
        if f.name in seen:
            raise RdlError("REG %s: duplicate field name %r (rename repeated "
                           "reserved rows to reserved_1, reserved_2 ...)"
                           % (rname, f.name))
        seen.add(f.name)
        reg.fields.append(f)
    return reg


def parse_field(p):
    p.expect_sym("{")
    props = {}
    while not p.accept_sym("}"):
        pname = p.expect_id()
        p.expect_sym("=")
        props[pname] = p.parse_value()
        p.expect_sym(";")
    known = {"sw", "hw", "onwrite", "onread", "reset", "attr", "desc"}
    for k in props:
        if k not in known:
            raise RdlError("unsupported field property %r (cdc/shadow/"
                           "setclear are not supported by this generator)" % k)
    fname = p.expect_id()
    p.expect_sym("[")
    k, v = p.next()
    msb = int(NumValue(v)) if k == "num" else None
    if msb is None:
        raise RdlError("field %s: bad msb" % fname)
    lsb = msb
    if p.accept_sym(":"):
        k, v = p.next()
        lsb = int(NumValue(v))
    p.expect_sym("]")
    p.expect_sym(";")

    attr = props.get("attr")
    if attr is None:
        raise RdlError("field %s: custom property attr=\"RW|W1C|...\" is "
                       "required (it carries the original Excel attribute)"
                       % fname)
    attr = attr.upper()
    if attr not in regmodel.ATTR_TOKENS:
        raise RdlError("field %s: unknown attr %r" % (fname, attr))

    reset = props.get("reset")
    if reset is None:
        raise RdlError("field %s: reset value is required" % fname)
    if isinstance(reset, NumValue):
        value = reset.text
        if regmodel.parse_value(value) is None and \
                regmodel.norm_reserved_name(fname) != "reserved":
            raise RdlError("field %s: reset %r must use <width>'<radix> form"
                           % (fname, value))
        if regmodel.parse_value(value) is None:
            value = "0"
    else:
        raise RdlError("field %s: reset must be a number literal" % fname)

    # interop cross-check: standard sw/onwrite/onread, when present, must
    # agree with the attr token mapping (attr is authoritative for output)
    sw, onwrite, onread = regmodel.RDL_SW[attr]
    for key, expect in (("sw", sw), ("onwrite", onwrite), ("onread", onread)):
        got = props.get(key)
        if got is not None and got != expect:
            raise RdlError("field %s: %s=%r conflicts with attr=%s (expected "
                           "%r); attr is authoritative -- fix the RDL"
                           % (fname, key, got, attr, expect))

    desc = props.get("desc", "")
    if not isinstance(desc, str):
        desc = ""
    return Field(fname, msb, lsb, attr, value, desc=desc)


def validate_rdl(mod):
    """Full-model validation (shared Excel/RDL invariants)."""
    mod.validate()
    for reg in mod.regs:
        if re.search(r"^FUSA_CTRL", reg.gname) and not reg.fields[-1].rname == \
                "reserved" and reg.fields[-1].lsb != 0:
            pass  # informational only; perl requires no such rule


# ===========================================================================
# Verilog emitters -- 1:1 port of reg_gen_parity.pl
# ===========================================================================

class Grp(object):
    """A perl accumulator string ('{};' or '32'h0;') with its s/};/T};/ op."""

    def __init__(self, val):
        self.val = val

    def subst(self, term):
        # s/\};/$term};/g -- terms never contain '};' so a single replace
        # is equivalent; no-op when the shortcut '32'h0;' has no '};'
        if "};" in self.val:
            self.val = self.val.replace("};", term + "};")

    def wholesale(self, val):
        self.val = val

    def clean(self):
        # s/\{,/\{/g
        self.val = self.val.replace("{,", "{")


def _vlog_value(field):
    """value normalization from Gen_ecc_reg (width prefix for 'h0 form)."""
    v = field.value
    if re.match(r"^\d+'\w+$", v):
        return v
    if re.match(r"^'\w+$", v):
        return "%d%s" % (field.width, v)
    return v


def _hvalue(field):
    if field.width == 1:
        return "1'b1"
    return "%d{1'b1}" % field.width


def gen_rtl_iop(mod):
    """Gen_rtl_iop -- port list + ext_int collection (returns lines)."""
    L = []
    ext_int = []          # (name, width) in collection order
    aw = mod.addr_width
    L.append("//APB bus interface\n")
    L.append("    input             pclk;\n")
    L.append("    input             presetn;\n")
    L.append("    input             psel;\n")
    L.append("    input             penable;\n")
    L.append("    input [%2d:0]      paddr;\n" % (aw - 1))
    L.append("    input             pwrite;\n")
    L.append("    input [31:0]      pwdata;\n")
    L.append("    output[31:0]      prdata;\n")
    if mod.bus == "APB3":
        L.append("    output            pready;\n")
        L.append("    output            pslverr;\n")

    def w2(width):  # output/input section index
        return " " * 6 if width == 1 else "[%-2d:0]" % (width - 1)

    def w5(width):  # ecc section index
        return " " * 6 if width == 1 else "[%-5s" % ("%d:0]" % (width - 1))

    # ---- output signals (non-ecc, non-reserved, non-RO/RC) ----
    L.append("//output signals\n")
    for reg in mod.regs:
        if reg.ecc:
            continue
        for f in reg.fields:
            if f.rname == "reserved":
                continue
            if f.attr in ("RO", "RC"):
                continue
            L.append("    output %s     %s;\n" % (w2(f.width), f.rname))
            if f.attr in ("HW", "W1S", "W1C", "W0S", "W0C"):
                L.append("    input             %s_wr;\n" % f.rname)
                L.append("    input  %s     %s_in;\n" % (w2(f.width), f.rname))
            if f.attr in ("MRW", "MWO"):
                L.append("    input  %s     %s_mask;\n" % (w2(f.width), f.rname))
    # ---- input register signals ----
    L.append("//input signals\n")
    for reg in mod.regs:
        if reg.ecc:
            continue
        for f in reg.fields:
            if f.rname == "reserved":
                continue
            if f.attr == "RC":
                L.append("    input  %s     %s;\n" % (w2(f.width), f.rname))
                L.append("    output %s     %s_cap;\n" % (w2(f.width), f.rname))
            if f.attr == "RO":
                L.append("    input  %s     %s;\n" % (w2(f.width), f.rname))
    # ---- shadow (unsupported, headers kept for layout parity) ----
    L.append("\n//shadow register signals\n")
    L.append("\n//shadow register control signals\n")
    # ---- ECC signals ----
    L.append("//ECC signals\n")
    L.append("    output            mission_int;\n")
    for reg in mod.regs:
        for f in reg.fields:
            idx = w5(f.width)
            if reg.ecc and f.rname not in ("parity_err_status", "reserved"):
                if f.attr in ("HW", "W1C"):
                    if reg.is_fusa_ctrl():
                        L.append("    input             %s_wr;\n" % f.rname)
                    else:
                        L.append("    input  %s     %s_wr;\n"
                                 % (idx, f.rname))
                    L.append("    input  %s     %s_in;\n" % (idx, f.rname))
                if f.rname.endswith("_status"):
                    # perl: ext_int collection sits INSIDE the ecc guard
                    ext_int.append((f.rname[:-len("_status")], f.width))
            if reg.ecc and reg.is_fusa_ctrl() and f.rname not in (
                    "parity_decoder_enable", "fault_injection_en",
                    "parity_fault_injection", "reserved", "parity_invert"):
                # perl: if ($attr ne "RO|RC") -- literal string compare,
                # always true; ported as unconditional
                L.append("    output %s     %s;\n" % (idx, f.rname))
            if reg.ecc and f.attr == "RO" and f.rname != "reserved":
                L.append("    input %s      %s;\n" % (idx, f.rname))
    # ---- extended error outputs ----
    if ext_int:
        L.append("//Extended error sets\n")
        for name, width in ext_int:
            idx = w5(width)
            int_out = re.sub(r"_err_err", "_err", name + "_err")
            L.append("    output %s     %s;\n" % (idx, int_out))
    return L, ext_int


def gen_wr_logic(mod):
    """Gen_wr_logic -> (wr_logic lines, reg_num_w, reg_w_regs)."""
    aw = mod.addr_width
    addr_msb = aw - 1
    addr_cut = aw - 2
    addr_cut_msb = addr_cut - 1
    reg_w = []
    addr_param = ["//local parameters\n"]
    tmp = ["//register write logic\n",
           "assign  apb_wr = psel & penable & pwrite;\n",
           "assign  apb_rd = psel & ~penable & ~pwrite;\n",
           "\n",
           "//BUS addr parameter"]
    ecc_first = mod.ecc_first_offset()
    for reg in mod.regs:
        gname_uc = reg.gname_uc
        off = reg.offset
        addr_vcut = "%x" % (reg.offset_int // 4)
        addr_param.append("//'h%x\n" % reg.offset_int)
        addr_param.append(
            "localparam [%d:0] %-35s = ADDR_BASE[%-2s:2] + %d'h%s ;\n"
            % (addr_cut_msb, gname_uc, addr_msb, addr_cut, addr_vcut))
        if reg.reg_attr in ("RO", "RES"):
            continue
        hwr = "%-34s" % ("hwr_" + reg.gname)
        hrd = "%-34s" % ("hrd_" + reg.gname)
        if reg.ecc and (off == ecc_first or not mod.has_passwd):
            # no PASSWORD register in the map -> no key storage -> no gating
            # (the perl would compare against an undeclared passwd forever,
            # i.e. ECC writes dead AND the module does not even compile)
            tmp.append("assign %s = apb_wr && (paddr[%d:2] == %s);\n"
                       % (hwr, addr_msb, gname_uc))
        elif reg.ecc:
            tmp.append("assign %s = apb_wr && (paddr[%d:2] == %s)\n"
                       % (hwr, addr_msb, gname_uc))
            tmp.append("%s&& (passwd==32'h95f2d303);\n" % (" " * 51))
        else:
            tmp.append("assign %s = apb_wr && (paddr[%d:2] == %s);\n"
                       % (hwr, addr_msb, gname_uc))
            if reg.flags["rc"]:
                tmp.append("assign %s = apb_rd && (paddr[%d:2] == %s);\n"
                           % (hrd, addr_msb, gname_uc))
        reg_w.append(reg)
    tmp.append("\n")
    # assembly (perl Gen_reg_file order): 5 header elements (4 lines +
    # the '//BUS addr parameter' comment), then local params, then the
    # '//BUS wr access signal' banner, then the hwr assigns + trailing "\n"
    head = tmp[:5]
    tail = tmp[5:]
    wr = head + addr_param + ["\n\n//BUS wr access signal for each register\n"] + tail
    return wr, len(reg_w), reg_w


def gen_man_def(mod):
    """Gen_man_def -- bank wire/reg declarations. Returns lines."""
    msb = mod.func_num_w - 1
    txt = (
        "\n"
        "wire          reg_parity_error;\n"
        "wire          reg_parity_error_and;\n"
        "wire          reg_parity_error_or;\n"
        "wire   [31:0] reg_data_res               [%d:0];\n"
        "wire   [31:0] reg_data_w1s               [%d:0];\n"
        "wire   [31:0] reg_data_w1c               [%d:0];\n"
        "wire   [31:0] reg_data_w0s               [%d:0];\n"
        "wire   [31:0] reg_data_w0c               [%d:0];\n"
        "wire   [31:0] reg_data_wt                [%d:0];\n"
        "wire   [31:0] reg_data_rc                [%d:0];\n"
        "wire   [31:0] reg_data_wr                [%d:0];\n"
        "wire   [31:0] reg_data_hw                [%d:0];\n"
        "wire   [31:0] hw_wdata                   [%d:0];\n"
        "wire   [35:0] reg_default_value          [%d:0];\n"
        "wire   [%d:0] reg_parity_update;\n"
        "wire   [31:0] reg_enc_data_in            [%d:0];\n"
        "wire   [31:0] reg_enc_data_out           [%d:0];\n"
        "wire   [3 :0] reg_enc_parity_out         [%d:0];\n"
        "reg    [31:0] reg_enc_data               [%d:0];\n"
        "reg    [3 :0] reg_enc_parity             [%d:0];\n"
        "wire   [3 :0] reg_enc_parity_mux         [%d:0];\n"
        "wire   [31:0] reg_dec_data_out           [%d:0];\n"
        "wire   [3 :0] reg_dec_parity_out         [%d:0];\n"
        "wire   [%d:0] parity_dec_error;\n"
    ) % tuple([msb] * 21)
    return [txt]


def gen_attr_dec(mod):
    """Gen_attr_dec -- reg_data_* / hw_wdata assigns (bank decode)."""
    out = []
    num = 0
    blank = " " * 36
    for reg in mod.regs:
        if reg.reg_attr in ("RO", "RES"):
            continue
        num += 1
        flags = reg.flags
        # reversed digit list: list[0]=ro .. list[9]=res
        lst = [flags[k] for k in reversed(regmodel.FLAG_ORDER)]
        sc = "".join(str(x) for x in lst[8:4:-1])  # w1s,w1c,w0s,w0c
        res = Grp("32'h0;" if lst[9] == 0 else "{};")
        w1s = Grp("32'h0;" if lst[8] == 0 else "{};")
        w1c = Grp("32'h0;" if lst[7] == 0 else "{};")
        w0s = Grp("32'h0;" if lst[6] == 0 else "{};")
        w0c = Grp("32'h0;" if lst[5] == 0 else "{};")
        wt = Grp("32'h0;" if lst[4] == 0 else "{};")
        rc = Grp("32'h0;" if lst[3] == 0 else "{};")
        wr = Grp("32'h0;" if (lst[2] == 0 and lst[1] == 0) else "{};")
        hwz = (lst[1] == 0 and lst[3] == 0 and sc == "0000")
        hw = Grp("32'h0;" if hwz else "{};")
        hwd = Grp("32'h0;" if hwz else "{};")

        for f in reg.fields:
            w = f.width
            hwr = "hwr_" + reg.gname
            hrd = "hrd_" + reg.gname
            # perl 'X=(...) and (...)' idiom: the ,\n+blank prefix applies
            # for ALL widths (the `and` result is discarded)
            if w == 1:
                wr_t = hwr
                mwr_t = hwr + " & ~" + f.rname + "_mask"
            elif w == 32:
                wr_t = "32{" + hwr + "}"
                mwr_t = "{32{" + hwr + "}} & ~" + f.rname + "_mask"
            else:
                wr_t = "{%d{%s}}" % (w, hwr)
                mwr_t = "{%d{%s}} & ~%s_mask" % (w, hwr, f.rname)
            wr_t = ",\n" + blank + wr_t
            mwr_t = ",\n" + blank + mwr_t
            if w == 1:
                hw_t = f.rname + "_wr"
                hwd_t = f.rname + "_in"
            elif w == 32:
                hw_t = "32{" + f.rname + "_wr}"
                hwd_t = f.rname + "_in[31:0]"
            else:
                hw_t = "{%d{%s_wr}}" % (w, f.rname)
                hwd_t = "%s_in[%d:0]" % (f.rname, w - 1)
            hw_t = ",\n" + blank + hw_t
            hwd_t = ",\n" + blank + hwd_t
            # perl term prefixes (read from the s/\};/...};/ replacements):
            #   zero terms    ",w'h0"           (comma)
            #   w1 flag term  ",hwr"/",hrd"     (comma -- FIXED)
            #   w>1 flag term ",{w{hwr}}"       (comma)
            #   RC hw/hwd     ",field"          (comma -- FIXED)
            #   tmp terms     ",\n"+blank+X     (wr/hw/hwd/mwr)
            # The perl writes the w==1 flag and RC hw/hwd terms WITHOUT the
            # leading comma (s/\};/hwr_X};/) -- invalid Verilog the moment a
            # bank-member register carries a w==1 W1S/W1C/W0S/W0C/WT/RC
            # field after any other field.  Every legacy map keeps those
            # attributes inside bank-skipped Set*/Status* regs, so the perl
            # never emitted the broken line; v2 FuSa maps (STA_PAR) do.
            # Comma-prefix them here -- legacy output is untouched.
            zero = "," + "%d'h0" % w

            if f.rname == "reserved":
                if w == 1:
                    res.subst(",1'b1")
                elif w == 32:
                    res.wholesale("{32{%s}};" % hwr)
                else:
                    res.subst(",{%d{1'b1}}" % w)
                for g in (w1s, w1c, w0s, w0c, wt, rc, wr, hw, hwd):
                    g.subst(zero)
            elif f.attr in ("W1F", "W1S"):
                res.subst(zero)
                if w == 1:
                    w1s.subst("," + hwr)
                elif w == 32:
                    w1s.wholesale("{32{%s}};" % hwr)
                else:
                    w1s.subst(",{%d{%s}}" % (w, hwr))
                for g in (w1c, w0s, w0c, wt, rc, wr):
                    g.subst(zero)
                if f.attr == "W1S":
                    hw.subst(hw_t)
                    hwd.subst(hwd_t)
                else:
                    hw.subst(zero)
                    hwd.subst(zero)
            elif f.attr == "W1C":
                res.subst(zero)
                w1s.subst(zero)
                if w == 1:
                    w1c.subst("," + hwr)
                elif w == 32:
                    w1c.wholesale("{32{%s}};" % hwr)
                else:
                    w1c.subst(",{%d{%s}}" % (w, hwr))
                for g in (w0s, w0c, wt, rc, wr):
                    g.subst(zero)
                hw.subst(hw_t)
                hwd.subst(hwd_t)
            elif f.attr == "W0S":
                for g in (res, w1s, w1c):
                    g.subst(zero)
                if w == 1:
                    w0s.subst("," + hwr)
                elif w == 32:
                    w0s.wholesale("{32{%s}};" % hwr)
                else:
                    w0s.subst(",{%d{%s}}" % (w, hwr))
                for g in (w0c, wt, rc, wr):
                    g.subst(zero)
                hw.subst(hw_t)
                hwd.subst(hwd_t)
            elif f.attr in ("W0F", "W0C"):
                for g in (res, w1s, w1c, w0s):
                    g.subst(zero)
                if w == 1:
                    w0c.subst("," + hwr)
                elif w == 32:
                    w0c.wholesale("{32{%s}};" % hwr)
                else:
                    w0c.subst(",{%d{%s}}" % (w, hwr))
                for g in (wt, rc, wr):
                    g.subst(zero)
                if f.attr == "W0C":
                    hw.subst(hw_t)
                    hwd.subst(hwd_t)
                else:
                    hw.subst(zero)
                    hwd.subst(zero)
            elif f.attr == "WT":
                for g in (res, w1s, w1c, w0s, w0c):
                    g.subst(zero)
                if w == 1:
                    wt.subst("," + hwr)
                elif w == 32:
                    wt.wholesale("{32{%s}};" % hwr)
                else:
                    wt.subst(",{%d{%s}}" % (w, hwr))
                for g in (rc, wr, hw, hwd):
                    g.subst(zero)
            elif f.attr == "RC":
                data = f.rname
                for g in (res, w1s, w1c, w0s, w0c, wt):
                    g.subst(zero)
                if w == 1:
                    rc.subst("," + hrd)
                    hw.subst("," + data)
                    hwd.subst("," + data)
                elif w == 32:
                    rc.wholesale("{32{%s}};" % hrd)
                    hw.wholesale(data + "[31:0];")
                    hwd.wholesale(data + "[31:0];")
                else:
                    rc.subst(",{%d{%s}}" % (w, hrd))
                    hw.subst("," + data)
                    hwd.subst("," + data)
                wr.subst(zero)
            elif f.attr in ("RW", "WO"):
                res.subst(zero)
                w1s.subst(zero)
                w1c.subst(zero)
                for g in (w0s, w0c, wt, rc):
                    g.subst(zero)
                wr.subst(wr_t)
                hw.subst(zero)
                hwd.subst(zero)
            elif f.attr in ("MRW", "MWO"):
                res.subst(zero)
                w1s.subst(zero)
                w1c.subst(zero)
                for g in (w0s, w0c, wt, rc):
                    g.subst(zero)
                wr.subst(mwr_t)
                hw.subst(zero)
                hwd.subst(zero)
            elif f.attr == "HW":
                res.subst(zero)
                w1s.subst(zero)
                w1c.subst(zero)
                for g in (w0s, w0c, wt, rc):
                    g.subst(zero)
                wr.subst(wr_t)
                hw.subst(hw_t)
                hwd.subst(hwd_t)
            elif f.attr == "RO":
                for g in (res, w1s, w1c, w0s, w0c, wt, rc, wr, hw, hwd):
                    g.subst(zero)
        for g in (res, w1s, w1c, w0s, w0c, wt, rc, wr, hw, hwd):
            g.clean()
        if reg.skipped_from_bank():
            num -= 1
        if not reg.skipped_from_bank():
            idx = num - 1
            out.append("\n// address %x\n" % reg.offset_int)
            out.append("assign reg_data_res[%d][31:0] = %s\n" % (idx, res.val))
            out.append("assign reg_data_w1s[%d][31:0] = %s\n" % (idx, w1s.val))
            out.append("assign reg_data_w1c[%d][31:0] = %s\n" % (idx, w1c.val))
            out.append("assign reg_data_w0s[%d][31:0] = %s\n" % (idx, w0s.val))
            out.append("assign reg_data_w0c[%d][31:0] = %s\n" % (idx, w0c.val))
            out.append("assign reg_data_wt[%d][31:0]  = %s\n" % (idx, wt.val))
            out.append("assign reg_data_rc[%d][31:0]  = %s\n" % (idx, rc.val))
            out.append("assign reg_data_wr[%d][31:0]  = %s\n" % (idx, wr.val))
            out.append("assign reg_data_hw[%d][31:0]  = %s\n" % (idx, hw.val))
            out.append("assign hw_wdata[%d][31:0]         = %s\n"
                       % (idx, hwd.val))
    return out


def reg_value_loop1(mod):
    """Reg_value loop-1: per-reg concat of verbatim defaults.

    Perl accumulates '{...};' via s/};/,TERM};/, the Gen_ecc_logic consumer
    strips '{'/'};' from the stored value and re-appends with a leading ','.
    We store the inner content (braces and ';' already stripped).
    """
    for reg in mod.reg_w_regs():
        g = Grp("{};")
        for f in reg.fields:
            pr = regmodel.parse_value(f.value)
            # perl R1280/R1283: BOTH replacements carry a leading comma
            #   s/\};/,${width}'h0};/        (reserved)
            #   s/\};/,${width}'$radix$str};/ (others)
            if f.rname == "reserved":
                g.subst(",%d'h0" % f.width)
            else:
                radix, digits = pr if pr else ("h", "0")
                g.subst(",%d'%s%s" % (f.width, radix, digits))
        g.clean()
        reg.reg_value_concat = g.val[1:-2]  # '{inner};' -> 'inner'


def reg_value_loop2(mod):
    """Reg_value loop-2: per-reg hex default + mask (informational)."""
    for reg in mod.regs:
        val_bits = []
        mask_bits = []
        for f in reg.fields:
            val_bits.append(format(regmodel.value_int(f.value, f.width),
                                   "0%db" % f.width))
            if f.rname == "reserved" or f.attr in ("RO", "RC"):
                mask_bits.append("0" * f.width)
            else:
                mask_bits.append("1" * f.width)
        reg.reg_value_hex = "%08X" % int("".join(val_bits) or "0", 2)
        reg.reg_mask_hex = "%08X" % int("".join(mask_bits) or "0", 2)


def gen_ecc_reg(mod, ext_int):
    """Gen_ecc_reg -- PASSWORD always + status register alwayss."""
    ext_names = ["parity_err"] + [n for n, _ in ext_int]
    L = ["//---ECC register wr logic\n"]
    for reg in mod.regs:
        if not (reg.ecc and reg.reg_attr != "RO"):
            continue
        if reg.is_fusa_or_mask():
            if not reg.is_password():
                continue  # FUSA_CTRL / Mask regs: bank-driven, no always
            # ---- PASSWORD ----
            w1c_flag = any(f.attr == "W1C" for f in reg.fields)
            if w1c_flag:
                for f in reg.fields:
                    if f.rname == "reserved" or f.attr != "W1C":
                        continue
                    w = f.width
                    idx = "[%d]" % f.msb if w == 1 else "[%d:%d]" % (f.msb, f.lsb)
                    L.append("\n  always @(posedge pclk or negedge presetn)"
                             "\n  begin\n      if (!presetn) begin\n"
                             "          %s  <= %s;\n      end" %
                             (f.rname, _vlog_value(f)))
                    L.append("\n      else if (|%s_wr) begin" % f.rname)
                    for n in range(w):
                        L.append("\n          if (%s_wr[%d]) \n"
                                 "              %s[%d] <= %s_in[%d];"
                                 % (f.rname, n, f.rname, n, f.rname, n))
                    L.append("\n      end")
                    L.append("\n      else if (hwr_%s) begin" % reg.gname)
                    if w == 1:
                        L.append("\n          if (pwdata%s == 1'b1) begin\n"
                                 "              %s  <= ~pwdata%s;\n          end"
                                 % (idx, f.rname, idx))
                    else:
                        for n in range(w):
                            cur = f.lsb + n
                            L.append("\n          if (pwdata[%d] == 1'b1)\n"
                                     "              %s[%d]  <= ~pwdata[%d];"
                                     % (cur, f.rname, n, cur))
                    L.append("\n      end")
                    L.append("\n  end\n        ")
            else:
                L.append("\n  always @(posedge pclk or negedge presetn)"
                         "\n  begin\n      if (!presetn) begin")
                for f in reg.fields:
                    if f.rname == "reserved" or f.attr == "RO":
                        continue
                    L.append("\n          %s  <= %s;" % (f.rname, _vlog_value(f)))
                for f in reg.fields:
                    if f.attr != "W1C":
                        continue
                    w = f.width
                    L.append("\n      end \n      else if (|%s_wr) begin"
                             % f.rname)
                    for n in range(w):
                        L.append("\n          if (%s_wr[%d]) \n"
                                 "              %s[%d] <= %s_in[%d];"
                                 % (f.rname, n, f.rname, n, f.rname, n))
                L.append("\n      end \n      else if (hwr_%s) begin"
                         % reg.gname)
                for f in reg.fields:
                    if f.rname == "reserved":
                        continue
                    w = f.width
                    idx = "[%d]" % f.msb if w == 1 else "[%d:%d]" % (f.msb, f.lsb)
                    if f.attr == "W1C":
                        if w == 1:
                            L.append("\n          if (pwdata%s == 1'b1) begin"
                                     "\n              %s  <= ~pwdata%s;"
                                     "\n          end" % (idx, f.rname, idx))
                        else:
                            for n in range(w):
                                cur = f.lsb + n
                                L.append("\n          if (pwdata[%d] == 1'b1)"
                                         "\n              %s[%d]  <= ~pwdata[%d];"
                                         % (cur, f.rname, n, cur))
                    else:
                        L.append("\n          %s  <= pwdata%s;"
                                 % (f.rname, idx))
                L.append("\n      end")
                if any(f.rname == "parity_invert" for f in reg.fields):
                    L.append("\n      else if(parity_invert_d) begin\n"
                             "          parity_invert <= 1'b0;\n      end\n"
                             "            ")
                L.append("\n  end\n        ")
            continue
        if not reg.skipped_from_bank():
            # bank-member ECC regs (v2 FuSa shape: STA_PAR / CFG_REGST):
            # storage is the parity bank (bank decode W1C/WO + gen_reg_wr
            # readouts); a bare always here would multi-drive the names.
            # Legacy maps only ever reach branch 2 with Set*/Status*.
            continue
        # ---- branch 2: Set / Status / other ECC regs ----
        for f in reg.fields:
            if not reg.ecc:
                continue
            if re.search(r"^PASSWORD$|^FUSA_CTRL$|Mask\d$", reg.gname):
                continue  # note: single-digit Mask guard (perl 2240)
            if f.rname == "reserved" or f.attr == "RO":
                continue
            w = f.width
            idx = "[%d]" % f.msb if w == 1 else "[%d:%d]" % (f.msb, f.lsb)
            if reg.is_set():
                if f.attr == "RW":
                    raise RdlError("REG %s: set should be WO attribute"
                                   % reg.gname)
                continue
            if not f.rname.endswith("_status"):
                L.append("\n  always @(posedge pclk or negedge presetn)"
                         "\n  begin\n      if (!presetn) begin\n"
                         "          %s  <= %s;\n      end"
                         "\n      else if (hwr_%s) begin\n"
                         "          %s  <= pwdata%s;\n      end\n  end\n        "
                         % (f.rname, _vlog_value(f), reg.gname, f.rname, idx))
                continue
            field_pre = f.rname.replace("_status", "")
            if field_pre not in ext_names:
                continue
            set_reg = reg.status_set_regname()
            if w > 1:
                L.append("\n  reg  [%d-1:0] %s;%s\n"
                         "genvar i_%s;\ngenerate\n"
                         "for(i_%s=0;i_%s<%d;i_%s=i_%s+1)begin: gen_%s\n"
                         % (w, f.rname, " " * 26, f.rname, f.rname, f.rname,
                            w, f.rname, f.rname, f.rname))
                L.append("\n  always @(posedge pclk or negedge presetn)"
                         "\n  begin\n      if (!presetn) begin\n"
                         "          %s[i_%s]  <= 1'b0;\n      end"
                         % (f.rname, f.rname))
            else:
                L.append("\nreg                  %s;%s\n"
                         "  always @(posedge pclk or negedge presetn)"
                         "\n  begin\n      if (!presetn) begin\n"
                         "          %s  <= %s;\n      end"
                         % (f.rname, " " * 26, f.rname, _vlog_value(f)))
            if f.rname == "parity_err_status":
                L.append("\n      else if (reg_parity_error) begin\n"
                         "          %s  <= %s;\n      end"
                         % (f.rname, _hvalue(f)))
            elif f.attr in ("HW", "W1C"):
                if w == 1:
                    L.append("\n      else if (%s_wr) begin\n"
                             "          %s  <= %s_in;\n      end"
                             % (f.rname, f.rname, f.rname))
                else:
                    L.append("\n      else if (%s_wr[i_%s]) begin"
                             % (f.rname, f.rname))
                    L.append(" \n          %s[i_%s]  <= %s_in[i_%s];"
                             % (f.rname, f.rname, f.rname, f.rname))
                    L.append("\n      end")
            if w == 1:
                L.append("\n      else if (hwr_%s & pwdata%s) begin\n"
                         "          %s  <= 1'b1;\n      end"
                         % (set_reg, idx, f.rname))
            else:
                L.append("\n      else if (hwr_%s) begin" % set_reg)
                L.append("\n          if (pwdata[i_%s+%d])\n"
                         "              %s[i_%s]  <= 1'b1;"
                         % (f.rname, f.lsb, f.rname, f.rname))
                L.append("\n      end")
            L.append("\n      else if (hwr_%s) begin" % reg.gname)
            if f.attr in ("RW", "HW"):
                L.append("\n          %s  <= pwdata%s;" % (f.rname, idx))
            if f.attr == "W1C":
                if w == 1:
                    L.append("\n          if (pwdata%s == 1'b1) begin\n"
                             "              %s  <= ~pwdata%s;\n          end"
                             % (idx, f.rname, idx))
                else:
                    L.append("\n          if (pwdata[i_%s+%d] == 1'b1)\n"
                             "              %s[i_%s]  <= ~pwdata[i_%s+%d];"
                             % (f.rname, f.lsb, f.rname, f.rname,
                                f.rname, f.lsb))
            L.append("\n      end\n  end\n        ")
            if w > 1:
                L.append("\nend\nendgenerate\n        ")
    L.append(
        "\n"
        "  always @(posedge pclk or negedge presetn)\n"
        "  begin\n"
        "      if (!presetn) begin\n"
        "          parity_invert_d <= 1'b0;\n"
        "      end\n"
        "\n"
        "      else\n"
        "          parity_invert_d <= parity_invert;\n"
        "      end\n"
        "\n"
        "  always @(posedge pclk or negedge presetn)\n"
        "  begin\n"
        "      if (!presetn) begin\n"
        "          parity_invert_d2 <= 1'b0;\n"
        "      end\n"
        "\n"
        "      else\n"
        "          parity_invert_d2 <= parity_invert_d;\n"
        "      end\n"
        "\n"
        "   assign parity_invert_posedge = parity_invert & (~parity_invert_d);\n"
        "   assign parity_invert_d_posedge = parity_invert_d & (~parity_invert_d2);\n"
        "   assign parity_invert_2cycle = parity_invert_posedge | parity_invert_d_posedge;\n"
        "            ")
    return L


def gen_ecc_logic(mod):
    """Gen_ecc_logic -- bank default values + enc/dec generate."""
    L = ["\n//--- ECC process logic\n"]
    num = 0
    for reg in mod.reg_w_regs():
        num += 1
        g = Grp("{};")
        g.subst("," + reg.reg_value_concat)
        g.clean()
        if reg.skipped_from_bank():
            num -= 1
        if not reg.skipped_from_bank():
            L.append("assign reg_default_value[%d][31:0] = %s\n"
                     % (num - 1, g.val))
    fn = mod.func_num_w
    L.append(
        "\n"
        "genvar i;\n"
        "genvar j;\n"
        "generate\n"
        "  for (i=0; i<%d; i=i+1) begin: reg_data_bank\n"
        "    for (j=0; j<32; j=j+1) begin: in_bank_data_l\n"
        "      assign reg_enc_data_in[i][j] = \n"
        "             reg_data_res[i][j] ? 1'b0                :\n"
        "             reg_data_hw[i][j]  ? hw_wdata[i][j]      :\n"
        "             reg_data_w1s[i][j] ? pwdata[j]  | reg_enc_data[i][j]:\n"
        "             reg_data_w1c[i][j] ? ~pwdata[j] & reg_enc_data[i][j]:\n"
        "             reg_data_w0s[i][j] ? ~pwdata[j] | reg_enc_data[i][j]:\n"
        "             reg_data_w0c[i][j] ? pwdata[j]  & reg_enc_data[i][j]:\n"
        "             reg_data_wt[i][j]  ? ~reg_enc_data[i][j] :\n"
        "             reg_data_wr[i][j]  ? pwdata[j]           :\n"
        "             reg_data_rc[i][j]  ? 1'b0                :\n"
        "\t\t                          reg_enc_data[i][j]  ; \n"
        "    end\n" % fn)
    L.append(
        "\n"
        "    assign reg_parity_update[i] = ~fault_injection_en &((|reg_data_w1s[i])| \n"
        "                                                       (|reg_data_w1c[i]) |\n"
        "                                                       (|reg_data_w0s[i]) |\n"
        "                                                       (|reg_data_w0c[i]) |\n"
        "                                                       (|reg_data_wt[i] ) |\n"
        "                                                       (|reg_data_rc[i] ) |\n"
        "                                                       (|reg_data_wr[i] ) |\n"
        "                                                       (|reg_data_hw[i] ))\n"
        "                                | fault_injection_en & (|reg_data_wr[i] )\n"
        "                                | parity_invert_2cycle; \n"
        "\n"
        "\n"
        "  end\n")
    L.append("endgenerate\n\n\n")
    L.append("//Default value logic\n")
    L.append(
        "\n"
        "//get the parity bits of default value\n"
        "generate \n"
        "  for (i=0; i<%d; i=i+1) begin: parity_default\n"
        "    parity_enc #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)\n"
        "      u_parity_deft_enc(\n"
        "        .parity_enc_bypass         (1'b0                           ), //I\n"
        "        .parity_enc_data_in        (reg_default_value[i][31:0]     ), //I\n"
        "        .parity_enc_parity_in      (4'h0                           ), //I\n"
        "        .parity_enc_data_out       (                               ), //O\n"
        "        .parity_enc_parity_out     (reg_default_value[i][35:32]    )  //O\n"
        "    );\n"
        "  end\n"
        "endgenerate\n" % fn)
    L.append(
        "\n"
        "generate \n"
        "  for (i=0; i<%d; i=i+1) begin: reg_parity\n"
        "    assign reg_enc_parity_mux[i] = parity_invert_2cycle ? (~reg_enc_parity[i]) : reg_enc_parity_out[i];\n"
        "\n"
        "    always @(posedge pclk or negedge presetn)\n"
        "      if (!presetn) begin\n"
        "        reg_enc_parity[i] <= reg_default_value[i][35:32];\n"
        "      end else if(reg_parity_update[i]) begin\n"
        "        reg_enc_parity[i] <= reg_enc_parity_mux[i][3:0];\n"
        "      end\n"
        "\n"
        "    always @(posedge pclk or negedge presetn)\n"
        "      if (!presetn) begin\n"
        "        reg_enc_data[i] <= reg_default_value[i][31:0];\n"
        "      end else if(reg_parity_update[i]) begin\n"
        "        reg_enc_data[i] <= reg_enc_data_out[i][31:0];\n"
        "      end\n"
        "\n"
        "    parity_enc #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)\n"
        "      u_parity_enc(\n"
        "        .parity_enc_bypass         (fault_injection_en&(|reg_data_wr[i])), //I\n"
        "        .parity_enc_data_in        (reg_enc_data_in[i][31:0]   ), //I\n"
        "        .parity_enc_parity_in      (parity_fault_injection     ), //I\n"
        "        .parity_enc_data_out       (reg_enc_data_out[i][31:0]  ), //O\n"
        "        .parity_enc_parity_out     (reg_enc_parity_out[i][3:0] )  //O\n"
        "    );\n"
        "\n"
        "    parity_dec #(PARITY_MODE, ENC_BIT, DATA_WD, PARITY_WD)\n"
        "      u_parity_dec(\n"
        "        .parity_dec_bypass         (parity_decoder_bypass      ), //I\n"
        "        .parity_dec_data_in        (reg_enc_data[i][31:0]      ), //I\n"
        "        .parity_dec_parity_in      (reg_enc_parity[i][3:0]     ), //I\n"
        "        .parity_dec_data_out       (reg_dec_data_out[i][31:0]  ), //O\n"
        "        .parity_dec_parity_out     (reg_dec_parity_out[i][3:0] ), //O\n"
        "        .parity_dec_error          (parity_dec_error[i]        )  //O\n"
        "    );\n"
        "  end\n"
        "endgenerate\n"
        "\n" % fn)
    # parity_dec_error OR / AND chains
    b1, b2 = " " * 32, " " * 2
    L.append("//get register parity error information\n")
    L.append("\n//REG_field: reg_ecc_error_type\n")
    L.append("assign reg_parity_error_or    =\n")
    for i in range(fn):
        s = (b1 if i % 2 == 0 else b2) + "parity_dec_error[%d] |" % i
        if i == fn - 1:
            s = s.replace("|", ";")
        L.append(s)
        if i % 2 != 0:
            L.append("\n")
    L.append("\n")
    L.append("\n\nassign reg_parity_error_and   =\n")
    L.append("%sreg_parity_error_or & \n" % b1)
    for i in range(fn):
        s = (b1 if i % 2 == 0 else b2) + "parity_dec_error[%d] &" % i
        if i == fn - 1:
            s = s.replace("&", ";")
        L.append(s)
        if i % 2 != 0:
            L.append("\n")
    L.append("\n")
    return L


def gen_reg_wr(mod, ext_int):
    """Gen_reg_wr -- field assigns from corrected bank + error regs."""
    L = ["//get configuration and status data from ecc correct data\n"]
    src = "reg_dec_data_out"
    num = 0
    for reg in mod.regs:
        L.append("//%s\n" % reg.offset)
        if reg.reg_attr in ("RO", "RES"):
            L.append("\n")
            continue
        num += 1
        if reg.skipped_from_bank():
            num -= 1
            L.append("\n")
            continue
        numi = num - 1
        for f in reg.fields:
            if f.rname == "reserved" or f.attr == "RO":
                continue
            w = f.width
            idx = "" if w == 1 else "[%d:0]" % (w - 1)
            if f.attr == "RC":
                sig = "assign %s_cap%s" % (f.rname, idx)
            elif re.search(r"mem_cfg\d*$", f.rname):
                sig = "assign %s_pre%s" % (f.rname, idx)
            else:
                sig = "assign %s%s" % (f.rname, idx)
            fmt = "%-30s" % sig
            if w == 1:
                s = "%s = %s[%d][%d];" % (fmt, src, numi, f.msb)
            else:
                s = "%s = %s[%d][%d:%d];" % (fmt, src, numi, f.msb, f.lsb)
            L.append(s + " //deft: %s\n" % f.value)
            if re.search(r"mem_cfg\d*$", f.rname):
                for k in range(w - 1 + 1):
                    L.append("cell_buf u_%s_%d (.I(%s_pre[%d]), "
                             ".Z(%s[%d]));\n" % (f.rname, k, f.rname, k,
                                                 f.rname, k))
        L.append("\n")
    L.append("//Shadow registers\n")
    # shadow instances unsupported (model rejects shad)
    str_int = [" assign %-16s = (%s)? %s : %s;\n"
               % ("reg_parity_error", "parity_invert_2cycle",
                  "reg_parity_error_and", "reg_parity_error_or")]
    for name, width in ext_int:
        int_out = re.sub(r"_err_err", "_err", name + "_err")
        if width == 1:
            str_int.append(
                " \n"
                "  always @(posedge pclk or negedge presetn)\n"
                "  begin\n"
                "      if(!presetn) begin\n"
                "        %s <= 1'b0; \n"
                "   end \n"
                "   else begin\n"
                "        %s <= ~%s_mask & %s_status; \n"
                "   end\n"
                "end\n"
                "\n" % (int_out, int_out, name, name))
        else:
            for bit in range(width):
                str_int.append(
                    " \n"
                    "  always @(posedge pclk or negedge presetn)\n"
                    "  begin\n"
                    "      if(!presetn) begin\n"
                    "        %s[%d] <= 1'b0; \n"
                    "   end \n"
                    "   else begin\n"
                    "        %s[%d] <= ~%s_mask[%d] & %s_status[%d]; \n"
                    "   end\n"
                    "end\n"
                    "\n" % (int_out, bit, int_out, bit, name, bit, name, bit))
    L.append("\n// register_error\n" + " ".join(str_int))
    L.append(
        "\n"
        "// mission_int, include SW parity_invert injection\n"
        "\n"
        "  always @(posedge pclk or negedge presetn)\n"
        "  begin\n"
        "      if(!presetn) begin\n"
        "        mission_int <= 1'b0; \n"
        "   end \n"
        "   else begin\n"
        "        mission_int <= ~parity_err_mask & parity_err_status; \n"
        "   end\n"
        "end\n"
        "\n"
        "\n")
    return L


def gen_reg_rd(mod):
    """Gen_reg_rd -- software read mux + prdata register."""
    aw = mod.addr_width
    ecc_first = mod.ecc_first_offset()
    L = ["//Bus read reg logic\n", "always @(*) begin\n",
         "  case(paddr[%d:2])\n" % (aw - 1)]
    blank45 = " " * 45
    for reg in mod.regs:
        g = Grp("{};")
        for f in reg.fields:
            w = f.width
            wsuf = "" if w == 1 else "[%d:0]" % (w - 1)
            if f.rname == "reserved":
                sig = "%d'h0" % w
            elif f.attr == "RC":
                sig = f.rname + "_cap" + wsuf
            elif f.attr in ("WO", "MWO"):
                sig = "%d'h0" % w
            elif (ecc_first is not None and reg.offset == ecc_first
                    and reg.is_password()):
                sig = "32'h0badbeef"
            else:
                sig = f.rname + wsuf
            g.subst(",\n" + blank45 + sig)
        g.clean()
        fmt = "%-35s" % ("      %s:" % reg.gname_uc)
        L.append("//0x%x\n" % reg.offset_int)
        L.append("%s prdata_in = %s\n" % (fmt, g.val))
    L.append("//shadow register read\n")
    L.append("      default: prdata_in = 32'h0;\n")
    L.append("  endcase\n")
    L.append("end\n")
    L.append(
        "\n"
        "always @(posedge pclk or negedge presetn) begin\n"
        "  if (!presetn) begin\n"
        "    prdata               <= 32'h0;\n"
        "  end else if(apb_rd) begin\n"
        "    prdata               <= prdata_in;\n"
        "  end\n"
        "end\n"
        "\n"
        "assign pready  = 1'b1;\n"
        "assign pslverr = 1'b0;\n"
        "\n")
    return L


def gen_macro_def(mod):
    """Gen_macro_def -- commented \`define footer + bit info."""
    upper = mod.name.upper()
    base_val = int(mod.base_addr, 16) if re.match(
        r"^0[xX][0-9a-fA-F]+$", mod.base_addr or "") else int(mod.base_addr or 0)
    base_str = "32'h%X" % base_val
    def_base = "BASE_ADDR_" + upper
    L = ["\n\n//---- *reg addr define*----",
         "\n//`ifndef %s_DEF_V_" % upper,
         "\n//`define %s_DEF_V_\n" % upper,
         "//\n",
         "//Register macro defines\n",
         "//\n",
         "//`define %-40s  %s\n" % (def_base, base_str)]
    for reg in mod.regs:
        f1 = "%-40s" % ("OFST_%s_%s" % (upper, reg.gname_uc))
        f2 = "%-10s" % def_base
        f3 = "%04x" % reg.offset_int
        L.append("//`define %s  (%s + 'h%s)\n" % (f1, f2, f3))
    L.append("//`endif //%s_DEF_V_\n\n\n" % upper)
    L.append("//---- *reg sig bit info*----\n")
    for reg in mod.regs:
        for f in reg.fields:
            if f.rname == "reserved":
                continue
            f1 = "%-30s" % f.rname
            f2 = "%-40s" % ("OFST_%s_%s" % (upper, reg.gname_uc))
            if f.width == 1:
                L.append("//%s,`%s,bit[%d]\n" % (f1, f2, f.msb))
            else:
                L.append("//%s,`%s,bit[%d:%d]\n" % (f1, f2, f.msb, f.lsb))
    return L


# ===========================================================================
# Top-level assembly (Gen_reg_file)
# ===========================================================================

def generate(mod, date_str, user_str):
    out = []
    # copyright header (perl printf literals)
    out.append(
        "/*\n * Horizon Robotics\n *\n * Copyright (C) 2022 Horizon "
        "Robotics Inc.\n * All rights reserved.\n *\n * This file is auto "
        "generated by Horizon Robotics for Sigiriya Chip.\n * Version : "
        "J6B-fusa update\n * %s %s*/" % (date_str, user_str))
    out.append("\n//Auto generated file - Parity script %s\n" % VERSION)
    out.append("\nmodule %s (/*autoarg*/);\n\n" % mod.name)
    out.append("parameter ADDR_BASE   = %d'h0; //lower bits of the bus addr\n"
               % mod.addr_width)
    out.append("localparam PARITY_MODE = 0;    //0-EVEN/1-ODD\n")
    out.append("localparam ENC_BIT     = 8;    //Number of bits to calculate "
               "parity on\n")
    out.append("localparam DATA_WD     =32;    //Data bus width which to be "
               "protected\n")
    out.append("localparam PARITY_WD   = 4;    //Parity bit of data bus\n")

    iop, ext_int = gen_rtl_iop(mod)
    # Gen_reg_file: every <int>_mask / <int>_set must exist
    all_fields = [f.rname for r in mod.regs for f in r.fields]
    for name, _w in ext_int:
        if (name + "_mask") not in all_fields:
            raise RdlError("A %s_mask must be added for the %s_status enable."
                           % (name, name))
        if (name + "_set") not in all_fields:
            raise RdlError("A %s_set must be added for the %s_status value "
                           "set." % (name, name))

    out.append("\n")
    out.append("//-----------------------------------\n")
    out.append("//Port signals definition \n")
    out.append("//-----------------------------------\n")
    out += iop
    out.append("\n\n")

    out.append("//-----------------------------------\n")
    out.append("//Define list\n")
    out.append("//-----------------------------------\n")
    out.append("/*autodefine*/\n\n//auto wires{{{\n\n//}}}\n"
               "//auto regs{{{\n\n//}}}\n//End of automatic define\n\n")

    out += gen_man_def(mod)

    wr, _reg_num_w, _reg_w = gen_wr_logic(mod)
    out.append("\n")
    out.append("//-----------------------------------\n")
    out.append("//Glue logic\n")
    out.append("//-----------------------------------\n")
    out += wr

    reg_value_loop1(mod)
    reg_value_loop2(mod)
    out.append("\n//reg attribution logic")
    out += gen_attr_dec(mod)
    out.append("\n\n")

    out += gen_ecc_reg(mod, ext_int)
    # parity_decoder_enable absent from the map (v2 FuSa CTRL carries no
    # such field) -> decoder hard-enabled; the perl leaves an undeclared,
    # X-evaluated enable that permanently bypasses the decoder.
    if any(f.rname == "parity_decoder_enable"
           for r in mod.regs for f in r.fields):
        out.append("\nassign parity_decoder_bypass = ~parity_decoder_enable;\n")
    else:
        out.append("\nassign parity_decoder_bypass = 1'b0;\n")
    out += gen_ecc_logic(mod)
    out.append("\n\n")

    out += gen_reg_wr(mod, ext_int)
    # Control names the bank/mission_int logic references unconditionally:
    # when the map carries the field it is read out of the bank (above) or
    # driven by the *_status machinery; when it does not, tie them to their
    # SAFE state (no injection, no status) so nothing evaluates X.
    field_names = {f.rname for r in mod.regs for f in r.fields}
    for nm, tie in (("fault_injection_en", "1'b0"),
                    ("parity_fault_injection[3:0]", "4'h0"),
                    ("parity_invert", "1'b0"),
                    ("parity_err_status", "1'b0"),
                    ("parity_err_mask", "1'b0")):
        if nm.split("[")[0] not in field_names:
            out.append("assign %s = %s;\n" % (nm, tie))
    out.append("\n")

    out += gen_reg_rd(mod)
    out.append("\n\n")

    out += gen_macro_def(mod)
    out.append("\n\n")
    out.append("endmodule")

    text = "".join(out)
    # Auto_def_post: strip leftover vim-macro lines
    lines = [ln for ln in text.splitlines(True)
             if not re.search(r"reg\s*\[i\]", ln)
             and not re.search(r"wire\s*\[i\]", ln)]
    return "".join(lines)


def main():
    args = sys.argv[1:]
    infile = None
    outfile = None
    date_str = None
    user_str = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-o":
            outfile = args[i + 1]
            i += 2
        elif a == "--date":
            date_str = args[i + 1]
            i += 2
        elif a == "--user":
            user_str = args[i + 1]
            i += 2
        else:
            if infile is not None:
                sys.stderr.write("usage: rdl2reg.py <in.rdl> [-o out.v.raw] "
                                 "[--date s] [--user s]\n")
                sys.exit(1)
            infile = a
            i += 1
    if infile is None:
        sys.stderr.write("usage: rdl2reg.py <in.rdl> [-o out.v.raw] "
                         "[--date s] [--user s]\n")
        sys.exit(1)
    if outfile is None:
        outfile = os.path.splitext(os.path.basename(infile))[0] + ".v.raw"
    if date_str is None:
        date_str = datetime.now().strftime("Date : %Y-%m-%d %H:%M:%S")
    if user_str is None:
        try:
            user_str = subprocess.check_output(
                ["whoami"]).decode().strip()
        except Exception:
            user_str = "unknown"

    print("\n[INFO]: input rdl file is  %s" % infile)
    print("[INFO]: output file name is %s" % outfile)
    try:
        mod = parse_rdl(infile)
        text = generate(mod, date_str, user_str)
    except RdlError as e:
        sys.stderr.write("[ERROR] %s\n" % e)
        sys.exit(1)
    with open(outfile, "w") as fh:
        fh.write(text)
    print("[INFO]: %d regs, bank width %d, ext_int %s"
          % (len(mod.regs), mod.func_num_w,
             [n for n, _ in getattr(mod, "ext_int", [])]))
    print("[INFO]: Generation DONE")


if __name__ == "__main__":
    main()
