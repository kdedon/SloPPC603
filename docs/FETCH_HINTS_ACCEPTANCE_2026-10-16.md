<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Three-bit fetch hints: candidate evidence, 2026-10-16

Recorded: connected/leaf/benchmark/physical acceptance at `e848682e21c4bcc94ded557e9fc0cd4439ee4b36`, with unchanged connected implementation from `ce9d5105bbf7a24235f4b21f294eb08fd4023862`; combined spec/BAT-PR checks at `45f630f89dc4d47a4c0f69f378c4245589a97514` plus the reviewed checker adaptation; 2026-10-16.

The enabled candidate closes at **42.41 MHz hot / 42.60 MHz cold**, compared with the prior matched CPU profile's 41.75/42.52 MHz. It does **not** meet 66 MHz. Connected functional gates, the 24-profile cache matrix and a matched integer benchmark passed. This records a reviewable candidate, not completed adoption or aggregate CI acceptance.

The implementation checkpoint is `ce9d5105bbf7a24235f4b21f294eb08fd4023862`; child `e848682e21c4bcc94ded557e9fc0cd4439ee4b36` changes only the cache bench's first-reset comparison ownership. The connected tests consume unchanged implementation sources at both checkpoints. The child supplies the final leaf, benchmark and physical-fit source. Consumed sources remained unchanged through those gates, and the physical experiment restored its QSF. Inherited Git metadata in the isolated checkout is not the fitted-source identity.

## Implementation and architectural boundary

`ENABLE_FETCH_HINTS` defaults off. A stateless `ppc_fetch_hints` classifies eight line words and the scalar response with the actual `ppc_decode`, binding all 18 decoder parameters. Each word carries `{raw cr_writer, branch, needs_IU}` from the original shared predicates. There is no replacement opcode table or decode fallback on cache hits.

Hints follow the existing data owner through refill, cache RAM, scalar/bypass selection, fetch buffering/promotion and FD capture/split. No CPU stage, allocation capacity, IQ payload, valid/ready authority, branch policy, retirement rule or ISA latency changes. The generic cache keeps `ENABLE_METADATA=0` and `WORD_META_BITS=2` defaults. Enabled assembly uses three bits per word: line word `w` at `[23-3*w -:3]`, response lane0 `[2:0]`, lane1 `[5:3]`. Each enabled RAM row is `{12 metadata bits,128 data bits}`; disabled rows remain 128 bits. Data and metadata use the same actual RAM addresses/enables and half-line captures. The existing selective INSTALL-abort victim fix is preserved.

The actual classifier maps word zero to `3'b000` with supervisor exceptions either on or off. Router word-zero responses therefore carry zero hints. Class consumption retains the original procedural fault priority. Lane0 CR demand remains `(queued.fault == FETCH_OK) && raw_writer`; lane1 remains `FETCH_WIDTH == 2 && raw_writer`, without a new fault gate. IABR and endian/fault views retain their original qualification points. Raw writer is the shared original CR-demand predicate, not the pair-predecode CR-write field.

Local hint muxes mirror the corresponding word muxes, including procedural X-false selection versus ternary merging. Nonlinear classification does not generally commute with an arbitrary unknown selector or a corrupted multiway OR. Exact architectural/cycle preservation is bounded by the existing reset/protocol ownership contract, with initialized selected rows, known single-way selection and no selected undefined read-during-write. Enabled core assertions compare meaningful consumed hints against the original actual decoder and CR predicate. Universal X/Z-selector equivalence and exhaustive temporal induction are not claimed.

## Canonical functional gates

The focused runner completed eight existing Make targets, producing eleven build variants. It uses DW2, LSU1, one compiler worker, strict assertions/Wall, unique initialization and seed1/reset2; FDREG is selected per profile. Existing numerical, public bus and architectural oracles were retained.

| Target/profile | Recorded acceptance |
|---|---|
| `test-core-bat-cached-bus60x`, FD0 | 1,729 checks;41 retirements;14 addresses;7 line fills;54 hits;7 misses;5 bypasses;one data read/write |
| `test-core-bat-cached-bus60x-cacheops`, FD0 | 5,128 checks;259 retirements;9 exceptions;84 icbi waits;12 overlaps;6 instruction retries;3 data retries |
| `test-core-bat-cached-bus60x-coherence`, FD1 | 1,341 checks;66 retirements;13 offers;old/new fetch bins1/2;4 alias witnesses;17 stale witnesses |
| `test-core-bat-cached-bus60x-irq`, FD0 | 546 checks;18 retirements;IRQ1;handler2;rfi1;target1 |
| `test-core-bat-cached-bus60x-drain`, FD1 | 731 checks;48 retirements;4 alias lines |
| `test-chip-icache-real`, FD0, four variants | ICE1 variants each4 checks at528/604/604 cycles;ICE0 variant3 checks,256 single fetches,4,312 cycles |
| `test-chip-pins`, FD1 | 2,596 checks;398,977 cycles;2,207 streamed fetches |
| `test-chip-fpu-lsu-pipe`, FD0 | Golden firmware PASS;98,174 cycles;6,279 tenures;486 retries;351 data retries;130 read bursts;2 write bursts;one doubleword read/write |

Strict enabled lint passed with FPU0 and FPU1. Spec checks passed 190 rows/41 rules/391 locators, 259 tool tests and29 cosimulation tests. Quartus17 analysis/elaboration passed with zero errors/62 warnings. The optional actual-source abort-control proof passed4,096 observations; unchanged abort-install public tests passed54/96 checks.

From the candidate source tree, reproduce the connected gates with:

```sh
make -C sim -j1 check-fetch-hint-config
make -C sim -j1 test-fetch-hints FETCH_HINTS_PROFILE=focused FETCH_HINTS_VALUE=1
```

Recorded: `OBJCACHE= make -C sim -j1 test-fetch-hints FETCH_HINTS_PROFILE=stress` and the same command with `FETCH_HINTS_PROFILE=timer`, commit `115d24b`, 2026-10-16: PASS. These add two targets to the eight-target result above. Stress seeds 1–4 passed 76,427/77,702/76,678/69,443 checks, 1,696/1,720/1,724/1,657 retirements and 35,828/36,493/35,866/32,605 cycles. Each observed 36 icbi operations, external/decrementer events, maintenance, retry/data-retry, held-tenure and refill/maintenance-overlap witnesses. Timer promotion passed 1,465 checks and 27 retirements, one external and one decrementer event, two entries into each handler and the expected target fetch.

Recorded: `OBJCACHE= make -C sim -j1 test-fetch-hints FETCH_HINTS_PROFILE=le`, commit `d11428c` plus the optional `le` runner entry, 2026-10-16: PASS. The unchanged self-checking package program uses both caches, PID7v/FULL FPU, DW2/FW2/LSU1 and FD0. It completed in 27,445 cycles with 788 tenures, 60 retries, 177 data retries, 500 read bursts and 16 write bursts. This adds one build/target to the ten connected targets above; other CPU variants remain outside this enabled result.

`test-fetch-hints-cached` selects all seven cached profiles; `test-fetch-hints-package` selects the three package targets. These optional enabled results still do not establish every supported configuration or aggregate release acceptance.

## Cache transport and selected-row evidence

The canonical `test-icache-metadata` passed all24 profiles: geometries128x4/128x2/64x2 ×FW1/2 ×metadata off/on ×word metadata2/3 bits. The final rerun explicitly enabled compile-time unique initialization as well as runtime seed1/reset2. It compared all15 original public outputs and retained independent public word and opaque metadata oracles, including every metadata code. The two instances use the same current cache implementation with metadata off/on; this is not an independent old-RTL pair. The actual-source inverse guard separately reconstructs the validated premetadata cache and its original abort-control baseline.

| Geometry | FW1 checks | FW2 checks | Fetches | Hits/misses | Line requests | FW2 pair responses |
|---|---:|---:|---:|---:|---:|---:|
|128x4|61,075|65,589|5,218|4,649/567|552|4,514|
|128x2|32,024|34,444|2,869|2,576/291|278|2,420|
|64x2|17,816|19,212|1,717|1,552/163|150|1,396|

Each profile required500 streamed hits, including200 in201 cycles; all first-settled-reset certificates were1 and all subsequent pre/post comparison counts were positive. The first comparison waits until a real synchronous reset edge has settled. All15 outputs are then compared unconditionally forever, including invalid cycles and later held resets; no payload-valid mask was added. Earlier strict bench projection errors and the pre-reset independently randomized payload mismatch were fixture failures, not accepted legal post-reset mismatches.

The recorded strong matrix used the former recipe with an explicit `VERILATOR_TOOL` override adding both unique flags. The subsequent recipe repair uses `$(VERILATOR)` so normal Make XRAND flags propagate; that repaired recipe has not yet been rerun. Reproduce the same strong profile with the repaired recipe:

```sh
make -C sim -j1 test-icache-metadata \
  BUILD_DIR=build/metadata-unique-validation \
  XRAND=1 XRAND_SEED=1 \
  SIM_ARGS='+verilator+seed+1 +verilator+rand+reset+2'
```

A separate observer-only 128x4/FW2/metadata1/three-bit run checked the actual140-bit selected row. It retained the same public/metadata oracles and passed65,589 checks,85,617 metadata observations, first-reset1 and22,779/22,780 pre/post comparisons. Read-only ghosts sampled actual per-way row read ownership and pre-write initialization/collision, held certificates when the RAM read enable was low, and required known onehot selection, accepted public row/word ownership, initialized complete rows and no selected collision. Mandatory every-way/both-half/held/scalar/reset bins were nonzero. Counts were19,869 selected,14,716 held,2,204 scalar,13 reset and549 writes of each half. There were537 legal unselected read collisions and no unknown read/selector samples.

That bounded supplemental observer is not installed in the canonical matrix and is not a permanent target. Its result does not substitute for the canonical public content oracle, prove arbitrary multiway/X corruption behavior or establish full-refill-version induction. Reset invalidity, accepted half0 write, half1/tag/valid publication and selective abort exclusion provide the source induction structure; exhaustive legal-interleaving proof remains separate. The older12-profile two-bit monitor result is not being relabeled as this140-bit run.

## Matched integer benchmark

The canonical matched benchmark ran the enabled hints with both FPU settings. Relative to the original hints-off result, all prior metrics, loop cycles, complete retire digests and optional quiet observations were identical; only the reported hints field changed to1. Both arms passed23 firmware checks.

| Loop metric | FPU off | FPU on |
|---|---:|---:|
|Cycles|6,398,440|6,482,446|
|Complete retire packets/macros|1,180,007|1,180,007|
|Partial packets/removed branches/FP packets|0/0/0|0/0/0|
|Branch packets|236,000|236,000|
|Speculative starts|173,999|173,999|
|Resolves|159,999|173,999|
|Mispredictions|17,999|17,999|
|Accepted early recoveries|17,999|0|
|Accepted late recoveries|0|17,999|

Both full27-field streams have SHA256 `f3de54f4afecee80e55b42389933d831932fead86833d9d01022b61e42fed422`. The fixed profile is data-uncached32, DW2/FW2, LSU1, branch removal0, FDREG0, immediate mispredict fetch1, full decode1, SQ0, snoop1/basewait1, CPU model0 and IQ6/CQ5/GPR rename5. The 128x4 instruction cache is present and enabled by the firmware. Reported CE_DIV2 is the video divider; SYS_MHZ50 is firmware metadata. The loop counter measures system-clock edges directly, with no divide-by-two conversion. FPU off/on retains the existing early-recovery policy difference. Firmware-marked loop measurements were6,399,168/6,483,181 cycles and1,180,117 packets in each arm. This establishes no modeled throughput change from fetch hints for this image; it is not a cached64 production throughput measurement or a claim about FP numerical latency.

Both arms initialize all 32,768 64-bit RAM words to zero before loading the same image, while CPU state uses unique initialization/seed1/reset2. This defines identical architectural RAM input; it does not mask retire fields or zero CPU state. Image SHA256 is `9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6`; dump SHA256 is `3fc726a3853abb0ace9794ed3dfaac2087cc90b54a90c801bd298dac5124a6cb`. The input certificate, full digest and recovery bins remain required.

Quiet observation remained unchanged: DQ0 starts165,999/eligible7,999/denied158,000; DQ1 starts8,000/eligible4,000/denied4,000. Denials were LSU-nonempty; FP-pending and special-busy observations were zero. These are baseline-schedule observations, not enabled quiescent recovery, future opportunities or cycles saved.

```sh
make -C sim -j1 benchmark-integer-fpu-pair INTEGER_PAIR_HINTS=0 \
  BUILD_DIR=build/fetch-hints-pair-off \
  SIM_ARGS='+verilator+seed+1 +verilator+rand+reset+2 +INTEGER_QUIET_OBSERVE'
make -C sim -j1 benchmark-integer-fpu-pair INTEGER_PAIR_HINTS=1 \
  BUILD_DIR=build/fetch-hints-pair-on \
  SIM_ARGS='+verilator+seed+1 +verilator+rand+reset+2 +INTEGER_QUIET_OBSERVE'
```

Compare both complete result objects and require identical prior fields after removing only the new hints setting; retain the firmware checks, full tuple hash, loop cycles and quiet observations. See [the matched benchmark contract](INTEGER_FPU_MATCHED_THROUGHPUT_2026-10-16.md) for input and architectural-oracle scope.

Recorded: `OBJCACHE= make -C sim -j1 benchmark-fetch-hints FETCH_HINTS_BENCH_QUIET=1`, commit `ad87053`, 2026-10-16: PASS. The optional canonical target ran all four hints-off/on × FPU-off/on arms on the same source and required identical complete metrics, quiet observations and retirement digests. Both modes retained 6,398,440/6,482,446 loop cycles and 23 firmware checks per FPU arm; all four full streams retained the 1,180,007-packet digest above. Input and complete source fingerprints matched, and raw tuple files were removed after digesting. Make's `override VERILATOR +=` preserves the compile-time unique flags even with a command-line compiler variable.

```sh
OBJCACHE= make -C sim -j1 benchmark-fetch-hints FETCH_HINTS_BENCH_QUIET=1
```

## Matched physical fit and outstanding gates

Quartus17 CPU-only MiSTer fit used the existing Balanced/Standard-fit seed1 profile, DW2/LSU1/FPU0, unchanged SDC and66MHz request; only `ENABLE_FETCH_HINTS=1` was added to the temporary QSF. Source checks passed before/after and the original QSF was restored. Native slow-corner Fmax is42.41/42.60MHz; setup slack is−8.427/−8.321ns at slow100°C/−40°C and+2.316/+4.341ns at fast100°C/−40°C. Corresponding holds are+.200/+.197/+.128/+.106ns. All unconstrained-clock/input/output panels are zero. Timing remains unmet.

Resources are23,368ALMs,16,145 registers,46M10Ks,54MLAB LABs (26,624MLAB bits),292,608 block-memory bits and2DSPs. Do not infer140-bit physical RAM packing solely from the logical row width or these aggregate totals. Detailed STA confirms the next limiter has moved beyond the classified frontend cone. The worst hot path runs CQ generations → indexed pivot-owner selection → retained/kill decisions → branch CR → fetch redirect → instruction uTLB → cache update. The worst cold path runs CQ head → pivot-age comparison → retained/kill decisions → LSU adoption → special result. Of the hot top20 paths, starts are CQ10/SRU7/IQ3 and endpoints cache9/LSU10/SRU1; cold starts are IU12/SRU7/CQ1 and endpoints cache12/LSU7/SRU1. This supports measuring a separately proved CQ-pivot candidate next; no rename change is implied or included. Hot worst data delay is23.113ns across22 cells:15.157ns wire and7.956ns cell, with−.405ns skew. Cold data delay is22.948ns across23 cells:12.398ns wire and10.550ns cell. Detailed storage mapping and final combined acceptance remain adoption gates.

Reproduce from the candidate after setting exactly one QSF `set_parameter -name ENABLE_FETCH_HINTS 1`, preserving seed1/Standard/Balanced and the original SDC, then restore the QSF after:

```sh
bash quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66
```

The combined source at `45f630f89dc4d47a4c0f69f378c4245589a97514` plus the reviewed metadata-aware source checker passed fresh spec checks (259 tool/29 cosimulation tests), BAT-PR four-state proof (122,690 observations in each runtime profile,63,296/63,490 captures) and actual-router pair (73 checks/77 edges). The checker strips only exact reviewed metadata additions, then recovers the existing full source identities, frozen original router and94 public comparisons. The initial attempt hit a read-only ccache sandbox; rerunning with `OBJCACHE=` passed without an RTL fix. These checks do not replace the broader enabled acceptance above.

No aggregate CI pass is claimed. The earlier full CI on prefeature sources completed functional regression/firmware but failed coverage accounting before xrand/FPU-all phases; the later narrow coverage repair does not retroactively complete those phases. Before adoption, combine the reviewed source-identity adapters and coverage fixes, run fresh complete regression/firmware/coverage/xrand/FPU gates on that combined source, preserve all manual-relative numerical/cycle assertions, and review the measured critical paths. Additional supported configuration/fault/endian/IABR interleavings and formal refinement remain bounded by their actual acceptance evidence, not the enabled lint result.
