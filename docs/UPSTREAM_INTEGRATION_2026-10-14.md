# Upstream integration, 2026-10-14

The validated local timing checkpoint is merge `9a68a26`, containing
`f2da169` (CPU/tests), `9c13500` (build/benchmarks), and `f7c2621` (skills).
Its CPU-only limiting-corner result is 40.66 MHz; full release gates remain
pending. Local work had incorrectly started before synchronizing remote main.

Integration branch: `codex/integrate-upstream-20261014`. Remote main was
freshly fetched at `e5cddb9`; nine previously missing commits are integrated.
They include response-payload pre-read, fixed-head kill, explicit GPR read-copy
instances and registered-address block-RAM inference, and demo reset changes.
No new clock, stage, manual cycle, architectural instruction or exception
policy is intended. Preserve all local owner-wrap and exception checks.

Conflict ownership: core frontend/dispatch, completion/recovery, I-cache and
router payload selection are reviewed independently. The router retains the
local separate reset-independent payload block, which already implements
upstream's intent and preserves refetch priority and procedural unknown-control
behavior. Data-page projection and held-OFFER snapshots remain unchanged.

The five eligible GPR read ports request block RAM; their existing registered
addresses must be absorbed without shifting externally visible latency.
Write-through behavior and actual fitted memory tiers must be checked rather
than inferred from source attributes.

Validation order: strict lint/specification, focused GPR/core fetch/recovery/
completion/cache/owner-wrap and verified-cycle gates; then one serial capped
matched CPU-only Quartus fit. Full CI, X-randomization and FPU/reference gates
remain required for release acceptance. No additional timing experiment is
stacked onto this integration. All physical results for the combined source
are pending; the saved checkpoint remains the comparison baseline.

## Saved merge and initial checks

Resolved upstream merge: `22eb2b0`, parents `9a68a26` and `e5cddb9`.
The local checkpoint remains reachable; remote history is included without
rewriting either parent. Future implementation starts with an upstream fetch
and regular committed checkpoints, now stated in `AGENTS.md`.

Recorded: `OBJCACHE= make -C sim -j1 test-regfile-gpr-ports test-regfile-tgpr
 test-completion-arrival test-completion-mixed-pair-cut test-rename-recovery`,
commit `9a68a26` plus upstream-merge changes (subsequently committed as
`22eb2b0`), 2026-10-14. All targets pass. Four GPR profiles retain
242,880/242,688 read checks and 1,295,360/1,294,336 view checks depending
on TGPR configuration, with single/dual writes and same-cycle old-value reads.
TGPR overlay profiles each retain 35 checks. Completion arrival retains
221 scenarios, 1,723 steps and 42,943 checks; both mixed-pair runs pass.
Rename recovery retains 2,644,718 total checks, including 288 forwarding
combinations and unshifted recovery remove0/1/2 coverage of 729/422/200.
These leaf GPR runs use default LUT copies; the production mixed block/LUT
profile is a separate pending gate. No fitted RAM inference is established
by these behavioral tests.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
 test-dtlb-projection-composition test-core-fetch-fault
 test-core-fetch-fault-disabled test-core-translated-held-cr
 test-core-branch-fold test-core-dual-lsu-pipe test-core-recovery
 test-core-lsu-wake-wrap test-core-lsu-response-wrap
 test-core-lsu-timing-snoop test-core-lsu-timing-602
 test-core-dcache-lsu-pipe test-core-dcache-lsu-pipe-projection-off
 test-icache test-icache-managed test-core-fpu-machine-check-lsu
 test-core-fpu-split`, commit `9a68a26` plus upstream-merge changes
(subsequently committed as `22eb2b0`), 2026-10-14. All targets pass and
all 79 RTL files remain stable. Strict lint, seven stage anchors, 259 tool
tests and 29 co-simulation checker tests pass; those checker tests are not
a fresh full reference run. Data-page source composition retains 131,072
finite cases across four profiles.

Enabled/disabled cache-core profiles each retain 105,303 checks, 2,452
retirements, ten expected exceptions and 12,112 cycles, including equal bus
retry/DRTRY and snoop counts. Dual LSU retains 74 retirements in 228/213
cycles and 65 identical packets. All four held-CR profiles retain their
verified owner/request/dispatch edges. The seven wake-wrap and two
canceled-response profiles retain all counts from the prior checkpoint.
LSU snoop retains 29,151/27,094 cycles and 602 retains 36,112/33,938.
FP machine check retains 31,134 cycles and split FP memory retains
38,307/35,601. Recovery retains 1,107 checks. Instruction cache single/pair
profiles pass 61,031/65,545 checks; managed cache retains 267 checks.
Fetch-fault enabled/disabled profiles pass 14,350/4,021 checks. No expected
exception, assertion, checked owner or manual cycle count is weakened.

Recorded: `OBJCACHE= make -C sim -j1 test-regfile-gpr-ports-registered
 check-spec`, commit `22eb2b0` plus the registered-profile test extension,
2026-10-14. All four production-mask `111011` profiles pass with the same
independent read/view and collision counts as the original four LUT profiles.
The original profiles remain; the mixed-copy target joins the default test
set. This confirms source-level behavior of both RAM branches, not mapped
read-during-write behavior or register absorption. Fresh fit remains pending.

## Matched upstream fit

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
 --sys-mhz 66`, commit `0cf0429`, 2026-10-14, Quartus 17.0.2 Build 602
and the same pinned image and constraints as the saved checkpoint. Main flow
completes in 29m00s, zero errors and 86 warnings. CPU-only restricted Fmax is
**40.12 MHz at slow 100 C**, and 40.74 MHz at slow -40 C. The limiting result
is below the predecessor's 40.66 MHz; this integration establishes an area
improvement, not a clock improvement or 66 MHz closure.

Resources: 21,957 ALMs, 15,948 registers, 46 M10Ks, two DSPs, 54 MLAB LABs,
26,624 MLAB bits and 280,320 block-memory bits. Relative to the saved fit,
this saves 1,768 ALMs and 2,567 registers while adding four M10Ks.

| Corner | Setup slack at 66 MHz (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -9.775 | +0.239 |
| Slow -40 C | -9.392 | +0.230 |
| Fast 100 C | +1.517 | +0.132 |
| Fast -40 C | +3.622 | +0.115 |

All unconstrained categories remain zero. All source/configuration pins match
before/after; all 79 RTL files remain unchanged, and the original QSF is
restored. The summary's dirty flag reflects temporary generated run settings;
no RTL is changed during compilation. Full CI, reference, X-randomization
and board release acceptance remain pending.

The reports confirm ten GPR M10Ks, versus six in the preceding fit; all five
requested BLOCK ports in both banks map as intended. Each has a registered
RAM address/input and unregistered output. Port2 in each bank is MLAB.
GPR hierarchical ALMs fall from 1,763.9 to 450.7, and dedicated registers
from 3,121 to 604. New mixed-port read-during-write is reported as Don't care
with explicit synthesized pass-through logic; the old blocks reported Old
data with pass-through. Warning 276020 increases from six to ten, explaining
the four additional warnings; other map/fit warning-code counts are unchanged.
These reports confirm mapping, not a post-fit whole-core behavioral simulation.

Subsequent all-corner detailed STA completes in 2m26s, zero errors and three
warnings, using the exact run SDC. Both slow worst paths launch at checkstop
and traverse managed error qualification, router instruction normalization,
lane1 predecode/branch classification, `fd_next_iu`, `after1_iu`, and
`d1_station_ready` into station operand capture. Hot/cold data delay is
24.312/23.928 ns, with clock skew -0.554/-0.555 ns. Frontend lookahead is on
74 of 80 reported setup paths, including 37 of 40 slow paths. Six remaining
paths launch from BS tag/index through pivot recovery and SQ overlap.
The direct branch/needs-IU projection is therefore the next measured-relevant
candidate; changing reset/error normalization is a broader semantic change
and is not included. No direct-class timing result exists yet.

## Reproducible held-release expression check

Recorded: `OBJCACHE= make -C sim -j1 test-held-release-equivalence check-spec`,
commit `0cf0429` plus the canonical expression tool, 2026-10-14, Icarus 12.0.
Pass: 131,072 matrix cases (65,536 known-valid equivalence assertions and
65,536 unknown-valid diagnostics, including 8,352 differences), plus 72
independent directed cases. Required positive target checks are B=4, BC=4,
BCLR=4, BCCTR=4, crossing both frontend configurations; breakpoint matching
and six individual release inhibitors are checked. This confirms bounded
initialized-valid expression behavior, not arbitrary unknown sequential
state or a complete ISA/temporal proof. Strict spec checks remain passing.

The initial private fixture's positive target comparison was vacuous because
IABR always matched and LR readiness was coupled to a blocking control.
Independent review caught both gaps. The committed fixture uses nonmatching/
disabled/matching breakpoint profiles and independent controls with required
nonzero target coverage. Production RTL was not changed to repair the test.
