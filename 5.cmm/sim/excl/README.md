# cmm 结构常量排除集 ( urg -elfilelist excl/elist.txt )

2026-11-07 house 地图 retrofit (reg_wrap 五件套升级 + cmm_regfile REGST/REGSEL
改造) + TB regroup 0..12 扫描与 ERRSTAT pattern 写 (321 checks) 后全量再生成,
并完成"已覆盖旧项退役"修剪。
最终: LINE/COND/TOGGLE/FSM/BRANCH 五指标 **100.00 双域** (实例域 + 模块定义域),
0 INVMQV/Unknown
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
   → COND bins "01"/"11"、BRANCH 0to1 臂)。若未来 TB 跑
   N_DUT>5 配置, 本族 i>=8 部分需重审。
3. **reg_wrap 自检注入路径**: 12 个普通 wrap 的 `v.par_q = ~(^wdata)`
   (写+key 同拍) + 4 个镜像 wrap (wr 恒 1) 的 `v.par_q = ~r.par_q` (无写注入)
   与 wr=0 分支臂 —— **selftest_key 全例化实接** (`regst_st` 选通),
   不可达纯因结构: ① 普通 wrap 的 REGST 注错脉冲与目标寄存器写**永不同拍**
   (单口 mbus 一拍只译一个地址); ② 镜像 wrap wr 恒 1, 无写注入臂与 wr=0 臂
   不可达 (ia wr 恒 1 同款判例)。**模块域 W=64 参数组只含镜像 wrap**, 其
   `if (selftest_key)`/`v.par_q = ~r.par_q` (108/110 行) 同判例。
4. **双轨一致性**: cmm_core `(dead_a|dead_b|ne_dup)` bins "010"/"100"
   (noedge_cnt 与其反相副本同拍装载, ne_dup=0 时 dead_a≡dead_b);
   cmm_top `(wend_a^wend_b)|(win_cnt_n!=~win_cnt)` bin "10" (wend 旗标由同一
   win_cnt 双轨派生, 旗标失步必伴随轨失步)。
5. **keyword/映射孔** (cond): q_regst bin "11011" (REGST 无 key 模式, TB 只以
   WKEY 写保护寄存器 — 4bit-key 判例); `wr_ok&&!keyed_bad` bin "1101"
   (regst_key_bad=1 ⇒ 第 4 项恒 0 逻辑矛盾)。
6. **FSM 伪态**: `fsm_state` 是结构字段, 复位为整结构 `REF_REG_RST` 装载 →
   urg 把复位常数建成 95-bit 伪态, 其 6 条转移为 artifacts; 另 ARM→ERR
   设计上不可达 (onehot 校验在 ARM 态只可能 tst_clr→ARM / →RUN)。
   四条真实生命周期转移 (ARM→RUN, ERR→ARM, RUN→ARM, RUN→ERR) 保持测量。
7. **窗口 < 256**: win_cnt[15:8] (TB 全配置 N_WIN < 256)。
8. **结构常量位** (toggle): `perr_w[11]` (组 11 = latch 通道, assign 恒 1'b0)。

## RTL/TB 改动后再生成流程 (VM ~/work/cmm/sim)

```
./run_vcs.sh cov                       # 全新 vdb + 无排除 urg_report
for m in line cond branch fsm tgl; do
  urg -lca -dir simv.vdb -dump full_exclusions $m -report /tmp/x
  mv fullexclude.$m        fresh_$m.dump        # 实例域
  mv fullexclude_module.$m fresh_${m}_mod.dump  # 模块域 (一次 dump 双域两文件!)
done
python3 rebuild_tgl_el.py     # 旧 tgl .el -> excl_new_{inst,mod}.tgl
python3 rebuild_misc_el.py    # 旧 line/cond/branch/fsm -> excl_new_<m>.el
python3 append_supplement.py  # 结构补集 (reg_wrap 注入/通道对称/双轨/伪态)
python3 append_struct.py      # 手工族 A-I (双轨 cond/S1 臂/D 矛盾/ENHI/perr_w[11]/W=64 108-110)
# elist_final.txt 列出 6 个 excl_new_* 后:
urg -lca -dir simv.vdb -report urg_chk -elfilelist elist_final.txt -format both
python3 retire_covered.py     # 退役: 无排除基线中已覆盖、却被排除的行 (toggle 区间拆分)
urg ... urg_chk2 ...          # 误退会掉分 -> 回贴
python3 restore_holes.py urg_chk2   # 从 *.pre 快照找回误退行 (退役前先 cp 六件为 *.pre)
urg ... 复验 100.00 双域 → 拷回 excl/ 正名
```

要点/坑 (详见 fusa 记忆 urg 排除流程):
- 行/条件/分支行按**内容**寻址: `Branch 0 "哈希" "(!rst_n)" (1) "..."` 中哈希
  每次 compile 都变, 匹配必须剥哈希 (rebuild_misc_el.py `nohash()`);
- `MODULE: reg_wrap ( parameter W=3,RESET=0 ) ` 行尾空格是 urg 对位键的一部分;
- full_exclusions dump 列的是全部**可排除对象** (含已覆盖), "在 dump 里"≠"未覆盖",
  未覆盖判定以 modinfo 为准; 已覆盖旧项必须退役 (retire_covered.py),
  误退由 restore_holes.py 从 *.pre 回贴 (闭环收敛, 两步各跑一次即可);
  残余 -excl_strict UCAPI-ILOAD 警告 6 条 (旧全量集 8 条), 均为退役检测
  盲区 (dump 行号映射失败) 的已覆盖项, 不影响五指标 100.00;
- modinfo 段头形如 `... for Module : cmm_regfile(x)` 的 `(x)` 后缀须剥掉
  才能对上 el/dump 的 scope 键;
- `-dump full_exclusions` 每次覆盖 CWD 的 fullexclude.* 且**同时**产出
  fullexclude_module.* —— 双域一次拿齐。
