# 10.dup_ctrl — DCLS 控制器设计规格

> 版本: v2.0 (2026-11-08) · 状态: RTL v2 (err 粘滞迁入 mod_clk 域 + FI 同步入本模块)
> 上游: `4.fusa_ips[资料]/1.duplication` (dcls_auto.py 生成物)
> 风格: 全仓统一 rtl-coding-style (GRLIB two-process / logic / 例化对齐 / 公共单元单一源)
>
> v2 相对 v1 的架构变更 (用户钦定):
> 1. **err 粘滞搬进 mod_clk (dup 模块时钟) 域** —— v1 在 mbus 域粘滞, 功能时钟
>    显著快于 mbus 时钟时单个功能拍失配可能被同步链整个错过; v2 捕获单元
>    跑功能时钟, 每个功能拍失配必被粘滞, 状态同步到 mbus 寄存器面。
> 2. **W1C 跨域往返**: dup_ctrl 产生 w1c 事件 (mbus 单拍) → toggle → 同步到
>    mod_clk → 清粘滞 (置位优先, 源在线清不掉) → 像回 0。
> 3. **fi 同步收进本模块** (v1 放在对端 DCLS 侧): u_fi_sync 同步进 mod_clk
>    域后直连 dcls_fault_injection。
> 4. **单 dup wrapper**: 只服务一个 err 通道 (一个 err_fusadcls_<mod>);
>    多 wrapper 各配一个实例, 不做多通道聚合 (NUM_ERR 参数撤销)。

---

## 1. 背景与动机

`dcls_auto.py` 对功能 RTL 生成 DCLS 顶层(func/shadow 复制 + 延迟对齐 + 比较器),
demo 实测 (`demo/test_dcls.v`, 9/9 PASS) 暴露两个交付缺口:

1. **err 非 sticky**: `err_fusadcls_<mod>` 是比较器 err 的打拍**电平**,
   func/shadow 失配消失后 err 跟着回 0。瞬时失配(如单粒子扰动后自恢复)
   软件可能永远读不到 —— 必须在 err 产生时**捕获并粘滞到寄存器端**,
   由软件 W1C 清除。且粘滞必须在 **err 的源时钟域**(mod_clk)完成:
   v1 把粘滞放 mbus 域, 当功能时钟显著快于 mbus 时钟时, 单个功能拍的
   失配可能在 mbus 同步链的两个采样沿之间整段穿过(漏捕获) —— v2 捕获
   单元与 err 同拍, 逐功能拍捕获, 无漏拍窗口。
2. **FI 无控制**: `dcls_fault_injection[1:0]` 是裸端口, 比较器/报错通路
   的在线自检(注错)无法由软件发起, 也无法禁止 —— 需要**寄存器化 + 双保险门控**
   (4bit 编码使能 + 写 key), 并同步到 mod_clk 域后才接比较器
   (FI 是组合输入, 不同步则翻转沿可能在比较器下游寄存器亚稳捕获 → 毛刺
   err 被粘滞成假报)。

本设计(`dup_ctrl`)即补这两块: mbus 配置接口 + mod 域 err 粘滞捕获 +
W1C 跨域清除 + FI 寄存器控制/同步, 作为 DCLS 生成物与 mbus/ESM 之间的控制面。

## 2. 顶层结构

```
                        mbus (APB 桥侧)
       ce/wr/addr/wdata/par ─────────────►│
                                           ▼
                        ┌────────── dup_ctrl_regfile ──────────► rdata
                        │        (8 寄存器面, 4×reg_wrap, mbus 域)
        en_on (准静态) ──┤ sta_w1c (单拍事件)          fi_m (准静态)
        ▼                ▼                            ▼
   u_en_sync        w1c_tgl ──► u_w1c_sync      u_fi_sync      [mod_clk 域]
   (sync_2dff)      (toggle)    │+边沿检出       (sync_2dff,      │
        │                       ▼w1c_clr          复位00)         ▼
        │                      ▼                                 fi_o ──► dcls_
   ┌────┴──────────────────────────────────────────┐          fault_injection
   │ 捕获单元 r_cap (mod_clk 域, Q/Q_n 双副本)      │
   │   sticky: 置位=en_mod&err_i (优先) > W1C 清除   │◄── err_i (err_fusadcls_)
   │   flt:    扰动锁存 (sticky 对失配 → 记录)      │
   └────┬──────────────────┬───────────────────────┘
        │ u_sta_sync        │ u_modflt_sync          u_raw_sync
        ▼ (sync_2dff)       ▼ (sync_2dff)            ▼ (sync_2dff)   [mbus 域]
      err_sta ──► STA_ERR/  mod_flt ──► PERR3      err_raw ──► STA_RAW
                  esm_err/_n             (进 PAR_FAULT 聚合)   (诊断, 允许漏拍)
```

- `dup_ctrl_top` — 集成顶层: `rst_sync`(mod 域复位释放) + 捕获单元 +
  6×`sync_2dff`(en/fi/w1c 进 mod 域, sta/flt/raw 回 mbus 域) + regfile 例化。
  参数 `IDX`(mbus 实例号) / `ERR_SYNC_STAGE`(2|3, 默认 3, 六条同步链统一)。
- `dup_ctrl_regfile` — 全部寄存器语义(见 §3/§5), 纯 mbus 单域; STA_ERR/
  STA_RAW/PERR3 是跨域同步像而非本域存储。
- 复位: `rstn` 异步低有效直入 mbus 域; mod 域经 `u_mod_rst`(rst_sync,
  异步断言/2FF 释放对齐 mod_clk)。复位两域同源。

## 3. 寄存器地图 (mbus, 32bit)

addr[15:8] = IDX(实例号), addr[7:0] = 偏移; `par` = `^{addr,wr,wdata}` 命令在途偶校验。

| 偏移 | 名称 | 属性 | 复位 | 说明 |
|---|---|---|---|---|
| 0x00 | CFG_EN | RW | `0xF` | [3:0] 监测使能, 4bit 编码(1111/0000)。非法码整写拒绝; 1bit 错纠回并**写回**; 2bit 平局默认**开**(fail-visible)。只门控捕获单元新置位(en_on 准静态跨域), STA_RAW 读出永不受门控 |
| 0x04 | CFG_INJ_EN | RW+key | `0x0` | [3:0] 注错(FI)使能, 4bit 编码, 平局默认**关**(fail-safe)。写需 [7:4]=`4'b1010`, 否则整写忽略 |
| 0x08 | CFG_FI | RW | `0x0` | [1:0] FI 模式(00/01/10)。存储面自由写; **输出** `fi = INJ_EN 开 ? CFG_FI : 00`, top 同步进 mod 域 —— key+编码双保险下模式值本身不再加 key |
| 0x10 | STA_ERR | W1C/RO | `0x0` | [0] DCLS err 粘滞 = 捕获单元 sticky 的**同步像**(RO)。写 1 = 触发 mod 域清除事件(与 0x18 bit5 等价); **置位优先于清除**(源在线清不掉, 撤源后可清); 清除经跨域往返生效(~2×STAGES+2 拍两域), 软件 poll 读到 0 |
| 0x14 | STA_RAW | RO | `0x0` | [0] 同步后 err 当前电平(组合读, 区分"正在报"与"报过已粘滞")。**诊断面, 允许漏单拍** —— 保证捕获在 mod 域捕获单元 |
| 0x18 | STA_PAR | RW1C/RO | 静息读 `0x2` | [0] PAR_FAULT 电平, 写 1 只清自测锁存; [1] PAR_FAULT_N 反轨(RO); [6:2] PERR4..PERR0(W1C 清对应组); [7] 保留读 0 |
| 0x1C | CFG_REGST | W+key | — | [3:0] key=`1010`; [4] REG_SELFTEST 脉冲(对 [11:8] REGSEL 选中的组 0/1/2/4 注校验错; **组 3 保留**(捕获单元无 wrap 存储可注错, 扰动路径由 TB force 覆盖, 与 int_prot cnt_par_err 同例); >4 忽略); [5] PAR_SELFTEST 脉冲(只置自测锁存 = "有 fault 无源" 签名)。读回 0 |
| 0xFC | ID | RO | `5AFE_2001\|IDX` | 实例识别 (v2: 地图/语义改版标识, v1=2000) |

PERR 组号 ↔ STA_PAR bit = 2+组号: **0** CFG_EN / **1** CFG_INJ_EN / **2** CFG_FI /
**3** 捕获单元扰动像(mod 域 flt 的同步像, 无 wrap; W1C = 触发与 STA_ERR
同一 mod 域清除事件, 清 sticky 连带清 flt) / **4** 命令在途奇偶粘滞
(cmd wrap, W=1)。

## 4. CDC 策略

本模块为 mbus + mod_clk 两时钟域, 六条同步通路(级数统一 `ERR_SYNC_STAGE`,
默认 3)。复位: rstn 异步断言直入 mbus 域; mod 域经 rst_sync(异步断言/
2FF 释放)。

| 信号 | 方向 | 策略 |
|---|---|---|
| err_i | mod 域 → 捕获单元 | **同域直入**(生成物已打拍), 捕获单元与 err 同拍 —— 每个功能拍失配必被粘滞(v1 的"≥2 拍可观测宽度"约束就此作废, 单拍即捕获) |
| err_sta / mod_flt | mod 域 → mbus 域 | 电平, `u_sta_sync`/`u_modflt_sync`(sync_2dff)同步; STA_ERR 读出/esm_err/PERR3 都是同步像。esm_err 置位延迟 ≈ 捕获 1 拍 + STAGES 拍 |
| err_raw | mod 域 → mbus 域 | 电平, `u_raw_sync` 同步, STA_RAW 诊断读出(允许漏单拍) |
| en_on | mbus 域 → mod 域 | **准静态**电平(4bit 解码后的 1bit), `u_en_sync` 同步后门控捕获置位; 写 CFG_EN 后 STAGES+1 个 mod_clk 生效 |
| fi | mbus 域 → mod 域 | **准静态** 2bit(INJ_EN 门控后), `u_fi_sync` 同步(复位 00 fail-safe)后**直连 dcls_fault_injection** —— v2 收进本模块(原约定对端同步作废)。逐位同步不保多 bit 相干: 软件切换模式一律**经 00 中转**(00→01 / 01→00 / 00→10 / 10→00 均单比特翻转无毛刺; 禁止 01↔10 直切 —— 直切瞬态 00/11 均为无注错行为, 不误报但模式短暂失效); 写后等待同步级数+1 个 mod_clk 再生效 |
| sta_w1c | mbus 域 → mod 域 | **事件**, toggle 跨域: sta_w1c 单拍 → `w1c_tgl` 翻转 → `u_w1c_sync` 同步 → 边沿检出(XOR 本地打一拍)→ `w1c_clr` 单 mod 拍脉冲 → 清 sticky+flt(置位优先于清除)。**约束**: (a) 两次 W1C 间隔须 ≥ 跨域往返延迟(偶数次 toggle 在 mod 同步前发生会抵消 = 丢事件); (b) mod_clk 须在跑 —— 时钟停摆期间的 W1C 不生效, 服务程序访问 DCLS 监测寄存器/FI 前须确保功能时钟运行(与 fi 生效约束同源) |
| clk / rstn | — | rstn 异步低有效; mbus 域直入, mod 域 rst_sync 释放对齐 |

esm_err / reg_par_fault 为 mbus 域输出, 与 int_prot 同按 ESM 侧约定消费。

## 5. 加固规格

1. **4bit 编码使能**(规则11): CFG_EN/CFG_INJ_EN 均 d=4 码(纠1检2), 最近邻纠 1bit 并
   **写回存储**(功能自愈); 平局方向: 监测=开(fail-visible)/注错=关(fail-safe),
   复位值即默认方向; 注错使能写带 key [7:4]=1010。
2. **寄存器奇偶**(reg_wrap × 4): CFG_EN/CFG_INJ_EN/CFG_FI/命令粘滞 = 存储+偶校验+
   selftest_key 注错+flt 粘滞(双副本 SEU 自愈, W1C CPU 优先)。注错只翻 parity,
   数据不动; **治愈 = 重写该寄存器**(parity 重算)。STA_ERR/STA_RAW/PERR3 无本域
   存储面(跨域同步像), 不入 wrap —— 组 3 槽位由捕获单元扰动像占用(见 §3)。
3. **捕获单元 Q/Q_n 双副本**(规则12): sticky 正本 err_q + 反相副本 err_q_n
   逐拍互补自检; 任一副本被扰动(失配)→ **清 0 自愈 + 副本回贴** + 扰动锁存
   flt 记录(flt 自身也是 Q/Q_n 对, 自身失配回贴 SET, 重报不丢)。扰动像同步
   到 mbus 报 PERR3, W1C 清除(= STA_ERR 同一事件)。已锁事件被 SEU 清除时:
   事件丢失(自愈到 0)但扰动被记录 —— fail-visible。
4. **命令在途奇偶**(PERR4): ce 拍重组比对 par, 失配 = APB→mbus 通路在途损坏。
   fail-safe: 坏命令**写不落任何寄存器**(wr_ok 由 par_ok 门控), **读驱 0**
   (不交付错地址数据), 粘滞 PERR4 可 W1C。
5. **ESM 双轨**(规则13): `esm_err/_n`(DCLS 检错 = STA_ERR 像, 电平不可屏蔽)、
   `reg_par_fault/_n`(寄存器/通路奇偶), 互补两轨, ESM 侧做互补校验。
6. **PAR_SELFTEST 锁存**: q/q_n 反相副本逐拍比较, 失配自愈回 SET(正本被 SEU
   清除时重报不丢), W1C 走 STA_PAR bit0。用途: ESM 服务程序自检签名
   ("有 fault 无源" = 锁存通路完好)。

## 6. 与 dcls_auto 生成物的集成约束

| 本模块端口 | 生成物(test_dcls.v)侧 | 约束 |
|---|---|---|
| mod_clk | 该 wrapper 的比较时钟(DCLS 主时钟) | 单 wrapper 单比较时钟(生成物强制单一主比较时钟); 捕获/FI/W1C 生效均需该时钟在跑 |
| err_i | `err_fusadcls_<mod>`(1 路) | **单 dup wrapper 专用**(v2 钦定); 多 wrapper = 多个 dup_ctrl 实例各接 1 路 |
| rstn | DCLS 复位(异步低) | 两域共源复位 |
| fi_o[1:0] | `dcls_fault_injection[1:0]` | **直连**(v2 已在本模块同步, 对端再加同步链冗余但无害); 模式切换经 00 中转, 见 §4 |
| — | `icg_mode` / scan 类 | 不入寄存器, 集成者接 DFT 信号或 tie 0 |
| — | `<mclk>_dcls_gate` 等 | 生成物内部时钟门控, 本模块不触碰 |

注: dcls_auto 生成物为多时钟 DCLS IP 时, err 通道应按"每比较时钟域一组"聚合
(生成物强制单一主比较时钟, 见 1.duplication 分析); 跨域异步 err 的对齐不在
本模块职责内。

## 7. 验证计划 (tb_dup_ctrl, T1–T16)

双时钟: mbus #21 (~23.8MHz) + mod_clk #13 (~38.5MHz, 非整数比相位渐变,
功能快于总线 = v1 漏拍压力场景)。

| # | 内容 | 关键点 |
|---|---|---|
| T1 | 复位默认值 + ID(2001) + 双轨全 0 | EN=F(开)/INJ_EN=0(关)/FI=0 |
| T2 | CFG_EN 编码切换 | 1111→0000→1111 读写回 |
| T3 | 拒写三连 | 非法 nibble / 无 key / key+非法 |
| T4 | err 电平→同步→RAW+STA | mod 域驱动 (negedge+#3) |
| T5 | **sticky 核心** | 源撤销 RAW 回 0, STA/esm 保持; 离线 W1C 跨域往返清 0 |
| T6 | W1C 语义 | 在线清不掉(置位优先, 像无下陷); 撤源后清; 空闲重复 W1C 无害 |
| T7 | EN 门控 | 关时只反映 RAW 不粘滞; 重开恢复 |
| T8 | FI 三重门 | 含 fi_o mod 域同步延迟 (wait_fi); 存储/门控/恢复 |
| T9 | ESM 双轨电平 | 全程互补监视(run_check) + 显式电平查 |
| T10 | REGST 逐组 0/1/2/4 | 注错→PERR→重写治愈+W1C; **REGSEL=3 保留忽略**; >4 忽略 |
| T11 | PAR_SELFTEST | 锁存→bit0(+反轨 bit1=0)→W1C |
| T12 | 命令在途坏 par | 拒写+读 0+PERR4+W1C |
| T13 | 静默类 | 未映射/错实例/写 ID/写 RAW/写 STA=0 无事件 |
| T14 | 复位清除 | err 在线+已粘滞时复位全默认; mod_rstn 断言/释放检查 |
| T15 | **单功能拍捕获** (v2 头条) | err 单个 mod_clk 拍 → STA_ERR 必粘滞; PERR3 bit5 W1C 等价清除路径 |
| T16 | 捕获单元扰动 (force) | sticky 副本失配→清 0 自愈+PERR3; sticky 正本失配→已锁事件清 0(自愈)+PERR3; flt 正本误置→回贴 SET+PERR3; W1C 清 |

运行: VM rocky-eda `~/work`, `bash sim/run_vcs.sh`(自检 grep TB PASS/FAIL,
SVA/$display 不进退出码)。
