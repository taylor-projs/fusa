# CMM — Clock Monitor Module (multi-channel, SIL2-oriented) — Design Spec

X7A MCU System / TR4 / MCUSys / FuSa. Successor of the legacy single-channel
`cmm_m1` + 1oo2D `cmm_m1_top` (kept in `legacy/`). SystemVerilog rework with
mbus configuration, parameterized channel count, dual-rail counters,
register parity, fault injection and config-path hang monitoring.

## 1. Features

- **N_DUT parameterized** clocks under test (1..16, e.g. 5 or 16 by parameter).
- **Two reference clocks**, SW-selectable (REFSEL), glitch note + quiesce
  protocol (§7).
- Per-channel **window frequency check** (prescaled-DUT edges per reference
  window vs programmed [WIN_LO, WIN_HI]) with **N_DEB-window debounce**.
- Per-channel **DEAD detection** (no DUT edge for NDEAD reference cycles,
  re-issuing).
- **mbus** leaf configuration interface (zero-wait, command in-flight parity).
- **Register parity** on every SW-visible register (`reg_wrap`, storage +
  even parity + injection + sticky fault with inverted duplicate).
- **SIL2 counter integrity**: all counters stored with inverted duplicates
  (dual-rail), fire = A|B|dup — a corrupted counter forces the event *now*,
  never late.
- **Sticky status** everywhere (alarms, integrity, protection), W1C via CDC
  handshake, TST_CLR global self-test clear.
- **Fault injection**: per-channel verdict FORCE, integrity injection
  (cnt/cmp/psc classes), parity injection in both clock domains, "no-source"
  ESM service signature, hang/stale injection.
- **Config-path hang monitoring** (new): CFG_HANG (ack timeout), REF_STALE
  (window-alive watchdog), WR_DROPPED — dual-rail ESM event `cfg_hang`.

## 2. Structure

```
rtl/
  (reg_wrap.sv 移至 fusa 根 common_modules/, 经 filelist 引用:
   register cell: storage + even parity + selftest injection
  cmm_core.sv         ONE instance monitors ALL N_DUT dut clocks against the
                      ONE shared reference window: channels are vectorized
                      slices of one record (clk_ref domain) + one generate
                      loop of per-domain prescalers (each clk_dut is its own
                      clock domain). Per-channel [WIN_LO, WIN_HI] min/max
                      bounds, dual-rail counters, dead detect, injection.
                      (2026-11 rewrite: 取代旧的 per-channel cmm_clk_dut_mon
                      N 例化方案 — 不再例化 N 个通道模块)
  cmm_regfile.sv      mbus leaf + register wraps (both domains) + CDC toggle
                      handshake + hang/stale/drop monitors + read mux
  cmm_top.sv          ref clock select, reset sync, shared window generator
                      (dual-rail), lifecycle FSM, verdict latches / sticky
                      vectors, aggregation, ESM rails, nERR
sim/
  tb_cmm_top.sv       self-checking TB (319 checks, N_DUT=5 instance)
  run_vcs.sh          VCS build+run (+cov: coverage & urg report)
  run_iverilog.sh     iverilog -g2012 build+run (WSL)
  excl/               urg structural exclusion set (see excl/README.md)
doc/
  cmm_sil2_design.md  this document
  cmm_timing_sw_guide.md  parameters, expire values, timing budgets, error
                      classes, software flows (init / FAIL_FREQ / FU / config,
                      single- and multi-channel)
  fusa_coverage_sil.md  FMEDA-style coverage + SIL assessment
```

## 3. Clocks and reset

| Domain | Clock | Content |
|---|---|---|
| monitor | `clk_ref` = refclk0/refclk1 selected by REFSEL | window gen, FSM, channels, config shadows |
| config | `mbus_clk` | mbus leaf, register wraps, hang monitors |
| dut(i) | `clk_dut[i]` | free-running prescaler only (no reset) |

- `rst_n`: async POR; `rst_ref_n` (active-low) generated async-assert /
  sync-release into `clk_ref`; all flops use negedge async reset.
  `mbus_rstn`: mbus-domain reset. **Both must assert together**
  (CDC toggle handshake alignment).
- Verdict logic lives entirely in `clk_ref`: a dead DUT clock cannot be
  detected in its own domain.
- FAIL_DEAD of `clk_ref` itself: covered by REF_STALE (needs `mbus_clk`
  independent of refclk0/1) plus the external voter (PMIC WDG) — a dead
  clock cannot report its own death.

## 4. Measurement principle

Per channel: free-running ÷2^(PSC+1) prescaler in the DUT domain (PSC per
channel via `DUT_PSC` parameter), 2FF sync into `clk_ref`, registered edge
detect, edges counted per reference window of N_WIN cycles:

    expected count = N_WIN * f_dut / (f_ref * 2^(PSC+1))

Constraint: `f_dut / 2^(PSC+1) <= f_ref / 4` (2FF + edge-detect Nyquist
margin). CDC quantization: ±1 ref cycle per edge, plus at most 1 edge lost
at the window boundary — both far inside the production window margin
(±5% of ~1-2k counts).

Verdicts (detection events; sticky latches in top):
- `FAIL_FREQ`: shadow count outside [WIN_LO, WIN_HI] for N_DEB consecutive
  windows. Dual compare (A from counter, B from inverted copy), disagreement
  = CMP integrity fault; a counter-duplicate mismatch anywhere in the window
  poisons that window (forces the verdict — never late).
- `DEAD`: no prescaled edge for NDEAD ref cycles (counter wraps and
  re-issues while the clock stays dead). Set in ARM and RUN.
- Integrity: `FU_CNT` (counter/shadow duplicate broken), `FU_CMP`
  (comparators disagree), `FU_PSC` (prescaler duplicate, debounced 4 cycles
  to filter power-up settling of the un-reset dut-domain pair).
- Severity ordering: a counter dual-rail break raises `FU_CNT` instantly and
  the FSM leaves RUN before the FAIL_FREQ debounce (N_DEB windows) can
  accumulate — counter integrity faults always report on the FU rail, never
  as FAIL_FREQ. The per-window count poison (`ecnt_flt_w`, cleared at
  `window_fire` so it survives to the debounce sample point) is
  defense-in-depth behind that ordering.

### 4.1 Relation to industry CMM topologies (CLMA / CMU_FM / DCC)

The canonical automotive clock-monitor structure (Renesas RH850 CLMAn, NXP
CMU_FM, TI Hercules DCC) has three elements:

| element | CLMAn | CMU_FM | DCC | this design |
|---|---|---|---|---|
| window length (expire value, in ref cycles) | sampling interval from CLMATSMP | REF_CNT | CNT0 seed | `N_WIN` |
| allowed band (min/max counts = nominal ± tolerance) | CLMAnCMPL/CMPH | LFREF/HFREF | CNT1 seed ± VALID seed | `WIN_LO`/`WIN_HI` |
| stopped-clock timeout | count reads 0 < CMPL at next boundary | freq-low | count-low at expiry | `NDEAD` ref-cycle no-edge timer (fires ≪ one window, re-issuing) |

The industry structure counts the monitored clock **in its own domain**:
the ref domain defines a window, a boundary toggle is synchronized into the
DUT domain, the 1st synced edge starts a DUT-cycle counter, the 2nd edge is
the check point and restarts the next count. This design keeps the identical
measurement semantics (ratio-metric windowed count vs a [min,max] band) but
relocates the counting: the DUT clock is prescaled in its own domain and the
resulting 1-bit square wave is 2FF-synchronized into `clk_ref`, where edges
are counted per window. Rationale for the relocation (SIL2):

- **The checker never depends on the clock under test.** With in-DUT-domain
  compare, a dead DUT clock freezes the compare logic itself; detection then
  requires an extra ref-domain "no result" watchdog. Here dead detection is
  intrinsic (`NDEAD` no-edge timer in the always-alive ref domain) and the
  window/verdict/sticky logic all live in one domain.
- **Minimal CDC surface.** Only a 1-bit square wave crosses per channel;
  thresholds never leave the ref domain. In-DUT counting needs boundary
  toggle in, verdict (or quasi-static held count) out, and thresholds
  crossing as quasi-static multi-bit values.
- **Integrity protection stays in one timing domain.** All dual-rail
  counters/compares close timing in `clk_ref`; the only DUT-domain logic is
  the prescaler pair, whose corruption merely shifts the square-wave phase
  (frequency unchanged) and is still made fail-visible (`FU_PSC`).
- **Fail-safe under misconfiguration.** A PSC programmed too small violates
  the Nyquist constraint, edges are lost, the count reads low → below
  `WIN_LO` → alarm direction, never silent.

Costs (accepted): quantization ±1 prescaled edge per window (~0.012% at
production settings, far inside the ±5% band), and the PSC/Nyquist
configuration constraint above. If strict register-level equivalence with
CLMA is ever required (e.g., a standard driver), the migration path is:
count raw DUT cycles in the DUT domain, capture-and-clear on the
synchronized boundary toggle, and compare the held count in the ref domain
— thresholds and verdict logic stay unchanged.

## 5. Register map

Instance selected by `addr[15:8] == IDX`; byte offset `addr[7:0]`.
`par = ^{addr,wr,wdata}` command in-flight parity, checked at every `ce`;
bad-parity command: writes blocked, read data 0, PERR_CMD latched.
Keyed registers require `wdata[31:28] == WKEY` (else REG_PROT, write
rejected). All W1C writes cross to `clk_ref` through the CDC handshake.

| Off | Name | Acc | Key | Content |
|---|---|---|---|---|
| 0x00 | ID | RO | | `0xC44D_0100 \| N_DUT` |
| 0x04 | GCTRL | RW | ✓ | [0] REFSEL · [1] TST_CLR (pulse) · [7:4] DBGSEL. Every write re-stores REFSEL/DBGSEL (RMW discipline) |
| 0x08 | GSTAT | RO | | [0] alarm · [1] fu · [2] active · [5:3] fsm (ARM=1,RUN=2,ERR=4) · [6] cfg_busy · [7] nerr_n · [8] refsel · [9] any_en · [10] reg_par_fault · [11] cfg_hang |
| 0x0C | ENLO | RW | | ch0..7 coded enables, nibble `F`=on / `0`=off (others illegal → REG_PROT, nibble rejected) |
| 0x10 | ENHI | RW | | ch8..15 (masked 0 beyond N_DUT) |
| 0x14 | ERRSTAT | W1C | | [i] channel i alarm (fail\|dead) |
| 0x18 | SRCSTAT | W1C | | [2i] fail · [2i+1] dead |
| 0x1C | FUSTAT | W1C | | [0] cnt_any · [1] cmp_any · [2] win · [3] psc_any · [4] hierr · [5] fsm · [6] reg_prot · [7] wr_dropped · [8] cfg_hang · [9] ref_stale |
| 0x20 | FUSRC0 | W1C | | ch0..7 nibbles {psc, cfgpar, cmp, cnt} |
| 0x24 | FUSRC1 | W1C | | ch8..15 |
| 0x28 | FORCE | RW | ✓ | [N_DUT-1:0] per-ch verdict force · [16] force_hang · [17] force_stale · [18] inj_psc · [19] inj_cmp · [20] inj_cnt (inj targets channel DBGSEL) |
| 0x2C | DBG0 | RO | | {4b0, noedge, 4b0, shadow} of channel DBGSEL |
| 0x30 | DBG1 | RO | | {win_cnt[15:0], 4b0, edgecnt} of channel DBGSEL |
| 0x34 | STA_PAR | W1C | | [0] PAR_FAULT (W1C 清自测锁存) · [1] _n · [14:2] PERR group 0..12 (bit = 2+组号) · [14] PERR12 CMD |
| 0x38 | CFG_REGST | WO | ✓ | key[3:0]=1010 · [4] REG_SELFTEST + REGSEL[12:8] (0..12; 11 无注错目标) · [5] PAR_SELFTEST 无源注错 · REGSEL 16+i: ref-domain shadow of ch i |
| 0x40+12i | CHi_WIN_LO / +4 WIN_HI / +8 NDEAD | RW | ✓ | 12-bit fields per channel |

寄存器地图位置 (house standard): STA_PAR 倒数第 3、CFG_REGST 倒数第 2
(固定段内; 变长通道数组区 0x40+ 不参与倒数, ID 留 0x00)。CFG_REGST 用
house key `wdata[3:0]=4'b1010` (非 WKEY 空间), 错 key = REG_PROT。

STA_PAR PERR groups (bit 2+k): 0 ENLO · 1 ENHI · 2 GCTRL · 3 FORCE ·
4 CLO · 5 CHI · 6 CDEAD · 7 ERRSTAT image · 8 SRCSTAT image · 9 FUSRC
image · 10 FUSTAT image · 11 in-flight payload (latch lane, W1C bit13,
无注错目标) · 12 CMD (W=1 wrap: 命令在途奇偶粘滞体, W1C bit14 即重写).

## 6. CDC and liveness

- **Handshake**: one-at-a-time toggle req/ack; payload {wsel,wdata} latched
  at the write, held stable while in flight (parity-checked through the
  flight window → PERR11). Ref side: 2FF + registered edge → apply → **ack
  follows** the synced request level (`ack_t <= req_s2`), so alignment
  self-heals after an ack-mask injection.
- **Busy**: GSTAT[6]; SW must poll before the next forwarded write. A write
  while busy is dropped (FUSTAT[7]) — local state stays consistent with the
  ref domain (drops are atomic, never half-applied).
- **CFG_HANG** (FUSTAT[8]): busy longer than HANG_TO mbus cycles → the
  clk_ref capture side or the ack path is dead. Dual-rail watchdog counter.
  force_hang (FORCE[16]) masks the ack for self-test; it is synced 3FF so
  the write that *sets* it still completes (req path is 2FF, one cycle
  faster) and only subsequent writes hang. **Recovery**: write FORCE with
  bit16=0 — always accepted even while busy (escape path, local only).
- **REF_STALE** (FUSTAT[9]): window_fire toggle (2FF into mbus domain)
  absent for WIN_ALIVE_MAX mbus cycles while any channel is enabled → the
  whole monitor (ref clock / window machinery) is dead. force_stale
  (FORCE[17]) freezes the sync chain for self-test. Note: after release the
  saturated watchdog re-fires until the next window toggle — clear it one
  window later.
- `cfg_hang`/`cfg_hang_n` = OR(dropped, hang, stale), dual rail to ESM.

## 7. Reference clock switch protocol

`clk_ref = cfg_refsel ? refclk1 : refclk0` is a plain combinational select
(ASIC integrator may substitute a clock-mux cell; a glitchless handshake mux
cannot switch *away* from a dead clock — the plain mux + protocol is the
fail-visible choice):

1. ENLO/ENHI ← 0 (quiesce; disables alarm latching and the stale watchdog)
2. GCTRL ← REFSEL (keyed)
3. GCTRL ← REFSEL | TST_CLR (FSM back to ARM, stickies cleared)
4. ENLO/ENHI ← enables; N_DEB debounce absorbs the transition window

A wrong/stuck REFSEL is also self-revealing: all channels report FAIL_FREQ
(the measurement cross-checks the reference).

## 8. Safety outputs

| Output | Domain | Meaning |
|---|---|---|
| `nerr_n` | clk_ref | active-low level to PMIC, 2FF glitch-filtered, held while any alarm/integrity sticky set |
| `cmm_err`/`_n` | clk_ref | dual rail: any channel alarm (FAIL_FREQ/DEAD) |
| `cmm_fu`/`_n` | clk_ref | dual rail: monitor integrity (counter dup, compare disagree, window dup, prescaler dup, EN codeword, FSM, config-shadow parity, key violation) |
| `reg_par_fault`/`_n` | mbus | dual rail: register parity (incl. command + in-flight) |
| `cfg_hang`/`_n` | mbus | dual rail: config-path liveness |
| `cmm_active` | clk_ref | FSM in RUN |

## 9. Parameters

Summary below; full sizing rules, worked examples and the elaboration-time
review checklist in `cmm_timing_sw_guide.md` §1/§4.

| Param | Default | Meaning |
|---|---|---|
| N_DUT | 16 | channels under test (1..16) |
| N_WIN | 32768 | window length [ref cycles] |
| WIN_LO_RST / WIN_HI_RST | 1621 / 1792 | window bounds reset defaults |
| NDEAD_RST | 4095 | no-edge timeout reset default [ref cycles] |
| N_DEB | 3 | FAIL_FREQ debounce [windows] |
| WKEY | 4'h5 | keyed-write key [31:28] |
| DUT_PSC | all 3 | per-channel prescaler tap (4 bits/ch), 0..15 |
| HANG_TO | 1024 | CFG_HANG timeout [mbus cycles] |
| WIN_ALIVE_MAX | 131072 | REF_STALE timeout [mbus cycles] |
| IDX | 0 | mbus instance id |

## 10. Verification summary

`sim/tb_cmm_top.sv`, iverilog 12 (-g2012), N_DUT=5 instance with asymmetric
channels (25 MHz ×3, 100 MHz, 1 MHz), scaled windows: **84/84 checks pass**.
Every FuSa mechanism is exercised end-to-end (fault → detection → sticky →
rail → W1C → recovery): DEAD, FAIL_FREQ, FORCE, key/RO protection,
threshold self-test with real edges, parity injection in both domains
(image self-restore / config rewrite-restore / command parity / no-source),
CFG_HANG + WR_DROPPED + escape, REF_STALE, inj_cnt/cmp/psc per class,
ref-domain shadow injection, EN illegal-nibble rejection, disable gating,
REFSEL switch with quiesce protocol. See `fusa_coverage_sil.md` for the
check→mechanism mapping.

## 11. Integration notes

- `reg_wrap` originates from the hang_prot/ia_bus_timeo projects (same
  semantics; style-adapted here: logic+assign declarations, negedge rst_n).
- iverilog compatibility: no SV size casts, no parameter part-selects, no
  complex genvar expressions in port connections (kept on named wires) —
  the style is deliberate, keep it.
- The `sorry: constant selects in always_*` messages from iverilog are
  benign (sensitivity-list over-approximation only).
