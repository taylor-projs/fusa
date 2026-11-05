# cmm 结构常量排除集 ( urg -elfilelist excl/elist.txt )

2026-11-05 多通道重写 (cmm_core 单例化方案) 后全量再生成。
最终: LINE/COND/TOGGLE/FSM/BRANCH 五指标 **100.00**, 0 INVMQV/Unknown
(VM `~/work/cmm/sim`, `urg -lca -dir simv.vdb -report <r> -elfilelist excl/elist.txt`)。

## 文件

| 文件 | 域 | 内容 |
|---|---|---|
| `cmm_excl.tgl` | 实例域 | toggle 排除 |
| `cmm_excl_mod.tgl` | 模块域 | toggle 排除 (实例域排除不进模块定义域 bin, 双域各一份) |
| `cmm_excl.line/.cond/.branch/.fsm` | 双域混合 | 行/条件/分支/FSM 排除 |
| `elist.txt` | — | elfile 清单 (一次 urg 跑全部; 多个 `-elfile` 会失败, 必须用 `-elfilelist`) |

## 排除族 (全部结构不可达, 有既有判例)

1. **映射孔洞 / 对齐常量** (toggle): `addr[15:9]` (IDX 之外全落未知桶),
   `addr[1:0]` 字对齐, 读恒 0 保留字段, one-hot 合法码外位 (GCTRL.MODE[3]
   经 mode_ok 写门)。
2. **通道对称** (N_DUT=5, TB 全配置 ≤5): `[191:60]` FUSRC1 通道 5-15 toggle;
   模块域 ENHI 路径 (line `cw_wd[40:37]` ENHI 支路 + `nib_ok_hi` 需 i>=8 恒 0
   → COND bins "01"/"11"、q_fusrc 全 OR 右臂 bin "01")。若未来 TB 跑
   N_DUT>5 配置, 本族 i>=8 部分需重审。
3. **reg_wrap 自检注入路径** (实例域): 12 个普通 wrap 的 `v.par_q = ~(^wdata)`
   (写+key 同拍) + 4 个镜像 wrap (wr 恒 1) 的 `v.par_q = ~r.par_q` (无写注入)
   与 wr=0 分支臂 —— cmm 注错走 cmm_core FORCE/REGST 通道, 不驱动 regfile
   侧 selftest_key (ia wr 恒 1 同款判例)。
4. **双轨一致性**: cmm_core `(dead_a|dead_b|ne_dup)` bins "010"/"100"
   (noedge_cnt 与其反相副本同拍装载, ne_dup=0 时 dead_a≡dead_b);
   cmm_top `(wend_a^wend_b)|(win_cnt_n!=~win_cnt)` bin "10" (wend 旗标由同一
   win_cnt 双轨派生, 旗标失步必伴随轨失步)。
5. **keyword/映射孔** (cond): q_regst bin "11011" (REGST 无 key 模式, TB 只以
   WKEY 写保护寄存器 — 4bit-key 判例)。
6. **FSM 伪态**: `fsm_state` 是结构字段, 复位为整结构 `REF_REG_RST` 装载 →
   urg 把复位常数建成 95-bit 伪态, 其 6 条转移为 artifacts; 另 ARM→ERR
   设计上不可达 (onehot 校验在 ARM 态只可能 tst_clr→ARM / →RUN)。
   四条真实生命周期转移 (ARM→RUN, ERR→ARM, RUN→ARM, RUN→ERR) 保持测量。
7. **窗口 < 256**: win_cnt[15:8] (TB 全配置 N_WIN < 256)。

## RTL 改动后再生成流程 (VM ~/work/cmm/sim)

```
./run_vcs.sh cov                       # 全新 vdb + 无排除 urg_report
for m in line cond branch fsm tgl; do
  urg -lca -dir simv.vdb -dump full_exclusions $m -report /tmp/x
  mv fullexclude.$m        fresh_$m.dump        # 实例域
  mv fullexclude_module.$m fresh_${m}_mod.dump  # 模块域 (一次 dump 双域两文件!)
done
python3 rebuild_tgl_el.py     # 旧 tgl .el -> excl_new_{inst,mod}.tgl (退役已覆盖行)
python3 rebuild_misc_el.py    # 旧 line/cond/branch/fsm -> excl_new_<m>.el
python3 append_supplement.py  # 结构补集 (reg_wrap 注入/通道对称/双轨/伪态)
# elist_final.txt 列出 6 个 excl_new_* 后:
urg -lca -dir simv.vdb -report urg_chk -elfilelist elist_final.txt -format both
# 检查 dashboard 100.00 + modinfo 无 "Not Covered" 残留 → 拷回 excl/ 正名
```

要点/坑 (详见 fusa 记忆 urg 排除流程):
- 行/条件/分支行按**内容**寻址: `Branch 0 "哈希" "(!rst_n)" (1) "..."` 中哈希
  每次 compile 都变, 匹配必须剥哈希 (rebuild_misc_el.py `nohash()`);
- `MODULE: reg_wrap ( parameter W=3,RESET=0 ) ` 行尾空格是 urg 对位键的一部分;
- full_exclusions dump 列的是全部**可排除对象** (含已覆盖), "在 dump 里"≠"未覆盖",
  未覆盖判定以 modinfo 为准; 已覆盖旧项必须退役;
- `-dump full_exclusions` 每次覆盖 CWD 的 fullexclude.* 且**同时**产出
  fullexclude_module.* —— 双域一次拿齐。
