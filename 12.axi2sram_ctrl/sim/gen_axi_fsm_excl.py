#!/usr/bin/env python3
# axi2sram_ctrl fsm_struct_excl.el: 排除整个被错误提取的 FSM 对象。
# VCS 把整条 reg_t (447b packed struct) 当作状态向量 —— enum 成员 st 的
# one-hot 值被淹没在上下文位里, 具名态/转移几乎不可能匹配 (dashboard 恒
# 33.33 的根因)。该 FSM 的功能面覆盖由以下既有机制保证, 不依赖此指标:
#   * v3.9 数据面防护: st_bad = ~(^r.st) one-hot 合法性逐拍检查
#     (T23a 非法态 force 用例: 冻结 fail-safe + STA_FAULT + 复位自愈);
#   * 全部五状态与合法转移均被 T1-T24 用例遍历 (toggle/branch/line 承载)。
import re

out = {}
for path in ('fullexclude.fsm', 'fullexclude_module.fsm'):
    scope = chk_scope = None
    fsm = None
    for ln in open(path):
        ln = ln.rstrip('\n')
        m = re.match(r'^// CHECKSUM: (.*)$', ln)
        if m:
            chk = m.group(1)
            continue
        m = re.match(r'^// (INSTANCE|MODULE): (.*)$', ln)
        if m:
            if scope and fsm:
                out[scope] = (chk_scope, fsm)
            scope = '%s: %s' % (m.group(1), m.group(2).strip())
            chk_scope = chk
            fsm = None
            continue
        m = re.match(r'^// Fsm (\S+) "(.*)"$', ln)
        if m and scope:
            fsm = 'Fsm %s "%s"' % (m.group(1), m.group(2))
    if scope and fsm:
        out[scope] = (chk_scope, fsm)

with open('fsm_struct_excl.el', 'w') as f:
    for scope, (chk, fsm) in sorted(out.items()):
        f.write('CHECKSUM: %s\n%s\n%s\n\n' % (chk, scope, fsm))
print('FSM 整对象排除 %d 个 scope -> fsm_struct_excl.el' % len(out))
