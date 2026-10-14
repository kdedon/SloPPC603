# Payload width and dispatch metadata review, 2026-10-13

This pass continues the 66 MHz work after the rejected IQ/rename mux candidates.
Manual-verified instruction behavior and cycle counts remain the target.

## Candidate plan

- IQ: store one of six immediate forms in three bits and reconstruct from the
  already-stored instruction. Preserve complete decoded uops, including partial
  illegal forms. The sequencer's absolute EA override occurs after IQ unpacking.
- LSU: retain a 186-bit memory descriptor instead of the 250-bit full uop in P1,
  P2, Q and replay. Remove only rotate mask and branch displacement; retain every
  other field, PC, instruction, EA and producer identity. Assert exact round-trip
  for admitted integer memory operations and memory-only fault adoption.
- Dispatch: reuse IQ unit/direction metadata for FP classification, and decoded
  source-use fields for committed-source checks. Preserve the exclusion of 602
  SP/LT moves and all mode, exception and update-form admission gates.
- SRU: remove the redundant DQ1 IU condition already covered by existing
  lookahead. Keep the same queue horizon and scheduling policy.

No clock domain, reset, queue depth, acceptance edge, pipeline stage or request
protocol changes. IQ compression removes 174 declared bits across six entries;
the LSU descriptor removes 384 across six holders. Synthesis already merges and
prunes bits, so these are not measured register or area savings.

## Verification gates

Independent complete-uop round trips across BASE/FULL decode and all CPU
variants; instruction-based FP source/direction checks; exact dispatch/stage
checks; LSU timing with base-wait and snoop; FP fault, split-access, update and
602 paths. Then strict lint and serialized, resource-capped Quartus synthesis
against the retained pre-candidate board map. A favorable map permits a fresh
full fit. Synthesis alone cannot establish 66 MHz.

Astra independently reviewed immediate assignments, the descriptor's 56 retained
fields, adoption's saved-EA path, sequencer placement and qualified FP metadata
equivalence. No blocking defect was found by source inspection. Dynamic checks
and measured resource/timing results remain required.

## Fresh simulation

Recorded: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-decode-sweep variant-decode-sweep-1 variant-decode-sweep-2 variant-decode-sweep-3 variant-decode-sweep-4`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus candidate changes, 2026-10-13. All five variants passed 170,752 complete-uop immediate round trips each, including all six forms and BASE/FULL profiles.

Recorded: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-decode-iq-fpu test-core-dual test-stage`, same commit plus candidate changes, 2026-10-13. All five FPU-enabled variants passed another 170,752 round trips each. Instruction-based FP source/direction checks passed. Dual-width traces retained 65 matching retired packets and 74 retirements in 239/224 cycles; the stage schedule retained 14 retirements and its last dispatch event at cycle 75.

Recorded: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-core-lsu-timing test-core-lsu-timing-snoop test-core-fpu-machine-check-lsu test-core-dcache-lsu-pipe test-core-fpu-split test-core-lsu-timing-602`, same commit plus candidate changes, 2026-10-13. All targets passed.

| Check | Fresh result |
|---|---|
| LSU base-wait, stalled/unstalled | 8,307/8,306 retirements; 29,158/27,094 cycles, matching the earlier run |
| LSU snoop, stalled/unstalled | 8,306 retirements each; 29,151/27,094 cycles |
| FP/LSU machine check | 3,195 checks; 8,509 retirements |
| Data-cache integration | 105,303 checks; 2,452 retirements, 10 exceptions, retry/snoop traffic |
| Split FP, stalled/unstalled | 1,955/2,032 checks; 8,175/8,174 retirements |
| 602 FP/LSU, stalled/unstalled | 1,601/1,614 checks; 9,693/9,692 retirements |

Initial strict builds exposed unused packet-field warnings and an unsized
test parameter override. These were corrected with narrow, explained field-use
waivers and a sized parameter literal before the passing runs. No architectural
or cycle expectation was relaxed. Full CI and release acceptance remain pending.

## Synthesis measurement

Recorded: pinned Quartus 17.0.2 `quartus_map ppc603e -c ppc603e --read_settings_files=on --write_settings_files=off`, COMPACT FPU / dual dispatch / pipelined LSU at the prepared 66 MHz board profile, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus payload/metadata candidate changes, 2026-10-13.

The serialized job completed with zero errors in 10 minutes 7 seconds, using two
CPU cores, an 8 GiB ceiling without swap and the repository Quartus lock.

| Synthesis measure | Before this pass | Payload/metadata pass |
|---|---:|---:|
| Whole-board combinational ALUTs for logic | 47,046 | 46,451 |
| Whole-board registers (map summary) | 28,623 | 28,329 |
| IQ direct ALUTs / registers | 1,565 / 1,555 | 1,406 / 1,381 |
| LSU direct ALUTs / registers | 2,239 / 2,196 | 2,196 / 2,076 |

The measured board reduction is 595 ALUTs and 294 registers. These are map
counts, not fitted ALMs or Fmax. Individual hierarchy deltas cannot fully
attribute the combined pass: cross-boundary optimization also changed other
entities. The retained `ppc603e.pre_candidate.map.rpt` and
`ppc603e.payload.map.rpt` reports permit comparison. Keep the passing candidate
and continue with completion metadata before a fresh routed timing run.
