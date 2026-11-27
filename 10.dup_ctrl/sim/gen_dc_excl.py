#!/usr/bin/env python3
# gen_dc_excl.py - dup_ctrl true-coverage structural exclusion builder
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
    raise SystemExit("cond 仍有 raw 洞; dup_ctrl 不允许 cond 结构排除")

READ_ZERO = {"rdata[12:9]", "rdata[16:14]", "rdata[24]", "rdata[26]", "rdata[29]"}
REGFILE_ZERO = {
    "en_r[31:4]", "ien_r[31:4]", "fi_r[31:2]",
    "en_w[31:4]", "ien_w[31:4]", "fi_w[31:2]",
}
STATUS_SCOPE = re.compile(r"\.u_(err_st|err_s2|raw_s2)$")


def toggle_family(scope, sig):
    if scope in ("MODULE: dup_ctrl_top", "MODULE: dup_ctrl_regfile") and sig in READ_ZERO:
        return "ZREAD: 所有可读寄存器在这些位均恒 0, ID_VAL 对应位也为 0"
    if scope == "MODULE: dup_ctrl_regfile" and sig == "par_l_dup_f[1]":
        return "SCALAR_NE: 向量 != 结果为 1 bit, 赋给 2b par_l_dup_f 时 bit1 结构恒 0 (RTL 死位已报告)"
    if scope == "MODULE: dup_ctrl_regfile" and sig in REGFILE_ZERO:
        return "ZFIELD: en/ien 仅 4b、fi 仅 2b, 父级零拼接高位结构恒 0"
    m = re.match(r"^(wdata|rdata|r\.data_q|rin\.data_q)\[(31:4|31:2)\]$", sig)
    if m:
        if m.group(2) == "31:4" and (scope.startswith("MODULE: reg_wrap ( parameter W=32,RESET")
                                     or re.search(r"\.u_w_(en|ien)$", scope)):
            return "ZFIELD: W=32 en/ien/fi 模块并集的高 [31:4] 由父级零拼接恒 0"
        if m.group(2) == "31:2" and scope.endswith(".u_w_fi"):
            return "ZFIELD: fi 仅低 2 位有存储, [31:2] 由父级零拼接恒 0"
    if STATUS_SCOPE.search(scope) and sig == "wr":
        return "WR_TIE1: err_st/err_s2/raw_s2 是跟随型状态 wrap, wr 端口硬连 1'b1"
    return None


def line_family(scope, line):
    if STATUS_SCOPE.search(scope) and line in (108, 110):
        return line, "WR_TIE1: 跟随型 wrap wr 恒 1, else-if(selftest_key) 及其赋值基本块不可达"
    return None, None


def branch_family(scope, vector):
    if STATUS_SCOPE.search(scope) and vector in ("0,-,1", "0,-,0"):
        return "WR_TIE1: wr 恒 1, 分支向量 wr=0 的 selftest/missing-else 两臂不可达"
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
        suffix = '"wr %s"' % vector
        candidates = [x for x in DUMPS.get(scope, {}).get("items", [])
                      if x["text"].startswith("Branch ") and x["text"].endswith(suffix)
                      and re.search(r"\([0-9]+\) \"", x["text"])]
        if len(candidates) != 1:
            raise SystemExit("branch dump 匹配数=%d: [%s] %s" % (len(candidates), scope, vector))
        key = (DUMPS[scope]["checksum"]["branch"], scope)
        MISC_BLOCKS.setdefault(key, []).append(candidates[0]["text"])


def write_el(filename, header, blocks):
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write(header)
        for (checksum, scope), rows in sorted(blocks.items()):
            out.write("CHECKSUM: %s\n%s\n%s\n\n" % (checksum, scope, "\n".join(rows)))
    print("wrote %s (%d scopes, %d rows)" % (path, len(blocks), sum(map(len, blocks.values()))))


TGL_HEADER = """// dup_ctrl TRUE-COVERAGE toggle exclusions; regenerated from current raw holes only.
// ZREAD: rdata 列出的保留位在全部读源及 ID_VAL 中均恒 0。
// ZFIELD: en/ien 仅 4b、fi 仅 2b; image/wrap 的 wdata/rdata/r.data_q/rin.data_q 高位由父级零拼接恒 0。
// SCALAR_NE: par_l_dup_f 的 RHS 是向量 != 的标量结果, bit1 结构恒 0; 这是已报告的 RTL 死位, 未改 RTL。
// WR_TIE1: err_st/err_s2/raw_s2 为跟随型状态 wrap, wr 硬连 1'b1。
// 不排除地址/总线/SEC/dup_err/write-selftest: TB T19-T20 已用真实激励或 FI 覆盖。
"""
MISC_HEADER = """// dup_ctrl TRUE-COVERAGE line/branch exclusions; regenerated from current raw holes only.
// WR_TIE1: err_st/err_s2/raw_s2 的 wr 硬连 1'b1, 故 reg_wrap 108/110 行及 wr=0 两个分支向量不可达。
// 无 cond 排除: 当前 TB 已覆盖全部可达条件组合。
"""
write_el("tgl_struct_excl.el", TGL_HEADER, TGL_BLOCKS)
write_el("misc_struct_excl.el", MISC_HEADER, MISC_BLOCKS)
