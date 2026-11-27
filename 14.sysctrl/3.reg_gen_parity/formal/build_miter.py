#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a self-checking original-vs-parity miter for mcusys_ciu.

The generated SV is a simulation/SVA miter, not a replacement for a formal
engine.  It drives every APB register offset and explicitly exercises the
legacy behaviors which a table-only conversion cannot represent.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "script"))
from verilog2regtable import reverse, functional_name  # noqa: E402

ORIG = HERE.parent.parent / "1.orig" / "mcusys_ciu.v"
GEN = HERE.parent / "outfile" / "mcusys_ciu.v"
OUT = HERE / "miter_mcusys_ciu.sv"


def decls(text):
    pat = re.compile(r"^\s*(input|output)\s+(?:reg\s+)?"
                     r"(?:\[(\d+):(\d+)\]\s+)?(\w+)\s*[,)]", re.M)
    ans = []
    for m in pat.finditer(text):
        hi, lo = m.group(2), m.group(3)
        width = 1 if hi is None else int(hi) - int(lo) + 1
        ans.append((m.group(1), m.group(4), width))
    return ans


def vec(name, width):
    return name if width == 1 else "[%d:0] %s" % (width - 1, name)


def main():
    orig_text = ORIG.read_text(encoding="utf-8")
    original_decls = decls(orig_text)
    regs = reverse(ORIG)
    ro_offsets = [r["offset"] for r in regs
                  if any(f["attr"] == "RO" and f["name"] != "reserved"
                         for f in r["fields"])]
    fc_offsets = [r["offset"] for r in regs
                  if r["name"].endswith("CLK_CTRL")
                  and any(f["name"].endswith("_clk_ctrl")
                          for f in r["fields"])]
    # The group-name prefix is not present in the source signal names.
    fc_offsets = [r["offset"] for r in regs
                  if any(f["name"] in (
                      "mcusys_aclk_ctrl", "mcusys_pclk_ctrl",
                      "mcusys_rv_core_clk_ctrl", "mcusys_m85_core0_clk_ctrl",
                      "mcusys_m85_core1_clk_ctrl", "mcusys_m85_core2_clk_ctrl",
                      "mcusys_m85_core3_clk_ctrl")
                      for f in r["fields"])]
    fc_done_names = [n for d, n, w in original_decls
                     if d == "input" and n.endswith("_fc_done")]

    s = []
    s.append("`timescale 1ns/1ps")
    s.append("module miter_mcusys_ciu;")
    s.append("  integer output_checks = 0, output_mismatch = 0;")
    s.append("  integer fc_req_mismatch = 0, other_output_mismatch = 0;")
    s.append("  integer read_checks = 0, read_mismatch = 0;")
    s.append("  integer invalid_read_mismatch = 0, ro_sync_read_mismatch = 0;")
    s.append("  reg [31:0] ro_pattern = 32'h5A5A_A5A5;")
    s.append("  integer stable_ro_read_mismatch = 0;")
    s.append("  reg pclk = 0;")
    s.append("  always #5 pclk = ~pclk;")
    for direction, name, width in original_decls:
        if direction == "input" and name != "pclk":
            s.append("  reg %s;" % vec(name, width))
    s.append("")
    # Original and generated output wires, with explicit legacy-name mapping.
    for direction, name, width in original_decls:
        if direction != "output":
            continue
        s.append("  wire %s;" % vec("orig_" + name, width))
        s.append("  wire %s;" % vec("gen_" + functional_name(name), width))
    s.append("")
    s.append("  mcusys_ciu_orig u_orig (")
    conns = []
    for direction, name, width in original_decls:
        if direction == "input":
            conns.append("    .%s(%s)" % (name, name))
        else:
            conns.append("    .%s(orig_%s)" % (name, name))
    s.append(",\n".join(conns))
    s.append("  );")
    s.append("")
    s.append("  mcusys_ciu u_parity (")
    conns = []
    for direction, name, width in original_decls:
        if direction == "input":
            if name == "por_n":
                continue
            if name == "prstn":
                conns.append("    .presetn(prstn)")
            elif name == "paddr":
                conns.append("    .paddr(paddr[9:0])")
            else:
                conns.append("    .%s(%s)" % (name, name))
        else:
            conns.append("    .%s(gen_%s)" % (functional_name(name),
                                              functional_name(name)))
    s.append(",\n".join(conns))
    s.append("    ,.pslverr()")
    s.append("    ,.mission_int()")
    s.append("    ,.lockstep_fault_injection()")
    s.append("  );")
    s.append("")
    s.append("  task automatic check_one(input string tag, input string name,")
    s.append("                           input [31:0] a, input [31:0] b,")
    s.append("                           input bit is_fc);")
    s.append("    begin")
    s.append("      output_checks = output_checks + 1;")
    s.append("      if (a !== b) begin")
    s.append("        output_mismatch = output_mismatch + 1;")
    s.append("        if (is_fc) fc_req_mismatch = fc_req_mismatch + 1;")
    s.append("        else other_output_mismatch = other_output_mismatch + 1;")
    s.append("        if (output_mismatch <= 60 || !is_fc)")
    s.append("          $display(\"[%0t] OUT-DIFF %s %s orig=%h parity=%h\",")
    s.append("                  $time, tag, name, a, b);")
    s.append("      end")
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic check_outputs(input string tag);")
    s.append("    begin")
    for direction, name, width in original_decls:
        if direction != "output" or name in ("prdata", "pready"):
            continue
        is_fc = name in (
            "mcusys_aclk_ctrl", "mcusys_pclk_ctrl", "mcusys_rv_core_clk_ctrl",
            "mcusys_m85_core0_clk_ctrl", "mcusys_m85_core1_clk_ctrl",
            "mcusys_m85_core2_clk_ctrl", "mcusys_m85_core3_clk_ctrl")
        s.append("      check_one(tag, \"%s\", orig_%s, gen_%s, %d);"
                 % (name, name, functional_name(name), int(is_fc)))
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic check_prdata(input string tag, input string kind);")
    s.append("    begin")
    s.append("      read_checks = read_checks + 1;")
    s.append("      if (kind == \"ro_sync\")")
    s.append("        $display(\"RO_DBG t=%0t addr=%h orig=%h parity=%h aud_sync=%h aud_raw=%h q1=%b q2=%b\", $time, paddr, orig_prdata, gen_prdata, u_orig.aud_spare_in_sync, aud_spare_in, u_orig.u_aud_spare_in_sync[0].u_dsync.q1, u_orig.u_aud_spare_in_sync[0].u_dsync.q2);")
    s.append("      if (orig_prdata !== gen_prdata) begin")
    s.append("        if (kind == \"invalid\") invalid_read_mismatch = invalid_read_mismatch + 1;")
    s.append("        else if (kind == \"ro_sync\") ro_sync_read_mismatch = ro_sync_read_mismatch + 1;")
    s.append("        else if (kind == \"stable_ro\") stable_ro_read_mismatch = stable_ro_read_mismatch + 1;")
    s.append("        else read_mismatch = read_mismatch + 1;")
    s.append("        $display(\"[%0t] PRDATA-DIFF %s/%s addr=%h orig=%h parity=%h\",")
    s.append("                 $time, tag, kind, paddr, orig_prdata, gen_prdata);")
    s.append("      end")
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic read_reg(input [31:0] a, input string tag, input string kind);")
    s.append("    begin")
    s.append("      @(negedge pclk); paddr = a; psel = 1; penable = 0; pwrite = 0;")
    s.append("      if (kind == \"ro_sync\") begin")
    s.append("        // Change at the setup edge, not one full cycle earlier.")
    s.append("        set_ro_inputs(ro_pattern); ro_pattern = ~ro_pattern;")
    s.append("        // One setup edge only: q2 of the original 2FF sync is old,")
    s.append("        // while the generated direct-input read data is new.")
    s.append("        @(posedge pclk); #1; check_prdata(tag, kind);")
    s.append("      end else begin")
    s.append("        @(negedge pclk); penable = 1;")
    s.append("        #1; check_prdata(tag, kind);")
    s.append("      end")
    s.append("      @(negedge pclk); psel = 0; penable = 0;")
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic write_reg(input [31:0] a, input [31:0] d, input string tag);")
    s.append("    begin")
    s.append("      @(negedge pclk); paddr = a; pwdata = d; psel = 1; penable = 0; pwrite = 1;")
    s.append("      @(negedge pclk); penable = 1;")
    s.append("      @(negedge pclk); psel = 0; penable = 0; pwrite = 0;")
    s.append("      #1; check_outputs(tag);")
    s.append("      read_reg(a, tag, \"write_read\");")
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic set_ro_inputs(input [31:0] value);")
    s.append("    begin")
    for direction, name, width in original_decls:
        if direction != "input" or name in ("por_n", "pclk", "prstn", "paddr",
                                               "pwrite", "psel", "penable", "pwdata"):
            continue
        if name.endswith("_fc_done"):
            continue
        s.append("      %s = value;" % name)
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  task automatic set_fc_done(input bit value);")
    s.append("    begin")
    for name in fc_done_names:
        s.append("      %s = value;" % name)
    s.append("    end")
    s.append("  endtask")
    s.append("")
    s.append("  integer i;")
    s.append("")
    s.append("  initial begin")
    s.append("    por_n = 1'b1; prstn = 1'b0; paddr = 0; pwrite = 0; psel = 0; penable = 0; pwdata = 0;")
    for direction, name, width in original_decls:
        if direction == "input" and name not in ("por_n", "pclk", "prstn", "paddr",
                                                   "pwrite", "psel", "penable", "pwdata"):
            s.append("    %s = '0;" % name)
    s.append("    repeat (4) @(negedge pclk);")
    s.append("    check_outputs(\"reset_assert\");")
    s.append("    prstn = 1'b1;")
    s.append("    repeat (3) @(negedge pclk);")
    s.append("    check_outputs(\"reset_release\");")
    s.append("    for (i = 0; i < 157; i = i + 1) begin")
    s.append("      write_reg(i * 4, 32'hA5A5_5A5A ^ (i * 32'h0101_0101), \"all_offsets\");")
    s.append("    end")
    s.append("    // Invalid addresses use the original prdata_d hold path, not zero.")
    s.append("    write_reg(32'h34, 32'h1234_5678, \"invalid_setup\");")
    s.append("    read_reg(32'h34, \"valid_before_invalid\", \"write_read\");")
    s.append("    read_reg(32'h3fc, \"invalid_address\", \"invalid\");")
    s.append("    // Stable RO inputs should agree after the two-FF sync delay.")
    s.append("    set_ro_inputs(32'hA5A5_5A5A);")
    s.append("    repeat (4) @(negedge pclk);")
    for off in ro_offsets:
        s.append("    read_reg(32'h%03x, \"stable_ro\", \"stable_ro\");" % off)
    s.append("    // Immediate changes expose missing synchronizers in generated RTL.")
    s.append("    // Each RO read toggles the input at its setup edge below.")
    for off in ro_offsets:
        s.append("    read_reg(32'h%03x, \"ro_sync\", \"ro_sync\");" % off)
    s.append("    // fc_done=0 asynchronously clears the legacy fc_req bit [4].")
    s.append("    set_fc_done(1'b0);")
    for off in fc_offsets:
        s.append("    write_reg(32'h%03x, 32'h0000_0010, \"fc_req_clear\");" % off)
    s.append("    set_fc_done(1'b1);")
    s.append("    $display(\"FC_DBG before_set: done=%b prstn=%b custom_resetn=%b ctrl=%h\", mcusys_aclk_fc_done, prstn, u_orig.mcusys_aclk_ctrl4_prstn, orig_mcusys_aclk_ctrl);")
    for off in fc_offsets:
        s.append("    write_reg(32'h%03x, 32'h0000_0010, \"fc_req_set\");" % off)
    s.append("    set_fc_done(1'b0);")
    s.append("    #1; check_outputs(\"fc_req_done_fall\");")
    s.append("    // A final global reset must restore every common output.")
    s.append("    prstn = 1'b0;")
    s.append("    repeat (3) @(negedge pclk);")
    s.append("    check_outputs(\"final_reset\");")
    s.append("    $display(\"=== MITER SUMMARY ===\");")
    s.append("    $display(\"output_checks=%0d output_mismatch=%0d fc_req_mismatch=%0d other_output_mismatch=%0d\",")
    s.append("             output_checks, output_mismatch, fc_req_mismatch, other_output_mismatch);")
    s.append("    $display(\"read_checks=%0d write_read_mismatch=%0d invalid_read_mismatch=%0d stable_ro_mismatch=%0d ro_sync_mismatch=%0d\",")
    s.append("             read_checks, read_mismatch, invalid_read_mismatch, stable_ro_read_mismatch, ro_sync_read_mismatch);")
    s.append("    if (output_mismatch || read_mismatch || invalid_read_mismatch || stable_ro_read_mismatch || ro_sync_read_mismatch)")
    s.append("      $display(\"MITER_RESULT: DIFFERENCES_FOUND\");")
    s.append("    else")
    s.append("      $display(\"MITER_RESULT: EQUIVALENT_UNDER_TESTED_PROTOCOL\");")
    s.append("    $finish;")
    s.append("  end")
    s.append("endmodule")
    OUT.write_text("\n".join(s) + "\n", encoding="utf-8")
    # Keep a renamed source beside the miter for a simple VCS file list.
    renamed = orig_text.replace("module mcusys_ciu(", "module mcusys_ciu_orig(", 1)
    (HERE / "mcusys_ciu_orig.v").write_text(renamed, encoding="utf-8")
    print("wrote %s (%d RO offsets, %d fc offsets)" %
          (OUT, len(ro_offsets), len(fc_offsets)))


if __name__ == "__main__":
    main()
