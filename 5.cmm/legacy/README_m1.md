# CMM M1 — 3-State Clock Monitor (reference RTL)

Reference implementation of the M1 clock monitor for the dcxo-direct-boot
clock-safety scheme. Monitors the dcxo (device under test) frequency against
an independent rc_osc reference, entirely in the dcxo domain.

## Files

| File | Description |
|---|---|
| `cmm_m1.v` | RTL (Verilog-2001). Three voters + Tier1 EN codeword + self-test engine |
| `tb_cmm_m1.v` | Self-test testbench, 9 checks, scaled parameters |
| `waves/*.png` | GTKWave-style waveform renders (A–E scenarios, generated from a cycle-accurate Python model) |

## Architecture summary

- **Domain scheme**: all logic in `clk_dcxo`; rc_osc crosses only via a
  ÷16 prescaler (rc domain) + 2FF synchronizer + registered edge detect
  (CDC quantization clamped to ±1 LSB).
- **Three voters**:
  1. `FAIL_FREQ` — edges-per-window vs (WIN_LO, WIN_HI), dual comparators
     (magnitude + subtract, XOR = black-box mismatch), N_DEB-window debounce.
  2. `UNAVAILABLE` — no-edge timeout (3rd state; sole voter after M2 removal).
  3. `CMM dead` — window-refresh watchdog.
  - `FAIL_DEAD` (dcxo stop) is silent by design; covered by the external
    voter (PMIC WDG / CPU WDT). A dead clock cannot report its own death.
- **Tier1 EN codeword**: `cmm_en` is the only flip-to-dangerous control bit
  (1→0 mutes all voter latches). Stored as a 4-bit high-integrity codeword
  (`1100`=armed / `0011`=muted, d_min=4): 1-bit SEU self-heals, 2–3-bit
  upsets latch `hi_err` + force armed (fail-safe direction), 4-bit alias is
  the accepted residual (probability + layout MBU spacing + periodic
  readback). All other control bits are Tier2 (fail-safe direction or
  independently covered — audit table in the design notes).
- **Self-test** (boot-mandatory, the only backstop against stuck-PASS):
  - `INJ_FREQ` — mux the prescaler to ÷INJ_DIV (full detection chain)
  - `INJ_DEAD` — gate edges (exercises the 3rd state)
  - `INJ_BB` — perturb comparator B input by MSB flip (non-invasive:
    `bb_seen` observation bit only, never pulls nERR mid-boot)
  - `CTRL.TST_FORCE` — synthetic out-of-window pulses (µs-scale path check)
- **CSR**: 4-bit write key (`WKEY`) on CTRL/TESTMODE; wrong key latches
  `reg_prot`. CTRL is a full-intent write: every write must carry the
  intended `en` value.

## Register map

| Addr | Name | Bits |
|---|---|---|
| 0 | ID | 0x0C11 |
| 1 | CTRL | [3:0]=WKEY, [8]=en, [9]=tst_clr, [10]=tst_force |
| 2 | TESTMODE | [7:4]=WKEY, [1:0]=mode (0 off / 1 inj_freq / 2 inj_dead / 3 inj_bb) |
| 3 | STATUS | [0]fail [1]unavail [2]stale [3]bb [4]fsm_err [5]reg_prot [6]active [7]wfire [8]bb_seen [9]hi_err |
| 4 | SHADOW | [10:0] window edge count (fleet diagnostics) |
| 5 | NOEDGE | [12:0] no-edge counter |
| 6 | WDG | [15:0] window-refresh watchdog |
| 7 | DEB/FSM | [1:0] debounce, [4:2] one-hot FSM |

CTRL write values (full-intent contract): `tst_clr=0x0305`,
`tst_force=0x0505`, mute=0x0005, re-arm=0x0105 (all with WKEY=5).

## Parameters (production scaling: 24MHz dcxo / 20MHz rc)

N_WIN=32768 (window 1.365ms), window [1621,1792] (≈±5%; recommend
[0.94,1.06]×C_nom at tape-out, wide OTP window at POR), N_DEAD=4096
(170.7µs, 213× margin), N_STALE=65536 (2× window), N_DEB=3 (detection
≈5.5ms), INJ_DIV=18 (−11.1%). The tb uses scaled-down parameters
(N_WIN=1024, window [45,62], INJ_DIV=24) — window and injection amplitude
are coupled; see the scaling rules in the design notes.

## Simulation

```
iverilog -o cmm.vvp cmm_m1.v tb_cmm_m1.v && vvp cmm.vvp   # expect: ALL PASS
```

Verification status: structural lint clean (begin/end balance, async-reset
shape, case defaults, unused signals); behavior validated against a
cycle-accurate Python reference model (window snapshot 53, fail @ c5122,
unavail @ c2248, EN codeword SEU sweep: 1-bit heals / 2-bit alarms / 4-bit
alias confirmed). Dynamic simulation pending on a machine with iverilog.

Design notes and the full audit trail live in the internal skill
(`functional-safety-analysis` → `cmm-m1-three-state-design.md`).
