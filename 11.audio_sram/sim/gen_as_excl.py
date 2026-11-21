#!/usr/bin/env python3
# gen_as_excl.py - audio_sram tgl structural-constant exclusion builder
# (playbook hang_prot 2026-11-17: 行名必须与 dump 对象名一致)
# 2026-11-21 全仓覆盖率战役: 首次建成 (此前 int_prot 无排除流)
import re

FAMILY = [
    (re.compile(r"dup_err"),
     "reg_wrap 双轨检测臂 — cmm A 族判例"),
    (re.compile(r"par_l"),
     "在途锁存奇偶双轨族 (锁存/副本/检测臂/次态) — cmm A 族判例"),
    (re.compile(r"^(r|rin)_mb\.wdata_q"),
     "在途写锁存高位值域常量 (寄存器语义值域)"),
    (re.compile(r"^(r|rin)_cnt\."),
     "CNT_DUP 计数器值域常量位 (测试错误次数未达的计数值)"),
    (re.compile(r"^wr$"),
     "镜像 wrap wr 恒 1 — cmm S1 判例"),
    (re.compile(r"^addr\["),
     "mbus 地址常量 (字对齐/实例域)"),
    (re.compile(r"^wdata|^rdata|^r\.data_q|^rin\.data_q"),
     "寄存器窄于 32b 总线: 读恒 0 / 写丢弃保留位"),
    (re.compile(r"^inj_pos"),
     "注错位置字段 lane 激励空间 (单注错通道未扫的位)"),
    (re.compile(r"scan_mode"),
     "DFT 扫描模式 TB 不激励"),
    (re.compile(r"\.fix$"),
     "dec4 fix 输出: 写路径恒合法码 + 码扰动经 force 注入, 解码输入永无 1bit 偏移 (激励空间)"),
    (re.compile(r"^cnt_s2"),
     "CNT_DUP 计数器 mbus 回读 sync 位域 (测试错误次数值域常量)"),
    (re.compile(r"lat"),
     "STA_LAT 存储/次态/回读 sync 值域常量位 (延迟测量值位域)"),
    (re.compile(r"^regsel"),
     "REGSEL 字段地图常量 (寄存器数 < 字段宽)"),
    (re.compile(r"sync_ff"),
     "rst_sync 复位同步链 lane 常量"),
    (re.compile(r"wpar_err"),
     "在途写奇偶 err 脉冲 lane 激励空间"),
    (re.compile(r"^inj_sh"),
     "注错影子寄存器保留位"),
    (re.compile(r"^[a-z0-9_]+_[rw]\["),
     "32b image/shadow 存储拼装高位 + 寄存器保留位 (字段宽 < 32)"),
]


def family_of(sig, scope=""):
    for pat, doc in FAMILY:
        if pat.search(sig):
            return doc
    # sync 单元值域 lane: 同步总线的常量位 (d/q/s1-s3 名在 sync scope 下)
    if re.search(r"sync", scope or ""):
        base = sig.split("[", 1)[0]
        rng = sig.split("[", 1)[1] if "[" in sig else ""
        if base in ("d", "q", "s1", "s2", "s3") and re.match(r"^[0-9:]+$", rng.rstrip("]")):
            return "sync 单元同步总线值域常量位 (低/高段恒 0)"
    return None


def parse_dump(path):
    out, cur, chk = {}, None, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            cur = ("%s: %s" % (m.group(1), m.group(2))).rstrip()
            out.setdefault(cur, {"checksum": chk, "decl": {}})
            continue
        if cur:
            m = re.match(r"^// Toggle (\S+) \"(.*)\"$", ln)
            if m:
                out[cur]["decl"][m.group(1)] = m.group(2)
    return out


D = {}
D.update(parse_dump("fullexclude.tgl"))
D.update(parse_dump("fullexclude_module.tgl"))

holes, hdr = {}, None
unclassified = {}
for ln in open("urg_raw/modinfo.txt", encoding="utf-8", errors="replace"):
    m = re.match(r"^Toggle Coverage for (Instance|Module) : (.*)$", ln)
    if m:
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(2).strip()).rstrip()
        hdr = ("INSTANCE: " if m.group(1) == "Instance" else "MODULE: ") + hdr
        continue
    mm = re.match(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                  r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$", ln)
    if mm and "No" in (mm.group(2), mm.group(3), mm.group(4)):
        sig = mm.group(1)
        if family_of(sig, hdr or "") is None:
            unclassified.setdefault(sig, set()).add(hdr)
        holes.setdefault(hdr, set()).add(sig)

if unclassified:
    for s, hs in sorted(unclassified.items()):
        print("  !! 未归类:", s, sorted(hs)[:2])
    raise SystemExit("存在未归类信号, 中止")
print("洞 scope 数: %d" % len(holes))

with open("tgl_struct_excl.el", "w") as f:
    f.write("// int_prot tgl structural exclusions - gen_ip_excl.py"
            " 2026-11-21 (全仓覆盖率战役首建)\n")
    for key in sorted(holes):
        decls = D.get(key, {}).get("decl", {})
        if not decls:
            print("  !! dump 无此 scope:", key)
            raise SystemExit(1)
        rows = []
        for sig in sorted(holes[key]):
            rowname, decl = sig, decls.get(sig)
            if decl is None:
                base = re.match(r"^([\w.]+)", sig).group(1)
                rowname, decl = base, decls.get(base)
            if decl is None:
                for k2, v2 in decls.items():
                    if k2.split("[")[0] == base:
                        rowname, decl = k2, v2
                        break
            if decl is None:
                print("  !! 无声明:", key, sig)
                raise SystemExit(1)
            rows.append('Toggle %s "%s"' % (rowname, decl))
        f.write("CHECKSUM: %s\n%s\n%s\n\n"
                % (D[key]["checksum"], key, "\n".join(rows)))
print("el 写出: tgl_struct_excl.el")
