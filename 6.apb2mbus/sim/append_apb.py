#!/usr/bin/env python3
# apb2mbus tgl_struct_excl.el 增补: 实例域三行的模块定义域副本
# (实例域排除不进模块定义域 bin —— 双域各一份, cmm/rst_checker 同规)
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
            out[cur] = {"checksum": chk}
            continue
    return out

mod = scopes("fullexclude_module.tgl")
k = "MODULE: apb2mbus"
rows = [
    'Toggle addr [15:9] "logic addr[15:0]"',
    'Toggle r_apb.paddr_q [15:9] "logic r_apb.paddr_q[15:0]"',
    'Toggle rin_apb.paddr_q [15:9] "logic rin_apb.paddr_q[15:0]"',
]
with open("tgl_struct_excl.el", "a") as f:
    f.write("\n// ---- 2026-11-07 增补: 上三行的模块定义域副本 (双域各一份) ----\n")
    f.write("CHECKSUM: %s\n%s\n%s\n\n"
            % (mod[k]["checksum"], k, "\n".join(rows)))
print("appended 1 module-domain block")
