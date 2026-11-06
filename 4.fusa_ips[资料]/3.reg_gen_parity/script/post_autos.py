#!/usr/bin/env python3
# post_autos.py — generic stand-in for the AR/AF/AD vim macros that
# reg_gen_parity.pl's Vim_auto() step invokes (team-vimrc commands :AR/:AF/:AD
# are unavailable here, so the raw generator output ships with unfilled
# /*autoarg*/ and missing declarations).
#   AF: fill module port list from body port decls
#   AD: declare wires driven by `assign` but never declared
#   AR: declare regs driven procedurally but never declared, including
#       reg-overrides for output ports (net -> reg redeclaration)
# Tolerates spaced widths ("[3 :0]") and unpacked arrays ("wire [31:0] x [3:0];").
import re, sys

WIDTH_EXTRAS = {"prdata_in": "[31:0]", "passwd": "[31:0]"}  # 32-bit targets

def declared_names(txt):
    names = set()
    for m in re.finditer(
            r'^\s*(?:input|output|inout|wire|reg)\s*(?:\[[^\]]*\]\s*)?(\w+)', txt, re.M):
        names.add(m.group(1))
    return names

src, dst = sys.argv[1], sys.argv[2]
txt = open(src).read()
declared = declared_names(txt)

# ---------------- AF: port list ----------------
ports_out, ports_in = [], []
for m in re.finditer(
        r'^\s*(input|output)\s*(?:\[[^\]]*\]\s*)?(\w+)\s*;', txt, re.M):
    (ports_out if m.group(1) == "output" else ports_in).append(m.group(2))
assert txt.count("/*autoarg*/);") == 1
portlist = ("/*autoarg*/\n    //Outputs\n    " + ", ".join(ports_out) +
            ",\n    //Inputs\n    " + ", ".join(ports_in))
txt = txt.replace("/*autoarg*/);", portlist + ");", 1)

# ---------------- collect undeclared drivers ----------------
assign_w = {}   # name -> "[msb:lsb]" when the assign itself part-selects
for m in re.finditer(r'^\s*assign\s+(\w+)\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]', txt, re.M):
    assign_w[m.group(1)] = "[%s:%s]" % (m.group(2), m.group(3))
wire_want = {m.group(1) for m in re.finditer(r'^\s*assign\s+(\w+)\b', txt, re.M)}
reg_want  = {m.group(1) for m in re.finditer(r'^\s+(\w+)\s*(?:\[[^\]]*\]\s*)?<=', txt, re.M)}
# always @(*) blocking assigns of the read mux, incl. after a case label
reg_want |= {m.group(1) for m in re.finditer(
    r'^\s+(?:\w+\s*:\s*)?(\w+)\s*(?:\[[^\]]*\]\s*)?=\s*\{', txt, re.M)}

def width_of(n):
    return WIDTH_EXTRAS.get(n) or assign_w.get(n) or ""

need_wire = sorted(wire_want - declared)
need_reg  = sorted(reg_want - declared)
# output ports driven procedurally need a reg redeclaration (net -> reg)
need_ovr  = sorted(reg_want & set(ports_out))

wire_decls = "".join("wire %-6s %-40s; // AD\n" % (width_of(n), n) for n in need_wire)
reg_decls  = "".join(
    "reg  %-6s %-40s; // AR%s\n" % (width_of(n), n,
                                    " (output reg override)" if n in ports_out else "")
    for n in need_reg + need_ovr)

WIRE_BLOCK, REG_BLOCK = "//auto wires{{{", "//auto regs{{{"
assert WIRE_BLOCK in txt and REG_BLOCK in txt
txt = txt.replace(WIRE_BLOCK, WIRE_BLOCK + "\n" + wire_decls, 1)
txt = txt.replace(REG_BLOCK, REG_BLOCK + "\n" + reg_decls, 1)

open(dst, "w").write(txt)
print("AF: %d out + %d in; AD wires: %s; AR regs: %s"
      % (len(ports_out), len(ports_in), need_wire, need_reg))
