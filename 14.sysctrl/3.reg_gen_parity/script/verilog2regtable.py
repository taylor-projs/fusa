#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reverse a simple APB Verilog regfile into reg_gen_parity CSV/XLSX tables.

Supported input shape (mcusys_ciu.v):
  * APB read mux entries: 8'hNN: prdata = <signal | {concat}> ;
  * writes:             signal <= pwdata[msb:lsb] ;
  * reset assignments:  signal <= <width>'<radix><digits> ;

The read mux is authoritative for field placement.  A signal written from
pwdata is RW; every other read-mux signal is RO.  Zero concatenation items
become reserved/RO gaps.  The generated workbook keeps the perl-compatible
header rows and the mandatory "registers group" separator.
"""

import argparse
import csv
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
HEADERS = ["Offset", "Register Name", "SubBits", "Field Name",
           "Attribute", "DefaultValue", "Description"]


def bits_of(token):
    m = re.match(r"(\d+)'([bBoOdDhH])([0-9a-fA-F_xXzZ]+)$", token)
    if not m:
        raise ValueError("bad literal %r" % token)
    width = int(m.group(1))
    radix = m.group(2).lower()
    digits = m.group(3).replace("_", "")
    base = {"b": 2, "o": 8, "d": 10, "h": 16}[radix]
    value = int(re.sub(r"[xXzZ]", "0", digits), base)
    return width, value


def functional_name(name):
    """Avoid the generator's reserved-field name check for real RW regs.

    The legacy RTL calls several writable registers reserved0_rv_s etc.;
    unlike a literal `reserved` gap, these are functional storage.  Rename
    only the numbered form to rsvd*, leaving actual reserved gaps untouched.
    """
    return re.sub(r"^reserved(?=\d)", "rsvd", name, flags=re.I)


def declared_width(ports, name):
    if name not in ports:
        raise ValueError("signal %s is not declared in the module ports" % name)
    msb, lsb = ports[name]
    return msb - lsb + 1


def split_concat(expr):
    expr = expr.strip()
    if expr.startswith("{") and expr.endswith("}"):
        return [x.strip() for x in expr[1:-1].split(",")]
    return [expr]


def reverse(verilog):
    text = verilog.read_text(encoding="utf-8")
    ports = {}
    decl_re = re.compile(
        r"^\s*(?:input|output)\s+(?:reg\s+)?"
        r"(?:\[(\d+):(\d+)\]\s+)?(\w+)\s*[,)]", re.M)
    for m in decl_re.finditer(text):
        hi, lo, name = m.groups()
        ports[name] = (int(hi), int(lo)) if hi is not None else (0, 0)

    rw_signals = set()
    wr_re = re.compile(r"(\w+)(?:\[\d+(?::\d+)?\])?\s*<=\s*pwdata")
    for m in wr_re.finditer(text):
        rw_signals.add(m.group(1))

    reset_bits = {}
    reset_tokens = {}
    rst_re = re.compile(
        r"(\w+)(?:\[(\d+)(?::(\d+))?\])?\s*<=\s*"
        r"(\d+'[bBoOdDhH][0-9a-fA-F_xXzZ]+)\s*;")
    for m in rst_re.finditer(text):
        name, hi, lo, token = m.groups()
        # Internal bookkeeping registers (e.g. prdata_d) are not table fields.
        if name not in ports:
            continue
        width = declared_width(ports, name)
        if hi is None:
            lhs_hi, lhs_lo = width - 1, 0
            reset_tokens[name] = token
        else:
            lhs_hi = int(hi)
            lhs_lo = int(lo) if lo is not None else lhs_hi
        _, value = bits_of(token)
        per_signal = reset_bits.setdefault(name, {})
        for bit in range(lhs_lo, lhs_hi + 1):
            per_signal[bit] = (value >> (bit - lhs_lo)) & 1

    group_names = {}
    group_re = re.compile(
        r"//\s*Address\s+0x([0-9a-fA-F]+):\s*Group\s+\d+\s*-\s*([^\r\n]+)")
    for m in group_re.finditer(text):
        index = int(m.group(1), 16) // 4  # byte address -> paddr[9:2] index
        first = m.group(2).split(" and ")[0].strip()
        group_names[index] = functional_name(first.upper())

    read_re = re.compile(
        r"8'h([0-9a-fA-F]+)\s*:\s*prdata\s*=\s*([^;]+);")
    registers = []
    for m in read_re.finditer(text):
        index = int(m.group(1), 16)
        items = split_concat(m.group(2))
        fields = []
        lsb = 0
        for item in reversed(items):
            zm = re.match(r"(\d+)'b0+$", item)
            if zm:
                width = int(zm.group(1))
                name = "reserved"
                attr = "RO"
                default = "0"
            else:
                if not re.match(r"^\w+$", item):
                    raise ValueError("unsupported read-mux item %r at 0x%x"
                                     % (item, index * 4))
                sync_name = item
                raw_name = re.sub(r"_sync$", "", sync_name)
                name = functional_name(raw_name)
                width = declared_width(ports, raw_name)
                attr = "RW" if raw_name in rw_signals else "RO"
                if attr == "RO":
                    default = "%d'h0" % width
                elif raw_name in reset_tokens:
                    # A whole-signal reset token is kept verbatim.
                    default = reset_tokens[raw_name]
                    if bits_of(default)[0] != width:
                        default = None
                else:
                    default = None
                if attr == "RW" and default is None:
                    known = reset_bits.get(raw_name, {})
                    missing = [b for b in range(width) if b not in known]
                    if missing:
                        raise ValueError(
                            "%s at 0x%x: no reset value for bits %s"
                            % (raw_name, index * 4, missing))
                    value = sum(known[b] << b for b in range(width))
                    default = "%d'h%X" % (width, value)
            fields.append({"name": name, "msb": lsb + width - 1,
                           "lsb": lsb, "attr": attr, "default": default})
            lsb += width
        if lsb != 32:
            raise ValueError("read mux 0x%x covers %d bits, expected 32"
                             % (index * 4, lsb))
        fields.sort(key=lambda f: f["msb"], reverse=True)
        reg_name = group_names.get(index)
        if not reg_name:
            reg_name = next((f["name"].upper() for f in fields
                             if f["name"] != "reserved"), "REG_%02X" % index)
        # Generated localparams share the register name.  Prefix every
        # register to avoid collisions with same-named output ports/fields
        # (MGCR, MCUSYS_ACLK_CTRL, ...).
        if not reg_name.startswith("R_"):
            reg_name = "R_" + reg_name
        registers.append({"index": index, "offset": index * 4,
                          "name": reg_name, "fields": fields})

    registers.sort(key=lambda r: r["offset"])
    if not registers:
        raise ValueError("no APB read-mux entries found")
    for prev, cur in zip(registers, registers[1:]):
        if cur["offset"] <= prev["offset"]:
            raise ValueError("register offsets are not strictly increasing")
    return registers


def rows_for(registers, addr_width, ecc_offset):
    rows = [["BASE_ADDR:0x0", "", "", "", "", "", ""],
            ["ADDR_WIDTH=%d" % addr_width, "", "", "", "", "", ""],
            ["APB3", "", "", "", "", "", ""],
            ["REG_NUM=%d" % len(registers), "", "", "", "", "", ""],
            ["ECC_OFFSET:0x%03x" % ecc_offset, "", "", "", "", "", ""],
            HEADERS,
            ["registers group", "", "", "", "", "", ""]]
    for reg in registers:
        for i, field in enumerate(reg["fields"]):
            sub = ("[%d]" % field["msb"] if field["msb"] == field["lsb"]
                   else "[%d:%d]" % (field["msb"], field["lsb"]))
            rows.append([("%02Xh" % reg["offset"]) if i == 0 else "",
                         reg["name"] if i == 0 else "",
                         sub, field["name"], field["attr"],
                         field["default"], ""])
    return rows


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows(rows)


def write_xlsx(path, template, rows):
    """Clone the template package and replace Registers/sheet1.xml.

    Shared strings (rather than inlineStr) are used deliberately: the VM's
    openpyxl normal-mode reader drops some inlineStr cells after blank rows,
    while its shared-string path is the same one used by the reference xlsx.
    """
    strings = []
    string_ids = {}
    for row in rows:
        for value in row:
            value = str(value)
            if value not in string_ids:
                string_ids[value] = len(strings)
                strings.append(value)

    with zipfile.ZipFile(str(template), "r") as zin:
        root = ET.fromstring(zin.read("xl/worksheets/sheet1.xml"))
        sheet_data = root.find("{%s}sheetData" % NS)
        if sheet_data is None:
            raise ValueError("template has no sheetData")
        for child in list(sheet_data):
            sheet_data.remove(child)
        for r_idx, values in enumerate(rows, 1):
            row = ET.SubElement(sheet_data, "{%s}row" % NS,
                                {"r": str(r_idx), "spans": "1:7"})
            for c_idx, value in enumerate(values):
                ref = "%s%d" % (chr(ord("A") + c_idx), r_idx)
                cell = ET.SubElement(row, "{%s}c" % NS,
                                     {"r": ref, "t": "s"})
                v = ET.SubElement(cell, "{%s}v" % NS)
                v.text = str(string_ids[str(value)])
        # The template's merged ranges belong to its old register rows.  A
        # reversed table has different row spans; keeping them turns valid
        # offset/name cells into MergedCell(None) on openpyxl load.
        merged = root.find("{%s}mergeCells" % NS)
        if merged is not None:
            root.remove(merged)
        dim = root.find("{%s}dimension" % NS)
        if dim is not None:
            dim.set("ref", "A1:G%d" % len(rows))
        ET.register_namespace("", NS)
        ET.register_namespace(
            "mc", "http://schemas.openxmlformats.org/markup-compatibility/2006")
        ET.register_namespace(
            "x14ac", "http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac")
        ET.register_namespace(
            "r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
        xml = ET.tostring(root, encoding="utf-8", xml_declaration=True)

        sst = ET.Element("{%s}sst" % NS, {
            "count": str(len(rows) * 7), "uniqueCount": str(len(strings))})
        for value in strings:
            si = ET.SubElement(sst, "{%s}si" % NS)
            t = ET.SubElement(si, "{%s}t" % NS)
            t.text = value
        shared_xml = ET.tostring(sst, encoding="utf-8", xml_declaration=True)

        with zipfile.ZipFile(str(path), "w", zipfile.ZIP_DEFLATED) as zout:
            for info in zin.infolist():
                if info.filename == "xl/worksheets/sheet1.xml":
                    data = xml
                elif info.filename == "xl/sharedStrings.xml":
                    data = shared_xml
                else:
                    data = zin.read(info.filename)
                zout.writestr(info, data)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("verilog", type=Path)
    ap.add_argument("-o", "--output-prefix", type=Path, required=True,
                    help="output prefix without .csv/.xlsx suffix")
    ap.add_argument("--template", type=Path, required=True)
    ap.add_argument("--addr-width", type=int, default=10)
    ap.add_argument("--ecc-offset", type=lambda x: int(x, 0), default=0x280)
    args = ap.parse_args()
    registers = reverse(args.verilog)
    if args.ecc_offset <= registers[-1]["offset"]:
        raise SystemExit("ECC_OFFSET must be above the last functional register")
    rows = rows_for(registers, args.addr_width, args.ecc_offset)
    csv_path = args.output_prefix.with_suffix(".csv")
    xlsx_path = args.output_prefix.with_suffix(".xlsx")
    write_csv(csv_path, rows)
    write_xlsx(xlsx_path, args.template, rows)
    rw = sum(1 for r in registers for f in r["fields"] if f["attr"] == "RW")
    ro = sum(1 for r in registers for f in r["fields"]
             if f["attr"] == "RO" and f["name"] != "reserved")
    print("reversed %d registers, %d RW fields, %d RO fields, %d table rows"
          % (len(registers), rw, ro, len(rows)))
    print("wrote %s" % csv_path)
    print("wrote %s" % xlsx_path)


if __name__ == "__main__":
    main()
