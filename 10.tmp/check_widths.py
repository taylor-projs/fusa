#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""静态核对 reg.v (部分文件): 拼接位宽 / res-wr-hw 位一致性 / 每寄存器位属性表"""
import re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "reg.v"
text = open(SRC, encoding="utf-8", errors="replace").read()

WIDTH = {"noc_lp_idle": 16, "noc_lp_idleack": 16, "noc_lp_idle_1": 16,
         "noc_lp_idleack_1": 16, "pmu_fsm_state": 25}

def item_width(tok):
    tok = tok.strip()
    m = re.fullmatch(r"\{(\d+)\{(.+)\}\}", tok, re.S)
    if m:
        return int(m.group(1)) * item_width(m.group(2))
    m = re.fullmatch(r"(\d+)'[hbdHBD][0-9a-fA-FxXzZ_?]+", tok)
    if m:
        return int(m.group(1))
    if re.fullmatch(r"\d+", tok):
        return 32
    if re.fullmatch(r"[A-Za-z_][\w$]*", tok):
        return WIDTH.get(tok, 1)
    return None

def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "{":
            depth += 1; cur += ch
        elif ch == "}":
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out

def expand(rhs):
    """RHS -> 按 MSB..LSB 逐位 token 列表"""
    rhs = re.sub(r"\s+", "", rhs)
    m = re.fullmatch(r"\{(\d+)\{(.+)\}\}", rhs)   # 整体复制 {N{tok}}
    if m:
        return expand(m.group(2)) * int(m.group(1))
    inner = rhs[1:-1] if rhs.startswith("{") and rhs.endswith("}") else rhs
    bits = []
    for t in split_top(inner):
        t = t.strip()
        m = re.fullmatch(r"\{(\d+)\{(.+)\}\}", t, re.S)
        if m:
            bits += expand("{" + m.group(2) + "}") * int(m.group(1))
            continue
        m = re.fullmatch(r"(\d+)'([hbdHBD])([0-9a-fA-FxXzZ_?]+)", t)
        if m:
            n, base, digits = int(m.group(1)), m.group(2), m.group(3)
            scale = {"h": 16, "d": 10, "b": 2, "H": 16, "D": 10, "B": 2}[base]
            v = int(digits.replace("_", "").replace("?", "0").replace("x", "0").replace("X", "0").replace("z", "0").replace("Z", "0"), scale)
            mask = (1 << n) - 1
            bits += [("1" if (v >> i) & 1 else "0") for i in range(n - 1, -1, -1)]
            continue
        if re.fullmatch(r"\d+", t):
            v = int(t); n = 32
            bits += [("1" if (v >> i) & 1 else "0") for i in range(n - 1, -1, -1)]
            continue
        bits.append(t)
    return bits

pat = re.compile(
    r"assign\s+(reg_data_(?:res|w1s|w1c|w0s|w0c|wt|rc|wr|hw)|hw_wdata|reg_default_value)\[(\d+)\]\[31:0\]\s*=\s*(.+?);",
    re.S)

rows = {}
issues = []
for m in pat.finditer(text):
    kind, idx, rhs = m.group(1), int(m.group(2)), m.group(3)
    bits = expand(rhs)
    w = len(bits)
    rows.setdefault(idx, {})[kind] = bits
    if w != 32:
        issues.append(f"  [{kind}[{idx}]] 展开位宽 = {w} (应为 32)")

print("=== 位宽检查 ===")
print("\n".join(issues) if issues else "  全部 32 位, OK")

def is_zero(t):
    return t in ("0", "1") and t == "0" or re.fullmatch(r"1'b[0]", t or "")

print("\n=== res=1(保留) 位上存在 SW/HW 写源 检查 ===")
n = 0
for idx in sorted(rows):
    res = (rows[idx].get("reg_data_res") or [None] * 32)
    for sk in ("reg_data_wr", "reg_data_hw"):
        src = rows[idx].get(sk)
        if not src:
            continue
        for b in range(32):
            if b >= len(src) or b >= len(res):
                print(f"  reg[{idx}] 长度不足 32, 跳过 ({sk})")
                break
            s, r = src[b], res[b]
            if s in (None, "0") or s == "1'b0":
                continue
            if r == "1" or r == "1'b1":
                print(f"  reg[{idx}] bit{31-b}: res=1 但 {sk} 写源 {s}")
                n += 1
print("  OK, 无冲突" if n == 0 else f"  共 {n} 处")

# 寄存器号 -> 地址注释映射
addr_of = {}
for m in re.finditer(r"// address ([0-9a-fA-F]+)\s*\n((?:assign reg_data_\w+\[\d+\][^\n]*\n)+)", text):
    idx_m = re.search(r"reg_data_res\[(\d+)\]", m.group(2))
    if idx_m:
        addr_of[int(idx_m.group(1))] = m.group(1)

print("\n=== 每寄存器位属性表 (MSB->LSB, R=保留 W=SW可写 H=HW写 ro=只读) ===")
for idx in sorted(rows):
    res = rows[idx].get("reg_data_res") or ["0"] * 32
    wr = rows[idx].get("reg_data_wr") or ["0"] * 32
    hw = rows[idx].get("reg_data_hw") or ["0"] * 32
    hwd = rows[idx].get("hw_wdata") or [None] * 32
    attrs = []
    for b in range(32):
        if res[b] in ("1", "1'b1"):
            a = "R"
        elif wr[b] not in ("0", "1'b0", None) and hw[b] not in ("0", "1'b0", None):
            a = "B"  # SW+HW 双写
        elif wr[b] not in ("0", "1'b0", None):
            a = "W"
        elif hw[b] not in ("0", "1'b0", None):
            a = "H"
        else:
            a = "."
        attrs.append(a)
    # 压缩成 range 形式
    rngs, s = [], 0
    for i in range(1, 33):
        if i == 32 or attrs[i] != attrs[s]:
            rngs.append((31 - s, 31 - (i - 1), attrs[s]))  # (hi, lo, attr)
            s = i
    txt = " ".join((f"[{hi}]" if hi == lo else f"[{hi}:{lo}]") + a for hi, lo, a in rngs)
    hwsrc = [hwd[b] for b in range(32) if hw[b] not in ("0", "1'b0", None) and hwd[b] not in (None, "0")]
    dft = rows[idx].get("reg_default_value")
    dhex = ""
    if dft and len(dft) == 32:
        v = 0
        for b in range(32):
            v = (v << 1) | (1 if dft[b] in ("1", "1'b1") else 0)
        dhex = f"  deft=0x{v:08x}"
        bad = [31 - b for b in range(32)
               if dft[b] in ("1", "1'b1") and res[b] in ("1", "1'b1")]
        if bad:
            dhex += f"  !!保留位默认值非0: {bad}"
    print(f"  reg[{idx:2d}] @0x{addr_of.get(idx,'??'):>4}  {txt}{dhex}")
    if hwsrc:
        print(f"           HW源: {', '.join(dict.fromkeys(hwsrc))}")
