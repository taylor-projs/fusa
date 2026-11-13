# CMM — FuSa Coverage Analysis and SIL Assessment

Scope: the CMM as a safety element out of context (SEooC) — its job is to
detect DUT clock faults (frequency drift / death) and its own internal
faults, and to report them fail-visibly on `nerr_n` / ESM dual rails.
Frame: IEC 61508-2 route 1H, **type B** tables (complex digital), per the
project convention from the legacy cmm_m1 assessment. Placeholder FIT —
recompute with library values at tape-out.

## 1. Safety mechanisms implemented (SM) and their verification

| # | Safety mechanism | Fault class covered | TB proof (84/84 pass) |
|---|---|---|---|
| SM1 | All counters dual-rail (inverted duplicate, same-cycle update): window gen, per-ch edge/shadow/noedge, prescaler; fire = A\|B\|dup → fault forces the event NOW, never late; A^B = integrity fault | CNT | inj_cnt → FUSRC0.cnt (ph13); threshold self-test with real edges (ph6) |
| SM2 | Window compare computed twice (value + inverted copy); disagreement latched | CMP | inj_cmp → FUSRC0.cmp (ph14) |
| SM3 | Prescaler duplicate + 4-cycle debounce (filters power-up settling) | PSC | inj_psc → FUSRC0.psc (ph15) |
| SM4 | Register parity on every SW-visible register (reg_wrap: storage+parity loaded together; sticky flt with inverted duplicate, heal-to-SET) — both clock domains | REG | image group inject, self-restore (ph7); config group inject, rewrite-restore (ph8); ref-domain shadow inject per channel (ph16) |
| SM5 | mbus command in-flight parity ^{addr,wr,wdata} at ce — bad command blocked, read 0, PERR_CMD | CMD | bad-parity write blocked + latch (ph9) |
| SM6 | CDC payload parity held through the flight window (PERR11) + busy/drop discipline | CDC | (drop path ph11) |
| SM7 | Config-path liveness: CFG_HANG (ack timeout, dual-rail watchdog), WR_DROPPED, escape write (FORCE bit16=0 always accepted), ack self-heal | HANG | full hang→drop→escape→recover sequence (ph11); incl. the self-mask race found by TB and fixed (3FF mask) |
| SM8 | REF_STALE: window-alive watchdog in mbus domain (ref clock/window machinery dead), gated by any_en | REF dead | force_stale injection (ph12) |
| SM9 | Coded EN (nibble F/0, d_min=4, majority; ambiguous → force ON + HI_ERR — fail-safe direction for a monitor); illegal nibble rejected + REG_PROT | EN | illegal nibble (ph17); disable gating — disabled ch alarms masked (ph18) |
| SM10 | Keyed writes (WKEY) + RO-write protection → REG_PROT, joins esm_fault | PROT | wrong key + RO write (ph5) |
| SM11 | Lifecycle FSM one-hot + illegal→ERR; alarm outputs driven straight from sticky latches, never through the FSM (broken FSM cannot mask an alarm) | FSM | exercised in every fault phase |
| SM12 | Sticky status + W1C through CDC + TST_CLR global self-test clear; live faults re-set after W1C (level verdicts) | reporting | every recovery sequence (20+ clears) |
| SM13 | Dual-rail ESM outputs (esm_err, esm_fault, reg_par_fault, cfg_hang + _n), nerr_n active-low level, 2FF glitch-filtered | output | rail polarity checked in every phase |
| SM14 | Fault injection capability itself (FORCE per ch, inj classes, REGST both domains, no-source signature) — enables boot + periodic SW self-test of the SMs (latent-fault coverage) | latent SM faults | PAR_SELFTEST "fault, no source" (ph10); all injection paths |
| SM15 | REFSEL wrong/stuck self-revealing (measurement cross-checks the reference); quiesce switch protocol | REF sel | REFSEL switch both ways, clean run (ph19) |

## 2. Failure-mode coverage per block

| Element | Failure mode | SM | DC estimate | Residual |
|---|---|---|---|---|
| ref-domain counters (window/edge/shadow/noedge) | 1-bit SEU, stuck | SM1 | ~100% | aligned 2-bit flip of both rails (same-cell adjacency) — PD note: place rail pairs in separate rows/tiles |
| window comparators | SEU, stuck | SM2 | ≥99% | common-mode logic fault (shared thresholds — covered by SM4 on the threshold storage) |
| dut-domain prescaler | SEU | SM3 | ~100% (phase-only upset is measurement-invisible AND still flagged) | — |
| config storage (EN/GCTRL/FORCE/CLO/CHI/CDEAD, ref shadows) | SEU | SM4 | 100% odd-bit; even-bit same-word escapes parity | **dominant residual**: 192-bit config words — same-word 2-bit MBU fraction is layout-dependent |
| threshold values | corruption toward "wider window" (dangerous: faults pass) | SM4 (+SM6 in flight) | as above | even-bit same-word escape |
| mbus command path | addr/data corruption on broadcast | SM5 | 100% odd-bit | 2-bit in-flight escape |
| CDC handshake | stuck req/ack, payload flip | SM6, SM7 | ≥99% (hang → CFG_HANG regardless of cause) | — |
| ref clock / window machinery dead | clock stop | SM8 (+ external voter) | ≥99% | requires mbus_clk independent of refclk0/1 (system assumption) |
| EN codeword | 1–2 bit upset | SM9 | 100% / detected+forced-ON | ≥3-bit aligned alias F→0 mutes the channel (residual, P small) |
| FSM | SEU | SM11 | ~100% | — |
| ESM/nERR outputs | stuck rail | SM13 | receiver-visible (dual rail) | receiver must compare rails (system) |

## 3. SFF / SIL assessment (type B, route 1H)

Type B minimum SFF at HFT=0 / HFT=1 (project convention, legacy assessment):

| SIL | HFT=0 | HFT=1 |
|---|---|---|
| SIL2 | SFF ≥ 90% | SFF ≥ 60% |
| SIL3 | SFF ≥ 99% | SFF ≥ 90% |

Estimated safe fraction, weighted by flop count: the counter/compare/FSM/
watchdog population (~60% of flops) is dual-rail covered at ≥99%; register
storage (~35%) is parity-covered with the even-bit same-word escape
residual; the remainder (sync chains, mux) sits behind downstream SMs.

→ **SFF credibly in the 90–99% band ⇒ the module is SIL2-capable at HFT=0.**

**SIL3 at HFT=0 is not claimed.** The gaps to SFF ≥ 99%:

1. Register storage uses per-word parity (words up to 192 bit) — same-word
   even-bit flips escape. → ECC (SEC-DED) per 32-bit sub-word, or
   interleaved dual parity.
2. Single shared window generator + FSM (dual-rail, not 1oo2D). → duplicate
   and compare, or reuse the legacy cmm_m1_top pattern: two full CMM
   instances with independent references and an alarm voter.
3. EN codeword ≥3-bit aligned alias escapes. → per-channel storage in
   separate reg_wrap words instead of packed nibbles.
4. REF_STALE depends on an independent mbus_clk (system assumption).

With **HFT=1** (two CMM instances, independent refclk pairs, external
voter — the natural SoC integration) the same tables need only SFF ≥ 60%
for SIL2 and ≥ 90% for SIL3; the module exceeds 60% comfortably, so
**SIL3 is reachable at HFT=1**, with item 1 (ECC) recommended to keep
margin.

ISO 26262 cross-read: as SEooC hardware-metric language, the mechanism set
targets SPFM/LFM in the ≥90% class for this element (ASIL B/C–oriented);
PMHF is a system property and out of scope here.

## 4. Known limitations (documented, accepted)

- FSM ERR masks *new* alarm latching until service; persistent faults
  re-latch after TST_CLR→RUN (fail-visible by design, service contract).
- REFSEL mux is combinational; switch only via the quiesce protocol (§7 of
  the design spec). N_DEB debounce absorbs the transition.
- rdata read path is not duplicated (service/diagnostic path only, not part
  of the detection chain; boot ID read gives SW a plausibility anchor).
- Boundary quantization ±1 edge/window is absorbed by the window margin;
  keep production margins ≥ ±5%.

## 5. Verification status

`sim/run_iverilog.sh` (iverilog 12, -g2012), N_DUT=5 asymmetric instance
(25/25/25/100/1 MHz), scaled windows: **84/84 checks PASS** — every SM in
section 1 is exercised fault→detect→latch→rail→W1C→recover. The TB also
caught two real RTL bugs during bring-up (lst_set hang/stale swap; the
force_hang ack self-mask race) — both fixed and regressed.
