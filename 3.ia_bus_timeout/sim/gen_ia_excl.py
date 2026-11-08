#!/usr/bin/env python3
# ia_bus_timeout tgl_struct_excl.el 增补: 复验残 16 行未覆盖 toggle
# (全部 hang_prot/cmm 已有判例家族的模块域副本):
#   mbus_rdata/rdata 读恒 0 保留位 / cfg_key 4b1010 常量 /
#   reg_wrap W=10 镜像 wr 恒 1 / par_l_dup_f[1] 双轨检测臂
import re

FAMILY = [
    (re.compile(r"^wr$"), "镜像 wrap wr 恒 1"),
    (re.compile(r"^cfg_key"), "cfg_key 绑 key 比较器常量"),
    (re.compile(r"^mbus_rdata|^rdata(\[|$)"), "读恒 0 保留位"),
    (re.compile(r"par_l_dup_f"), "双轨副本失步检测臂"),
    (re.compile(r"^wdata(\[|$)"), "聚合 sticky wrap 高位恒 0 (NUM_CORE<32 拼装)"),
    (re.compile(r"^r\.data_q|^rin\.data_q"), "聚合 sticky wrap 存储高位恒 0"),
    (re.compile(r"^sta_\w+_r(\[|$)"), "聚合器 sticky [31:NUM_CORE] 恒 0"),
    (re.compile(r"^sta_par_rb"), "聚合器 STA_PAR 读出拼接高位恒 0"),
]

def family_of(sig):
    for pat, doc in FAMILY:
        if pat.search(sig):
            return doc
    return None

def parse_dump(path):
    out, cur, chk, raw = {}, None, None, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            raw = "%s: %s" % (m.group(1), m.group(2))
            cur = raw.rstrip()
            out.setdefault(cur, {"checksum": chk, "decl": {}, "hdr": raw})
            continue
        if cur:
            m = re.match(r"^// Toggle (\S+) \"(.*)\"$", ln)
            if m:
                out[cur]["decl"][m.group(1)] = m.group(2)
    return out

D = {}
D.update(parse_dump("fullexclude.tgl"))
D.update(parse_dump("fullexclude_module.tgl"))

tgl_re = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                    r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
ob_re = re.compile(r"^\s*Other bits of (\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                   r"\s*$")
holes = {}
hdr = None
unclassified = set()
for raw_ln in open("/tmp/urg_ia_el/modinfo.txt",
                   encoding="utf-8", errors="replace"):
    ln = raw_ln.rstrip("\n")
    m = re.match(r"^Toggle Coverage for (Instance|Module) : (.*)$", ln)
    if m:
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(2).strip()).rstrip()
        hdr = ("INSTANCE: " if m.group(1) == "Instance" else "MODULE: ") + hdr
        continue
    if hdr is None:
        continue
    m = tgl_re.match(ln) or ob_re.match(ln)
    if m and "No" in (m.group(2), m.group(3), m.group(4)):
        sig = m.group(1)
        if ln.lstrip().startswith("Other bits of "):
            mm = re.match(r"^Other bits of ([\w.]+)((?:\[[^\]]+\])+)$",
                          ln.strip())
            sig = mm.group(1) + mm.group(2) if mm else sig
        if family_of(sig) is None:
            unclassified.add(sig)
        holes.setdefault(hdr, set()).add(sig)

print("洞 scope 数: %d" % len(holes))
for s in sorted(unclassified):
    print("  !! 未归类:", s)
if unclassified:
    raise SystemExit("存在未归类信号, 中止")

blocks, cur = [], None
for ln in open("tgl_struct_excl.el"):
    ln = ln.rstrip("\n")
    if ln.startswith("CHECKSUM: "):
        if cur:
            blocks.append(cur)
        cur = [ln, None, []]
        continue
    if cur is None:
        continue
    if re.match(r"^(INSTANCE|MODULE): ", ln):
        cur[1] = ln
    elif ln.strip():
        cur[2].append(ln)
if cur:
    blocks.append(cur)

bymap = {}
for b in blocks:
    if b[1]:
        bymap.setdefault(b[1].rstrip(), []).append(b)

added = 0
new_blocks = []
for key, sigs in sorted(holes.items()):
    decls = D.get(key, {}).get("decl", {})
    rows = []
    for sig in sorted(sigs):
        m = re.match(r"^([\w.]+)((?:\[[^\]]+\])+)$", sig)
        if m:
            base, rng = m.group(1), m.group(2)
        else:
            base, rng = sig, ""
        decl = decls.get(base)
        if decl is None:
            for k2, v2 in decls.items():
                if k2.split("[")[0] == base:
                    decl = v2
                    break
        if decl is None:
            print("  !! 无声明:", key, sig)
            raise SystemExit(1)
        rows.append('Toggle %s %s "%s"' % (base, rng, decl))
    if key in bymap:
        blk = bymap[key][-1]
        old = set(blk[2])
        new = [r for r in rows if r not in old]
        blk[2].extend(new)
        added += len(new)
    elif key in D:
        new_blocks.append(["CHECKSUM: %s" % D[key]["checksum"],
                           D[key]["hdr"], rows])
        added += len(rows)
    else:
        print("  !! dump 无此 scope:", key)
        raise SystemExit(1)
blocks.extend(new_blocks)

with open("tgl_struct_excl_new.el", "w") as f:
    for chk, h, rows in blocks:
        f.write("%s\n%s\n%s\n\n" % (chk, h, "\n".join(rows)))
print("新增 %d 行 -> tgl_struct_excl_new.el" % added)
