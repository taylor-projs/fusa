#!/usr/bin/env python3
# gen_ip_excl.py - int_prot true-coverage structural exclusion builder
# 输入: 当前编译的 urg raw modinfo + 四种 full_exclusions dump。
# 纪律: 只处理当前 raw 洞; 任何未归类 line/cond/branch/toggle 洞均中止。
import os
import re
import sys

REPORT = sys.argv[1] if len(sys.argv) > 1 else "urg_report"
OUT_DIR = os.environ.get("EXCL_OUT", os.path.dirname(os.path.abspath(__file__)))
os.makedirs(OUT_DIR, exist_ok=True)


def parse_dump(path):
    entries = {}
    cur = None
    checksum = None
    source_line = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", line)
        if m:
            checksum = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", line)
        if m:
            cur = ("%s: %s" % (m.group(1), m.group(2))).rstrip()
            entries[cur] = {"checksum": checksum, "items": []}
            source_line = None
            continue
        m = re.match(r"^// ANNOTATION: .*LineNumber: ([0-9]+)\"$", line)
        if m:
            source_line = int(m.group(1))
            continue
        m = re.match(r"^// ((?:Toggle|Block|Branch) .*)$", line)
        if m and cur is not None:
            entries[cur]["items"].append(
                {"text": m.group(1), "source_line": source_line})
    return entries


def parse_holes(path):
    holes = {"Toggle": {}, "Line": {}, "Branch": {}}
    cond_holes = []
    metric = None
    scope = None
    cond_line = None
    cond_expr = None
    table_re = re.compile(r"^([\s01\-]+?)\s(Covered|Not Covered|Excluded)\s*$")
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        # self-instances 标题后的实例评分行不匹配洞格式; 后续 Totals/Details
        # 仍是模块定义域汇总, 必须继续归属当前 MODULE scope。
        if re.match(r"^(Line|Cond|Branch|Toggle) Coverage for Module self-instances", line):
            continue
        m = re.match(r"^(Line|Cond|Branch|Toggle) Coverage for (Instance|Module) : (.*)$", line)
        if m:
            metric = m.group(1)
            scope = ("%s: %s" % ("INSTANCE" if m.group(2) == "Instance" else "MODULE",
                                  re.sub(r"\s*\(x\)\s*$", "", m.group(3).strip()))).rstrip()
            cond_line = None
            cond_expr = None
            continue
        if metric is None or scope is None:
            continue
        if metric == "Toggle":
            m = re.match(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                         r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$", line)
            if not m:
                m = re.match(r"^\s*Other bits of (\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)\s*$", line)
            if m and "No" in (m.group(2), m.group(3), m.group(4)):
                if m.group(3) == "No" and m.group(4) == "No":
                    direction = None
                elif m.group(3) == "No":
                    direction = "1to0"
                else:
                    direction = "0to1"
                old = holes["Toggle"][scope].get(m.group(1), "covered") \
                    if scope in holes["Toggle"] else "covered"
                if old == "covered" or old is None or direction is None or old == direction:
                    holes["Toggle"].setdefault(scope, {})[m.group(1)] = direction
                else:
                    holes["Toggle"].setdefault(scope, {})[m.group(1)] = None
        elif metric == "Line":
            m = re.match(r"^\s*([0-9]+)\s+0/[0-9]+\s", line)
            if m:
                holes["Line"].setdefault(scope, set()).add(int(m.group(1)))
        elif metric == "Cond":
            m = re.match(r"^\s*LINE\s+([0-9]+)\s*$", line)
            if m:
                cond_line = int(m.group(1))
                continue
            m = re.match(r"^\s*EXPRESSION\s+(.*)$", line)
            if m:
                cond_expr = re.sub(r"\s+", " ", m.group(1)).strip()
                continue
            m = table_re.match(line)
            if m and m.group(2) == "Not Covered" and cond_line is not None:
                cond_holes.append((scope, cond_line, cond_expr,
                                   "".join(m.group(1).split())))
        elif metric == "Branch":
            m = table_re.match(line)
            if m and m.group(2) == "Not Covered":
                holes["Branch"].setdefault(scope, set()).add(
                    ",".join(m.group(1).split()))
    return holes, cond_holes


DUMPS = {}
for domain, filename in (("INSTANCE", "fullexclude"), ("MODULE", "fullexclude_module")):
    for metric in ("tgl", "line", "branch"):
        parsed = parse_dump(filename + "." + metric)
        for scope, entry in parsed.items():
            slot = DUMPS.setdefault(scope, {"checksum": {}, "items": []})
            slot["checksum"][metric] = entry["checksum"]
            slot["items"].extend(entry["items"])

HOLES, COND_HOLES = parse_holes(os.path.join(REPORT, "modinfo.txt"))
if COND_HOLES:
    for item in COND_HOLES:
        print("UNCLASSIFIED cond hole:", item)
    raise SystemExit("cond 仍有 raw 洞; int_prot 不允许 cond 结构排除")

HIGH32 = {"wdata", "rdata", "r.data_q", "rin.data_q"}
REGFILE_ZERO = {
    "en_r[31:4]", "ien_r[31:4]", "sta_err_r[31:4]", "sta_flt_r[30:4]",
    "en_w[31:4]", "ien_w[31:4]", "sta_err_w[31:4]", "sta_flt_w[30:4]",
    "sta_par_rb[31:9]",
}


def toggle_family(scope, sig):
    if scope == "MODULE: int_prot_regfile" and sig in REGFILE_ZERO:
        return "ZFIELD: 字段拼接/状态字保留位恒 0 (en/ien 4b, sta_err NUM_INT=4, sta_flt 低4+bit31)"
    m = re.match(r"^(wdata|rdata|r\.data_q|rin\.data_q)\[(31:4|30:4)\]$", sig)
    if m:
        bits = m.group(2)
        if bits == "31:4" and re.search(r"\.u_w_(en|ien|sta)$", scope):
            return "ZFIELD: 对应 en/ien/sta_err 存储高 28 位由父级零拼接, 结构恒 0"
        if bits == "30:4" and scope.endswith(".u_w_flt"):
            return "ZFIELD: sta_flt 仅低 4 个计数器位和 bit31 自测位可写, [30:4] 结构恒 0"
    return None


def line_family(scope, line):
    if scope in ("INSTANCE: tb_int_prot.dut.u_int_prot", "MODULE: int_prot_core") \
            and line in (188, 189):
        return 188, "PARAM_POSEDGE: DUT POSEDGE_DETECT_ONLY=1, 全沿 XOR else 臂经参数常量折叠不可达"
    return None, None


def branch_family(scope, vector):
    return None


TGL_BLOCKS = {}
for scope in sorted(HOLES["Toggle"]):
    if scope not in DUMPS:
        raise SystemExit("dump 无 toggle scope: " + scope)
    declarations = {}
    for item in DUMPS[scope]["items"]:
        m = re.match(r"^Toggle (?:[01]to[01] )?(\S+) \"(.*)\"$", item["text"])
        if m:
            declarations[m.group(1)] = m.group(2)
    for sig in sorted(HOLES["Toggle"][scope]):
        direction = HOLES["Toggle"][scope][sig]
        if toggle_family(scope, sig) is None:
            raise SystemExit("UNCLASSIFIED toggle hole: [%s] %s" % (scope, sig))
        m = re.match(r"^([\w.]+)(\[.+\])?$", sig)
        if not m:
            raise SystemExit("无法解析 toggle 对象: " + sig)
        base, select = m.group(1), m.group(2)
        if base not in declarations:
            raise SystemExit("dump 无声明: [%s] %s" % (scope, base))
        prefix = "Toggle " + (direction + " " if direction else "")
        select_text = " " + select if select else ""
        row = '%s%s%s "%s"' % (prefix, base, select_text, declarations[base])
        key = (DUMPS[scope]["checksum"]["tgl"], scope)
        TGL_BLOCKS.setdefault(key, []).append(row)

MISC_BLOCKS = {}
for scope in sorted(HOLES["Line"]):
    for line in sorted(HOLES["Line"][scope]):
        dump_line, reason = line_family(scope, line)
        if reason is None:
            raise SystemExit("UNCLASSIFIED line hole: [%s] %d" % (scope, line))
        candidates = [x for x in DUMPS.get(scope, {}).get("items", [])
                      if x["source_line"] == dump_line and x["text"].startswith("Block ")]
        if len(candidates) != 1:
            raise SystemExit("line dump 匹配数=%d: [%s] %d" % (len(candidates), scope, line))
        key = (DUMPS[scope]["checksum"]["line"], scope)
        if candidates[0]["text"] not in MISC_BLOCKS.get(key, []):
            MISC_BLOCKS.setdefault(key, []).append(candidates[0]["text"])

for scope in sorted(HOLES["Branch"]):
    for vector in sorted(HOLES["Branch"][scope]):
        if branch_family(scope, vector) is None:
            raise SystemExit("UNCLASSIFIED branch hole: [%s] %s" % (scope, vector))


def write_el(filename, header, blocks):
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write(header)
        for (checksum, scope), rows in sorted(blocks.items()):
            out.write("CHECKSUM: %s\n%s\n%s\n\n" % (checksum, scope, "\n".join(rows)))
    print("wrote %s (%d scopes, %d rows)" % (path, len(blocks), sum(map(len, blocks.values()))))


TGL_HEADER = """// int_prot TRUE-COVERAGE toggle exclusions; regenerated from current raw holes only.
// ZFIELD: en/ien 仅 4b、sta_err 仅 NUM_INT=4 位、sta_flt 仅低4位+bit31; 其余位由父级零拼接/保留译码恒 0。
// ZFIELD: sta_par_rb[31:9] 为寄存器地图保留位, 无存储/读回驱动源。
// 不排除通道/地址/复位/dup_err/write-selftest: TB T18-T20 已用真实激励或 FI 覆盖。
"""
MISC_HEADER = """// int_prot TRUE-COVERAGE line/branch exclusions; regenerated from current raw holes only.
// PARAM_POSEDGE: int_prot_core 的 POSEDGE_DETECT_ONLY 是 elaboration 参数; DUT=1 时 188/189 全沿 else 基本块不可达。
// 无 cond/branch 排除: 当前 TB 已覆盖全部可达组合与分支。
"""
write_el("tgl_struct_excl.el", TGL_HEADER, TGL_BLOCKS)
write_el("misc_struct_excl.el", MISC_HEADER, MISC_BLOCKS)
