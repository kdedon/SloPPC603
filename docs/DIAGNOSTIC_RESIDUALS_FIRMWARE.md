# Diagnostic residuals compiled-firmware acceptance

Recorded: `make -C toolchain rtl-residuals` (inside `make -C sim ci`), commit 55e2b78 plus uncommitted doc edits, 2026-09-28.
Recorded: `make -C sim ci`, `make -C sim reference-acceptance`, commit 4498a25 (reference) and 55e2b78 (ci), 2026-09-28.

Contract: [DIAGNOSTIC_RESIDUALS.md](DIAGNOSTIC_RESIDUALS.md).

## Compiled program

`toolchain/residuals-smoke.c` with `residuals-handler.S` runs on the
translated cached 60x profile (`tb_compiled_residuals_firmware`, scripted
bus target with retries and data retries). Every former diagnostic case runs
with IR and DR set, and the bench fails on any `halted_o`:

- BAT writes with reserved bits read back cleared and still map; a BL outside
  PEM Table 7-10 masks bitwise; overlapping DBATs resolve to the lower entry
  (a read-only DBAT1 over a read/write DBAT2 takes a DSI, swapped it stores).
- `mtspr SDR1` with a non-contiguous HTABMASK and unaligned HTABORG reads
  back unchanged.
- SC, trap, illegal, DSI, alignment, trace, IABR and decrementer exceptions
  taken with MSR[TGPR]=1: each clears TGPR, SRR1 never holds it, and r3 of
  the normal bank survives.
- A data TLB miss taken with TGPR set enters with TGPR set again; HASH1 and
  DMISS match the bitwise PEM 7.6.1.4.2 formula and read back under
  translation.
- `tlbld` under translation with H=1, an API mismatch and nonzero RPA
  reserved and R bits maps the page; the same tag loaded into the other way
  replaces the first; V=0 leaves the entry invalid and the next access misses.

Result: **PASS**, checks=241,652, 6,347 retirements, 58,516 cycles, one
decrementer entry, 125 address retries, 97 data retries. `ci` passed all 32
compiled-firmware RTL profiles, regression and coverage (77.0 % line
coverage, 1,403/1,823).

## Reference comparison

`reference-acceptance` passed: every flat, memory, BAT, cached, managed and
cache-disabled reference profile, six compiled-firmware lockstep comparisons
against DingusPPC (smoke, live-context, dsi, sdr1, lsu, full-decode) and two
stress suites of 32 seeds at 512 blocks (130,492 and 130,251 snapshots, 105
dynamic forms). The residuals program is not in the DingusPPC comparison.

## Unit benches

The benches that asserted the old rejections now check the manual result:
`test-exception-state`, `test-exception-tlb-miss`, `test-bat-service`
(+ independent oracle), `test-bat-runtime-service`, `test-bat-memory-router`
(+ live), `test-bat-data-fault` (+ disabled), `test-tlb-service`
(+ independent oracle), `test-tlb-prepared-refill`,
`test-tlb-runtime-fill-router`, `test-core-tlb-load`, `test-miss-derive`,
`test-core-sdr1`, `test-core-tgpr` and `test-core-tlb-miss`.
`test-core-tlb-miss` drops two phases that injected router responses the core
now asserts unreachable (a capsule with a mismatched EA, a changed-page fault
on a load).

Not established: behavior with MSR[LE] (out of MVP scope), and agreement
with silicon where the manuals leave results undefined (duplicate TLB tags,
overlapping BATs, non-table BL); those follow the documented choices.
