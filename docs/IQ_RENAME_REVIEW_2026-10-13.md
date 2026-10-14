# IQ and rename optimization review, 2026-10-13

Recorded: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-iq test-rename-pair test-recovery-storage test-recovery-state test-execution test-core-dual test-core-alignment-dependencies test-stage test-core-lsu-timing test-fpu-timing-603 test-fpu-timing-602 lint check-spec`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus uncommitted changes, 2026-10-13.

The functional targets completed successfully. That batch was interrupted during
lint; a separate `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-iq lint check-spec`
completed successfully after the Quartus-compatible generate declaration fix.
Full CI, x-random sweeps and the full FPU suite were not rerun. This record does
not establish release acceptance, fitted area or frequency.

## Candidates evaluated, then reverted

The IQ candidate used parallel, mutually exclusive masks for payload shifts and
pushes instead of a priority mux. Queue count, admission, dequeue positions and
record/fold update ordering are unchanged, including speculative writes to
invalid slots and count-width wrap behavior. The new independent queue oracle
covers depths six and seven, all occupancy and two-lane push/pop combinations,
record/fold overlap, reset, flush and clear. It is part of `make test`.

The rename candidate resolved payload and readiness once per physical slot before
the architectural-register lookup, sharing that logic across six ordinary and
two early reads. Stored readiness, exact producer identities, late-result
qualification and wake-port priority remain unchanged. Recovery and allocation
logic were not altered. The retained directed forwarding oracle exercises distinct early
payloads; the random recovery coverage is not an exhaustive proof of simultaneous
dual-wake/recovery behavior.

An independent Astra source review found no blocking semantic or cycle-equivalence
issue in these two changes. Its broader [architecture review](DESIGN_REVIEW_2026-10-13.md)
identifies further LSU and dispatch/decode design debt. Source inspection is not
a correctness or timing proof.

## Fresh checks

| Check | Result |
|---|---|
| Independent IQ oracle | 38,897 checks at depth six; 49,153 at depth seven |
| Rename pair model | 2,333,735 checks; 1,351 recoveries |
| Directed rename forwarding | 288 combinations, six ordinary and two early reads |
| Recovery storage/state | 22 / 5,871 checks |
| Execution forwarding | 64 source combinations plus unit/ownership checks |
| Dual-width trace | 65 identical retired packets; 74 retirements in 239 / 224 cycles |
| Alignment dependencies | 738 checks across seven variants |
| Stage timing | 14 retirements, exact dispatch schedule and boundary checks |
| LSU/FPU integration | Stalled and unstalled runs, 8,307 / 8,306 retirements |
| FULL FPU timing | 76 603e and 52 602 responses and finish predictions |
| Strict lint/spec | Passed; 252 main and 29 bus Python tests |

The MiSTer framework patch also explicitly supplies zero for reserved scaler
mode bit four, matching the five-bit VHDL port and preserving its active bits.
The pinned original and patched framework digests were verified. The HDL skill
now uses the actual 41,910-ALM device budget instead of confusing logic elements
with ALMs. No manual timing constants or acceptance percentages were changed.

## Synthesis result and decision

Recorded: pinned Quartus 17.0.2 `quartus_map ppc603e -c ppc603e --read_settings_files=on --write_settings_files=off`, COMPACT FPU / dual dispatch / pipelined LSU at the prepared 66 MHz board profile, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus uncommitted candidate changes, 2026-10-13.

The single synthesis process used the repository Quartus lock, two CPU cores,
8 GiB memory and no swap. It completed with zero errors in 8 minutes 58 seconds.
The explicit scaler reserved bit removed the mode-port width warning.

| Synthesis measure | Before candidates | Both candidates |
|---|---:|---:|
| IQ direct combinational ALUTs | 1,565 | 2,612 |
| Rename direct combinational ALUTs | 3,049 | 3,153 |
| Whole-board combinational ALUTs for logic | 47,046 | 47,667 |

These are synthesis ALUT counts, not fitted ALMs. Whole-board optimization
means entity deltas need not add to the board delta. This comparison includes
the reserved-bit framework patch; no active scaler mode bit changed.

Both RTL candidates were reverted because they increase logic in a design
already constrained by routing and area. Their independent IQ and expanded
rename tests remain. No second full fit was run and no frequency gain is claimed.
The retained board map report describes the rejected candidates; the earlier
fit report describes the pre-candidate routing failure. Neither is a fitted
timing result for the final source tree.

Recorded after reversion: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-iq test-rename-pair test-execution test-recovery-state`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus final uncommitted changes, 2026-10-13. All four targets passed again with the original IQ and rename RTL and the retained stronger oracles.
