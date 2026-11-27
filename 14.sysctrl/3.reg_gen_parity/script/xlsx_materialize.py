#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xlsx_materialize.py -- write the auto-appended standard FuSa block back out
as plain excel rows.

Takes a functional-only xlsx (std block auto-appended by excel2rdl) and
produces the equivalent FULL map with every std register as explicit rows.
Use it to feed the legacy perl reg_gen_parity.pl (interop / ground truth)
or to freeze a map for review.

Usage:
    python3 xlsx_materialize.py in.xlsx [-o out.xlsx]
"""

import os
import sys

import excel2rdl
from regmodel import RdlError

try:
    import openpyxl
except ImportError:
    sys.stderr.write("[ERROR] openpyxl is required\n")
    sys.exit(1)


def materialize(mod):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Registers"
    # header rows in the perl-canonical single-cell format (BASE_ADDR:0x0 /
    # ADDR_WIDTH=13 / bus / REG_NUM=n / ECC_OFFSET:0x04) -- both the perl
    # reg_gen_parity.pl and excel2rdl.py accept this layout
    ws.append(["BASE_ADDR:%s" % mod.base_addr])
    ws.append(["ADDR_WIDTH=%d" % mod.addr_width])
    ws.append([mod.bus])
    ws.append(["REG_NUM=%d" % mod.reg_num_hdr])
    ws.append(["ECC_OFFSET:0x%02x" % mod.ecc_offset])
    ws.append(["Offset", "Register Name", "SubBits", "Field Name",
               "Attribute", "DefaultValue", "Description"])
    # perl Proc_info SKIPS the first row after the column header
    # unconditionally (the 'registers group' section separator in the
    # Horizon template) -- the row is mandatory for perl compatibility
    ws.append(["registers group"])
    for r in mod.regs:
        for i, f in enumerate(r.fields):
            sub = ("[%d]" % f.msb if f.msb == f.lsb
                   else "[%d:%d]" % (f.msb, f.lsb))
            # f.rname: reserved_N -> literal 'reserved' (perl semantics)
            ws.append([r.offset if i == 0 else "",
                       r.gname if i == 0 else "",
                       sub, f.rname, f.attr, f.value, f.desc])
    return wb


def main():
    args = sys.argv[1:]
    infile = outfile = None
    i = 0
    while i < len(args):
        if args[i] == "-o" and i + 1 < len(args):
            outfile = args[i + 1]
            i += 2
        elif infile is None:
            infile = args[i]
            i += 1
        else:
            sys.stderr.write("usage: xlsx_materialize.py in.xlsx "
                             "[-o out.xlsx]\n")
            sys.exit(1)
    if infile is None:
        sys.stderr.write("usage: xlsx_materialize.py in.xlsx [-o out.xlsx]\n")
        sys.exit(1)
    if outfile is None:
        base, _ = os.path.splitext(infile)
        outfile = base + "_full.xlsx"
    try:
        mod = excel2rdl.load_xlsx(infile)
        if not mod.std_appended:
            raise RdlError("%s already carries the standard FuSa block "
                           "(nothing to materialize)" % infile)
        materialize(mod).save(outfile)
    except RdlError as e:
        sys.stderr.write("[ERROR] %s\n" % e)
        sys.exit(1)
    print("[INFO]: wrote %s (%d registers, std block materialized)"
          % (outfile, len(mod.regs)))


if __name__ == "__main__":
    main()
