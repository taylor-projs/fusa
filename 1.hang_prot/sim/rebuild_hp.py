#!/usr/bin/env python3
# hang_prot tgl_struct_excl.el 重建:
#   1) INSTANCE 路径改名映射 (u_hang_prot_gen_wrap -> u_hang_prot_top 等改名 fallout)
#   2) CHECKSUM 从合并 dump (fullexclude*.tgl) 刷新
#   3) 报告找不到的 scope / 行 (真结构变化, 需人工判断)
# 用法: python3 rebuild_hp.py <old.el> <dump_inst> <dump_mod> <out.el>
import re, sys

old, di, dm, out = sys.argv[1:5]

# 改名映射: 旧实例段 -> 新实例段 (按 2026-11 顶层改名)
RENAME = [
    ("u_hang_prot_gen_wrap.", "u_hang_prot_top."),
    ("u_hang_prot_gen_wrap", "u_hang_prot_top"),   # 路径末段 (无后缀)
]

def scopes(path):
    out = {}
    cur = chk = None
    for ln in open(path):
        ln = ln.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", ln)
        if m:
            cur = "%s: %s" % (m.group(1), m.group(2))
            out[cur] = {"checksum": chk, "rows": set()}
            continue
        if cur and re.match(r"^// Toggle ", ln):
            out[cur]["rows"].add(ln[3:])
    return out

D = {}
D.update(scopes(di))
D.update(scopes(dm))

def renamed(hdr):
    h = hdr
    for a, b in RENAME:
        h = h.replace(a, b)
    return h

blocks, cur = [], None
for ln in open(old):
    ln = ln.rstrip("\n")
    if ln.startswith("CHECKSUM: "):
        if cur:
            blocks.append(cur)
        cur = [ln, None, []]
        continue
    if cur is None:
        if ln.strip():
            pass  # 文件头注释丢弃 (重建文件头另写)
        continue
    if re.match(r"^(INSTANCE|MODULE): ", ln):
        cur[1] = ln
    elif ln.strip() and not ln.startswith("//"):
        cur[2].append(ln)
    # 块内注释行丢弃
if cur:
    blocks.append(cur)

miss_scope, miss_rows, ok = [], [], 0
with open(out, "w") as f:
    f.write("// ==================================================================\n")
    f.write("// tgl_struct_excl.el -- hang_prot structural-constant toggle\n")
    f.write("// exclusions (urg -elfile, merged report of tb a/b/gen).\n")
    f.write("// 2026-11-07 重建: 实例路径按 u_hang_prot_top 改名刷新,\n")
    f.write("// CHECKSUM 全部取自本次合并 vdb 的 fullexclude dump.\n")
    f.write("// RTL 改动后重新生成:\n")
    f.write("//   cd obj_vcs && urg -lca -flex_merge modules -dir a/simv.vdb \\\n")
    f.write("//     -dir b/simv.vdb -dir gen/simv.vdb -dump full_exclusions tgl \\\n")
    f.write("//     -report /tmp/x   (fullexclude.tgl / fullexclude_module.tgl)\n")
    f.write("// ==================================================================\n\n")
    for chk, hdr, rows in blocks:
        if hdr is None:
            continue
        new = renamed(hdr)
        if new not in D:
            miss_scope.append((hdr, new))
            continue
        lost = [r for r in rows
                if r not in D[new]["rows"]
                and not re.match(r"^Toggle \S+ \[\d+", r)]  # 位选行 dump 本就无
        lost = [r for r in rows
                if r not in D[new]["rows"]
                and ("[" not in r.split('"')[0])]
        if lost:
            miss_rows.append((new, lost))
            continue
        f.write("CHECKSUM: %s\n%s\n%s\n\n"
                % (D[new]["checksum"], new, "\n".join(rows)))
        ok += 1
print("块重建 %d | 丢scope %d | 丢行块 %d" % (ok, len(miss_scope), len(miss_rows)))
for o, n in miss_scope:
    print("  SCOPE缺失: %s -> %s" % (o, n))
for h, l in miss_rows:
    print("  行缺失 @ %s" % h)
    for r in l[:4]:
        print("     ", r[:90])
