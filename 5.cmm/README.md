# CMM — Clock Monitor Module (X7A / TR4 / FuSa)

Multi-channel clock monitor, SIL2-oriented. SystemVerilog rework of the
legacy single-channel `cmm_m1` design (kept in `legacy/`): mbus
configuration, parameterized channel count (N_DUT = 1..16), two selectable
reference clocks, dual-rail (inverted-duplicate) counters, register parity
on all SW-visible registers, sticky status + W1C, full fault injection, and
config-path hang monitoring.

## Layout

| Dir | Content |
|---|---|
| `rtl/` | `cmm_top.sv` (top: ref mux, window gen, FSM, channels, ESM rails) · `cmm_regfile.sv` (mbus leaf + parity wraps + CDC + hang monitors) · `cmm_clk_dut_mon.sv` (per-channel measurement) · reg_wrap 由 fusa 根 `common_modules/reg_wrap.sv` 单一源提供 (filelist 引用) |
| `sim/` | `tb_cmm_top.sv` (self-checking TB, 84 checks) · `run_iverilog.sh` |
| `doc/` | `cmm_sil2_design.md` (architecture + register map) · `cmm_timing_sw_guide.md` (parameters, expire values, timing, error classes, SW flows) · `fusa_coverage_sil.md` (SM list, FMEDA-style coverage, SIL assessment) |
| `legacy/` | previous cmm_m1 design (Verilog), its README and safety assessment |

## Quick start

```sh
# WSL (iverilog 12, -g2012)
cd sim && ./run_iverilog.sh        # -> "ALL 84 CHECKS PASSED"
```

## Status

- RTL: 4 files, iverilog -g2012 clean (elaboration + simulation).
- Verification: 84/84 checks pass — every safety mechanism exercised
  end-to-end (fault → detect → latch → rail → W1C → recover).
- FuSa: **SIL2-capable at HFT=0** (type B, SFF 90–99% band); SIL3 requires
  HFT=1 (dual instance + voter) or ECC on config storage — details in
  `doc/fusa_coverage_sil.md`.

## Key interface facts

- mbus leaf: `ce` single-cycle pulse, `addr[15:8]=IDX`, command parity
  `par=^{addr,wr,wdata}`; bad parity → write blocked + PERR_CMD.
- Keyed registers need `wdata[31:28]==WKEY` (GCTRL/FORCE/REGST/CH space).
- Forwarded writes go through a one-at-a-time CDC handshake: poll
  GSTAT[6] (CFG_BUSY) between writes; a write while busy is dropped
  (FUSTAT[7]). Hang recovery: FORCE write with bit16=0 always accepted.
- GCTRL writes always re-store {DBGSEL, REFSEL} — use read-modify-write.
