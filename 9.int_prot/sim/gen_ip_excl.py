#!/usr/bin/env python3
# gen_ip_excl.py - int_prot tgl structural-constant exclusion builder
# (playbook hang_prot 2026-11-17: 行名必须与 dump 对象名一致)
# 2026-11-21 全仓覆盖率战役: 首次建成 (此前 int_prot 无排除流)
import re

FAMILY = [
    (re.compile(r"^inj_(spi|chk)|^spi_inj|^chk_inj"),
     "注错使能 lane 激励空间 (TB 只注代表性通道)"),
    (re.compile(r"^spi\[|^spi_in\[|^spi_sync\[|^r\.spi|^rin\.spi"
                r"|spi_changed|spi_sync_q|spi_syncc"),
     "SPI 通道 lane 激励空间 (TB 只驱动代表性通道, ch3 全链常 0)"),
    (re.compile(r"cnt_par_err|change_cnt_error|diff_cnt_error"),
     "per-channel 错误脉冲 lane 激励空间 (FI 只注代表性通道)"),
    (re.compile(r"^r\.change_cnt|^rin\.change_cnt"),
     "去抖计数高位 (测试阈值配置下的值域常量)"),
    (re.compile(r"^wr$"),
     "镜像 wrap wr 恒 1 — cmm S1 判例"),
    (re.compile(r"^addr\["),
     "mbus 地址常量 (字对齐/实例域)"),
    (re.compile(r"^wdata|^rdata|^r\.data_q|^rin\.data_q"),
     "寄存器窄于 32b 总线: 读恒 0 / 写丢弃保留位"),
    (re.compile(r"^(en|ien|sta_err|sta_flt|ichk|ispi)_[rw]\[|^sta_par_rb"),
     "32b image/shadow 存储拼装高位 + 寄存器保留位 (字段宽 < 32)"),
    (re.compile(r"flt_w1c"),
     "W1C 位图 decode lane 激励空间 (TB 只清代表性位)"),
    (re.compile(r"dup_err"),
     "reg_wrap 双轨检测臂 — cmm A 族判例"),
    (re.compile(r"^rst_n$|^rstn$|^mbus_rstn$"),
     "TB 复位策略常量 (mbus 域不复位, 相关 wrap/同步单元 rst_n 恒 1)"),
]


def family_of(sig, scope=""):
    for pat, doc in FAMILY:
        if pat.search(sig):
            return doc
    # 同步单元未用 lane: u_spi_sync/u_chk_sync scope 下的 d/q/s1-s3 位选
    if re.search(r"u_(spi|chk)_sync$", scope):
        base = sig.split("[", 1)[0]
        rng = sig.split("[", 1)[1] if "[" in sig else ""
        if base in ("d", "q", "s1", "s2", "s3") and re.match(r"^[0-9:]+$", rng.rstrip("]")):
            return "sync_2dff 未用 lane (TB 只驱动代表性 SPI 位)"
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
