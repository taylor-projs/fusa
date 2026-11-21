#!/usr/bin/env python3
# gen_parity_excl.py - parity(edc) tgl structural-constant exclusion builder
# (playbook hang_prot 2026-11-17: 行名必须与 dump 对象名一致)
import re

FAMILY = [
    (re.compile(r"^inj_pos_e"), "注入位置字段参数宽常量 (实例 DW<128, [127:64] 恒 0)"),
    (re.compile(r"^wr$"), "镜像 wrap wr 恒 1 — cmm S1 判例"),
    (re.compile(r"^addr\["), "mbus 地址常量 (字对齐/实例域)"),
    (re.compile(r"^gen_msk"), "叶级无 PATH_SELFTEST 发生器, 掩码发生器恒 0"),
    (re.compile(r"^wdata|^rdata|^r\.data_q|^rin\.data_q"),
     "寄存器窄于 32b 总线: 读恒 0 / 写丢弃保留位"),
    (re.compile(r"user_o\["), "edc_gen AXI user 域常 0 (TB 不赋 user)"),
    (re.compile(r"^scan_mode|rst_sync"), "DFT 扫描模式 TB 不激励 (rst_sync 内部同因)"),
    (re.compile(r"wsel_q\[4\]"), "寄存器图 < 16 项, wsel[4] 恒 0"),
    (re.compile(r"^perr\["), "PERR 分组 lane 激励空间 (组4/组10 为 regfile TB 专属)"),
    (re.compile(r"dup_err"), "reg_wrap 双轨检测臂 — cmm A 族判例"),
    (re.compile(r"^sta_\w+?_r\[|^sta_par_rb"), "聚合器状态读出拼装高位恒 0 (NUM_CORE<32)"),
]

def parse_dump(path):
    out, cur, chk = {}, None, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m: chk = m.group(1); continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            cur = ("%s: %s" % (m.group(1), m.group(2))).rstrip()
            out.setdefault(cur, {"checksum": chk, "decl": {}})
            continue
        if cur:
            m = re.match(r"^// Toggle (\S+) \"(.*)\"$", ln)
            if m: out[cur]["decl"][m.group(1)] = m.group(2)
    return out

D = {}
D.update(parse_dump("fullexclude.tgl"))
D.update(parse_dump("fullexclude_module.tgl"))

holes, hdr = {}, None
unclassified = set()
for ln in open("urg_el/modinfo.txt", encoding="utf-8", errors="replace"):
    m = re.match(r"^Toggle Coverage for (Instance|Module) : (.*)$", ln)
    if m:
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(2).strip()).rstrip()
        hdr = ("INSTANCE: " if m.group(1) == "Instance" else "MODULE: ") + hdr
        continue
    mm = re.match(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                  r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$", ln)
    if mm and "No" in (mm.group(2), mm.group(3), mm.group(4)):
        sig = mm.group(1)
        if not any(p.search(sig) for p, _ in FAMILY):
            unclassified.add(sig)
        holes.setdefault(hdr, set()).add(sig)
if unclassified:
    for s in sorted(unclassified): print("  !! 未归类:", s)
    raise SystemExit("存在未归类信号, 中止")
print("洞 scope 数: %d" % len(holes))

# 以旧 el 为基座合并 (保留其块与 CHECKSUM), 新洞按 dump 对象名追加
import io
blocks, cur = [], None
for ln in io.open("tgl_struct_excl.el", errors="replace"):
    ln = ln.rstrip("\n")
    if ln.startswith("CHECKSUM: "):
        if cur: blocks.append(cur)
        cur = [ln, None, []]
        continue
    if cur is None: continue
    if re.match(r"^(INSTANCE|MODULE): ", ln): cur[1] = ln
    elif ln.strip(): cur[2].append(ln)
if cur: blocks.append(cur)
bymap = {}
for b in blocks:
    if b[1]: bymap.setdefault(b[1].rstrip(), []).append(b)

added = 0
new_blocks = []
for key, sigs in sorted(holes.items()):
    decls = D.get(key, {}).get("decl", {})
    if not decls:
        print("  !! dump 无此 scope:", key); raise SystemExit(1)
    rows = []
    for sig in sorted(sigs):
        rowname, decl = sig, decls.get(sig)
        if decl is None:
            base = re.match(r"^([\w.]+)", sig).group(1)
            rowname, decl = base, decls.get(base)
        if decl is None:
            for k2, v2 in decls.items():
                if k2.split("[")[0] == base: rowname, decl = k2, v2; break
        if decl is None:
            print("  !! 无声明:", key, sig); raise SystemExit(1)
        rows.append("Toggle %s \"%s\"" % (rowname, decl))
    if key in bymap:
        blk = bymap[key][-1]
        old = set(blk[2])
        new = [r for r in rows if r not in old]
        blk[2].extend(new); added += len(new)
    elif key in D:
        new_blocks.append(["CHECKSUM: %s" % D[key]["checksum"], D[key].get("hdr", key), rows])
        added += len(rows)
    else:
        print("  !! scope 缺声明:", key); raise SystemExit(1)
blocks.extend(new_blocks)
with io.open("tgl_struct_excl_v2.el", "w") as f:
    f.write("// parity(edc) tgl structural exclusions - gen_parity_excl.py 2026-11-21\n")
    for chk, h, rows in blocks:
        if h is None: continue
        f.write("%s\n%s\n%s\n\n" % (chk, h, "\n".join(rows)))
print("新增 %d 行 -> tgl_struct_excl_v2.el" % added)
