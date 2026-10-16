<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Matched integer throughput with FPU disabled and enabled

Recorded: `make -C sim -j1 benchmark-integer-fpu-pair` with the arguments below, commit `aa68f2b` plus uncommitted benchmark adapter and observer, 2026-10-16.

On2026-10-16 the same fixed Dhrystone image retired an identical complete normalized packet stream with FPU0 and FPU1. The public loop window took6398440 versus6482446 simulated system-clock edges, a ratio of1.013129137727321 (FPU1/FPU0). Both firmware runs passed23 checks with zero mismatches. This measures one uncached32 integer workload; it is not a production cached64 comparison, FPU execution measurement or Fmax result.

## Reproduction and profile

From repository root, with the normal sole simulation/build owner:

```sh
make -C sim -j1 benchmark-integer-fpu-pair \
  INTEGER_PAIR_DIR=build/integer-fpu-pair-r5 INTEGER_PAIR_DIGEST_ARGS=--keep-tuples \
  SIM_ARGS='+verilator+seed+1 +verilator+rand+reset+2 +INTEGER_QUIET_OBSERVE'
```

The optional target builds/runs the two arms serially, freezes the existing image, checks instruction landmarks and source fingerprints, checks firmware/profile/recovery coverage, then compares all tuple fields and full SHA256. It does not rebuild firmware. Use a fresh run directory when preserving earlier evidence. Verilator5.020 with the repository wrapper and unique initialization was used. Each arm has the same input clock/reset schedule and seed1/random-reset2; only FPU enable differs.

Both profiles: physical data cache0, DMEM32, dispatch2/fetch2, pipelinedLSU1, FULL FPU implementation selection, CPU_PID7V_603E (reported0), branch removal0, FD register0, immediate misprediction fetch1, store queue0, base snoop1/base wait1, IC128sets/4ways, IQ6/CQ5/GPRrename5, CE_DIV2 and SYS_MHZ50. CPU execution cycles are not inferred by multiplying the observer count by the nominal MHz. The window counter samples the common timed testbench clock.

Branch speculation and early-recovery capability remain enabled. Existing policy selects BS_EARLY1 for FPU0 and0 for FPU1; BS_ANCHOR0 in both because removal is disabled. This recovery-policy difference is part of the measured FPU-enable configuration. The test does not isolate dormant arithmetic hardware from that policy.

Core source SHA256 in both arms: `0be6dda92c4395c5b6f5890a4c14dba72fad21ce1c90a5580712c74f718ad42c` (aa68f2b32beb86cce396414ecc99bcf98b08a686 baseline). No captured-quiescent recovery feature is installed. The demo adapter adds a default-preserving physical-data-cache parameter so both arms can use legal uncached32; existing cached profiles retain their default behavior.

Required image `toolchain/build/demo/dhrystone.hex` SHA256: `9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6`. Dump SHA256: `3fc726a3853abb0ace9794ed3dfaac2087cc90b54a90c801bd298dac5124a6cb`. First included packet is PCfff03ecc/word80810058; recording stops before PCfff03ff8/word48000c55, the final call to times(). Both landmarks are checked against the pinned dump and actual retired instruction words. Both retirement ports are recorded in order on the same observer edge, after head acceptance.

## Identical architectural RAM input

The benchmark target supplies optional +INTEGER_PAIR_ZERO_RAM to both arms. The existing image-loader initial process initializes all32768×64bit physical RAM words to0 before the unchanged image load. Its required exactly-once certificate reports actual$size/$bits: `INTEGER_PAIR_RAM_INIT words=32768 bits=64 fill=0 before_image=1`. Standard bench behavior without the argument is unchanged. CPU/internal randomized initialization remains enabled.

This fixes input identity rather than hiding a result difference. Earlier random-RAM paired runs failed the full digest: exactly2000 packets differed, only LWZ PCfff039a8/word80c60004, GPRvalue4e470035 versus4e470098. Reconstructing preceding retired writes gives r6fff0af98 in both; EAfff0af9c is the last word of a48byte record copied by memcpy. Firmware initializes the30-character string plusNUL and leaves the one tail padding bytefff0af9f unwritten. The record fields total47bytes, rounded to48. malloc does not clear heap, CRT clears BSS only throughfff0af40, and the pinned image endsfff0687f. Different elaborations' random RAM therefore supplied different architectural input despite the same seed. No byte, packet, field or digest requirement was removed. Explicit full RAM initialization makes input independent of model-layout random draw order.

## Accepted equality and timing observations

Both arms produce1180007 tuples/macros, zero partial packets,236000 retired branches, zero removed branches and zero FP packets. Full normalized stream SHA256:

`f3de54f4afecee80e55b42389933d831932fead86833d9d01022b61e42fed422`

The27-field tuple retains orderedPC/instruction, partial marker, flag demand, every integer/update/CR/XER write permission and active effect, branch/LR/CTR effects and branch nextPC. Inactive payloads are normalized by their actual write permissions; faults, FP packets and removed branches are rejected. This is neither a complete public memory-write trace nor an exception oracle; existing firmware checks supplement packet equality.

| Observation | FPU0 | FPU1 |
|---|---:|---:|
| Public loop clock edges |6398440|6482446|
| Speculative starts |173999|173999|
| Resolutions |159999|173999|
| Mispredictions |17999|17999|
| Accepted early recovery |17999|0|
| Accepted late recovery |0|17999|
| Firmware timed cycles |6399168|6483181|
| Firmware timed packets |1180117|1180117|
| Firmware cycles/run |3199.4|3241.4|

Public loop ratio is1.013129137727321; independent firmware-window ratio is1.0131287379859382. Their boundaries differ, so their cycle counts need not match. These results establish this pair's measured behavior, not a benefit for an unimplemented optimization or unchanged behavior for all programs.

## Quiet-start observation

+INTEGER_QUIET_OBSERVE is defaultOFF and never drives DUT controls. In the same timed window, FPU1 has165999 actual DQ0 starts and8000 DQ1 starts. The exact reviewed conservative eligibility expression is true for7999 DQ0 and4000 DQ1 starts, including DQ1's exclusion of older DQ0 FP/FP-memory work. All other158000/4000 starts are denied with LSU nonempty; FP pending, special busy, adoption, native release, delayed kill, replay, sticky wait, recovery and unknown-context counters are0. FPU0 observes the same runtime guard counts but reports potential_option1=0 because its existing early mode already applies.

The11999 eligible observed FPU1 starts are opportunities in this baseline schedule only. They do not establish a misprediction at those starts, safe younger-FP cancellation/adoption, cycles saved, future eligibility after changed recovery, or timing closure. Blocker counters can overlap; they are not independent stall-cycle totals. A captured-quiescent feature still requires separate ownership/recovery/manual acceptance and matched measurement.

## Evidence boundary and source guard

The measured checker fingerprints the complete RTL SV/SVH set, demo TB/SVH set, actual machine_trace.svh and integer_branch_profile.svh includes, Makefile and paired checker/target before and after the two runs. Image bytes are pinned separately. A source audit reconstructed the measured harness exactly from the original adapter plus explicit hierarchy, formal-only lint, typed-boolean and RAM-input repairs; no tuple/oracle/counter logic was dropped.

The measured checker did not fingerprint filelists or the Verilator wrapper and did not emit a structured version/argv manifest. Those are provenance limits of this result, not additional runtime checks claimed here. A separate post-run proposal can strengthen them for future runs without changing model logic; it must not be presented as having executed in this measurement. The optional external prototype-linkage source audit is separate from the self-contained runtime benchmark target.

Default cache-enabled SoC and bench strict lint also passed with `make -C sim -j1 lint-demo-soc check-spec`: 190 specification rows, 41 rules, 391 locators and 259 tool plus 29 cosimulation checks. Quartus analysis of the new default-preserving SoC parameter remains a separate pending gate; no hardware timing change is claimed.
