#!/usr/bin/env python3
# rst_checker tgl_struct_excl.el 增补: TB 109-check vdb 复验后残余 4 个未覆盖对象
#   rdata[18]/rdata_mux[18]  全图恒 0 (ID 0x5243_0001 bit18=0, 其余字段窄于 bit18)
#                            —— 读恒 0 保留位族, 同既有 [15:10]/[21:19] 判例
#   dup_err                  reg_wrap 双轨副本失配线, 总线路径不可达 (cmm F 族判例)
# 行风格随本仓: 无方向前缀整信号/位选行。CHECKSUM 取自当次 fullexclude dump。
import re

def scopes(path):
    out, cur, chk = {}, None, None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            cur = "%s: %s" % (m.group(1), m.group(2))
            out[cur] = {"checksum": chk, "rows": []}
            continue
        if cur and re.match(r"^// Toggle ", ln):
            out[cur]["rows"].append(ln[3:])
    return out

inst = scopes("fullexclude.tgl")
mod = scopes("fullexclude_module.tgl")

plan = []
k = "INSTANCE: tb_reset_checker.dut.u_reset_checker_regfile.u_w_cmd"
plan.append((inst[k]["checksum"], k, ['Toggle dup_err "logic dup_err"']))
k = "MODULE: reset_checker_top"
decl = [r for r in mod[k]["rows"] if r.startswith("Toggle rdata ")][0].split('"')[1]
plan.append((mod[k]["checksum"], k, ['Toggle rdata [18] "%s"' % decl]))
k = "MODULE: reset_checker_regfile"
sigd = [r for r in mod[k]["rows"] if r.startswith("Toggle rdata ")][0].split('"')[1]
sigm = [r for r in mod[k]["rows"] if r.startswith("Toggle rdata_mux ")][0].split('"')[1]
plan.append((mod[k]["checksum"], k, [
    'Toggle rdata [18] "%s"' % sigd,
    'Toggle rdata_mux [18] "%s"' % sigm,
]))
k = "MODULE: reg_wrap ( parameter W=1,RESET=0 ) "
plan.append((mod[k]["checksum"], k, ['Toggle dup_err "logic dup_err"']))

with open("tgl_struct_excl_new.el", "a") as f:
    f.write("\n// ---- 2026-11-07 增补 (TB 109-check vdb 复验残 4 对象) ----\n")
    f.write("// rdata[18]/rdata_mux[18]: 全图恒 0 (ID 0x5243_0001 bit18=0, 其余\n")
    f.write("//   字段窄于 bit18) —— 读恒 0 保留位族, 同 [15:10]/[21:19] 判例\n")
    f.write("// dup_err: reg_wrap 双轨副本失配线, 总线路径不可达 (cmm F 族判例)\n")
    for c, kk, rows in plan:
        f.write("CHECKSUM: %s\n%s\n%s\n\n" % (c, kk, "\n".join(rows)))
print("appended %d blocks" % len(plan))
