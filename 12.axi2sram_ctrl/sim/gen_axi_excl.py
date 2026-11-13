#!/usr/bin/env python3
# axi2sram_ctrl tgl_struct_excl.el 生成: 激励补强后剩余洞全部为结构常量,
# 家族 (scope 感知):
#   resp[1] SLVERR 预烘域 / 快照内容位 / mbus 对齐+IDX / 注错 pos-word 域 /
#   STA_LAT 结构 0 / INJ-CTRL-EN 保留与 key 常量位 / 检测臂 (dup_err,
#   CNT_DUP, par_l_dup_f, dec fix) / 跟随 wrap wr 电平 / wsel[4] 地图界 /
#   宏读向量未用位
import re
import sys

def fam(sig, scope):
    s = sig
    # ---- 通用信号名家族 ----
    if re.match(r'^dup_err$', s):
        return 'reg_wrap flt 双轨副本失配检测臂 (force-only)'
    if re.match(r'^wr$', s):
        return '跟随/粘滞型 wrap 写使能电平语义 (parent 常驱)'
    if re.match(r'^(ccnt_dup|dcnt_dup|par_l_dup_f)', s):
        return '副本失配检测臂 (force-only)'
    if re.match(r'^i[12]_dec_[si]\.fix$', s):
        return 'INJ 码字 fix 臂 (key+nibble 双门挡非法值, force-only)'
    if re.match(r'^(resp\[1\]|.*_resp\[1\])$', s):
        return 'resp[1]=SLVERR: 命令预烘域仅 OKAY/EXOKAY (SLVERR 为毒化响应拍收口)'
    if re.match(r'^(cmd_d|cmd_dw|cmd_q)\[1\]$', s):
        return '命令词 bit1 = resp[1] SLVERR 位 (预烘域不可达)'
    if re.match(r'^(rs_d|rskip_q)\[261\]$', s):
        return 'rskip 载荷 bit261 = resp[1] SLVERR 位'
    if re.match(r'^(d|q)\[1\]$', s):
        return 'cmdq fifo 词 bit1 = resp[1] SLVERR 位'
    if re.match(r'^(d|q)\[261\]$', s):
        return 'rskip fifo 词 bit261 = resp[1] SLVERR 位'
    if re.match(r'^axi_araddr\[0\]$', s):
        return None             # 应由 size=0 字节读覆盖, 出现即报未归类
    if re.match(r'^addr\[1:0\]$', s):
        return 'mbus 字对齐契约 (addr[1:0] 恒 0)'
    if re.match(r'^addr\[15:9\]$', s):
        return '实例号域 IDX=0 本集成恒 0'
    if re.match(r'^rv\[287:0\]$', s):
        return '宏 288b 读向量未用高 14 位 tie-0 (行 274b)'
    if re.match(r'^(inj[12]_pos\[7:5\]|i[12]_sh\[13:11\])$', s):
        return '注错位置域 ≤31: pos[7:5] 恒 0 (word 内 bit 位置)'
    if re.match(r'^(inj2_word\[1\]|i2_sh\[5\]|lat_word\[1\]|fail_word\[1\])$', s):
        return 'word=码字选择, 合法域 0/1 → word[1] 恒 0'
    if re.match(r'^fail_syn\[7\]$', s):
        return '注错快照 syn[7]: 位置域 ≤31 结构 0'
    if re.match(r'^lat_syn\[(5|8:7)\]$', s):
        return '注错快照 syn[8:5]: 位置域 ≤31 结构 0'
    # ---- scope 感知家族 ----
    if 'sn_cmd' in scope or re.match(r'^(r\.|rin\.)?(sn_cmd|sn_cmd_s2)', s) or \
       ('sync_2dff' in scope and re.match(r'^(d|q|s1|s2|s3)\[3:1\]$', s)):
        if re.match(r'^(d|q|s1|s2|s3)\[3:1\]$', s):
            return 'sn_cmd 同步链内容位 (毒词证据, 内容任意)'
        return '快照内容位: 毒命令词证据 = 故障现场 (resp[1]/a0[1:0] 随毒词)'
    if 'sn_w' in scope or re.match(r'^(r\.|rin\.)?(sn_w|sn_w_s2)', s):
        return '快照内容位: {wlast,行} 毒拍证据 + [15:9] 越界恒 0'
    if re.search(r'(lat_s2|st_lat|lat_sync|lat_st_s1)', scope) or \
       ('reg_wrap ( parameter W=32' in scope) or \
       ('sync_dff ( parameter WIDTH=32' in scope) or \
       re.match(r'^(r\.|rin\.)?(st_lat|lat_s2|lat_st_s1|st_lat_nxt)', s):
        if re.search(r'\[(5|7|8|8:7|10:9|31:17|31:19)\]$', s) or \
           re.match(r'^(d|q|wdata|rdata|r\.data_q|rin\.data_q)\[(5|7|8|8:7|10:9|31:17|31:19)\]$', s):
            return 'STA_LAT 结构 0: word 位 [10:9] v4.1 退役恒 0 + syn 域结构 + 保留/line 高位'
        return None
    if re.search(r'(w_i1|w_i2|c_i1|c_i2)', scope) or \
       ('reg_wrap ( parameter W=13' in scope) or \
       re.match(r'^(r\.|rin\.)?i[12]_(r|w|sh)', s):
        if re.search(r'\[(4|6|10:8|31:19)\]$', s):
            return 'INJ 寄存器结构位: [10:8] word 退役保留 + key=1010 常量 0 位 + 读 0 保留高位'
        return None
    if re.search(r'(w_ctrl)', scope) or re.match(r'^ctrl_[rw]\[', s):
        return 'CFG_CTRL 读 0 保留位 + key 常量 0 位'
    if re.search(r'(w_en|c_en)\b', scope) or re.match(r'^en_[rw]\[31:4\]$', s):
        return 'CFG_EN 读 0 保留位 ([3:0] 码字外恒 0)'
    if re.search(r'(st_err|err_s2|err_st_s1|err_sync|st_flt|flt_s2|flt_st_s1|flt_sync)', scope) or \
       ('reg_wrap ( parameter W=9' in scope) or \
       ('reg_wrap ( parameter W=2' in scope) or \
       ('sync_dff ( parameter WIDTH=9' in scope) or \
       ('sync_dff ( parameter WIDTH=2' in scope) or \
       re.match(r'^(r\.|rin\.)?(st_err|err_s2|err_st_s1|st_err_nxt|st_flt|st_flt_nxt|flt_s2|flt_st_s1)\[(3|0)\]$', s):
        if re.search(r'\[(3|0)\]$', s) or \
           re.match(r'^(d|q|wdata|rdata|r\.data_q|rin\.data_q)\[(3|0)\]$', s):
            return ('STA_ERR[3]/STA_FAULT[0..1] 保留或检测事件位: [3] 保留 0, '
                    'FLT[0]=CNT_DUP FLT[1]=DP_FSM 门 !dp_test (force-only/自测门控)')
        return None
    if re.match(r'^(wdata|rdata|rin\.data_q|r\.data_q)\[', s):
        return None             # 交由上面 scope 家族; 裸命中报未归类
    if re.match(r'^wsel_q\[4\]$', s) or re.match(r'^(r_mb|rin_mb)\.wsel_q\[4\]$', s):
        return '寄存器地图 ≤0x3C: wsel[4] 恒 0 (越界写被 range_ok 挡于锁存前)'
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
hdr = None
holes = {}
unclassified = set()
for raw_ln in open("urg_full/modinfo.txt", encoding="utf-8", errors="replace"):
    ln = raw_ln.rstrip("\n")
    m = re.match(r"^Toggle Coverage for (Instance|Module) : (.*)$", ln)
    if m:
        hdr = re.sub(r"\s*\(x\)\s*$", "", m.group(2).strip()).rstrip()
        hdr = ("INSTANCE: " if m.group(1) == "Instance" else "MODULE: ") + hdr
        continue
    if hdr is None:
        continue
    m = tgl_re.match(ln)
    if m and "No" in (m.group(2), m.group(3)):
        sig = m.group(1)
        if fam(sig, hdr) is None:
            unclassified.add(hdr + " :: " + sig)
        holes.setdefault(hdr, set()).add(sig)

print("洞 scope 数: %d" % len(holes))
for s in sorted(unclassified):
    print("  !! 未归类:", s)
if unclassified:
    sys.exit("存在未归类信号, 中止")

n = 0
with open("tgl_struct_excl.el", "w") as f:
    for key in sorted(holes):
        decls = D.get(key, {}).get("decl", {})
        rows = []
        for sig in sorted(holes[key]):
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
                sys.exit(1)
            rows.append('Toggle %s %s "%s"' % (base, rng, decl))
        f.write("CHECKSUM: %s\n%s\n%s\n\n" % (D[key]["checksum"], D[key]["hdr"],
                                              "\n".join(rows)))
        n += len(rows)
print("写入 %d 行 -> tgl_struct_excl.el" % n)
