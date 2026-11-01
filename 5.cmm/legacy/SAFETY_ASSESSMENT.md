# Functional Safety Assessment (rev D, type B tables) -- summary

Full FMEDA in the design notes (skill: functional-safety-analysis /
cmm-m1-three-state-design.md sections 8-10). Placeholder FIT; recompute
with library values at tape-out.

## Table correction (final, user-confirmed)

IEC 61508-2 route 1H has two tables: type A (simple) and type B
(complex). CMM is complex digital logic -> **type B**. SIL3 minimum HFT:

| SFF | type A | type B (CMM) |
|---|---|---|
| <60% | HFT=2 | HFT=2 |
| 60~90% | HFT=1 | HFT=1 |
| 90~99% | HFT=0 | **HFT=1** |
| >=99% | HFT=0 | HFT=0 |

Correct statement: type B SIL3 needs SFF>=99% at HFT=0; at HFT=1,
60% SFF suffices.

## Verdict

- **Single copy (rev C), HFT=0, SFF 90.7% -> SIL2** (type B ceiling).
  SIL3 at HFT=0 requires >=99%: unreachable for a 158-flop module with
  software-contract diagnostics. Single-copy architecture is
  structurally capped at SIL2.
- **1oo2D duplication (rev D), HFT=1, SFF 94.8~97.6% for beta 10~5% ->
  SIL3 holds** with large margin (the HFT=1 gate is only 60% SFF);
  even beta=30% keeps SFF at 85.4% (still SIL3). Duplication is
  therefore not robustness polish but the only route from SIL2 to SIL3
  for a type B element.
- PFH: 1.4e-9/h at beta=10% (SIL3 budget 1e-8~1e-7/h) -- beta
  sensitivity lands on PFH, not on the SFF gate.
- SIL4 (type B, HFT=1, >=99%): needs beta<2%; architecturally
  reachable but systematic capability (IEC 61508-3 SC4) caps the
  claim. Not claimed.

## rev C mechanisms carried into rev D

1. Software periodic self-test closes the loop end-to-end at the ESM:
   program WINLO/WINHI to force err, read the ESM status bit.
   Bidirectional discriminator: bit set = CMM + err path alive; bit
   clear = CMM or ESM-path fault (both detected, fail-safe). Resolves
   both rev B P0 findings (nERR on-chip segment, fsm stuck-ARM).
2. eclk defaults to dcxo and is monitored online by the PMIC
   (mechanism-independent second voter, window +/-8~10%).
3. dcxo voter counts: stop-run 2, stop-boot 2, coarse 3, slow 3,
   rc-dead 1; mid-band 5~43% remains M1-only -- the structural reason
   duplication of M1 itself is the SIL3 lever.

## Compare self-safety (who monitors the monitor)

L0 cmp_err latch outside both copies (drives nERR directly) |
L1 periodic error forcing (one-shot XOR mask, software contract) |
L2 shallow XOR tree: own SEU -> false alarm (fail-safe direction) |
L3 each copy keeps the threshold-programmed ESM self-test | L4 ESM
status readback.

Residual P1: nERR pin->PMIC final segment (needs a PMIC-side nERR
test or Q&A watchdog), csr_rdata 25% DU, threshold readback interval
window.

## Software contract (each missing item costs one SIL)

1. boot threshold-programmed self-test with ESM status-bit check
   (threshold must clear the CDC +/-1 quantization band)
2. periodic task under the OS watchdog: self-test + raw EN codeword
   readback (expect 1111/0000) + threshold readback + error forcing
3. PMIC: eclk online monitoring; nERR path test after POR
