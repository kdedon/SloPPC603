# Raw producer owner comparison trial

Prepared against `9bfdc43`, 2026-10-15. This is an isolated candidate plan,
not accuracy acceptance or a new timing result. The matched baseline is the
40.99 MHz CPU-only fit documented in
[the control-path review](CPU_CONTROL_PATH_REVIEW_2026-10-13.md).

## Hardware change

The measured hot path selects an 11-bit second-result producer before comparing
it with rename owners. That comparison controls early forwarded operand value,
which feeds incoming alignment and LSU P1 capture control. It does not consume
the returned operand ready bit.

Compare each of five registered owners against raw IU, special-lane and SRU
producer identities in parallel, then select the one-bit equality with the
existing SRU/special/IU priority. A relevant X/Z selector uses the original
selected-producer equality literally; an SRU selection ignores the secondary
selector. Preserve full index and generation, selected wake tag, offer, late,
payload priority, all eight readers, and every allocation/recovery/state update.
The projected equality is not a new wake or acceptance authority.

The core option defaults on for this trial so existing wrappers and core tests
exercise it; an explicit core option off retains comparison coverage. Standalone
rename defaults off and receives explicit unused-hint tie-offs. No pipeline
register, clock, reset, handshake, latency or throughput contract changes.
Existing core clocks and active-low resets remain authoritative.

This adds ten raw 11-bit comparisons and five selectors before optimization.
Routing, sharing and fallback pruning may outweigh the saved mux-before-compare
level. CQ tag lookup and early payload selection remain possible limits.

## Acceptance

Keep the original rename oracle and stimulus, adding a coherent enabled DUT
that compares complete public operands, early values, maps and allocation
outputs before and after edges. Require every raw source role during an offer.
Independently check actual-source four-state selector/owner equations and whole
readers, including unknown/unused tags, owner generation mismatches, real
port1 priority, invalid-map masking and poisoned disabled hints. Finite
combinational matrices do not establish arbitrary temporal or ISA equivalence.

Run strict lint/spec, both rename recovery organizations, recovery-state,
execution/stage, dual pipelined LSU and exact-owner wrap checks. Preserve manual
Table 6-6 base-wait/base-snoop timing at both dispatch widths. Commit the tested
candidate before one matched CPU-only fit at 66 MHz, two Quartus workers and
8 GiB without swap; inspect all setup/hold corners and unconstrained paths.
Do not combine CNTLZW, false hazards or FPU scheduling in this measurement.

Broad CI, initialization and FPU acceptance remain pending: the previous
aggregate process and its temporary completion log were unavailable on resume,
so no aggregate pass is inferred. Run full gates once for the next merged batch.

## Fresh focused results

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-rename-pair
test-rename-recovery test-recovery-state test-execution test-stage`, commit
`9bfdc43` plus this uncommitted candidate, 2026-10-15. All pass. Strict lint
has no blanket waiver. Spec checks cover 190 rows, 41 rules, 391 locators and
seven stage anchors; 259 tool tests and 29 bus-checker tests pass.

The original rename oracle passes 2,333,699 checks and 288 forwarding cases.
The paired observer compares 2,384,284 complete public observations; offered
IU/special/SRU roles each occur 384 times. The production unshifted recovery
oracle passes 2,644,718 checks with remove0/1/2 counts 729/422/200. Recovery
state passes 5,871 checks; execution covers 64 forwarding combinations.
The stage probe retains 14 retirements and its exact dispatch schedule,
ending at cycle 75.

Recorded: `make -C sim test-rename-raw-owner-equivalence`, same candidate and
date. Pass: 336,960 full owner comparisons and 1,669,632 complete-reader
comparisons across 104,352 reader vectors. Nonzero observations include
25 payload-priority collisions, 185 wrong-tag exclusions, 120 known-positive
alias fallback cases, 171,743 disabled-hint poison observations and 21,495
distinct early-value observations. Known mismatching index/generation cases,
both relevant-unknown fallback families, ignored secondary X/Z selectors,
all slots, invalid-map masking and unused/unknown tags are mandatory. This
is finite factored expression coverage, not arbitrary temporal equivalence.

Recorded: pinned Quartus 17.0.2 analysis/elaboration of `ppc603e_chip`, same
candidate and date. Command from the repository root:

```sh
. ci/pins.env
flock /tmp/ppc603e-sim.lock flock /tmp/ppc603e-quartus.lock \
  docker run --rm --network none --cpus 2 --memory 8g --memory-swap 8g \
  --user 1000:1000 --volume "$PWD:/work" --workdir /work/quartus/chip \
  "$QUARTUS_IMAGE_PIN" /opt/intelFPGA_lite/quartus/bin/quartus_map \
  ppc603e_chip -c ppc603e_chip --analysis_and_elaboration \
  --read_settings_files=on --write_settings_files=off
```

Pass: zero errors, 65 warnings, 32 seconds elapsed, 1,681 MiB peak virtual
memory. Project settings remain unchanged. This establishes compatibility,
not mapping, placement or timing improvement.

Recorded: `OBJCACHE= make -C sim -j1 test-core-dual-lsu-pipe
test-core-lsu-wake-wrap test-core-lsu-response-wrap test-core-dcache-lsu-pipe
test-core-fpu-machine-check-lsu`, same candidate and date. All pass. Both
dispatch widths retire 74 instructions in 228/213 cycles, with 65 identical
public packets and one required renamed-base DQ1 access. The exact-owner
wrap case retires 1,285 instructions in 3,959 cycles, including one invalid
port0 alias; six warm-length controls also pass. Both canceled-response
fault variants retain owner401, 1,282 retirements, 1,342 cycles and 1,280
killed-pending observations. Cache integration passes 105,303 checks,
2,452 retirements, ten exceptions and 12,112 cycles. FP memory machine-check
coverage passes 3,195 checks, 8,509 retirements and 31,134 cycles.

Recorded: `OBJCACHE= make -C sim -j1 DISPATCH_WIDTH=1 test-core-lsu-timing
test-core-lsu-timing-snoop`, repeated with `DISPATCH_WIDTH=2`, same candidate
and date. All pass with unchanged latency/spacing assertions. Every unstalled
profile checks 35 probes and 55 spacings; stalled profiles exercise backpressure.

| Dispatch width | Base option | Stalled cycles | Unstalled cycles |
|---|---|---:|---:|
| 1 | wait | 29,158 | 27,094 |
| 1 | snoop | 29,151 | 27,094 |
| 2 | wait | 29,158 | 27,086 |
| 2 | snoop | 29,151 | 27,084 |

No fitted frequency is attributed to this candidate yet. Full batch and
reference acceptance remain pending; 66 MHz remains open.
