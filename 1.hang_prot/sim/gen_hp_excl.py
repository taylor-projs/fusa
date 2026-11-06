#!/usr/bin/env python3
# hang_prot tgl_struct_excl.el 第二步: 把复验报告中的未覆盖 toggle 洞
# (全部落在 8 个结构常量家族, 见 FAMILY) 按 scope 合并进重建后的 el。
# 键规范化: 查找一律用 rstrip 后的 canonical key;
# 写回 el 时保留 dump/旧 el 的原始头文本 (reg_wrap 参数组行尾空格是键的一部分)。
import re

FAMILY = [
    (re.compile(r"^wr$"),
     "reg_wrap 镜像 wrap wr 恒 1 (RO image 每拍写) — cmm S1/镜像判例"),
    (re.compile(r"^cfg_key"),
     "cfg_key 绑 4b1010 key 比较器常量"),
    (re.compile(r"fu_src\[6\]$|^(r|rin)\.fu_src$|otd_sat|^[dq]\[6\]$"
                r"|^wdata\[6\]$|^rdata\[6\]$|data_q\[6\]$|fu_src_live"
                r"|^fusrc_s[12](\[6\])?$"),
     "otd 饱和链 bit6 恒 0 (monitor 封顶 OTD_MAX, otd_sat 永不置起) — 死链族"),
    (re.compile(r"s_a[rw]id|s_rid|mcore_fwd_id|s_arid_w"),
     "AXI ID remap 参数空间常量位 (AR/AW_ID_REMAP/MCORE_REMAP_IDS 只用低位)"),
    (re.compile(r"^rlen_ext"),
     "rlen_ext[8] = {1'b0, ar_len} 拼接常量位"),
    (re.compile(r"^mbus_rdata|^rdata(\[|$)"),
     "寄存器图读恒 0 保留位 (ID 常量 0 位 + 保留字段)"),
    (re.compile(r"par_l_dup_f"),
     "双轨副本失步检测臂 (par_lq_n != ~par_lq), 总线路径不可达 — cmm A 族判例"),
    (re.compile(r"^s_arready$"),
     "b_wrap 为写侧 SEU 测试, 读通道不激励 (TB 激励空间常量)"),
    (re.compile(r"aw_id|ar_id|aw_par|ar_par|ridx|mcore_fwd_id"),
     "ID/索引存储的未用 lane/位 (AXI ID remap 参数空间常量, 含其 parity 与副本)"),
    (re.compile(r"rbeat_cnt|ar_len|rlen_ext"),
     "beat/len 计数 bit8 恒 0 (AXI len[7:0] <= 255)"),
    (re.compile(r"ar_occ|ar_rp"),
     "每类占用/读指针高位恒 0 (monitor 封顶 OTD_MAX, 占用 < 2^NCLS)"),
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
D.update(parse_dump("obj_vcs/fullexclude.tgl"))
D.update(parse_dump("obj_vcs/fullexclude_module.tgl"))

tgl_re = re.compile(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                    r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$")
ob_re = re.compile(r"^\s*Other bits of (\S+)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                   r"\s*$")
holes = {}
hdr = None
unclassified = set()
for raw_ln in open("obj_vcs/urg_report_excl/modinfo.txt",
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
        if sig.startswith("Other bits of ") or ln.lstrip().startswith("Other bits of "):
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
    raise SystemExit("存在未归类信号, 中止 (纪律: 每行须有结构依据)")

blocks, cur = [], None
for ln in open("tgl_struct_excl_new.el"):
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

with open("tgl_struct_excl_v2.el", "w") as f:
    f.write("// ==================================================================\n")
    f.write("// tgl_struct_excl.el -- hang_prot structural-constant toggle\n")
    f.write("// exclusions (urg -elfile, merged report of tb a/b/gen).\n")
    f.write("// 2026-11-07 重建+补全: 实例路径按 u_hang_prot_top 改名刷新,\n")
    f.write("// CHECKSUM 全部取自本次合并 vdb 的 fullexclude dump; 复验残 175 行\n")
    f.write("// 未覆盖 toggle 按 8 个结构常量家族补齐 (双域各一份):\n")
    f.write("//   镜像wrap wr 恒1 / cfg_key 常量 / otd_sat 死链 bit6 (含同步级) /\n")
    f.write("//   AXI ID remap 参数位 / rlen_ext 拼接位 / 读恒0保留位 /\n")
    f.write("//   par_l_dup_f 双轨检测臂 / b_wrap 读通道不激励\n")
    f.write("// RTL 改动后重新生成:\n")
    f.write("//   cd obj_vcs && urg -lca -flex_merge modules -dir a/simv.vdb \\\n")
    f.write("//     -dir b/simv.vdb -dir gen/simv.vdb -dump full_exclusions tgl \\\n")
    f.write("//     -report /tmp/x   (fullexclude.tgl / fullexclude_module.tgl)\n")
    f.write("// ==================================================================\n\n")
    for chk, h, rows in blocks:
        f.write("%s\n%s\n%s\n\n" % (chk, h, "\n".join(rows)))
print("新增 %d 行 -> tgl_struct_excl_v2.el" % added)
