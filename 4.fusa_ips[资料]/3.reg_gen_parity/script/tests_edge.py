#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tests_edge.py -- special-case / edge-case test suite for reg_gen_py.

Verifies rdl2reg.py + regmodel.py (+ excel2rdl.py when openpyxl exists)
against the perl reg_gen_parity.pl semantics re-derived from the perl
source and the taylor_v3.v ground truth:

  * attribute dispatch matrix (attr_dec groups, ports, wr/rd paths)
  * width variants w1 / 1<w<32 / w32 (wholesale, replication, padding)
  * w>1 *_status -> generate loop (per-bit hw / set / W1C forms)
  * v2-style layout (PASSWORD/FUSA_CTRL outside the ECC region)
  * DefaultValue radix variants (b/o/d/h, verbatim round trip)
  * repeated reserved rows (reserved, reserved_1, ... -> perl 'reserved')
  * error paths (bad bits, dup names, bad attr, non-APB3, missing
    _set/_mask, unsupported cdc/shadow props, sw/attr conflicts)
  * xlsx -> RDL -> model round-trip equality (needs openpyxl)

Every expected string is built programmatically from the perl sprintf
templates (never hand-counted spaces).  Run:  python3 tests_edge.py
"""

import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import regmodel
from regmodel import Field, Reg, Module, RdlError
import rdl2reg

B36 = " " * 36
B45 = " " * 45
B51 = " " * 51


# ---------------------------------------------------------------------------
# perl sprintf helpers -- the single source of the expected-string formats
# ---------------------------------------------------------------------------

def IDX2(width):
    """non-ecc port index: 'x6' or '[%-2d:0]'."""
    return " " * 6 if width == 1 else "[%-2d:0]" % (width - 1)


def IDX5(width):
    """ecc-section port index: 'x6' or '[%-5s' of '<n>:0]'."""
    return " " * 6 if width == 1 else "[%-5s" % ("%d:0]" % (width - 1))


def P_OUT(width, name):
    return "    output %s     %s;\n" % (IDX2(width), name)


def P_IN(width, name):
    return "    input  %s     %s;\n" % (IDX2(width), name)


def P_OUT5(width, name):
    return "    output %s     %s;\n" % (IDX5(width), name)


def MUX(name):
    """read-mux case label, '%-35s' of '      NAME:'."""
    return ("      %s:" % name).ljust(35)


def HWRW(name, aw=13, gate=False, rd=False):
    """'assign h[rw]_X...' define-list line ('%-34s' padded LHS)."""
    sig = ("hrd_" if rd else "hwr_") + name
    s = "assign %s = apb_%s && (paddr[%d:2] == %s)" % (
        sig.ljust(34), "rd" if rd else "wr", aw - 1, name.upper())
    if gate:
        return s + "\n" + B51 + "&& (passwd==32'h95f2d303);\n"
    return s + ";\n"


def LOC(name, aw=13, vcut=0):
    """'localparam [N:0] NAME<pad35> = ADDR_BASE...' address line."""
    return ("localparam [%d:0] %-35s = ADDR_BASE[%-2d:2] + %d'h%x ;\n"
            % (aw - 3, name, aw - 1, aw - 2, vcut))


def ST1(name):
    """w1 status register declaration line (26 trailing spaces)."""
    return "\nreg                  %s;%s\n" % (name, " " * 26)


# ---------------------------------------------------------------------------
# RDL builders
# ---------------------------------------------------------------------------

def rdl_std(base=0x0, ecc_offset=None, pre_regs="", post_regs="",
            addr_width=13, name="std_min", set_fields="", status_fields="",
            mask_fields="", res_msb=1):
    """A standard-block-only RDL (smallest valid parity design).

    PASSWORD @base+0x0 / FUSA_CTRL @base+0x4 / Set @base+0x8 /
    Status @base+0xc / Mask @base+0x10.  ecc_offset defaults to `base`
    (std block inside the ECC region, PASSWORD = first ecc reg).
    `pre_regs` goes before the block (offsets < base), `post_regs` after.
    `res_msb` is the reserved top boundary of Set/Status/Mask
    (default 1 -> reserved[31:1]; use 3 for a 2-bit ext fault at [3:2]).
    """
    eo = base if ecc_offset is None else ecc_offset
    return """
property apb_addr_width { type = longint; component = addrmap; };
property bus_type       { type = string;  component = addrmap; };
property base_addr      { type = longint; component = addrmap; };
property ecc_offset     { type = longint; component = addrmap; };
property attr           { type = string;  component = field; };

addrmap %(name)s {
    apb_addr_width = %(aw)d;
    bus_type       = "APB3";
    base_addr      = 0x0;
    ecc_offset     = 0x%(eo)x;

    default regwidth = 32;
%(pre)s
    reg {
        field { sw = rw; hw = r; reset = 32'h0badbeef; attr = "RW"; }
            passwd[31:0];
    } PASSWORD @ 0x%(b0)x;

    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:13];
        field { sw = rw; hw = r; reset = 1'b0; attr = "RW"; }
            parity_invert[12];
        field { sw = rw; hw = r; reset = 4'b0; attr = "RW"; }
            parity_fault_injection[11:8];
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved_1[7:4];
        field { sw = rw; hw = r; reset = 2'b0; attr = "RW"; }
            lockstep_fault_injection[3:2];
        field { sw = rw; hw = r; reset = 1'b0; attr = "RW"; }
            fault_injection_en[1];
        field { sw = rw; hw = r; reset = 1'b0; attr = "RW"; }
            parity_decoder_enable[0];
    } FUSA_CTRL @ 0x%(b1)x;

    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:%(rm)d];
%(setf)s        field { sw = w;  hw = r; reset = 1'b0; attr = "WO"; }
            parity_err_set[0];
    } MIssionIntStatusSet0 @ 0x%(b2)x;

    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:%(rm)d];
%(statf)s        field { sw = rw; hw = rw; onwrite = woclr; reset = 1'b0;
                attr = "W1C"; }
            parity_err_status[0];
    } MIssionIntStatus0 @ 0x%(b3)x;

    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:%(rm)d];
%(maskf)s        field { sw = rw; hw = r; reset = 1'b0; attr = "RW"; }
            parity_err_mask[0];
    } MIssionIntMask0 @ 0x%(b4)x;
%(post)s
};
""" % {"name": name, "aw": addr_width, "eo": eo,
       "b0": base + 0x0, "b1": base + 0x4, "b2": base + 0x8,
       "b3": base + 0xc, "b4": base + 0x10, "rm": res_msb,
       "pre": pre_regs, "post": post_regs,
       "setf": set_fields, "statf": status_fields, "maskf": mask_fields}


def gen(rdl_text):
    """Parse RDL text and return (module, generated .v.raw text)."""
    fd, path = tempfile.mkstemp(suffix=".rdl")
    os.close(fd)
    with open(path, "w") as fh:
        fh.write(rdl_text)
    try:
        mod = rdl2reg.parse_rdl(path)
        text = rdl2reg.generate(mod, "Date : 2026-11-06 00:00:00", "eda")
    finally:
        os.remove(path)
    return mod, text


SW_PREFIX = {
    "RC": "sw = r; hw = r; onread = rclr;",
    "WO": "sw = w; hw = r;",
    "MWO": "sw = w; hw = r;",
    "W1S": "sw = rw; hw = r; onwrite = woset;",
    "W1F": "sw = rw; hw = r; onwrite = woset;",
    "W1C": "sw = rw; hw = rw; onwrite = woclr;",
    "W0S": "sw = rw; hw = r; onwrite = wzs;",
    "W0C": "sw = rw; hw = r; onwrite = wzc;",
    "W0F": "sw = rw; hw = r; onwrite = wzc;",
    "HW": "sw = rw; hw = rw;",
}


def func_reg(attr, width, value, msb=15, fname="val"):
    """One FUNC0 reg at 0x0: [31:msb+1] reserved + field + [lsb-1:0] reserved."""
    lsb = msb - width + 1
    rng = "[%d]" % msb if width == 1 else "[%d:%d]" % (msb, lsb)
    top = ""
    n = 0
    if msb < 31:
        top = ("        field { sw = r;  hw = r; reset = 'h0; attr = \"RO\"; }\n"
               "            reserved[31:%d];\n" % (msb + 1))
        n = 1
    bot = ""
    if lsb > 0:
        bot = ("        field { sw = r;  hw = r; reset = 'h0; attr = \"RO\"; }\n"
               "            reserved_%d[%d:0];\n" % (n, lsb - 1))
    sw = SW_PREFIX.get(attr, "sw = rw; hw = r;")
    return ("""    reg {
%s        field { %s reset = %s; attr = "%s"; }
            %s%s;
%s    } FUNC0 @ 0x0;
""" % (top, sw, value, attr, fname, rng, bot))


def func_module(attr, width, value, fname="val", msb=15):
    """Non-ecc FUNC0 @0x0 + std block from 0x4 (ecc from 0x8 on)."""
    return rdl_std(base=0x4, ecc_offset=0x8,
                   pre_regs=func_reg(attr, width, value, msb=msb,
                                     fname=fname))


# ---------------------------------------------------------------------------
# model unit tests
# ---------------------------------------------------------------------------

class TestRegModel(unittest.TestCase):

    def test_norm_reserved(self):
        self.assertEqual(regmodel.norm_reserved_name("reserved"), "reserved")
        self.assertEqual(regmodel.norm_reserved_name("reserved_12"),
                         "reserved")
        self.assertEqual(regmodel.norm_reserved_name("reservedness"),
                         "reservedness")

    def test_parse_value(self):
        self.assertEqual(regmodel.parse_value("32'h0badbeef"),
                         ("h", "0badbeef"))
        self.assertEqual(regmodel.parse_value("1'b0"), ("b", "0"))
        self.assertEqual(regmodel.parse_value("4'o17"), ("o", "17"))
        self.assertEqual(regmodel.parse_value("8'd255"), ("d", "255"))
        self.assertEqual(regmodel.parse_value("8'hF_X"), ("h", "F_X"))
        self.assertIsNone(regmodel.parse_value("0"))
        self.assertIsNone(regmodel.parse_value("17"))

    def test_value_int(self):
        self.assertEqual(regmodel.value_int("8'd255", 8), 255)
        self.assertEqual(regmodel.value_int("8'o17", 8), 15)
        self.assertEqual(regmodel.value_int("8'hff", 8), 255)
        self.assertEqual(regmodel.value_int("4'b10x1", 4), 9)
        self.assertEqual(regmodel.value_int("32'h1_0000_0000", 32), 0)
        self.assertEqual(regmodel.value_int("0", 4), 0)

    def test_numvalue(self):
        self.assertEqual(int(rdl2reg.NumValue("0x14")), 20)
        self.assertEqual(int(rdl2reg.NumValue("20")), 20)
        self.assertEqual(int(rdl2reg.NumValue("'h14")), 20)
        self.assertEqual(int(rdl2reg.NumValue("32'h0badbeef")), 0x0badbeef)
        self.assertEqual(rdl2reg.NumValue("32'h0badbeef").text,
                         "32'h0badbeef")

    def test_name_magic(self):
        # perl regexes are case-sensitive: 'Mask'/'Set'/'Status' keep the
        # mixed-case spelling used in the excel sheets
        self.assertTrue(Reg("FUSA_CTRL2", "18h").is_fusa_ctrl())
        self.assertTrue(Reg("FOO_Mask", "0h").is_mask())
        self.assertTrue(Reg("FOO_Mask2", "0h").is_mask())
        self.assertFalse(Reg("FOO_MASK", "0h").is_mask())
        self.assertTrue(Reg("FOO_Set", "0h").is_set())
        self.assertFalse(Reg("FOO_SET", "0h").is_set())
        self.assertTrue(Reg("FOO_Status3", "0h").is_status())
        self.assertTrue(Reg("PASSWORD", "0h").skipped_from_bank())
        self.assertEqual(Reg("A_Status0", "0h").status_set_regname(),
                         "A_StatusSet0")
        self.assertEqual(Reg("AB_Status_Cd_Status", "0h").status_set_regname(),
                         "AB_StatusSet_Cd_StatusSet")


# ---------------------------------------------------------------------------
# generation: attribute dispatch matrix (FUNC0 non-ecc, bank index 0)
# ---------------------------------------------------------------------------

class TestAttrDispatch(unittest.TestCase):

    def grp(self, text, idx, grp):
        # res/w1s/w1c/w0s/w0c use '= ' (1 space); wt/rc/wr/hw use '  = '
        # re.S + lazy: wr/hw values span lines (",\n"+36sp terms), and the
        # group value itself never contains ';'
        m = re.search(r"assign reg_data_%s\[%d\]\[31:0\]\s+= (.*?);\n"
                      % (grp, idx), text, re.S)
        return m.group(1) if m else None

    def hwd(self, text, idx):
        m = re.search(r"assign hw_wdata\[%d\]\[31:0\]\s+= (.*?);\n"
                      % idx, text, re.S)
        return m.group(1) if m else None

    def test_rw_w8(self):
        mod, text = gen(func_module("RW", 8, "8'h5a"))
        self.assertEqual(self.grp(text, 0, "wr"),
                         "{16'h0,\n%s{8{hwr_FUNC0}},8'h0}" % B36)
        # reserved fields mark res with ',{w{1'b1}}' (perl R1614-20); the
        # RW field itself contributes ',8'h0' to res
        self.assertEqual(self.grp(text, 0, "res"),
                         "{{16{1'b1}},8'h0,{8{1'b1}}}")
        # no HW/RC bits anywhere -> hwz shortcut '32'h0;'
        self.assertEqual(self.grp(text, 0, "hw"), "32'h0")
        self.assertEqual(self.hwd(text, 0), "32'h0")
        # default value concat: perl loop-1 terms all carry a comma
        self.assertIn("assign reg_default_value[0][31:0] = "
                      "{16'h0,8'h5a,8'h0};\n", text)
        # reg_wr field assign with %-30s padded LHS
        self.assertIn(("assign val[7:0]").ljust(30) +
                      " = reg_dec_data_out[0][15:8]; //deft: 8'h5a\n", text)
        # read mux sig (first item's comma eaten by s/{,/{/)
        self.assertIn(MUX("FUNC0") + " prdata_in = {\n%s16'h0,"
                      "\n%sval[7:0],\n%s8'h0};" % (B45, B45, B45), text)

    def test_w1c_w8(self):
        mod, text = gen(func_module("W1C", 8, "8'h0"))
        # perl R1661: w>1 flag term is the SINGLE-LINE ',{w{hwr}}' form
        self.assertEqual(self.grp(text, 0, "w1c"),
                         "{16'h0,{8{hwr_FUNC0}},8'h0}")
        # W1C fields contribute nothing to wr -> all-zero shortcut
        self.assertEqual(self.grp(text, 0, "wr"), "32'h0")
        self.assertIn(P_OUT(8, "val"), text)
        self.assertIn("    input             val_wr;\n", text)
        self.assertIn(P_IN(8, "val_in"), text)

    def test_hw_w8(self):
        mod, text = gen(func_module("HW", 8, "8'h0"))
        self.assertEqual(self.grp(text, 0, "hw"),
                         "{16'h0,\n%s{8{val_wr}},8'h0}" % B36)
        self.assertEqual(self.hwd(text, 0),
                         "{16'h0,\n%sval_in[7:0],8'h0}" % B36)

    def test_w1s_w1(self):
        mod, text = gen(func_module("W1S", 1, "1'b0", fname="flag"))
        # perl R1634 writes the w1 flag term BARE (s/};/hwr_X};/) which
        # fuses onto the preceding term -- invalid Verilog once a w1
        # flag/RC field joins the bank; FIXED to carry its comma (legacy
        # maps never trip it: regression stays byte-identical)
        self.assertEqual(self.grp(text, 0, "w1s"),
                         "{16'h0,hwr_FUNC0,15'h0}")
        self.assertEqual(self.grp(text, 0, "hw"),
                         "{16'h0,\n%sflag_wr,15'h0}" % B36)
        self.assertEqual(self.hwd(text, 0),
                         "{16'h0,\n%sflag_in,15'h0}" % B36)

    def test_wt_w1(self):
        mod, text = gen(func_module("WT", 1, "1'b0", fname="tog"))
        self.assertEqual(self.grp(text, 0, "wt"),
                         "{16'h0,hwr_FUNC0,15'h0}")

    def test_w0s_w0c_w1(self):
        mod, text = gen(func_module("W0S", 1, "1'b0", fname="s0"))
        self.assertEqual(self.grp(text, 0, "w0s"),
                         "{16'h0,hwr_FUNC0,15'h0}")
        mod, text = gen(func_module("W0C", 1, "1'b0", fname="c0"))
        self.assertEqual(self.grp(text, 0, "w0c"),
                         "{16'h0,hwr_FUNC0,15'h0}")

    def test_mrw_w8(self):
        mod, text = gen(func_module("MRW", 8, "8'h3", fname="cfg"))
        self.assertEqual(self.grp(text, 0, "wr"),
                         "{16'h0,\n%s{8{hwr_FUNC0}} & ~cfg_mask,8'h0}"
                         % B36)
        self.assertIn(P_IN(8, "cfg_mask"), text)

    def test_rc_w8(self):
        mod, text = gen(func_module("RC", 8, "8'h0", fname="cnt"))
        # perl R1751: single-line ',{w{hrd}}' replication term
        self.assertEqual(self.grp(text, 0, "rc"),
                         "{16'h0,{8{hrd_FUNC0}},8'h0}")
        # RC hw/hwdata append the field name (perl R1742 s/};/cnt};/ wrote
        # it bare, fusing into the list -- comma FIXED as for the w1 flag
        # terms; latent-only on legacy maps)
        self.assertEqual(self.grp(text, 0, "hw"), "{16'h0,cnt,8'h0}")
        self.assertEqual(self.hwd(text, 0), "{16'h0,cnt,8'h0}")
        self.assertIn(P_IN(8, "cnt"), text)
        self.assertIn(P_OUT(8, "cnt_cap"), text)
        self.assertIn(HWRW("FUNC0", rd=True), text)
        self.assertIn(("assign cnt_cap[7:0]").ljust(30) +
                      " = reg_dec_data_out[0][15:8]; //deft: 8'h0\n", text)
        self.assertIn(MUX("FUNC0") + " prdata_in = {\n%s16'h0,"
                      "\n%scnt_cap[7:0],\n%s8'h0};" % (B45, B45, B45), text)

    def test_ro_reg_excluded(self):
        mod, text = gen(rdl_std(base=0x4, ecc_offset=0x4, pre_regs="""
    reg {
        field { sw = r; hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:0];
    } ROONLY @ 0x0;
"""))
        self.assertNotIn("hwr_ROONLY", text)      # not in the bank
        self.assertIn(MUX("ROONLY") + " prdata_in = {\n%s32'h0};"
                      % B45, text)                 # read mux present
        self.assertNotIn("// address 0\n", text)   # no attr_dec block

    def test_wo_read_zero(self):
        mod, text = gen(func_module("WO", 8, "8'h0", fname="cmd"))
        self.assertIn(MUX("FUNC0") + " prdata_in = {\n%s16'h0,"
                      "\n%s8'h0,\n%s8'h0};" % (B45, B45, B45), text)

    def test_rw_w32(self):
        mod, text = gen(func_module("RW", 32, "32'ha5a5a5a5", msb=31,
                                    fname="big"))
        # wholesale replication term
        self.assertEqual(self.grp(text, 0, "wr"),
                         "{\n%s32{hwr_FUNC0}}" % B36)
        self.assertIn("assign reg_default_value[0][31:0] = "
                      "{32'ha5a5a5a5};\n", text)
        self.assertIn(P_OUT(32, "big"), text)


# ---------------------------------------------------------------------------
# generation: std block / ecc region
# ---------------------------------------------------------------------------

class TestStdBlock(unittest.TestCase):

    def test_min_std(self):
        mod, text = gen(rdl_std())
        self.assertEqual(mod.func_num_w, 2)
        self.assertEqual(mod.ext_int, [])
        # localparam line + ungated PASSWORD (ecc first) + gated rest
        self.assertIn(LOC("PASSWORD", 13, 0), text)
        self.assertIn(HWRW("PASSWORD"), text)
        self.assertIn(HWRW("FUSA_CTRL", gate=True), text)
        # PASSWORD always block (reset + write; note 'end ' trailing space)
        self.assertIn("\n  always @(posedge pclk or negedge presetn)\n"
                      "  begin\n      if (!presetn) begin\n"
                      "          passwd  <= 32'h0badbeef;\n      end \n"
                      "      else if (hwr_PASSWORD) begin\n"
                      "          passwd  <= pwdata[31:0];\n      end\n"
                      "  end\n        ", text)
        # read mux: PASSWORD -> fixed key, WO set fields -> 1'h0
        self.assertIn(MUX("PASSWORD") + " prdata_in = {\n"
                      + B45 + "32'h0badbeef};", text)
        self.assertIn("//0x8\n" + MUX("MISSIONINTSTATUSSET0") +
                      " prdata_in = {\n" + B45 + "31'h0,\n" + B45 +
                      "1'h0};", text)
        # parity_err_status reg (w1) with 26-space trailing padding
        self.assertIn(ST1("parity_err_status"), text)
        # status: hardware set priority, then W1C clear, set strobe
        self.assertIn("\n      else if (reg_parity_error) begin\n"
                      "          parity_err_status  <= 1'b1;\n      end",
                      text)
        self.assertIn("\n      else if (hwr_MIssionIntStatus0) begin\n"
                      "          if (pwdata[0] == 1'b1) begin\n"
                      "              parity_err_status  <= ~pwdata[0];\n"
                      "          end", text)
        self.assertIn("\n      else if (hwr_MIssionIntStatusSet0 & "
                      "pwdata[0]) begin\n"
                      "          parity_err_status  <= 1'b1;\n      end",
                      text)
        # mission_int block
        self.assertIn("        mission_int <= ~parity_err_mask & "
                      "parity_err_status; \n", text)
        # parity_invert_d pair + posedge assigns
        self.assertIn("   assign parity_invert_2cycle = "
                      "parity_invert_posedge | parity_invert_d_posedge;\n",
                      text)
        # OR/AND chain with func_num_w=2 (pair on one line)
        self.assertIn("assign reg_parity_error_or    =\n" + " " * 32 +
                      "parity_dec_error[0] |  parity_dec_error[1] ;\n", text)
        self.assertIn("\n\nassign reg_parity_error_and   =\n" + " " * 32 +
                      "reg_parity_error_or & \n", text)
        # man_def uses func_num_w-1 = 1
        self.assertIn("wire   [31:0] reg_data_res               [1:0];\n",
                      text)
        self.assertIn("wire   [1:0] parity_dec_error;\n", text)
        # reg_wr per-reg comment keeps the lc offset token
        self.assertIn("//00h\n", text)
        self.assertIn("//08h\n", text)
        # FUSA_CTRL has NO always block (bank-driven; perl branch-1 only
        # handles PASSWORD) -- taylor_v3.v ground truth confirms
        self.assertNotIn("parity_invert <= 1'b0;", text)

    def test_section_order(self):
        mod, text = gen(rdl_std())
        marks = [
            "//Port signals definition \n",
            "//Define list\n",
            "/*autodefine*/",
            "//End of automatic define\n\n",
            "wire          reg_parity_error;\n",
            "//Glue logic\n",
            "//reg attribution logic",
            "//---ECC register wr logic\n",
            "\nassign parity_decoder_bypass = ~parity_decoder_enable;\n",
            "\n//--- ECC process logic\n",
            "//get configuration and status data from ecc correct data\n",
            "//Bus read reg logic\n",
            "//---- *reg addr define*----",
            "//---- *reg sig bit info*----",
            "endmodule",
        ]
        pos = -1
        for m in marks:
            i = text.index(m)
            self.assertGreater(i, pos, "marker %r out of order" % m)
            pos = i

    def test_macro_footer(self):
        mod, text = gen(rdl_std())
        d = "BASE_ADDR_STD_MIN"
        # '`define %-40s  %s'
        self.assertIn("//`define " + d.ljust(40) + "  32'h0\n", text)
        o = "OFST_STD_MIN_PASSWORD"
        # '`define %-40s  (%-10s + 'h%04x)'
        self.assertIn("//`define " + o.ljust(40) + "  (" + d.ljust(10) +
                      " + 'h0000)\n", text)
        o2 = "OFST_STD_MIN_MISSIONINTSTATUS0"
        self.assertIn("//`define " + o2.ljust(40) + "  (" + d.ljust(10) +
                      " + 'h000c)\n", text)
        self.assertIn("//`endif //STD_MIN_DEF_V_\n\n\n", text)
        # '//%-30s,`%-40s,bit[..]'
        self.assertIn("//" + "passwd".ljust(30) + ",`" + o.ljust(40) +
                      ",bit[31:0]\n", text)
        f2 = "OFST_STD_MIN_FUSA_CTRL"
        self.assertIn("//" + "parity_invert".ljust(30) + ",`" +
                      f2.ljust(40) + ",bit[12]\n", text)
        self.assertIn("//" + "parity_fault_injection".ljust(30) + ",`" +
                      f2.ljust(40) + ",bit[11:8]\n", text)

    def test_addr_width_12(self):
        mod, text = gen(rdl_std(addr_width=12))
        self.assertIn("    input [11:0]      paddr;\n", text)
        self.assertIn(LOC("PASSWORD", aw=12, vcut=0), text)
        self.assertIn("  case(paddr[11:2])\n", text)
        self.assertIn("parameter ADDR_BASE   = 12'h0; "
                      "//lower bits of the bus addr\n", text)

    def test_ext_int_w1(self):
        setf = ('        field { sw = w; hw = r; reset = 1\'b0; '
                'attr = "WO"; }\n            lockstep_err_set[1];\n')
        statf = ('        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 1\'b0; attr = "W1C"; }\n'
                 '            lockstep_err_status[1];\n')
        maskf = ('        field { sw = rw; hw = r; reset = 1\'b0; '
                 'attr = "RW"; }\n            lockstep_err_mask[1];\n')
        mod, text = gen(rdl_std(res_msb=2, set_fields=setf,
                                status_fields=statf, mask_fields=maskf))
        self.assertEqual(mod.ext_int, [("lockstep_err", 1)])
        self.assertIn(P_OUT5(1, "lockstep_err"), text)
        self.assertIn(ST1("lockstep_err_status"), text)
        # perl R989-990: hw-side ports use the FULL status field name
        self.assertIn("\n      else if (lockstep_err_status_wr) begin\n"
                      "          lockstep_err_status  <= "
                      "lockstep_err_status_in;"
                      "\n      end", text)
        # ext always block (w1), incl. trailing spaces
        self.assertIn(" \n  always @(posedge pclk or negedge presetn)\n"
                      "  begin\n      if(!presetn) begin\n"
                      "        lockstep_err <= 1'b0; \n   end \n"
                      "   else begin\n"
                      "        lockstep_err <= ~lockstep_err_mask & "
                      "lockstep_err_status; \n   end\nend\n\n", text)

    def test_ext_int_w2_generate_loop(self):
        setf = ('        field { sw = w; hw = r; reset = 2\'b0; '
                'attr = "WO"; }\n            cnt_set[3:2];\n')
        statf = ('        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 2\'b0; attr = "W1C"; }\n'
                 '            cnt_status[3:2];\n')
        maskf = ('        field { sw = rw; hw = r; reset = 2\'b0; '
                 'attr = "RW"; }\n            cnt_mask[3:2];\n')
        mod, text = gen(rdl_std(res_msb=3, set_fields=setf,
                                status_fields=statf, mask_fields=maskf))
        self.assertEqual(mod.ext_int, [("cnt", 2)])
        self.assertIn(P_OUT5(2, "cnt_err"), text)
        self.assertIn("\n  reg  [2-1:0] cnt_status;%s\n"
                      "genvar i_cnt_status;\ngenerate\n"
                      "for(i_cnt_status=0;i_cnt_status<2;i_cnt_status="
                      "i_cnt_status+1)begin: gen_cnt_status\n" % (" " * 26),
                      text)
        self.assertIn("          cnt_status[i_cnt_status]  <= 1'b0;\n"
                      "      end", text)
        # w>1 hw branch: trailing space after 'begin'
        self.assertIn("\n      else if (cnt_status_wr[i_cnt_status]) begin"
                      " \n          cnt_status[i_cnt_status]  <= "
                      "cnt_status_in[i_cnt_status];\n      end", text)
        # w>1 set strobe
        self.assertIn("\n      else if (hwr_MIssionIntStatusSet0) "
                      "begin\n"
                      "          if (pwdata[i_cnt_status+2])\n"
                      "              cnt_status[i_cnt_status]  <= 1'b1;"
                      "\n      end", text)
        # w>1 W1C clear
        self.assertIn("\n          if (pwdata[i_cnt_status+2] == 1'b1)\n"
                      "              cnt_status[i_cnt_status]  <= "
                      "~pwdata[i_cnt_status+2];", text)
        # generate close
        self.assertIn("\n      end\n  end\n        \nend\nendgenerate\n"
                      "        ", text)
        # per-bit ext always blocks
        for bit in (0, 1):
            self.assertIn("        cnt_err[%d] <= 1'b0; \n   end \n"
                          "   else begin\n"
                          "        cnt_err[%d] <= ~cnt_mask[%d] & "
                          "cnt_status[%d]; \n   end\nend\n\n"
                          % (bit, bit, bit, bit), text)

    def test_passwd_w1c_path(self):
        # PASSWORD containing a W1C field -> field-level always (perl
        # $w1c_flag branch, unexercised by taylor_v3)
        plain = ("        field { sw = rw; hw = r; reset = 32'h0badbeef; "
                 "attr = \"RW\"; }\n            passwd[31:0];")
        w1c = ("        field { sw = r;  hw = r; reset = 'h0; "
               "attr = \"RO\"; }\n            reserved[31:4];\n"
               "        field { sw = rw; hw = rw; onwrite = woclr; "
               "reset = 4'hf; attr = \"W1C\"; }\n            passwd[3:0];")
        mod, text = gen(rdl_std().replace(plain, w1c))
        self.assertIn("\n  always @(posedge pclk or negedge presetn)\n"
                      "  begin\n      if (!presetn) begin\n"
                      "          passwd  <= 4'hf;\n      end", text)
        self.assertIn("\n          if (passwd_wr[0]) \n"
                      "              passwd[0] <= passwd_in[0];", text)
        # w>1 W1C clear is the per-bit form WITHOUT begin/end
        self.assertIn("\n          if (pwdata[0] == 1'b1)\n"
                      "              passwd[0]  <= ~pwdata[0];", text)

    def test_vlog_width_prefix(self):
        # reset written without width ('h form) gains the field width
        plain = ("        field { sw = rw; hw = r; reset = 32'h0badbeef; "
                 "attr = \"RW\"; }\n            passwd[31:0];")
        sub = ("        field { sw = r;  hw = r; reset = 'h0; "
               "attr = \"RO\"; }\n            reserved[31:4];\n"
               "        field { sw = rw; hw = r; reset = 'hf; "
               "attr = \"RW\"; }\n            passwd[3:0];")
        mod, text = gen(rdl_std().replace(plain, sub))
        # _vlog_value prefixes the width in the always block
        self.assertIn("passwd  <= 4'hf;\n      end", text)
        # PASSWORD is skipped from the bank: reg_default_value[0] is
        # FUSA_CTRL (bank index 0), all-zero defaults with commas
        self.assertIn("assign reg_default_value[0][31:0] = "
                      "{19'h0,1'b0,4'b0,4'h0,2'b0,1'b0,1'b0};\n", text)
        # passwd never reaches reg_default_value (skipped from bank)
        self.assertNotIn("4'hf};\n", text)


# ---------------------------------------------------------------------------
# generation: v2-style layout (std block OUTSIDE the ECC region)
# ---------------------------------------------------------------------------

class TestV2Layout(unittest.TestCase):

    def rdl_v2(self):
        # std block at 0x0..0x10 non-ecc, functional reg AFTER, ecc 0x14
        return rdl_std(ecc_offset=0x14, post_regs="""
    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:8];
        field { sw = rw; hw = r; reset = 8'ha5; attr = "RW"; }
            data[7:0];
    } FUNC @ 0x14;
""")

    def test_bank_and_gating(self):
        mod, text = gen(self.rdl_v2())
        # func_num_w = reg_num_w(6) - ecc_num_w(1) + fusa_ctrl_mask(0) = 5
        # (perl over-provisions the bank arrays -- ported faithfully)
        self.assertEqual(mod.func_num_w, 5)
        self.assertEqual(len(mod.bank_regs()), 3)
        self.assertIn("wire   [31:0] reg_data_res               [4:0];\n",
                      text)
        # NO passwd gate anywhere (no ecc reg after the first one)
        self.assertNotIn("passwd==32'h95f2d303", text)
        # PASSWORD is bank-skipped: no decode groups, no default value
        self.assertNotIn("32{hwr_PASSWORD}", text)
        # PASSWORD read mux shows passwd[31:0] (not the magic key)
        self.assertIn(MUX("PASSWORD") + " prdata_in = {\n"
                      + B45 + "passwd[31:0]};", text)
        # no status always block (Status reg is non-ecc)
        self.assertNotIn("reg                  parity_err_status;", text)
        # mission_int block still emitted
        self.assertIn("mission_int <= ~parity_err_mask & "
                      "parity_err_status; \n", text)
        # FUNC is ecc + first -> ungated
        self.assertIn(HWRW("FUNC"), text)
        # data readable from the bank (FUNC non-skipped, bank index 2)
        self.assertIn(("assign data[7:0]").ljust(30) +
                      " = reg_dec_data_out[2][7:0]; //deft: 8'ha5\n", text)


# ---------------------------------------------------------------------------
# radix / value handling
# ---------------------------------------------------------------------------

class TestValues(unittest.TestCase):

    def test_radix_verbatim(self):
        pre = """
    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:24];
        field { sw = rw; hw = r; reset = 8'd255; attr = "RW"; }
            vd[23:16];
        field { sw = rw; hw = r; reset = 8'hff; attr = "RW"; }
            vh[15:8];
        field { sw = rw; hw = r; reset = 4'o17; attr = "RW"; }
            vo[7:4];
        field { sw = rw; hw = r; reset = 4'b1010; attr = "RW"; }
            vb[3:0];
    } RADIX @ 0x0;
"""
        mod, text = gen(rdl_std(base=0x4, ecc_offset=0x8, pre_regs=pre))
        self.assertIn("assign reg_default_value[0][31:0] = "
                      "{8'h0,8'd255,8'hff,4'o17,4'b1010};\n", text)
        # //deft comments keep the token verbatim
        self.assertIn("//deft: 8'd255\n", text)
        self.assertIn("//deft: 4'o17\n", text)
        self.assertIn("//deft: 4'b1010\n", text)
        # RADIX non-ecc -> output ports, ungated hwr
        self.assertIn(P_OUT(8, "vd"), text)
        self.assertIn(HWRW("RADIX"), text)

    def test_reset_without_width_rejected(self):
        rdl = rdl_std().replace("reset = 32'h0badbeef;", "reset = 0;")
        with self.assertRaisesRegexp(RdlError, "width"):
            gen(rdl)


# ---------------------------------------------------------------------------
# parser / model error paths
# ---------------------------------------------------------------------------

class TestErrors(unittest.TestCase):

    def err(self, rdl, needle=None):
        try:
            gen(rdl)
        except RdlError as e:
            if needle:
                self.assertIn(needle, str(e))
            return str(e)
        self.fail("expected RdlError")

    def test_bits_not_32(self):
        self.err(rdl_std().replace("passwd[31:0];", "passwd[30:0];"),
                 "sum to 31")

    def test_bits_not_descending(self):
        # sums to 32 but fields listed ascending
        rdl = rdl_std(pre_regs="""
    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[15:0];
        field { sw = rw; hw = r; reset = 16'h0; attr = "RW"; }
            val[31:16];
    } BAD @ 0x0;
""", base=0x4, ecc_offset=0x4)
        self.err(rdl, "descending")

    def test_duplicate_field_name(self):
        rdl = rdl_std(pre_regs="""
    reg {
        field { sw = r;  hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:16];
        field { sw = rw; hw = r; reset = 16'h0; attr = "RW"; }
            val[15:0];
        field { sw = rw; hw = r; reset = 16'h0; attr = "RW"; }
            val[31:16];
    } DUP @ 0x0;
""", base=0x4, ecc_offset=0x4)
        self.err(rdl, "duplicate field name")

    def test_unknown_attr(self):
        self.err(rdl_std().replace('attr = "RW";', 'attr = "XX";', 1),
                 "unknown attr")

    def test_bus_not_apb3(self):
        self.err(rdl_std().replace('bus_type       = "APB3";',
                                   'bus_type       = "APB2";'), "APB3")

    def test_status_without_set(self):
        statf = ('        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 1\'b0; attr = "W1C"; }\n'
                 '            ghost_status[1];\n')
        maskf = ('        field { sw = rw; hw = r; reset = 1\'b0; '
                 'attr = "RW"; }\n            ghost_mask[1];\n')
        self.err(rdl_std(status_fields=statf, mask_fields=maskf),
                 "ghost_set")

    def test_status_without_mask(self):
        setf = ('        field { sw = w; hw = r; reset = 1\'b0; '
                'attr = "WO"; }\n            ghost_set[1];\n')
        statf = ('        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 1\'b0; attr = "W1C"; }\n'
                 '            ghost_status[1];\n')
        self.err(rdl_std(set_fields=setf, status_fields=statf),
                 "ghost_mask")

    def test_unsupported_property(self):
        self.err(rdl_std().replace("sw = rw; hw = r; reset = 32'h0badbeef;",
                                   "sw = rw; hw = r; reset = 32'h0badbeef; "
                                   "cdc = \"p2l\";"),
                 "unsupported field property")

    def test_sw_attr_conflict(self):
        # attr=W1C but sw=r (read-only) -> conflict
        rdl = rdl_std(pre_regs="""
    reg {
        field { sw = r; hw = r; reset = 'h0; attr = "RO"; }
            reserved[31:0];
    } X0 @ 0x0;
""", base=0x4, ecc_offset=0x4)
        rdl = rdl.replace("attr = \"RO\";", "attr = \"W1C\";", 1)
        self.err(rdl, "conflicts with attr")

    def test_no_regs(self):
        self.err("property attr { type = string; component = field; };\n"
                 "addrmap empty {\n    default regwidth = 32;\n};\n",
                 "no registers")

    def test_offsets_not_increasing(self):
        rdl = rdl_std().replace("} MIssionIntMask0 @ 0x10;",
                                "} MIssionIntMask0 @ 0xc;")
        self.err(rdl, "strictly increase")

    def test_dup_status_names(self):
        statf = ('        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 1\'b0; attr = "W1C"; }\n'
                 '            lockstep_err_status[1];\n'
                 '        field { sw = rw; hw = rw; onwrite = woclr; '
                 'reset = 1\'b0; attr = "W1C"; }\n'
                 '            lockstep_err_status[2];\n')
        self.err(rdl_std(status_fields=statf), "duplicate")


# ---------------------------------------------------------------------------
# Auto_def_post filter + sw interop defaults
# ---------------------------------------------------------------------------

class TestPostAndInterop(unittest.TestCase):

    def test_no_vim_macro_lines(self):
        mod, text = gen(rdl_std())
        for ln in text.splitlines():
            self.assertIsNone(re.search(r"reg\s*\[i\]", ln))
            self.assertIsNone(re.search(r"wire\s*\[i\]", ln))

    def test_rdl_sw_defaults(self):
        pairs = [("W1C", ("rw", "woclr", None)),
                 ("W1S", ("rw", "woset", None)),
                 ("RC", ("r", None, "rclr")),
                 ("WO", ("w", None, None)),
                 ("RW", ("rw", None, None))]
        for attr, expect in pairs:
            self.assertEqual(regmodel.RDL_SW[attr], expect)

    def test_vlog_value(self):
        f = Field("x", 7, 0, "RW", "8'h3")
        self.assertEqual(rdl2reg._vlog_value(f), "8'h3")
        f2 = Field("reserved", 7, 0, "RO", "'h0")
        self.assertEqual(rdl2reg._vlog_value(f2), "8'h0")
        self.assertEqual(rdl2reg._hvalue(Field("y", 3, 0, "W1C", "4'h0")),
                         "4{1'b1}")
        self.assertEqual(rdl2reg._hvalue(Field("z", 0, 0, "W1C", "1'b0")),
                         "1'b1")


# ---------------------------------------------------------------------------
# round trip xlsx -> RDL -> model (needs openpyxl)
# ---------------------------------------------------------------------------

class TestRoundTrip(unittest.TestCase):

    def setUp(self):
        try:
            import openpyxl  # noqa: F401
        except ImportError:
            self.skipTest("openpyxl not available")

    def test_round_trip(self):
        import excel2rdl
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(["BASE_ADDR", "0x0"])
        ws.append(["ADDR_WIDTH", "13"])
        ws.append(["APB3"])
        ws.append(["REG_NUM", "1"])
        ws.append(["ECC_OFFSET", "0x4"])
        ws.append(["Offset", "Register Name", "SubBits", "Field Name",
                   "Attribute", "DefaultValue", "Description"])
        rows = [
            ("00h", "CHIP_CFG", "[31:8]", "reserved", "RO", "0", "r"),
            ("00h", "", "[7:0]", "en", "RW", "8'h1", "enable"),
            ("04h", "PASSWORD", "[31:0]", "passwd", "RW", "32'h0badbeef",
             "key"),
            ("08h", "FUSA_CTRL", "[31:13]", "reserved", "RO", "0", "r"),
            ("08h", "", "[12]", "parity_invert", "RW", "1'b0", "inv"),
            ("08h", "", "[11:8]", "parity_fault_injection", "RW", "4'b0",
             "pfi"),
            ("08h", "", "[7:4]", "reserved", "RO", "0", "r"),
            ("08h", "", "[3:2]", "lockstep_fault_injection", "RW", "2'b0",
             "lsi"),
            ("08h", "", "[1]", "fault_injection_en", "RW", "1'b0", "fie"),
            ("08h", "", "[0]", "parity_decoder_enable", "RW", "1'b0", "pde"),
            ("0ch", "MIssionIntStatusSet0", "[31:1]", "reserved", "RO", "0",
             "r"),
            ("0ch", "", "[0]", "parity_err_set", "WO", "1'b0", "pes"),
            ("10h", "MIssionIntStatus0", "[31:1]", "reserved", "RO", "0",
             "r"),
            ("10h", "", "[0]", "parity_err_status", "W1C", "1'b0", "pe"),
            ("14h", "MIssionIntMask0", "[31:1]", "reserved", "RO", "0", "r"),
            ("14h", "", "[0]", "parity_err_mask", "RW", "1'b0", "pem"),
        ]
        for r in rows:
            ws.append(list(r))
        wb.save("rt_test.xlsx")

        m1 = excel2rdl.load_xlsx("rt_test.xlsx")
        rdl_text = excel2rdl.emit_rdl(m1)
        fd, path = tempfile.mkstemp(suffix=".rdl")
        os.close(fd)
        with open(path, "w") as fh:
            fh.write(rdl_text)
        m2 = rdl2reg.parse_rdl(path)
        os.remove(path)
        os.remove("rt_test.xlsx")

        def sig(m):
            return [(r.gname, r.offset_int,
                     [(f.rname, f.msb, f.lsb, f.attr, f.value)
                      for f in r.fields]) for r in m.regs]
        self.assertEqual(sig(m1), sig(m2))
        self.assertEqual(m1.func_num_w, m2.func_num_w)
        self.assertEqual(m1.ext_int, m2.ext_int)
        self.assertEqual(m1.ecc_offset, m2.ecc_offset)
        self.assertEqual(m1.addr_width, m2.addr_width)
        # derived numbers for this map: reg_num_w(6) - ecc_num_w(5)
        # + fusa_ctrl_mask(2: FUSA_CTRL + Mask) = 3 == len(bank_regs())
        # (CHIP_CFG is a genuine bank member: non-ecc regs are protected too)
        self.assertEqual(m2.func_num_w, 3)
        self.assertEqual(m2.func_num_w, len(m2.bank_regs()))
        self.assertEqual(m2.ext_int, [])

    def test_desc_escaping(self):
        import excel2rdl
        f = Field("x", 0, 0, "RW", "1'b0",
                  desc='quote " backslash \\ nl\nend')
        s = excel2rdl.emit_field(f)
        self.assertIn('desc = "quote \\" backslash \\\\ nl\\nend"', s)
        fd, path = tempfile.mkstemp(suffix=".rdl")
        os.close(fd)
        with open(path, "w") as fh:
            fh.write(
                "property attr { type = string; component = field; };\n"
                "property ecc_offset { type = longint; "
                "component = addrmap; };\n"
                "addrmap t {\n    ecc_offset = 0x4;\n"
                "    default regwidth = 32;\n"
                "    reg {\n"
                "        field { sw = r; hw = r; reset = 0; "
                "attr = \"RO\"; } reserved[31:1];\n"
                "%s\n"
                "    } R @ 0x0;\n};\n" % s)
        mod = rdl2reg.parse_rdl(path)
        os.remove(path)
        self.assertEqual(mod.regs[0].fields[1].desc,
                         'quote " backslash \\ nl\nend')


class TestStdAppend(unittest.TestCase):
    """Auto-appended standard FuSa block (fusa_std_block.md v1.0)."""

    def make_xlsx(self, path, rows, ext_rows=None, ecc="0x04"):
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        # perl-canonical single-cell header (same as the real template)
        ws.append(["BASE_ADDR:0x0"])
        ws.append(["ADDR_WIDTH=13"])
        ws.append(["APB3"])
        ws.append(["REG_NUM=1"])
        ws.append(["ECC_OFFSET:%s" % ecc])
        ws.append(["Offset", "Register Name", "SubBits", "Field Name",
                   "Attribute", "DefaultValue", "Description"])
        for r in rows:
            ws.append(list(r))
        if ext_rows is not None:
            es = wb.create_sheet("ExtInt")
            es.append(["Field Name", "Bits", "Description"])
            for r in ext_rows:
                es.append(list(r))
        wb.save(path)
        return path

    FUNC_ROW = ("00h", "CHIP_TOP_5", "[31:0]", "noc_idlereq_backup_reg",
                "RW", "32'h0", "functional")

    def tearDown(self):
        for f in ("sa_min.xlsx", "sa_ext.xlsx", "sa_full.xlsx",
                  "sa_conflict.xlsx", "sa_coll.xlsx", "sa_pe.xlsx",
                  "sa_rt.xlsx"):
            if os.path.exists(f):
                os.remove(f)

    def std_sig(self, m):
        return [(r.gname, r.offset_int) for r in m.regs
                if r.is_fusa_or_mask() or r.is_set() or r.is_status()]

    def test_auto_append_minimal(self):
        import excel2rdl
        m = excel2rdl.load_xlsx(self.make_xlsx(
            "sa_min.xlsx", [self.FUNC_ROW]))
        self.assertTrue(m.std_appended)
        self.assertEqual(self.std_sig(m), [
            ("PASSWORD", 0x4), ("FUSA_CTRL", 0x8),
            ("MIssionIntStatusSet0", 0xc), ("MIssionIntStatus0", 0x10),
            ("MIssionIntMask0", 0x14)])
        self.assertEqual(m.ext_int, [])
        # bank = CHIP_TOP_5 + FUSA_CTRL + Mask = 3 members
        self.assertEqual(m.func_num_w, 3)
        text = gen(excel2rdl.emit_rdl(m))[1]
        self.assertIn("hwr_FUSA_CTRL", text)
        self.assertIn("&& (passwd==32'h95f2d303);", text)
        self.assertIn("mission_int <= ~parity_err_mask & "
                      "parity_err_status;", text)

    def test_auto_append_extint(self):
        import excel2rdl
        ext = [("cnt", "2", "count fault"), ("lockstep_err", "1", "")]
        m = excel2rdl.load_xlsx(self.make_xlsx(
            "sa_ext.xlsx", [self.FUNC_ROW], ext_rows=ext))
        self.assertEqual(m.ext_int, [("cnt", 2), ("lockstep_err", 1)])
        setreg = [r for r in m.regs if r.is_set()][0]
        self.assertEqual([(f.name, f.msb, f.lsb, f.attr, f.value)
                          for f in setreg.fields], [
            ("reserved", 31, 4, "RO", "28'h0"),
            ("cnt_set", 3, 2, "WO", "2'b0"),
            ("lockstep_err_set", 1, 1, "WO", "1'b0"),
            ("parity_err_set", 0, 0, "WO", "1'b0")])
        text = gen(excel2rdl.emit_rdl(m))[1]
        self.assertIn(P_OUT5(2, "cnt_err"), text)   # perl: name+"_err"
        self.assertIn("reg  [2-1:0] cnt_status;%s\n" % (" " * 26), text)

    def test_full_map_no_append(self):
        import excel2rdl
        rows = [self.FUNC_ROW,
                ("04h", "PASSWORD", "[31:0]", "passwd", "RW",
                 "32'h0badbeef", "key")]
        m = excel2rdl.load_xlsx(self.make_xlsx("sa_full.xlsx", rows))
        self.assertFalse(m.std_appended)
        self.assertEqual(len(m.regs), 2)   # nothing appended

    def test_full_map_with_extint_sheet_err(self):
        import excel2rdl
        rows = [self.FUNC_ROW,
                ("04h", "PASSWORD", "[31:0]", "passwd", "RW",
                 "32'h0badbeef", "key")]
        with self.assertRaisesRegexp(RdlError, "ExtInt sheet"):
            excel2rdl.load_xlsx(self.make_xlsx(
                "sa_conflict.xlsx", rows, ext_rows=[("a", "1", "" )]))

    def test_func_reg_in_std_region_is_handwritten(self):
        # any register at/above ECC_OFFSET marks a hand-written ECC region
        # (no auto-append, no error) -- required for hand-sketched v2 FuSa
        # blocks; previously this raised
        import excel2rdl
        row = ("08h", "CHIP_TOP_5", "[31:0]", "val", "RW", "32'h0", "f")
        m = excel2rdl.load_xlsx(self.make_xlsx("sa_coll.xlsx", [row]))
        self.assertFalse(m.std_appended)
        self.assertEqual([r.gname for r in m.regs], ["CHIP_TOP_5"])

    def test_extint_parity_err_name_err(self):
        import excel2rdl
        with self.assertRaisesRegexp(RdlError, "parity_err"):
            excel2rdl.load_xlsx(self.make_xlsx(
                "sa_pe.xlsx", [self.FUNC_ROW],
                ext_rows=[("parity_err", "1", "")]))

    def test_std_block_regs_shape(self):
        """v1.0 fixed layout == taylor_v3 ground-truth std block."""
        six = [("pd_top_noc_idlereq_time_out", 1),
               ("pd_top_bisr_done_time_out", 1),
               ("pd_top_bisr_busy_time_out", 1),
               ("pd_top_pwr_off_time_out", 1),
               ("top_pmu_signal_chk_err", 1),
               ("lockstep_err", 1)]
        regs = regmodel.std_block_regs(0x4, six)
        sig = [(r.gname, r.offset_int,
                [(f.name, f.msb, f.lsb, f.attr, f.value)
                 for f in r.fields]) for r in regs]
        self.assertEqual(sig[0], ("PASSWORD", 0x4, [
            ("passwd", 31, 0, "RW", "32'h0badbeef")]))
        self.assertEqual(sig[1], ("FUSA_CTRL", 0x8, [
            ("reserved", 31, 13, "RO", "19'h0"),
            ("parity_invert", 12, 12, "RW", "1'b0"),
            ("parity_fault_injection", 11, 8, "RW", "4'b0"),
            ("reserved_1", 7, 4, "RO", "4'h0"),
            ("lockstep_fault_injection", 3, 2, "RW", "2'b0"),
            ("fault_injection_en", 1, 1, "RW", "1'b0"),
            ("parity_decoder_enable", 0, 0, "RW", "1'b0")]))
        ext = [("pd_top_noc_idlereq_time_out", 6, 6),
               ("pd_top_bisr_done_time_out", 5, 5),
               ("pd_top_bisr_busy_time_out", 4, 4),
               ("pd_top_pwr_off_time_out", 3, 3),
               ("top_pmu_signal_chk_err", 2, 2),
               ("lockstep_err", 1, 1)]
        self.assertEqual(sig[2], ("MIssionIntStatusSet0", 0xc, [
            ("reserved", 31, 7, "RO", "25'h0")]
            + [(n + "_set", msb, msb, "WO", "1'b0") for n, msb, _l in ext]
            + [("parity_err_set", 0, 0, "WO", "1'b0")]))
        self.assertEqual(sig[4], ("MIssionIntMask0", 0x14, [
            ("reserved", 31, 7, "RO", "25'h0")]
            + [(n + "_mask", msb, msb, "RW", "1'b0") for n, msb, _l in ext]
            + [("parity_err_mask", 0, 0, "RW", "1'b0")]))

    def test_rdl_roundtrip_appended(self):
        """auto-appended map survives RDL write->parse unchanged."""
        import excel2rdl
        m1 = excel2rdl.load_xlsx(self.make_xlsx(
            "sa_rt.xlsx", [self.FUNC_ROW],
            ext_rows=[("cnt", "2", ""), ("lockstep_err", "1", "")]))
        text = excel2rdl.emit_rdl(m1)
        self.assertIn("auto-appended", text)
        fd, path = tempfile.mkstemp(suffix=".rdl")
        os.close(fd)
        with open(path, "w") as fh:
            fh.write(text)
        m2 = rdl2reg.parse_rdl(path)
        os.remove(path)
        self.assertEqual(
            [(r.gname, r.offset_int,
              [(f.name, f.msb, f.lsb, f.attr, f.value) for f in r.fields])
             for r in m1.regs],
            [(r.gname, r.offset_int,
              [(f.name, f.msb, f.lsb, f.attr, f.value) for f in r.fields])
             for r in m2.regs])
        self.assertEqual(m1.ext_int, m2.ext_int)
        self.assertEqual(m1.func_num_w, m2.func_num_w)


class TestMaterialize(unittest.TestCase):
    """xlsx_materialize: full-map rows for the perl flow."""

    def tearDown(self):
        for f in ("mt_in.xlsx", "mt_full.xlsx"):
            if os.path.exists(f):
                os.remove(f)

    def test_roundtrip_and_perl_compat(self):
        import excel2rdl
        import xlsx_materialize
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(["BASE_ADDR:0x0"])
        ws.append(["ADDR_WIDTH=13"])
        ws.append(["APB3"])
        ws.append(["REG_NUM=1"])
        ws.append(["ECC_OFFSET:0x04"])
        ws.append(["Offset", "Register Name", "SubBits", "Field Name",
                   "Attribute", "DefaultValue", "Description"])
        ws.append(["registers group"])
        ws.append(["00h", "CHIP_TOP_5", "[31:0]", "noc_idlereq_backup_reg",
                   "RW", "32'h0", "f"])
        es = wb.create_sheet("ExtInt")
        es.append(["Field Name", "Bits", "Description"])
        es.append(["cnt", "2", ""])
        es.append(["lockstep_err", "1", ""])
        wb.save("mt_in.xlsx")

        m1 = excel2rdl.load_xlsx("mt_in.xlsx")
        self.assertTrue(m1.std_appended)
        xlsx_materialize.materialize(m1).save("mt_full.xlsx")

        # perl interop contract: single-cell header rows, mandatory
        # 'registers group' separator (perl skips the row after the column
        # header unconditionally), literal 'reserved' field names
        wb2 = openpyxl.load_workbook("mt_full.xlsx")
        ws2 = wb2.worksheets[0]
        self.assertEqual(ws2["A1"].value, "BASE_ADDR:0x0")
        self.assertEqual(ws2["A2"].value, "ADDR_WIDTH=13")
        self.assertEqual(ws2["A4"].value, "REG_NUM=1")
        self.assertEqual(ws2["A5"].value, "ECC_OFFSET:0x04")
        self.assertEqual(ws2["A6"].value, "Offset")
        self.assertEqual(ws2["A7"].value, "registers group")
        names = [row[3].value for row in ws2.iter_rows(min_row=8)
                 if row[3].value]
        self.assertNotIn("reserved_1", names)
        self.assertIn("reserved", names)

        # and the materialized map reloads identically (no re-append)
        m2 = excel2rdl.load_xlsx("mt_full.xlsx")
        self.assertFalse(m2.std_appended)
        sig = lambda m: [(r.gname, r.offset_int,
                          [(f.rname, f.msb, f.lsb, f.attr, f.value)
                           for f in r.fields]) for r in m.regs]
        self.assertEqual(sig(m1), sig(m2))
        self.assertEqual(m1.ext_int, m2.ext_int)
        self.assertEqual(m1.func_num_w, m2.func_num_w)


class TestV2FuSa(unittest.TestCase):
    """Hand-written v2 3-register FuSa block (n/m placeholders, W1C/R)."""

    ROWS = [
        ("00h", "REG_CFG0", "[31:0]", "module_en", "RW", "32'h0", ""),
        ("04h", "REG_CFG1", "[31:0]", "idle_en", "RW", "32'h0", ""),
        ("10h", "FUSA_CTRL", "[31:4]", "reserved", "RO", "0", ""),
        ("10h", "", "[3:0]", "fault_inj_en", "RW", "4'hf", ""),
        ("14h", "STA_PAR", "[31:n]", "reserved", "RO", "0", ""),
        ("14h", "", "[n-1:4]", "reg<m-1>~reg0_par_err_sta", "W1C/R",
         "<m>''b0", ""),
        ("14h", "", "[3:2]", "reserved", "RO", "0", ""),
        ("14h", "", "[1]", "par_fault_n_sta", "W1C/R", "1'b1", ""),
        ("14h", "", "[0]", "par_fault_sta", "W1C/R", "1'b0", ""),
        ("18h", "CFG_REGST", "[31:n]", "reserved", "RO", "0", ""),
        ("18h", "", "[n-1:4]", "par_selftest_reg_sel", "WO", "0", ""),
        ("18h", "", "[3:2]", "reserved", "RO", "0", ""),
        ("18h", "", "[1]", "reg_selftest_en", "WO", "0", ""),
        ("18h", "", "[0]", "par_selftest_en", "WO", "0", ""),
    ]
    # NOTE: the [3:2] reserved rows complete the hand-drawn sketch, whose
    # STA_PAR/CFG_REGST list [31:n]/[n-1:4]/[1]/[0] and leave bits 3:2
    # implicit (23+5+1+1 = 30); the loader demands an explicit 32-bit cover
    # and the demo xlsx carries the same two rows.

    def make_xlsx(self, path, rows, ecc="0x10"):
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(["BASE_ADDR:0x0"])
        ws.append(["ADDR_WIDTH=13"])
        ws.append(["APB3"])
        ws.append(["REG_NUM=1"])
        ws.append(["ECC_OFFSET:%s" % ecc])
        ws.append(["Offset", "Register Name", "SubBits", "Field Name",
                   "Attribute", "DefaultValue", "Description"])
        ws.append(["registers group"])
        for r in rows:
            ws.append(list(r))
        wb.save(path)
        return path

    def tearDown(self):
        for f in ("v2_map.xlsx", "v2_wide.xlsx"):
            if os.path.exists(f):
                os.remove(f)

    def load_v2(self):
        import excel2rdl
        return excel2rdl.load_xlsx(
            self.make_xlsx("v2_map.xlsx", self.ROWS))

    def test_v2_placeholder_resolution(self):
        m = self.load_v2()
        self.assertFalse(m.std_appended)       # ECC region non-empty
        self.assertEqual(len(m.regs), 5)
        self.assertEqual(m.func_num_w, 5)      # m: REG_CFG0/1 + all 3 v2 regs
        sta = [r for r in m.regs if r.gname == "STA_PAR"][0]
        self.assertEqual([(f.name, f.msb, f.lsb, f.attr, f.value)
                          for f in sta.fields], [
            ("reserved", 31, 9, "RO", "23'h0"),
            ("reg_par_err_sta", 8, 4, "W1C", "5'b0"),
            ("reserved_1", 3, 2, "RO", "2'h0"),
            ("par_fault_n_sta", 1, 1, "W1C", "1'b1"),
            ("par_fault_sta", 0, 0, "W1C", "1'b0")])
        cfg = [r for r in m.regs if r.gname == "CFG_REGST"][0]
        self.assertEqual([(f.name, f.msb, f.lsb, f.attr, f.value)
                          for f in cfg.fields], [
            ("reserved", 31, 9, "RO", "23'h0"),
            ("par_selftest_reg_sel", 8, 4, "WO", "5'h0"),
            ("reserved_1", 3, 2, "RO", "2'h0"),
            ("reg_selftest_en", 1, 1, "WO", "1'h0"),
            ("par_selftest_en", 0, 0, "WO", "1'h0")])

    def test_v2_w1cr_alias(self):
        # W1C/R rides through as canonical W1C in the RDL (C-legal ATTR)
        import excel2rdl
        m = self.load_v2()
        text = excel2rdl.emit_rdl(m)
        self.assertIn('attr = "W1C";', text)
        self.assertNotIn("W1C/R", text)

    def test_v2_bank_too_wide_err(self):
        # 25 functional regs -> m=28 -> n=32 -> [31:n] lsb 32 > 31
        groups = {"FUSA_CTRL": [], "STA_PAR": [], "CFG_REGST": []}
        cur = None
        for r in self.ROWS:
            if r[1]:
                cur = r[1]
            if cur in groups:
                groups[cur].append(r)
        rows = ([("%02xh" % (i * 4), "REG_F%d" % i, "[31:0]", "v", "RW",
                  "32'h0", "") for i in range(25)]
                + groups["FUSA_CTRL"] + groups["STA_PAR"]
                + groups["CFG_REGST"])
        import excel2rdl
        with self.assertRaisesRegexp(RdlError, "bit 31"):
            excel2rdl.load_xlsx(self.make_xlsx("v2_wide.xlsx", rows))

    def test_v2_rtl_shape(self):
        # bank-driven STA_PAR/CFG_REGST: single driver, hw set ports, no
        # passwd gating, decoder + control ties deterministic
        m = self.load_v2()
        text = gen(__import__("excel2rdl").emit_rdl(m))[1]
        self.assertNotIn("passwd==", text)
        self.assertIn("input  [4:0]      reg_par_err_sta_wr;", text)
        self.assertIn("input  [4:0]      reg_par_err_sta_in;", text)
        # bank readout (bank index 3: REG_CFG0/1/FUSA_CTRL/STA_PAR/...)
        self.assertIn("%-30s = reg_dec_data_out[3][8:4]; //deft: 5'b0\n"
                      % "assign reg_par_err_sta[4:0]", text)
        # exactly one driver: no bare always for a bank-member ECC reg
        self.assertNotIn("reg_par_err_sta <=", text)
        self.assertIn("%-30s = reg_dec_data_out[3][1]; //deft: 1'b1\n"
                      % "assign par_fault_n_sta", text)
        # safe ties (map carries no legacy FUSA_CTRL control fields)
        self.assertIn("assign parity_decoder_bypass = 1'b0;", text)
        self.assertIn("assign fault_injection_en = 1'b0;", text)
        self.assertIn("assign parity_fault_injection[3:0] = 4'h0;", text)
        self.assertIn("assign parity_invert = 1'b0;", text)
        self.assertIn("assign parity_err_status = 1'b0;", text)
        self.assertIn("assign parity_err_mask = 1'b0;", text)
        # WO selftest config: bank-stored, readback 0
        self.assertIn("%-30s = reg_dec_data_out[4][8:4]; //deft: 5'h0\n"
                      % "assign par_selftest_reg_sel[4:0]", text)
        # bank-member w==1 W1C terms keep their separating comma: the perl
        # writes them bare (s/\};/hwr_X};/) which fuses into 2'h0hwr_X --
        # invalid Verilog, latent until a W1C field joins the bank (STA_PAR)
        self.assertIn(",hwr_STA_PAR,hwr_STA_PAR};\n", text)
        self.assertNotIn("hwr_STA_PARhwr", text)

    def test_v2_legacy_untouched(self):
        # maps WITH a PASSWORD still gate on the key and keep the reader
        m, text = gen(rdl_std())
        self.assertIn("&& (passwd==32'h95f2d303);", text)
        self.assertIn("assign parity_decoder_bypass = ~parity_decoder_enable;",
                      text)
        self.assertNotIn("assign fault_injection_en = 1'b0;", text)


class TestDefines(unittest.TestCase):
    """rdl2def.py -- perl Gen_def_file / Gen_bdef_file port."""

    DATE = "Date : 2026-11-06 00:00:00"
    USER = "eda"

    def defines(self, rdl_text):
        import rdl2def
        mod = gen(rdl_text)[0]
        return {name: text for name, text in
                rdl2def.generate(mod, self.DATE, self.USER)}

    def test_define_v_and_h(self):
        d = self.defines(rdl_std())
        v = d["std_min_define.v"]
        h = d["std_min_define.h"]
        self.assertIn("\n`ifndef STD_MIN_DEF_V_", v)
        self.assertIn("\n`define STD_MIN_DEF_V_\n", v)
        self.assertIn("`define %-40s  (32'h0000)\n" % "OFST_STD_MIN_PASSWORD",
                      v)
        self.assertIn("`define %-40s  (32'h0004)\n" % "OFST_STD_MIN_FUSA_CTRL",
                      v)
        self.assertIn("\n`endif //STD_MIN_DEF_V_\n", v)
        self.assertIn("\n#ifndef STD_MIN_DEF_H_", h)
        self.assertIn("#define %-40s  (0x0000)\n" % "OFST_STD_MIN_PASSWORD",
                      h)
        self.assertIn("\n#endif //STD_MIN_DEF_H_\n", h)
        self.assertTrue(v.startswith("/*\n * Horizon Robotics\n"))

    def test_bit_define_sections(self):
        d = self.defines(rdl_std())
        b = d["std_min_bit_define.h"]
        self.assertTrue(b.startswith("/*\n * Horizon Robotics\n"))
        # 49-dash separators, section banners in perl order
        sep = "//" + "-" * 49 + "\n"
        self.assertIn(sep + "//Register offset macro defines\n" + sep, b)
        self.assertIn(sep + "//Register mask macro defines\n" + sep, b)
        self.assertIn(sep + "//Register default value macro defines\n" + sep,
                      b)
        self.assertIn(sep + sep + "//Register bit information\n" + sep + sep,
                      b)
        # OFST / MASK / DFLT per register, %-40s + two spaces + (%-10s)
        self.assertIn("#define %-40s  (0x0000)\n" % "OFST_STD_MIN_PASSWORD",
                      b)
        self.assertIn("#define %-40s  (0xFFFFFFFF)\n"
                      % "MASK_STD_MIN_PASSWORD", b)
        self.assertIn("#define %-40s  (0x0BADBEEF)\n"
                      % "DFLT_STD_MIN_PASSWORD", b)
        self.assertIn("#define %-40s  (0x00001F0F)\n"
                      % "MASK_STD_MIN_FUSA_CTRL", b)
        self.assertIn("#define %-40s  (0x00000000)\n"
                      % "DFLT_STD_MIN_MISSIONINTSTATUSSET0", b)

    def test_bit_define_bit_macros(self):
        d = self.defines(rdl_std())
        b = d["std_min_bit_define.h"]
        dots = "//" + "." * 31 + "\n"
        self.assertIn("\n" + dots + "//Register Name: OFST_STD_MIN_PASSWORD\n"
                      "//Register offset: 0x0\n" + dots, b)
        # width-1 field: BIT + ATTR lines
        self.assertIn("#define %-50s  (BIT_12)\n"
                      % "BIT_STD_MIN_FUSA_CTRL_PARITY_INVERT", b)
        self.assertIn("#define %-50s  (ATTR_RW)\n"
                      % "ATTR_STD_MIN_FUSA_CTRL_PARITY_INVERT", b)
        # multi-bit: (_X_) macro with the perl BIT_%-2d trailing-space quirk
        self.assertIn("#define %-50s  ((_X_) << 8  & "
                      "(BIT_8 |BIT_9 |BIT_10|BIT_11))\n"
                      % "BIT_STD_MIN_FUSA_CTRL_PARITY_FAULT_INJECTION(_X_)",
                      b)
        # literal-reserved skipped -- including the RDL dedup roundtrip
        # names (reserved_1..N fold back to 'reserved' via rname; the perl
        # compares the literal xlsx cell and skips every one of them)
        self.assertNotIn("BIT_STD_MIN_FUSA_CTRL_RESERVED(_X_)", b)
        self.assertNotIn("BIT_STD_MIN_FUSA_CTRL_RESERVED_1(_X_)", b)
        self.assertNotIn("ATTR_STD_MIN_FUSA_CTRL_RESERVED_1", b)
        # full-width [31:0] register (PASSWORD/passwd): header only, no macros
        self.assertNotIn("BIT_STD_MIN_PASSWORD_PASSWD", b)

    def test_bit_define_v2_values(self):
        import excel2rdl
        import rdl2def
        wb_x = TestV2FuSa().make_xlsx("v2_map.xlsx", TestV2FuSa.ROWS)
        try:
            m = excel2rdl.load_xlsx(wb_x)
            d = {n: t for n, t in rdl2def.generate(m, self.DATE, self.USER)}
            b = d["v2_map_bit_define.h"]
            # reg_par_err_sta[8:4] + par_fault_{n_,}sta[1:0] writable
            # (W1C counts), par_selftest_reg_sel[8:4] + [1:0] (WO counts)
            self.assertIn("#define %-40s  (0x00000002)\n"
                          % "DFLT_V2_MAP_STA_PAR", b)
            self.assertIn("#define %-40s  (0x000001F3)\n"
                          % "MASK_V2_MAP_STA_PAR", b)
            self.assertIn("#define %-40s  (0x0000000F)\n"
                          % "DFLT_V2_MAP_FUSA_CTRL", b)
            self.assertIn("#define %-40s  (0x0000000F)\n"
                          % "MASK_V2_MAP_FUSA_CTRL", b)
            self.assertIn("#define %-40s  (0x000001F3)\n"
                          % "MASK_V2_MAP_CFG_REGST", b)
            self.assertIn("#define %-40s  (0x00000000)\n"
                          % "DFLT_V2_MAP_CFG_REGST", b)
            # W1C/R normalized: C-legal ATTR token
            self.assertIn("(ATTR_W1C)", b)
            self.assertNotIn("W1C/R", b)
        finally:
            if os.path.exists("v2_map.xlsx"):
                os.remove("v2_map.xlsx")

    def test_bare_zero_normalization(self):
        # bare "0" -> w'h0 at Field construction (reserved and plain);
        # parseable tokens ride through untouched
        f1 = regmodel.Field("x", 3, 0, "RW", "0")
        self.assertEqual(f1.value, "4'h0")
        f2 = regmodel.Field("reserved", 12, 5, "RO", 0)
        self.assertEqual(f2.value, "8'h0")
        f3 = regmodel.Field("x", 31, 0, "RW", "32'h0")
        self.assertEqual(f3.value, "32'h0")
        f4 = regmodel.Field("x", 4, 4, "RW", "1'b1")
        self.assertEqual(f4.value, "1'b1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
